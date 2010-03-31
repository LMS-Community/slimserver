
--
-- Table: playlist_track
--
DROP TABLE IF EXISTS playlist_track;
CREATE TABLE playlist_track (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  position  int(10),
  playlist  int(10),
  track     text NOT NULL,
  FOREIGN KEY (`playlist`) REFERENCES `tracks` (`id`) ON DELETE CASCADE
);
CREATE INDEX positionIndex ON playlist_track (position);
CREATE INDEX playlistIndex ON playlist_track (playlist);
