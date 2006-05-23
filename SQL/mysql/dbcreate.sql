-- Increment the version below when you change the schema.
-- You also need to add an Upgrade script to the Upgrades 
-- directory and alter sql.version

-- It's important that there is a newline between all 
-- SQL statements, otherwise the parser will skip them.

SET foreign_key_checks = 0;

--
-- Table: metainformation
--
CREATE TABLE metainformation (
  version  int(10) unsigned,
  track_count  int(10) unsigned,
  total_time  int(10) unsigned,
  last_rescan_time int(10) unsigned
) TYPE=InnoDB;

INSERT INTO metainformation VALUES (18, 0, 0, 0);

--
-- Table: rescans
--
CREATE TABLE rescans (
  id int(10) unsigned NOT NULL auto_increment,
  files_scanned int(10) unsigned,
  files_to_scan int(10) unsigned,
  start_time int(10) unsigned,
  end_time int(10) unsigned,
  PRIMARY KEY (id)
) TYPE=InnoDB;

--
-- Table: unreadable_tracks
--
CREATE TABLE unreadable_tracks (
  id int(10) unsigned NOT NULL auto_increment,
  rescan int(10) unsigned,
  url text NOT NULL,
  reason text NOT NULL,
  PRIMARY KEY (id),
  INDEX unreadableRescanIndex (rescan)
) TYPE=InnoDB;

--
-- Table: tracks
--
CREATE TABLE tracks (
  id int(10) unsigned NOT NULL auto_increment,
  url text NOT NULL,
  title text,
  titlesort text,
  titlesearch text,
  customsearch text,
  album  int(10) unsigned,
  tracknum  int(10) unsigned,
  content_type varchar(255),
  tag  int(10) unsigned,
  timestamp  int(10) unsigned,
  filesize  int(10) unsigned,
  audio_size  int(10) unsigned,
  audio_offset  int(10) unsigned,
  year  smallint(5) unsigned,
  secs  float unsigned,
  cover varchar(255),
  thumb varchar(255),
  vbr_scale varchar(255),
  bitrate  float unsigned,
  samplerate  int(10) unsigned,
  samplesize  int(10) unsigned,
  channels  tinyint(1) unsigned,
  block_alignment  int(10) unsigned,
  endian  tinyint(1) unsigned,
  bpm  smallint(5) unsigned,
  tagversion varchar(255),
  drm  tinyint(1) unsigned,
  rating tinyint(1) unsigned,
  disc tinyint(1) unsigned,
  playCount int(10) unsigned,
  lastPlayed int(10) unsigned,
  audio tinyint(1) unsigned,
  remote tinyint(1) unsigned,
  lossless tinyint(1) unsigned,
  lyrics  text,
  moodlogic_id  int(10) unsigned,
  moodlogic_mixable  tinyint(1) unsigned,
  musicbrainz_id varchar(40),	-- musicbrainz uuid (36 bytes of text)
  musicmagic_mixable  tinyint(1) unsigned,
  replay_gain float,
  replay_peak float,
  multialbumsortkey  text,
  INDEX trackTitleIndex (title(255)),
  INDEX trackAlbumIndex (album),
  INDEX ctSortIndex (content_type),
  INDEX trackSortIndex (titlesort(255)),
  INDEX trackSearchIndex (titlesearch(255)),
  INDEX trackCustomSearchIndex (customsearch(255)),
  INDEX trackRatingIndex (rating),
  INDEX trackPlayCountIndex (playCount),
  INDEX trackAudioIndex (audio),
  INDEX trackRemoteIndex (remote),
  INDEX trackLosslessIndex (lossless),
  INDEX trackSortKeyIndex (multialbumsortkey(255)),
  INDEX urlIndex (url(255)),
  PRIMARY KEY (id),
--  UNIQUE KEY (url),
  FOREIGN KEY (`album`) REFERENCES `albums` (`id`) ON DELETE CASCADE
) TYPE=InnoDB CHARACTER SET utf8;

--
-- Table: playlist_track
--
CREATE TABLE playlist_track (
  id int(10) unsigned NOT NULL auto_increment,
  position  int(10) unsigned,
  playlist  int(10) unsigned,
  track  int(10) unsigned,
  PRIMARY KEY (id),
  INDEX trackIndex (track),
  FOREIGN KEY (`track`) REFERENCES `tracks` (`id`) ON DELETE CASCADE
) TYPE=InnoDB CHARACTER SET utf8;

--
-- Table: albums
--
CREATE TABLE albums (
  id int(10) unsigned NOT NULL auto_increment,
  title text,
  titlesort text,
  titlesearch text,
  customsearch text,
  contributor int(10) unsigned,
  compilation tinyint(1) unsigned,
  year  smallint(5) unsigned,
  artwork int(10) unsigned, -- pointer to a track id that contains artwork
  disc  tinyint(1) unsigned,
  discc  tinyint(1) unsigned,
  replay_gain float,
  replay_peak float,
  musicbrainz_id varchar(40),	-- musicbrainz uuid (36 bytes of text)
  musicmagic_mixable tinyint(1) unsigned,
  INDEX albumsTitleIndex (title(255)),
  INDEX albumsSortIndex (titlesort(255)),
  INDEX albumsSearchIndex (titlesearch(255)),
  INDEX albumsCustomSearchIndex (customsearch(255)),
  INDEX compilationSortIndex (compilation),
  PRIMARY KEY (id)
) TYPE=InnoDB CHARACTER SET utf8;


-- Testing
--
-- Table: contributors
--
CREATE TABLE contributors (
  id int(10) unsigned NOT NULL auto_increment,
  name text,
  namesort text,
  namesearch text,
  customsearch text,
  moodlogic_id  int(10) unsigned,
  moodlogic_mixable tinyint(1) unsigned,
  musicbrainz_id varchar(40),	-- musicbrainz uuid (36 bytes of text)
  musicmagic_mixable tinyint(1) unsigned,
  INDEX contributorsNameIndex (name(255)),
  INDEX contributorsSortIndex (namesort(255)),
  INDEX contributorsSearchIndex (namesearch(255)),
  INDEX contributorsCustomSearchIndex (customsearch(255)),
  PRIMARY KEY (id)
) TYPE=InnoDB CHARACTER SET utf8;

--
-- Table: contributor_track
--
CREATE TABLE contributor_track (
  role  int(10) unsigned,
  contributor  int(10) unsigned,
  track  int(10) unsigned,
  INDEX contributor_trackContribIndex (contributor),
  INDEX contributor_trackTrackIndex (track),
  INDEX contributor_trackRoleIndex (role),
  PRIMARY KEY (role,contributor,track),
  FOREIGN KEY (`track`) REFERENCES `tracks` (`id`) ON DELETE CASCADE,
  FOREIGN KEY (`contributor`) REFERENCES `contributors` (`id`) ON DELETE CASCADE
) TYPE=InnoDB CHARACTER SET utf8;

--
-- Table: contributor_album
--
CREATE TABLE contributor_album (
  role  int(10) unsigned,
  contributor  int(10) unsigned,
  album  int(10) unsigned,
  INDEX contributor_trackContribIndex (contributor),
  INDEX contributor_trackAlbumIndex (album),
  INDEX contributor_trackRoleIndex (role),
  PRIMARY KEY (role,contributor,album),
  FOREIGN KEY (`album`) REFERENCES `albums` (`id`) ON DELETE CASCADE,
  FOREIGN KEY (`contributor`) REFERENCES `contributors` (`id`) ON DELETE CASCADE
) TYPE=InnoDB CHARACTER SET utf8;

--
-- Table: genres
--
CREATE TABLE genres (
  id int(10) unsigned NOT NULL auto_increment,
  name text,
  namesort text,
  namesearch text,
  customsearch text,
  moodlogic_id  int(10) unsigned,
  moodlogic_mixable tinyint(1) unsigned,
  musicmagic_mixable tinyint(1) unsigned,
  INDEX genreNameIndex (name(255)),
  INDEX genreSortIndex (namesort(255)),
  INDEX genreSearchIndex (namesearch(255)),
  INDEX genreCustomSearchIndex (customsearch(255)),
  PRIMARY KEY (id)
) TYPE=InnoDB CHARACTER SET utf8;

--
-- Table: genre_track
--
CREATE TABLE genre_track (
  genre  int(10) unsigned,
  track  int(10) unsigned,
  INDEX genre_trackGenreIndex (genre),
  INDEX genre_trackTrackIndex (track),
  PRIMARY KEY (genre,track),
  FOREIGN KEY (`track`) REFERENCES `tracks` (`id`) ON DELETE CASCADE,
  FOREIGN KEY (`genre`) REFERENCES `genres` (`id`) ON DELETE CASCADE
) TYPE=InnoDB CHARACTER SET utf8;

--
-- Table: comments
--
CREATE TABLE comments (
  id int(10) unsigned NOT NULL auto_increment,
  track  int(10) unsigned,
  value text,
  PRIMARY KEY (id),
  INDEX trackIndex (track),
  FOREIGN KEY (`track`) REFERENCES `tracks` (`id`) ON DELETE CASCADE
) TYPE=InnoDB CHARACTER SET utf8;

--
-- Table: pluginversion
--
CREATE TABLE pluginversion (
  id int(10) unsigned NOT NULL auto_increment,
  name varchar(255),
  version  int(10) unsigned,
  PRIMARY KEY (id)
) TYPE=InnoDB CHARACTER SET utf8;
