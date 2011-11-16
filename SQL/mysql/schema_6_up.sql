-- Table to store persistent track information, e.g. ratings and playcounts
-- This data survives a rescan
DROP TABLE IF EXISTS tracks_persistent;
CREATE TABLE tracks_persistent (
  id int(10) unsigned NOT NULL auto_increment,
  url text NOT NULL,
  musicbrainz_id varchar(40),	-- musicbrainz uuid (36 bytes of text)
  track int(10) unsigned,
  added int(10) unsigned,
  rating tinyint(1) unsigned,
  playCount int(10) unsigned,
  lastPlayed int(10) unsigned,
  INDEX trackMusicBrainzIndex (musicbrainz_id),
  INDEX trackUrlIndex (url(255)),
  INDEX trackAddedIndex (added),
  INDEX trackRatingIndex (rating),
  INDEX trackPlayCountIndex (playCount),
  INDEX trackLastPlayedIndex (lastPlayed),
  PRIMARY KEY (id),
  UNIQUE KEY (track)
) ENGINE=InnoDB CHARACTER SET utf8 COLLATE utf8_unicode_ci;

ALTER TABLE tracks DROP rating;
ALTER TABLE tracks DROP playCount;
ALTER TABLE tracks DROP lastPlayed;

