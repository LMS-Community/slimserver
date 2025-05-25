ALTER TABLE albums ADD version blob;
ALTER TABLE tracks ADD lms_persistent_id text;
DROP INDEX IF EXISTS albumsLabelIndex;
CREATE INDEX albumsLabelIndex ON albums (label);
DROP TABLE IF EXISTS labels;
CREATE TABLE labels (
  id  integer PRIMARY KEY AUTOINCREMENT,
  name blob,
  namesort text,
  namesearch text
);
DROP TABLE IF EXISTS label_album;
CREATE TABLE label_album (
  label  int(10),
  album  int(10),
  PRIMARY KEY (label,album),
  FOREIGN KEY (`album`) REFERENCES `albums` (`id`) ON DELETE CASCADE,
  FOREIGN KEY (`label`) REFERENCES `labels` (`id`) ON DELETE CASCADE
);
DROP INDEX IF EXISTS label_albumAlbumIndex;
CREATE INDEX label_albumAlbumIndex ON label_album (album);
DROP INDEX IF EXISTS label_albumLabelIndex;
CREATE INDEX label_albumLabelIndex ON label_album (label);

