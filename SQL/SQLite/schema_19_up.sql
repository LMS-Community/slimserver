--
-- Table: library_track
--
DROP TABLE IF EXISTS library_track;
CREATE TABLE library_track (
  track  int(10),
  library  int(10),
  PRIMARY KEY (track,library),
  FOREIGN KEY (`track`) REFERENCES `tracks` (`id`) ON DELETE CASCADE
);
