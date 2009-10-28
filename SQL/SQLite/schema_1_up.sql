
CREATE TABLE IF NOT EXISTS metainformation (
  name  varchar(255) NOT NULL DEFAULT '',
  value varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY (name)
);

--
-- Table: rescans
--
DROP TABLE IF EXISTS rescans;
CREATE TABLE rescans (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  files_scanned int(10),
  files_to_scan int(10),
  start_time int(10),
  end_time int(10)
);

--
-- Table: unreadable_tracks
--
DROP TABLE IF EXISTS unreadable_tracks;
CREATE TABLE unreadable_tracks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  rescan int(10),
  url text NOT NULL,
  reason text NOT NULL
);
CREATE INDEX unreadableRescanIndex ON unreadable_tracks (rescan);
--
-- Table: tracks
--
DROP TABLE IF EXISTS tracks;
CREATE TABLE tracks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  url text NOT NULL,
  title blob,
  titlesort text,
  titlesearch text,
  customsearch text,
  album int(10),
  tracknum int(10),
  content_type varchar(255),
  timestamp int(10),
  filesize int(10),
  audio_size int(10),
  audio_offset int(10),
  year smallint(5),
  secs float,
  cover blob,
  vbr_scale varchar(255),
  bitrate float,
  samplerate int(10),
  samplesize int(10),
  channels tinyint(1),
  block_alignment int(10),
  endian  bool,
  bpm smallint(5),
  tagversion varchar(255),
  drm bool,
  disc tinyint(1),
  audio bool,
  remote bool,
  lossless bool,
  lyrics text, -- needs to be text so that searches are case insensitive.
  musicbrainz_id varchar(40),	-- musicbrainz uuid (36 bytes of text)
  musicmagic_mixable bool,
  replay_gain float,
  replay_peak float,
  extid varchar(64),
  FOREIGN KEY (`album`) REFERENCES `albums` (`id`) ON DELETE CASCADE
);
CREATE INDEX trackTitleIndex ON tracks (title);
CREATE INDEX trackAlbumIndex ON tracks (album);
CREATE INDEX ctSortIndex ON tracks (content_type);
CREATE INDEX trackSortIndex ON tracks (titlesort);
CREATE INDEX trackSearchIndex ON tracks (titlesearch);
CREATE INDEX trackCustomSearchIndex ON tracks (customsearch);
CREATE INDEX trackBitrateIndex ON tracks (bitrate);
CREATE INDEX trackDiscIndex ON tracks (disc);
CREATE INDEX trackFilesizeIndex ON tracks (filesize);
CREATE INDEX trackTimestampIndex ON tracks (timestamp);
CREATE INDEX trackTracknumIndex ON tracks (tracknum);
CREATE INDEX trackAudioIndex ON tracks (audio);
CREATE INDEX trackLyricsIndex ON tracks (lyrics);
CREATE INDEX trackRemoteIndex ON tracks (remote);
CREATE INDEX trackLosslessIndex ON tracks (lossless);
CREATE INDEX urlIndex ON tracks (url);
CREATE INDEX trackExtId ON tracks (extid);

--
-- Table: playlist_track
--
DROP TABLE IF EXISTS playlist_track;
CREATE TABLE playlist_track (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  position  int(10),
  playlist  int(10),
  track  int(10),
  FOREIGN KEY (`track`) REFERENCES `tracks` (`id`) ON DELETE CASCADE,
  FOREIGN KEY (`playlist`) REFERENCES `tracks` (`id`) ON DELETE CASCADE
);
CREATE INDEX trackIndex ON playlist_track (track);
CREATE INDEX positionIndex ON playlist_track (position);
CREATE INDEX playlistIndex ON playlist_track (playlist);

--
-- Table: albums
--
DROP TABLE IF EXISTS albums;
CREATE TABLE albums (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title blob,
  titlesort text,
  titlesearch text,
  customsearch text,
  compilation bool,
  year  smallint(5),
  artwork char(8), -- pointer to a track coverid that contains artwork
  disc  tinyint(1),
  discc  tinyint(1),
  replay_gain float,
  replay_peak float,
  musicbrainz_id varchar(40),	-- musicbrainz uuid (36 bytes of text)
  musicmagic_mixable bool,
  contributor int(10)
);
CREATE INDEX albumsTitleIndex ON albums (title);
CREATE INDEX albumsSortIndex ON albums (titlesort);
CREATE INDEX albumsSearchIndex ON albums (titlesearch);
CREATE INDEX albumsCustomSearchIndex ON albums (customsearch);
CREATE INDEX compilationSortIndex ON albums (compilation);
CREATE INDEX albumsYearIndex ON albums (year);
CREATE INDEX albumsDiscIndex ON albums (disc);
CREATE INDEX albumsDiscCountIndex ON albums (discc);
CREATE INDEX albumsArtworkIndex ON albums (artwork);

--
-- Table: years
--
DROP TABLE IF EXISTS years;
CREATE TABLE years (
  id smallint(5),
  PRIMARY KEY (id)
);

--
-- Table: contributors
--
DROP TABLE IF EXISTS contributors;
CREATE TABLE contributors (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name blob,
  namesort text,
  namesearch text,
  customsearch text,
  musicbrainz_id varchar(40),	-- musicbrainz uuid (36 bytes of text)
  musicmagic_mixable bool
);
CREATE INDEX contributorsNameIndex ON contributors (name);
CREATE INDEX contributorsSortIndex ON contributors (namesort);
CREATE INDEX contributorsSearchIndex ON contributors (namesearch);
CREATE INDEX contributorsCustomSearchIndex ON contributors (customsearch);

--
-- Table: contributor_track
--
DROP TABLE IF EXISTS contributor_track;
CREATE TABLE contributor_track (
  role  int(10),
  contributor  int(10),
  track  int(10),
  PRIMARY KEY (role,contributor,track),
  FOREIGN KEY (`track`) REFERENCES `tracks` (`id`) ON DELETE CASCADE,
  FOREIGN KEY (`contributor`) REFERENCES `contributors` (`id`) ON DELETE CASCADE 
);
CREATE INDEX contributor_trackContribIndex ON contributor_track (contributor);
CREATE INDEX contributor_trackTrackIndex ON contributor_track (track);
CREATE INDEX contributor_trackRoleIndex ON contributor_track (role);

--
-- Table: contributor_album
--
DROP TABLE IF EXISTS contributor_album;
CREATE TABLE contributor_album (
  role  int(10),
  contributor  int(10),
  album  int(10),
  PRIMARY KEY (role,contributor,album),
  FOREIGN KEY (`album`) REFERENCES `albums` (`id`) ON DELETE CASCADE,
  FOREIGN KEY (`contributor`) REFERENCES `contributors` (`id`) ON DELETE CASCADE
);
CREATE INDEX contributor_albumContribIndex ON contributor_album (contributor);
CREATE INDEX contributor_albumAlbumIndex ON contributor_album (album);
CREATE INDEX contributor_albumRoleIndex ON contributor_album (role);

--
-- Table: genres
--
DROP TABLE IF EXISTS genres;
CREATE TABLE genres (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name blob,
  namesort text,
  namesearch text,
  customsearch text,
  musicmagic_mixable bool
);
CREATE INDEX genreNameIndex ON genres (name);
CREATE INDEX genreSortIndex ON genres (namesort);
CREATE INDEX genreSearchIndex ON genres (namesearch);
CREATE INDEX genreCustomSearchIndex ON genres (customsearch);

--
-- Table: genre_track
--
DROP TABLE IF EXISTS genre_track;
CREATE TABLE genre_track (
  genre  int(10),
  track  int(10),
  PRIMARY KEY (genre,track),
  FOREIGN KEY (`track`) REFERENCES `tracks` (`id`) ON DELETE CASCADE,
  FOREIGN KEY (`genre`) REFERENCES `genres` (`id`) ON DELETE CASCADE
);
CREATE INDEX genre_trackGenreIndex ON genre_track (genre);
CREATE INDEX genre_trackTrackIndex ON genre_track (track);

--
-- Table: comments
--
DROP TABLE IF EXISTS comments;
CREATE TABLE comments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  track  int(10),
  value text, -- needs to be text so that searches are case insensitive.
  FOREIGN KEY (`track`) REFERENCES `tracks` (`id`) ON DELETE CASCADE
);
CREATE INDEX comments_trackIndex ON comments (track);

--
-- Table: pluginversion
--
DROP TABLE IF EXISTS pluginversion;
CREATE TABLE pluginversion (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name varchar(255),
  version  int(10)
);
