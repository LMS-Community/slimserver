# Polars Scanner – `alib` → `library.db` Mapping

The Python-based scanner consumes the staging table `alib` (produced by `tags2db-polars-multidrive-optimised.py`) and reproduces the database layout that the legacy Perl scanner leaves in `library.db`.  The mapping below documents how every field is derived.  Column names prefixed with `__` come directly from the staging table, while others are tag fields extracted by `audioinfo`.

## Tracks (`tracks`)

| `tracks` column | Source in `alib` | Notes |
| --- | --- | --- |
| `url` | `fileURL(__path)` | Stored as `file://` URL (same encoding as `Slim::Utils::Misc::fileURLFromPath`). |
| `title` | `title` | Raw tag value.
| `titlesort` | `title` | `Slim::Utils::Text::ignoreCaseArticles()` equivalent (upper-case, articles stripped, punctuation removed).
| `titlesearch` | `title` | `ignoreCase()` equivalent (case-insensitive, no article stripping).
| `customsearch` | `title` + `subtitle` | Concatenated and normalized identical to Perl scanner.
| `album` | FK produced from `album` table mapping | Deterministic key: (`album`, `albumartist`, `musicbrainz_albumid`, `discnumber`, `compilation`).
| `tracknum` | `track` | Parsed to integer; zero if missing.
| `content_type` | `__filetype` | Lower-case; same values server uses (e.g., `flc`, `mp3`).
| `timestamp` | `__file_mod_datetime_raw` | Seconds since epoch; float accepted.
| `filesize` | `__file_size_bytes` | Integer bytes.
| `audio_size` | `__file_size_bytes` | Same as `filesize` when full file scanned.
| `audio_offset` | `0` | Not tracked in staging data.
| `year` | `year` or fallback `originalyear` | Prefer release year; integer.
| `secs` | `__length_seconds` | Float seconds with millisecond precision.
| `cover` | `NULL` | Artwork from file is handled later by LMS.
| `vbr_scale` | `__bitrate` | Retained as text description.
| `bitrate` | `__bitrate_num` | Numeric kbps; converted from string if needed.
| `samplerate` | `__frequency_num` | Integer Hz.
| `samplesize` | `__bitspersample` | Integer.
| `channels` | `__channels` | Integer.
| `block_alignment` | `NULL` | Not exposed by `alib`.
| `endian` | `NULL` | Not exposed.
| `bpm` | `__bpm` if present | New tag fallback.
| `tagversion` | `__version` | 
| `drm` | `explicit` flag | 1 for DRM/explicit when flagged.
| `disc` | `disc` or `discnumber` | Integer disc index.
| `audio` | `1` | All staged files are audio.
| `remote` | `0` | Staging only contains local files.
| `lossless` | Derived from extension (`flac`,`alac`,`wv`,`aiff`,`ape`) | Boolean flag.
| `lyrics` | `lyrics` or `unsyncedlyrics` | UTF-8 text.
| `musicbrainz_id` | `musicbrainz_trackid` | 36-char UUID.
| `musicmagic_mixable` | `analysis` | Set to 1 when the `analysis` tag is non-null, otherwise 0.
| `replay_gain` | `replaygain_track_gain` | Normalized float.
| `replay_peak` | `replaygain_track_peak` | Float.
| `extid` | `tagminder_uuid` | Custom stable GUID for track.
| `urlmd5` | `md5(url)` | 32-char hex, same as Perl scanner.
| `coverid` | `NULL` | Populated later by LMS artwork pipeline.
| `cover_cached` | `NULL` |
| `virtual` | `0` | Only physical files handled.
| `added_time` | `__file_mod_datetime_raw` | Mirrors `updated_time` like the Perl scanner.
| `updated_time` | `__file_mod_datetime_raw` | Same as `timestamp`.

Any column not backed by staging data is set to `NULL` to allow LMS to fill it later.

## Albums (`albums`)

| Column | Source | Notes |
| --- | --- | --- |
| `title` | `album` |
| `titlesort` | `album` | `ignoreCaseArticles()`.
| `titlesearch` | `album` | `ignoreCase()`.
| `customsearch` | `album` + `albumartist` | Same logic as Perl scanner.
| `compilation` | `compilation` tag or heuristics | 1 if tagged or if there are multiple track artists and no albumartist tag.
| `year` | `year` or `originalyear` |
| `artwork` | `NULL` | Linked once tracks inserted.
| `disc` | minimum disc number |
| `discc` | maximum disc count across album |
| `replay_gain` / `replay_peak` | album-level replaygain tags |
| `musicbrainz_id` | `musicbrainz_albumid` |
| `musicmagic_mixable` | `amgtagged` |
| `contributor` | FK to album-artist `contributors.id` | Derived from albumartist tag or fallback to track artist.

Albums are keyed by (`title`,`albumartist`,`musicbrainz_albumid`,`discc`,`compilation`).

## Contributors (`contributors`)

Names are taken from the respective tag fields (artist, albumartist, composer, conductor, etc.).  For each role we:

1. Split multi-value tags using the `\\` literal delimiter (same as staging file).
2. Normalize `namesort` (`ignoreCaseArticles`), `namesearch` (`ignoreCase`), and transliterate to ASCII for indexes.
3. Store MusicBrainz IDs where available (e.g., `musicbrainz_artistid`, `musicbrainz_albumartistid`, etc.).

Roles follow the LMS internal IDs:

| Role | ID | `alib` column(s) |
| --- | --- | --- |
| ARTIST | 1 | `artist` |
| COMPOSER | 2 | `composer` |
| CONDUCTOR | 3 | `conductor` |
| BAND | 4 | `ensemble`, `band`, `orchestra` |
| ALBUMARTIST | 5 | `albumartist` |
| TRACKARTIST | 6 | `artist` (when distinct per track) |

Custom roles defined in `userDefinedRoles` (from `server.prefs`) are appended, preserving their IDs (≥ 21) so plugins continue to work.

`contributor_track` receives one row per `(track_id, role_id, contributor_id)` triple, and `contributor_album` aggregates `(album_id, role_id, contributor_id)` to mirror the Perl scanner’s behavior.

## Genres (`genres`, `genre_track`)

Tags `genre` and `style` are combined.  Each multi-value tag is split on the `\\` delimiter, normalized using the same case-folding as contributors, inserted (deduped) into `genres`, and related to tracks through `genre_track`.  `mood` and `theme` stay as plain tags and are not mapped to `genres`.

## Playlist & Comments

When `alib` exposes playlist or comment metadata:

- `playlist_track` gets rebuilt from staged playlist rows (path stored under `__path` with `__tag == 'playlist'`).  For now the scanner preserves existing playlist rows because staging focuses on audio files; LMS will rebuild playlists on demand.
- `comments` table receives `review`/`lyrics` style annotations keyed by track ID.

## Virtual Libraries & Release Types

After the core tables are populated:

1. `library_track`, `library_album`, `library_contributor`, and `library_genre` are regenerated when virtual libraries are enabled (matching the SQL found in `Slim/Music/VirtualLibraries.pm`).
2. Release type hints run the same queries as `Slim::Music::ReleaseTypes` to update `albums.release_type` for Singles/EPs.

## Full Text Search (optional)

If the Full Text Search plugin is enabled (`plugin.fulltext` pref), the scanner rebuilds `fulltext` and `fulltext_terms` with the SQL templates embedded in `Slim::Plugin::FullTextSearch::Plugin`.  The resulting tables are byte-for-byte compatible with the plugin’s importer, meaning LMS will not trigger another FTS rebuild when it starts.

---

This mapping guarantees that every table `scanner.pl` touches is populated with equivalent data, enabling the new Polars-based scanner to be a drop-in replacement.
