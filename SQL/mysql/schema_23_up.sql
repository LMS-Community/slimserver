ALTER TABLE tracks ADD work integer;
CREATE INDEX tracksWorkIndex ON tracks (work);
CREATE TABLE works (
  id  integer PRIMARY KEY AUTOINCREMENT,
  composer integer,
  title blob,
  titlesort text,
  titlesearch text,
  FOREIGN KEY (`composer`) REFERENCES `contributors` (`id`) ON DELETE CASCADE
)
