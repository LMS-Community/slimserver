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

INSERT INTO metainformation VALUES (4, 0, 0);

--
-- Table: tracks
--
CREATE TABLE tracks (
  id int(10) unsigned NOT NULL auto_increment,
  url text NOT NULL,
  title varchar(255),
  titlesort varchar(255),
  album  int(10) unsigned,
  tracknum  int(10) unsigned,
  ct varchar(255),
  tag  int(10) unsigned,
  age  int(10) unsigned,
  fs  int(10) unsigned,
  size  int(10) unsigned,
  offset  int(10) unsigned,
  year  int(10) unsigned,
  secs  int(10) unsigned,
  cover varchar(255),
  covertype varchar(255),
  thumb varchar(255),
  thumbtype varchar(255),
  vbr_scale varchar(255),
  bitrate  int(10) unsigned,
  rate  int(10) unsigned,
  samplesize  int(10) unsigned,
  channels  int(10) unsigned,
  blockalign  int(10) unsigned,
  endian  int(10) unsigned,
  bpm  int(10) unsigned,
  tagversion varchar(255),
  tagsize  int(10) unsigned,
  drm  int(10) unsigned,
  rating int(10) unsigned,
  playCount int(10) unsigned,
  lastPlayed int(10) unsigned,
  moodlogic_song_id  int(10) unsigned,
  moodlogic_artist_id  int(10) unsigned,
  moodlogic_genre_id  int(10) unsigned,
  moodlogic_song_mixable  int(10) unsigned,
  moodlogic_artist_mixable  int(10) unsigned,
  moodlogic_genre_mixable  int(10) unsigned,
  musicmagic_genre_mixable  int(10) unsigned,
  musicmagic_artist_mixable  int(10) unsigned,
  musicmagic_album_mixable  int(10) unsigned,
  musicmagic_song_mixable  int(10) unsigned,
  INDEX trackTitleIndex (title),
  INDEX trackAlbumIndex (album),
  INDEX trackSortIndex (titlesort),
  INDEX trackRatingIndex (rating),
  INDEX trackPlayCountIndex (playCount),
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
  contributors varchar(255),
  artwork_path varchar(255),
  disc  int(10) unsigned,
  discc  int(10) unsigned,
  INDEX albumsTitleIndex (title),
  INDEX albumsSortIndex (titlesort),
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
  INDEX contributorsNameIndex (name),
  INDEX contributorsSortIndex (namesort),
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
  album  int(10) unsigned,
  namesort varchar(255),
  INDEX contributor_trackContribIndex (contributor),
  INDEX contributor_trackTrackIndex (track),
  INDEX contributor_trackAlbumIndex (album),
  INDEX contributor_trackSortIndex (namesort),
  PRIMARY KEY (id),
  FOREIGN KEY (`track`) REFERENCES `tracks` (`id`) ON DELETE NO ACTION,
  FOREIGN KEY (`contributor`) REFERENCES `contributors` (`id`) ON DELETE NO ACTION,
  FOREIGN KEY (`album`) REFERENCES `albums` (`id`) ON DELETE NO ACTION
) TYPE=InnoDB;

--
-- Table: genres
--
CREATE TABLE genres (
  id int(10) unsigned NOT NULL auto_increment,
  name varchar(255),
  namesort varchar(255),
  INDEX genreNameIndex (name),
  INDEX genreSortIndex (namesort),
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
