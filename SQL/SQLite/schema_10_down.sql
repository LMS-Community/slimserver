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