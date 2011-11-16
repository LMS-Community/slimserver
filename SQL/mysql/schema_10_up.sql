
--
-- Table: playlist_track
--
DROP TABLE IF EXISTS playlist_track;
CREATE TABLE playlist_track (
  id int(10) unsigned NOT NULL auto_increment,
  position  int(10) unsigned,
  playlist  int(10) unsigned,
  track  text NOT NULL,
  PRIMARY KEY (id),
  INDEX positionIndex (position),
  INDEX playlistIndex (playlist),
  FOREIGN KEY (`playlist`) REFERENCES `tracks` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB CHARACTER SET utf8 COLLATE utf8_general_ci;

