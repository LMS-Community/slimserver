#!/usr/bin/env python3
"""Polars based replacement for scanner.pl.

This utility ingests the staging database produced by
``tags2db-polars-multidrive-optimised.py`` (table ``alib``) and materializes a
``library.db`` that mirrors the structure expected by the legacy Perl scanner.

The transformer focuses on table parity (tracks, albums, contributors, genres
and their join tables) so that Lyrion Media Server can pick the result up
without triggering its own rescan. It intentionally keeps artwork and playlist
handling minimal because LMS will refresh these on-demand.
"""

from __future__ import annotations

import argparse
import hashlib
import logging
import os
import re
import sqlite3
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple
from urllib.parse import quote

import polars as pl
import unicodedata

LOG = logging.getLogger("polars_scanner")

LOSSLESS_EXTS = {
    "aif",
    "aiff",
    "alac",
    "ape",
    "dsf",
    "dff",
    "flac",
    "tak",
    "wav",
    "wv",
}
ARTICLES = ("a", "an", "the")
MULTI_VALUE_DELIM = "\\\\"  # literal "\\" in tags
PUNCT_RE = re.compile(r"[^0-9a-zA-Z]+")


@dataclass(frozen=True)
class RoleDefinition:
    role_id: int
    name: str
    tag_names: Tuple[str, ...]
    mbid_tags: Tuple[str, ...] = ()


ROLE_DEFS: Tuple[RoleDefinition, ...] = (
    RoleDefinition(1, "ARTIST", ("artist",), ("musicbrainz_artistid",)),
    RoleDefinition(2, "COMPOSER", ("composer",), ("musicbrainz_composerid",)),
    RoleDefinition(3, "CONDUCTOR", ("conductor",), ("musicbrainz_conductorid",)),
    RoleDefinition(4, "BAND", ("ensemble", "band", "orchestra"), ("musicbrainz_ensembleid",)),
    RoleDefinition(5, "ALBUMARTIST", ("albumartist",), ("musicbrainz_albumartistid",)),
    RoleDefinition(6, "TRACKARTIST", ("artist",), ("musicbrainz_artistid",)),
)


class PolarsScanner:
    """Transform the staging SQLite database into ``library.db``."""

    REQUIRED_TABLES: Tuple[str, ...] = (
        "tracks",
        "albums",
        "contributors",
        "contributor_track",
        "contributor_album",
        "genres",
        "genre_track",
        "metainformation",
    )

    def __init__(
        self,
        alib_path: Path,
        library_db: Path,
        *,
        max_threads: Optional[int] = None,
        chunk_size: int = 1000,
        fts_sql: Optional[Path] = None,
    ) -> None:
        self.alib_path = alib_path
        self.library_db = library_db
        self.chunk_size = chunk_size
        self.fts_sql = fts_sql
        if max_threads:
            os.environ["POLARS_MAX_THREADS"] = str(max_threads)
        self._now = int(time.time())

    # ------------------------------------------------------------------
    def run(self) -> None:
        LOG.info("Loading staging rows from %s", self.alib_path)
        staging = self._load_staging()
        if staging.is_empty():
            raise RuntimeError("No rows found in alib staging table")

        LOG.info("Preparing derived track metadata")
        track_frame = self._annotate_tracks(staging)
        LOG.info("Building album dimension")
        albums = self._build_albums(track_frame)
        LOG.info("Assigning album ids to tracks")
        track_frame = self._attach_album_ids(track_frame, albums)
        LOG.info("Materializing track rows")
        tracks = self._build_tracks_table(track_frame)
        LOG.info("Deriving contributor relations")
        (
            contributors,
            contributor_track,
            contributor_album,
            primary_artist_map,
            contributor_lookup,
        ) = self._build_contributors(track_frame)
        LOG.info("Deriving genre relations")
        genres, genre_track = self._build_genres(track_frame)
        LOG.info("Finalizing track primary artist lookups")
        tracks = self._apply_primary_artists(tracks, primary_artist_map)
        albums = self._assign_album_contributors(albums, contributor_lookup)
        albums_payload = self._albums_storage_view(albums)

        LOG.info("Writing %d albums and %d tracks", albums.height, tracks.height)
        with self._connect_target() as conn:
            self._ensure_schema(conn)
            self._reset_tables(conn)
            self._bulk_insert(conn, "albums", albums_payload)
            self._bulk_insert(conn, "tracks", tracks)
            self._bulk_insert(conn, "contributors", contributors)
            self._bulk_insert(conn, "contributor_track", contributor_track)
            self._bulk_insert(conn, "contributor_album", contributor_album)
            self._bulk_insert(conn, "genres", genres)
            self._bulk_insert(conn, "genre_track", genre_track)
            self._refresh_metainformation(conn, tracks.height)
            self._maybe_rebuild_virtual_tables(conn)
            self._maybe_rebuild_fts(conn)
        LOG.info("Library rebuild finished successfully")

    # ------------------------------------------------------------------
    def _load_staging(self) -> pl.DataFrame:
        query = "SELECT * FROM alib"
        uri = f"sqlite:///{self.alib_path}"
        try:
            return pl.read_database_uri(query=query, uri=uri)
        except Exception as exc:  # pragma: no cover - connectorx optional
            LOG.warning("ConnectorX unavailable (%s), using sqlite3 fallback", exc)
            with sqlite3.connect(self.alib_path) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.execute(query)
                rows = [dict(row) for row in cursor.fetchall()]
            if not rows:
                return pl.DataFrame([])
            return pl.DataFrame(rows)

    # ------------------------------------------------------------------
    def _annotate_tracks(self, frame: pl.DataFrame) -> pl.DataFrame:
        required = [
            "__path",
            "title",
            "album",
            "track",
            "artist",
            "__filetype",
            "__file_mod_datetime_raw",
            "__file_size_bytes",
            "__length_seconds",
        ]
        for col in required:
            if col not in frame.columns:
                raise RuntimeError(f"Missing required staging column: {col}")

        defaults = {
            "subtitle": None,
            "albumartist": "",
            "compilation": 0,
            "year": None,
            "originalyear": None,
            "disc": None,
            "discnumber": None,
            "lyrics": None,
            "unsyncedlyrics": None,
            "musicbrainz_trackid": None,
            "musicbrainz_albumid": None,
            "musicbrainz_artistid": None,
            "musicbrainz_albumartistid": None,
            "musicbrainz_composerid": None,
            "musicbrainz_conductorid": None,
            "musicbrainz_ensembleid": None,
            "musicbrainz_workid": None,
            "analysis": None,
            "amgtagged": 0,
            "replaygain_track_gain": None,
            "replaygain_track_peak": None,
            "replaygain_album_gain": None,
            "replaygain_album_peak": None,
            "tagminder_uuid": None,
            "__bpm": None,
            "explicit": 0,
            "__bitrate": None,
            "__bitrate_num": None,
            "__frequency_num": None,
            "__bitspersample": None,
            "__channels": None,
            "__version": None,
            "discsubtitle": None,
            "genre": None,
            "style": None,
        }
        df = frame.clone()
        for column, default in defaults.items():
            if column not in df.columns:
                df = df.with_columns(pl.lit(default).alias(column))

        df = df.with_row_count(name="track_id", offset=1)
        df = df.with_columns([
            pl.col("__path").map_elements(file_url_from_path).alias("url"),
            pl.col("__path").map_elements(detect_lossless).alias("lossless"),
            pl.col("title").map_elements(normalize_sort_key).alias("titlesort"),
            pl.col("title").map_elements(normalize_search_key).alias("titlesearch"),
            pl.struct(["title", "subtitle"]).map_elements(normalize_custom_search).alias("customsearch"),
            pl.col("album").map_elements(normalize_sort_key).alias("album_titlesort"),
            pl.col("album").map_elements(normalize_search_key).alias("album_titlesearch"),
            pl.col("albumartist").map_elements(lambda v: v or "").alias("albumartist_clean"),
            pl.coalesce([pl.col("disc"), pl.col("discnumber")]).cast(pl.Int64).alias("disc_index"),
            pl.coalesce([pl.col("year"), pl.col("originalyear")]).cast(pl.Int64).alias("year_effective"),
            pl.col("__file_mod_datetime_raw").cast(pl.Int64).alias("timestamp"),
            pl.col("__file_mod_datetime_raw").cast(pl.Int64).alias("added_time"),
            pl.col("__file_mod_datetime_raw").cast(pl.Int64).alias("updated_time"),
            pl.col("__file_size_bytes").cast(pl.Int64).alias("filesize"),
            pl.col("__file_size_bytes").cast(pl.Int64).alias("audio_size"),
            pl.col("__length_seconds").cast(pl.Float64).alias("secs"),
            pl.lit(0).alias("audio_offset"),
            pl.when(pl.col("analysis").is_not_null() & (pl.col("analysis") != ""))
            .then(pl.lit(1))
            .otherwise(pl.lit(0))
            .cast(pl.Int8)
            .alias("musicmagic_mixable"),
            pl.col("lyrics").fill_null(pl.col("unsyncedlyrics")).alias("lyrics_combined"),
            pl.when(pl.col("explicit").cast(pl.Int64) > 0).then(pl.lit(1)).otherwise(pl.lit(0)).alias("drm"),
            pl.col("__filetype").str.to_lowercase().alias("content_type"),
            pl.col("__bitrate").alias("vbr_scale"),
            pl.col("__bitrate_num").cast(pl.Float64).alias("bitrate"),
            pl.col("__frequency_num").cast(pl.Int64).alias("samplerate"),
            pl.col("__bitspersample").cast(pl.Int64).alias("samplesize"),
            pl.col("__channels").cast(pl.Int64).alias("channels"),
            pl.col("__bpm").cast(pl.Int64).alias("bpm"),
            pl.col("__version").alias("tagversion"),
            pl.col("compilation").fill_null(0).cast(pl.Int8).alias("compilation_tag"),
            pl.col("amgtagged").fill_null(0).cast(pl.Int8).alias("amg_flag"),
            pl.concat_str(
                [
                    pl.col("album").fill_null(""),
                    pl.col("albumartist").fill_null(""),
                    pl.col("musicbrainz_albumid").fill_null(""),
                    pl.col("disc_index").fill_null(0).cast(pl.Utf8),
                ],
                separator="\\u241F",
            ).alias("album_token"),
        ])
        return df

    # ------------------------------------------------------------------
    def _build_albums(self, df: pl.DataFrame) -> pl.DataFrame:
        grouped = (
            df.groupby("album_token", maintain_order=True)
            .agg(
                [
                    pl.first("album").alias("title"),
                    pl.first("albumartist").alias("albumartist"),
                    pl.first("musicbrainz_albumartistid").alias("albumartist_mbid"),
                    pl.first("musicbrainz_albumid").alias("musicbrainz_id"),
                    pl.first("album_titlesort").alias("album_titlesort"),
                    pl.first("album_titlesearch").alias("album_titlesearch"),
                    pl.first("year_effective").alias("year"),
                    pl.min("disc_index").alias("disc"),
                    pl.max("disc_index").alias("discc"),
                    pl.first("replaygain_album_gain").alias("replay_gain"),
                    pl.first("replaygain_album_peak").alias("replay_peak"),
                    pl.max("amg_flag").alias("musicmagic_mixable"),
                    pl.max("compilation_tag").alias("comp_flag"),
                    pl.n_unique("artist").alias("artist_variants"),
                ]
            )
            .with_columns(
                [
                    pl.when(pl.col("comp_flag") > 0)
                    .then(pl.lit(1))
                    .when((pl.col("artist_variants") > 1) & (pl.col("albumartist") == ""))
                    .then(pl.lit(1))
                    .otherwise(pl.lit(0))
                    .cast(pl.Int8)
                    .alias("compilation"),
                    pl.col("title").map_elements(normalize_sort_key).alias("titlesort"),
                    pl.col("title").map_elements(normalize_search_key).alias("titlesearch"),
                    pl.struct(["title", "albumartist"])
                    .map_elements(normalize_custom_search)
                    .alias("customsearch"),
                ]
            )
        )
        grouped = grouped.with_row_count(name="id", offset=1)
        grouped = grouped.select(
            [
                "id",
                "title",
                "titlesort",
                "titlesearch",
                "customsearch",
                "compilation",
                "year",
                pl.lit(None).alias("artwork"),
                "disc",
                "discc",
                "replay_gain",
                "replay_peak",
                "musicbrainz_id",
                pl.col("musicmagic_mixable").cast(pl.Int8).alias("musicmagic_mixable"),
                pl.lit(None).alias("contributor"),
                "album_token",
                "albumartist",
                "albumartist_mbid",
            ]
        )
        return grouped

    # ------------------------------------------------------------------
    def _attach_album_ids(self, df: pl.DataFrame, albums: pl.DataFrame) -> pl.DataFrame:
        lookup = dict(zip(albums["album_token"].to_list(), albums["id"].to_list()))
        mapper = lambda token: lookup.get(token)  # noqa: E731
        return df.with_columns(pl.col("album_token").map_elements(mapper).alias("album_id"))

    # ------------------------------------------------------------------
    def _build_tracks_table(self, df: pl.DataFrame) -> pl.DataFrame:
        url_md5 = df.select(pl.col("url").map_elements(md5_hex).alias("urlmd5"))
        df = df.hstack(url_md5)
        frame = df.select(
            [
                pl.col("track_id").alias("id"),
                "url",
                "title",
                "titlesort",
                "titlesearch",
                "customsearch",
                pl.col("album_id").alias("album"),
                pl.col("track").cast(pl.Int64).alias("tracknum"),
                "content_type",
                "timestamp",
                "filesize",
                "audio_size",
                "audio_offset",
                pl.col("year_effective").alias("year"),
                "secs",
                pl.lit(None).alias("cover"),
                "vbr_scale",
                "bitrate",
                "samplerate",
                "samplesize",
                "channels",
                pl.lit(None).alias("block_alignment"),
                pl.lit(None).alias("endian"),
                "bpm",
                "tagversion",
                "drm",
                pl.col("disc_index").alias("disc"),
                pl.lit(1).alias("audio"),
                pl.lit(0).alias("remote"),
                "lossless",
                pl.col("lyrics_combined").alias("lyrics"),
                pl.col("musicbrainz_trackid").alias("musicbrainz_id"),
                "musicmagic_mixable",
                pl.col("replaygain_track_gain").alias("replay_gain"),
                pl.col("replaygain_track_peak").alias("replay_peak"),
                pl.col("tagminder_uuid").alias("extid"),
                pl.lit(None).alias("primary_artist"),
                "urlmd5",
                pl.lit(None).alias("coverid"),
                pl.lit(None).alias("cover_cached"),
                pl.lit(0).alias("virtual"),
                "added_time",
                "updated_time",
            ]
        )
        return frame

    # ------------------------------------------------------------------
    def _build_contributors(
        self, df: pl.DataFrame
    ) -> Tuple[
        pl.DataFrame,
        pl.DataFrame,
        pl.DataFrame,
        Dict[int, Optional[int]],
        Dict[Tuple[str, str], int],
    ]:
        rows = df.select(
            [
                "track_id",
                "album_id",
                "artist",
                "albumartist",
                "composer",
                "conductor",
                "ensemble",
                "band",
                "orchestra",
                "musicbrainz_artistid",
                "musicbrainz_albumartistid",
                "musicbrainz_composerid",
                "musicbrainz_conductorid",
                "musicbrainz_ensembleid",
            ]
        ).to_dicts()

        registry: Dict[Tuple[str, Optional[str]], Dict[str, object]] = {}
        contributor_track_rows: set[Tuple[int, int, int]] = set()
        contributor_album_rows: set[Tuple[int, int, int]] = set()
        primary_artist_map: Dict[int, Optional[int]] = {}
        next_id = 1

        for row in rows:
            track_id = row["track_id"]
            album_id = row.get("album_id")

            for role in ROLE_DEFS:
                for tag in role.tag_names:
                    raw = row.get(tag)
                    if not raw:
                        continue
                    names = split_multi_value(raw)
                    mbid_column = self._mbid_column_for_tag(row, role, tag)
                    mbids = split_multi_value(mbid_column) if mbid_column else [None] * len(names)
                    if len(mbids) != len(names):
                        if mbids:
                            mbids = mbids + [mbids[-1]] * (len(names) - len(mbids))
                        else:
                            mbids = [None] * len(names)
                    for name, mbid in zip(names, mbids):
                        key = (normalize_search_key(name), mbid)
                        if key not in registry:
                            registry[key] = {
                                "id": next_id,
                                "name": name,
                                "namesort": normalize_sort_key(name),
                                "namesearch": normalize_search_key(name),
                                "customsearch": normalize_search_key(name),
                                "musicbrainz_id": mbid,
                            }
                            next_id += 1
                        contributor_id = registry[key]["id"]
                        contributor_track_rows.add((role.role_id, contributor_id, track_id))
                        if album_id:
                            contributor_album_rows.add((role.role_id, contributor_id, album_id))
                        if role.role_id == 6 and track_id not in primary_artist_map:
                            primary_artist_map[track_id] = contributor_id

            if track_id not in primary_artist_map:
                albumartist = row.get("albumartist") or None
                if albumartist:
                    key = (normalize_search_key(albumartist), row.get("musicbrainz_albumartistid"))
                    if key not in registry:
                        registry[key] = {
                            "id": next_id,
                            "name": albumartist,
                            "namesort": normalize_sort_key(albumartist),
                            "namesearch": normalize_search_key(albumartist),
                            "customsearch": normalize_search_key(albumartist),
                            "musicbrainz_id": row.get("musicbrainz_albumartistid"),
                        }
                        next_id += 1
                    primary_artist_map[track_id] = registry[key]["id"]

        records = sorted(registry.values(), key=lambda entry: entry["id"])
        contributors_df = pl.DataFrame(
            {
                "id": [entry["id"] for entry in records],
                "name": [entry["name"] for entry in records],
                "namesort": [entry["namesort"] for entry in records],
                "namesearch": [entry["namesearch"] for entry in records],
                "customsearch": [entry["customsearch"] for entry in records],
                "musicbrainz_id": [entry["musicbrainz_id"] for entry in records],
                "musicmagic_mixable": [0] * len(records),
            }
        ) if records else pl.DataFrame(
            {
                "id": [],
                "name": [],
                "namesort": [],
                "namesearch": [],
                "customsearch": [],
                "musicbrainz_id": [],
                "musicmagic_mixable": [],
            }
        )

        contributor_track_df = (
            pl.DataFrame(list(contributor_track_rows), schema=["role", "contributor", "track"])
            if contributor_track_rows
            else pl.DataFrame({"role": [], "contributor": [], "track": []})
        )
        contributor_album_df = (
            pl.DataFrame(list(contributor_album_rows), schema=["role", "contributor", "album"])
            if contributor_album_rows
            else pl.DataFrame({"role": [], "contributor": [], "album": []})
        )
        contributor_lookup = {
            (entry["namesearch"], (entry["musicbrainz_id"] or "")): entry["id"] for entry in records
        }
        return (
            contributors_df,
            contributor_track_df,
            contributor_album_df,
            primary_artist_map,
            contributor_lookup,
        )

    # ------------------------------------------------------------------
    def _build_genres(self, df: pl.DataFrame) -> Tuple[pl.DataFrame, pl.DataFrame]:
        rows = df.select(["track_id", "genre", "style"]).to_dicts()
        registry: Dict[str, Dict[str, object]] = {}
        track_pairs: set[Tuple[int, int]] = set()
        next_id = 1
        for row in rows:
            track_id = row["track_id"]
            raw_values: List[str] = []
            for field in ("genre", "style"):
                raw_values.extend(split_multi_value(row.get(field)))
            for value in raw_values:
                key = normalize_search_key(value)
                if key not in registry:
                    registry[key] = {
                        "id": next_id,
                        "name": value,
                        "namesort": normalize_sort_key(value),
                        "namesearch": key,
                        "customsearch": key,
                    }
                    next_id += 1
                track_pairs.add((registry[key]["id"], track_id))

        if registry:
            genres_df = pl.DataFrame(
                {
                    "id": [entry["id"] for entry in registry.values()],
                    "name": [entry["name"] for entry in registry.values()],
                    "namesort": [entry["namesort"] for entry in registry.values()],
                    "namesearch": [entry["namesearch"] for entry in registry.values()],
                    "customsearch": [entry["customsearch"] for entry in registry.values()],
                    "musicmagic_mixable": [0] * len(registry),
                }
            )
        else:
            genres_df = pl.DataFrame({
                "id": [],
                "name": [],
                "namesort": [],
                "namesearch": [],
                "customsearch": [],
                "musicmagic_mixable": [],
            })

        genre_track_df = (
            pl.DataFrame(list(track_pairs), schema=["genre", "track"])
            if track_pairs
            else pl.DataFrame({"genre": [], "track": []})
        )
        return genres_df, genre_track_df

    # ------------------------------------------------------------------
    def _apply_primary_artists(self, tracks: pl.DataFrame, primary_artist_map: Dict[int, Optional[int]]) -> pl.DataFrame:
        mapper = lambda track_id: primary_artist_map.get(track_id)
        return tracks.with_columns(pl.col("id").map_elements(mapper).alias("primary_artist"))

    # ------------------------------------------------------------------
    def _assign_album_contributors(
        self, albums: pl.DataFrame, contributor_lookup: Dict[Tuple[str, str], int]
    ) -> pl.DataFrame:
        def resolver(row: Dict[str, Optional[str]]) -> Optional[int]:
            name = row.get("albumartist") or ""
            if not name:
                return None
            mbid = row.get("albumartist_mbid") or ""
            return contributor_lookup.get((normalize_search_key(name), mbid))

        return albums.with_columns(
            pl.struct(["albumartist", "albumartist_mbid"]).map_elements(resolver).alias("contributor")
        )

    # ------------------------------------------------------------------
    @staticmethod
    def _albums_storage_view(albums: pl.DataFrame) -> pl.DataFrame:
        keep = [
            "id",
            "title",
            "titlesort",
            "titlesearch",
            "customsearch",
            "compilation",
            "year",
            "artwork",
            "disc",
            "discc",
            "replay_gain",
            "replay_peak",
            "musicbrainz_id",
            "musicmagic_mixable",
            "contributor",
        ]
        return albums.select(keep)

    # ------------------------------------------------------------------
    def _connect_target(self) -> sqlite3.Connection:
        if not self.library_db.exists():
            raise RuntimeError(
                f"Target library database {self.library_db} does not exist. Start Lyrion once to bootstrap it."
            )
        conn = sqlite3.connect(self.library_db)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA synchronous=NORMAL")
        conn.execute("PRAGMA temp_store=MEMORY")
        conn.execute("PRAGMA cache_size=-200000")
        return conn

    # ------------------------------------------------------------------
    def _ensure_schema(self, conn: sqlite3.Connection) -> None:
        for table in self.REQUIRED_TABLES:
            if not self._table_exists(conn, table):
                raise RuntimeError(
                    f"Table '{table}' missing from {self.library_db}. Provide a server-initialized library.db first."
                )

    # ------------------------------------------------------------------
    @staticmethod
    def _table_exists(conn: sqlite3.Connection, table: str) -> bool:
        cursor = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?", (table,)
        )
        return cursor.fetchone() is not None

    # ------------------------------------------------------------------
    def _reset_tables(self, conn: sqlite3.Connection) -> None:
        tables = [
            "tracks",
            "albums",
            "contributors",
            "contributor_track",
            "contributor_album",
            "genres",
            "genre_track",
            "playlist_track",
            "comments",
            "library_track",
            "library_album",
            "library_contributor",
            "library_genre",
        ]
        for table in tables:
            if self._table_exists(conn, table):
                conn.execute(f"DELETE FROM {table}")
        conn.execute("DELETE FROM metainformation WHERE name IN ('isScanning','lastRescanTime','lastFullRescanTime','lastRescanTimeIsDST','scanChangeCount')")

    # ------------------------------------------------------------------
    def _bulk_insert(self, conn: sqlite3.Connection, table: str, frame: pl.DataFrame) -> None:
        if frame.is_empty():
            LOG.debug("Skipping %s insert (no rows)", table)
            return
        columns = frame.columns
        placeholders = ",".join(["?"] * len(columns))
        sql = f"INSERT INTO {table} ({','.join(columns)}) VALUES ({placeholders})"
        cursor = conn.cursor()
        for batch in frame.iter_slices(n_rows=self.chunk_size):
            cursor.executemany(sql, batch.rows())
        conn.commit()

    # ------------------------------------------------------------------
    def _refresh_metainformation(self, conn: sqlite3.Connection, track_count: int) -> None:
        now = self._now
        entries = {
            "isScanning": "0",
            "lastRescanTime": str(now),
            "lastFullRescanTime": str(now),
            "lastRescanTimeIsDST": "1" if time.localtime(now).tm_isdst else "0",
            "scanChangeCount": str(track_count),
        }
        for name, value in entries.items():
            conn.execute(
                "INSERT INTO metainformation (name, value) VALUES (?, ?) ON CONFLICT(name) DO UPDATE SET value=excluded.value",
                (name, value),
            )
        conn.commit()

    # ------------------------------------------------------------------
    def _maybe_rebuild_virtual_tables(self, conn: sqlite3.Connection) -> None:
        # Leave virtual library tables empty; LMS will rebuild them lazily when virtual libraries are enabled.
        pass

    # ------------------------------------------------------------------
    def _maybe_rebuild_fts(self, conn: sqlite3.Connection) -> None:
        if not self.fts_sql:
            LOG.info("Full Text Search rebuild skipped (no SQL template provided)")
            return
        script = Path(self.fts_sql).read_text(encoding="utf-8")
        conn.executescript("DELETE FROM fulltext; DELETE FROM fulltext_terms;")
        conn.executescript(script)
        conn.commit()

    # ------------------------------------------------------------------
    @staticmethod
    def _mbid_column_for_tag(row: dict, role: RoleDefinition, tag: str) -> Optional[str]:
        candidate = f"musicbrainz_{tag}id"
        if candidate in row and row[candidate]:
            return row[candidate]
        for column in role.mbid_tags:
            if column in row and row[column]:
                return row[column]
        return None


# ---------------------------------------------------------------------------
def normalize_sort_key(value: Optional[str]) -> str:
    if not value:
        return ""
    ascii_text = ascii_fold(value)
    lower = ascii_text.lower()
    for article in ARTICLES:
        if lower.startswith(article + " "):
            lower = lower[len(article) + 1 :]
            break
    collapsed = PUNCT_RE.sub(" ", lower)
    return collapsed.strip().upper()


def normalize_search_key(value: Optional[str]) -> str:
    if not value:
        return ""
    ascii_text = ascii_fold(value)
    collapsed = PUNCT_RE.sub(" ", ascii_text.lower())
    return collapsed.strip().upper()


def normalize_custom_search(row: dict) -> str:
    title = row.get("title") or ""
    secondary = row.get("subtitle") or row.get("albumartist") or ""
    merged = f"{title} {secondary}".strip()
    return normalize_search_key(merged)


def ascii_fold(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    return "".join(ch for ch in normalized if not unicodedata.combining(ch))


def split_multi_value(raw: Optional[str]) -> List[str]:
    if not raw:
        return []
    parts = [segment.strip() for segment in str(raw).split(MULTI_VALUE_DELIM)]
    return [segment for segment in parts if segment]


def file_url_from_path(path: str) -> str:
    resolved = Path(path).expanduser().resolve()
    return "file://" + quote(str(resolved))


def path_extension(path: str) -> str:
    return Path(path).suffix.lower().lstrip('.')


def detect_lossless(path: str) -> int:
    ext = path_extension(path)
    return 1 if ext in LOSSLESS_EXTS else 0


def md5_hex(value: str) -> str:
    return hashlib.md5(value.encode("utf-8")).hexdigest()


# ---------------------------------------------------------------------------
def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Rebuild library.db using Polars staging data")
    parser.add_argument("--alib", required=True, type=Path, help="Path to the staging SQLite database containing the alib table")
    parser.add_argument("--library-db", required=True, type=Path, help="Path to the target library.db to overwrite")
    parser.add_argument("--threads", type=int, default=None, help="Limit the number of Polars worker threads")
    parser.add_argument("--chunk-size", type=int, default=2000, help="Rows per SQLite executemany batch")
    parser.add_argument("--fts-sql", type=Path, default=None, help="Optional SQL script that rebuilds fulltext/fulltext_terms")
    parser.add_argument("--verbose", action="store_true", help="Enable debug logging")
    return parser.parse_args(argv)


def main(argv: Optional[Sequence[str]] = None) -> None:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s :: %(message)s",
    )
    scanner = PolarsScanner(
        alib_path=args.alib,
        library_db=args.library_db,
        max_threads=args.threads,
        chunk_size=args.chunk_size,
        fts_sql=args.fts_sql,
    )
    scanner.run()


if __name__ == "__main__":
    main()
