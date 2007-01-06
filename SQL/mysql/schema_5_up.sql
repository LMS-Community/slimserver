-- table to store progress information, e.g. scanning progress by importer

DROP TABLE IF EXISTS progress;
CREATE TABLE progress (
  id int(10) unsigned NOT NULL auto_increment,
  type varchar(255),
  name varchar(255),
  active bool,
  total int(10) unsigned,
  done int(10) unsigned,
  start int(10) unsigned,
  finish int(10) unsigned,
  info varchar(255),
  PRIMARY KEY (id)
) ENGINE=MEMORY;
