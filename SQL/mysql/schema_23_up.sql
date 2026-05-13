ALTER TABLE tracks ADD work integer;
ALTER TABLE tracks ADD subtitle blob;
ALTER TABLE tracks ADD grouping blob;
ALTER TABLE albums ADD subtitle blob;
ALTER TABLE albums ADD label blob;
CREATE INDEX albumsLabelIndex ON albums (label);
CREATE INDEX tracksWorkIndex ON tracks (work);
CREATE TABLE works (
  id  integer PRIMARY KEY AUTO_INCREMENT,
  composer int(10) unsigned,
  title blob,
  titlesort text,
  titlesearch text,
  FOREIGN KEY (`composer`) REFERENCES `contributors` (`id`) ON DELETE CASCADE
)
