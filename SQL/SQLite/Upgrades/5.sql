
-- Create a temporary tracks table to add new columns.
-- http://www.sqlite.org/faq.html
--

BEGIN TRANSACTION;

CREATE TEMPORARY TABLE albums_backup(
  id integer UNIQUE PRIMARY KEY NOT NULL,
  title varchar,           -- title
  titlesort varchar,       -- version of title used for sorting
  artwork_path varchar,    -- path to cover art
  disc integer,            -- album number in set
  discc integer            -- number of albums in set
);

-- do the copy

INSERT INTO albums_backup SELECT * FROM albums;
DROP TABLE albums;

-- recreate with the new columns

CREATE TABLE albums (
  id integer UNIQUE PRIMARY KEY NOT NULL,
  title varchar,           -- title
  titlesort varchar,       -- version of title used for sorting
  contributors varchar,    -- stringified list of contributors
  artwork_path varchar,    -- path to cover art
  disc integer,            -- album number in set
  discc integer            -- number of albums in set
);

CREATE INDEX albumsTitleIndex ON albums (title);

CREATE INDEX albumsSortIndex ON albums (titlesort);

INSERT INTO albums SELECT * FROM albums_backup;

DROP TABLE albums_backup;

UPDATE metainformation SET version = 5;

COMMIT;
