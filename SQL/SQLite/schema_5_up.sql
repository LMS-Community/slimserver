-- table to store progress information, e.g. scanning progress by importer

DROP TABLE IF EXISTS progress;
CREATE TABLE progress (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  type varchar(255),
  name varchar(255),
  active bool,
  total int(10),
  done int(10),
  start int(10),
  finish int(10),
  info varchar(255)
)