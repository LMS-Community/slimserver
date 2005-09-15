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
  total_time  int(10) unsigned
) TYPE=InnoDB;

INSERT INTO metainformation VALUES (16, 0, 0);

--
-- Table: tracks
--
CREATE TABLE tracks (
  id int(10) unsigned NOT NULL auto_increment,
  url text NOT NULL,
  title varchar(255),
  titlesort varchar(255),
  titlesearch varchar(255),
  album  int(10) unsigned,
  tracknum  int(10) unsigned,
  ct varchar(255),
  tag  int(10) unsigned,
  age  int(10) unsigned,
  fs  int(10) unsigned,
  size  int(10) unsigned,
  offset  int(10) unsigned,
  year  smallint(5) unsigned,
  secs  int(10) unsigned,
  cover varchar(255),
  covertype varchar(255),
  thumb varchar(255),
  thumbtype varchar(255),
  vbr_scale varchar(255),
  bitrate  int(10) unsigned,
  rate  int(10) unsigned,
  samplesize  int(10) unsigned,
  channels  tinyint(1) unsigned,
  blockalign  int(10) unsigned,
  endian  tinyint(1) unsigned,
  bpm  smallint(5) unsigned,
  tagversion varchar(255),
  tagsize  int(10) unsigned,
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
  INDEX trackTitleIndex (title),
  INDEX trackAlbumIndex (album),
  INDEX ctSortIndex (ct),
  INDEX trackSortIndex (titlesort),
  INDEX trackSearchIndex (titlesearch),
  INDEX trackRatingIndex (rating),
  INDEX trackPlayCountIndex (playCount),
  INDEX trackAudioIndex (audio),
  INDEX trackRemoteIndex (remote),
  INDEX trackLosslessIndex (lossless),
  INDEX trackSortKeyIndex (multialbumsortkey(255)),
  INDEX urlIndex (url(255)),
  PRIMARY KEY (id),
--  UNIQUE KEY (url),
  FOREIGN KEY (`album`) REFERENCES `albums` (`id`) ON DELETE NO ACTION
) TYPE=InnoDB;

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
  FOREIGN KEY (`track`) REFERENCES `tracks` (`id`) ON DELETE NO ACTION
) TYPE=InnoDB;

--
-- Table: dirlist_track
--
CREATE TABLE dirlist_track (
  id int(10) unsigned NOT NULL auto_increment,
  position  int(10) unsigned,
  dirlist  int(10) unsigned,
  item text,
  PRIMARY KEY (id)
) TYPE=InnoDB;

--
-- Table: albums
--
CREATE TABLE albums (
  id int(10) unsigned NOT NULL auto_increment,
  title varchar(255),
  titlesort varchar(255),
  titlesearch varchar(255),
  contributor varchar(255),
  compilation tinyint(1) unsigned,
  year  smallint(5) unsigned,
  artwork_path varchar(255),
  disc  tinyint(1) unsigned,
  discc  tinyint(1) unsigned,
  replay_gain float,
  replay_peak float,
  musicbrainz_id varchar(40),	-- musicbrainz uuid (36 bytes of text)
  musicmagic_mixable tinyint(1) unsigned,
  INDEX albumsTitleIndex (title),
  INDEX albumsSortIndex (titlesort),
  INDEX albumsSearchIndex (titlesearch),
  INDEX compilationSortIndex (compilation),
  PRIMARY KEY (id)
) TYPE=InnoDB;


-- Testing
--
-- Table: contributors
--
CREATE TABLE contributors (
  id int(10) unsigned NOT NULL auto_increment,
  name varchar(255),
  namesort varchar(255),
  namesearch varchar(255),
  moodlogic_id  int(10) unsigned,
  moodlogic_mixable tinyint(1) unsigned,
  musicbrainz_id varchar(40),	-- musicbrainz uuid (36 bytes of text)
  musicmagic_mixable tinyint(1) unsigned,
  INDEX contributorsNameIndex (name),
  INDEX contributorsSortIndex (namesort),
  INDEX contributorsSearchIndex (namesearch),
  PRIMARY KEY (id)
) TYPE=InnoDB;

--
-- Table: contributor_track
--
CREATE TABLE contributor_track (
  id int(10) unsigned NOT NULL auto_increment,
  role  int(10) unsigned,
  contributor  int(10) unsigned,
  track  int(10) unsigned,
  namesort varchar(255),
  INDEX contributor_trackContribIndex (contributor),
  INDEX contributor_trackTrackIndex (track),
  INDEX contributor_trackRoleIndex (role),
  INDEX contributor_trackSortIndex (namesort),
  PRIMARY KEY (id),
  FOREIGN KEY (`track`) REFERENCES `tracks` (`id`) ON DELETE NO ACTION,
  FOREIGN KEY (`contributor`) REFERENCES `contributors` (`id`) ON DELETE NO ACTION
) TYPE=InnoDB;

--
-- Table: contributor_album
--
CREATE TABLE contributor_album (
  id int(10) unsigned NOT NULL auto_increment,
  role  int(10) unsigned,
  contributor  int(10) unsigned,
  album  int(10) unsigned,
  INDEX contributor_trackContribIndex (contributor),
  INDEX contributor_trackAlbumIndex (album),
  INDEX contributor_trackRoleIndex (role),
  PRIMARY KEY (id),
  FOREIGN KEY (`album`) REFERENCES `albums` (`id`) ON DELETE NO ACTION,
  FOREIGN KEY (`contributor`) REFERENCES `contributors` (`id`) ON DELETE NO ACTION
) TYPE=InnoDB;

--
-- Table: genres
--
CREATE TABLE genres (
  id int(10) unsigned NOT NULL auto_increment,
  name varchar(255),
  namesort varchar(255),
  namesearch varchar(255),
  moodlogic_id  int(10) unsigned,
  moodlogic_mixable tinyint(1) unsigned,
  musicmagic_mixable tinyint(1) unsigned,
  INDEX genreNameIndex (name),
  INDEX genreSortIndex (namesort),
  INDEX genreSearchIndex (namesearch),
  PRIMARY KEY (id)
) TYPE=InnoDB;

--
-- Table: genre_track
--
CREATE TABLE genre_track (
  id int(10) unsigned NOT NULL auto_increment,
  genre  int(10) unsigned,
  track  int(10) unsigned,
  INDEX genre_trackGenreIndex (genre),
  INDEX genre_trackTraclIndex (track),
  PRIMARY KEY (id),
  FOREIGN KEY (`track`) REFERENCES `tracks` (`id`) ON DELETE NO ACTION,
  FOREIGN KEY (`genre`) REFERENCES `genres` (`id`) ON DELETE NO ACTION
) TYPE=InnoDB;

--
-- Table: comments
--
CREATE TABLE comments (
  id int(10) unsigned NOT NULL auto_increment,
  track  int(10) unsigned,
  value text,
  PRIMARY KEY (id),
  INDEX trackIndex (track),
  FOREIGN KEY (`track`) REFERENCES `tracks` (`id`) ON DELETE NO ACTION
) TYPE=InnoDB;

--
-- Table: pluginversion
--
CREATE TABLE pluginversion (
  id int(10) unsigned NOT NULL auto_increment,
  name varchar(255),
  version  int(10) unsigned,
  PRIMARY KEY (id)
) TYPE=InnoDB;
