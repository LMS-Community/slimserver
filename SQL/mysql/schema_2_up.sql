-- It's important that there is a newline between all 
-- SQL statements, otherwise the parser will skip them.

SET foreign_key_checks = 0;

--
-- Table: years
--

CREATE TABLE IF NOT EXISTS years (
  id smallint(5) unsigned,
  PRIMARY KEY (id)
) ENGINE=InnoDB CHARACTER SET utf8 COLLATE utf8_unicode_ci;
