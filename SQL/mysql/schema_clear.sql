SET foreign_key_checks = 0;

-- Use DELETE instead of TRUNCATE, as TRUNCATE seems to need unlocked tables.
DELETE FROM tracks;

OPTIMIZE TABLE tracks;

DELETE FROM playlist_track;

OPTIMIZE TABLE playlist_track;

DELETE FROM albums;

OPTIMIZE TABLE albums;

DELETE FROM years;

OPTIMIZE TABLE years;

DELETE FROM contributors;

OPTIMIZE TABLE contributors;

DELETE FROM contributor_track;

OPTIMIZE TABLE contributor_track;

DELETE FROM contributor_album;

OPTIMIZE TABLE contributor_album;

DELETE FROM genres;

OPTIMIZE TABLE genres;

DELETE FROM genre_track;

OPTIMIZE TABLE genre_track;

DELETE FROM comments;

OPTIMIZE TABLE comments;

DELETE FROM pluginversion;

OPTIMIZE TABLE pluginversion;

DELETE FROM unreadable_tracks;

OPTIMIZE TABLE unreadable_tracks;

UPDATE metainformation SET value = 0 WHERE name = 'lastRescanTime';

-- Clear the migration table so the schema is recreated
DELETE FROM dbix_migration;

SET foreign_key_checks = 1;
