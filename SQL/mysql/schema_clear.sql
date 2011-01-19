SET foreign_key_checks = 0;

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

UPDATE metainformation SET value = 0 WHERE name = 'lastRescanTime';

UPDATE tracks_persistent SET track = NULL;

SET foreign_key_checks = 1;
