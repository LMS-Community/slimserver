-- Keep a copy of the old autoincrement values
CREATE TEMPORARY TABLE old_autoincrement AS SELECT * FROM SQLITE_SEQUENCE;

-- Use DELETE instead of TRUNCATE, as TRUNCATE seems to need unlocked tables.
DELETE FROM tracks;

DELETE FROM playlist_track;

DELETE FROM albums;

DELETE FROM years;

DELETE FROM contributors;

DELETE FROM contributor_track;

DELETE FROM contributor_album;

DELETE FROM genres;

DELETE FROM genre_track;

DELETE FROM comments;

DELETE FROM pluginversion;

DELETE FROM unreadable_tracks;

DELETE FROM scanned_files;

DELETE FROM works;

DELETE FROM library_track;
DELETE FROM library_album;
DELETE FROM library_contributor;
DELETE FROM library_genre;

-- these table are created by the Fulltext Search plugin
DROP TABLE IF EXISTS fulltext;
DROP TABLE IF EXISTS fulltext_terms;

UPDATE metainformation SET value = 0 WHERE name = 'lastRescanTime';

-- start the contributor ID at the old offset to prevent ID overlap between scans
UPDATE SQLITE_SEQUENCE SET seq = (SELECT old.seq FROM old_autoincrement AS old WHERE old.name = 'contributors') WHERE name = 'contributors';

DROP TABLE old_autoincrement;