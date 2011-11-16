--
-- Table: playlist_track
--
DROP TABLE IF EXISTS playlist_track;
CREATE TABLE playlist_track (
  id int(10) unsigned NOT NULL auto_increment,
  position  int(10) unsigned,
  playlist  int(10) unsigned,
  track  int(10) unsigned,
  PRIMARY KEY (id),
  INDEX trackIndex (track),
  INDEX positionIndex (position),
  INDEX playlistIndex (playlist),
  FOREIGN KEY (`track`) REFERENCES `tracks` (`id`) ON DELETE CASCADE,
  FOREIGN KEY (`playlist`) REFERENCES `tracks` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB CHARACTER SET utf8 COLLATE utf8_unicode_ci;
