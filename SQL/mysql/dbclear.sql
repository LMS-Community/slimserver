SET foreign_key_checks = 0;

UPDATE metainformation SET value = 0 WHERE name = 'trackCount';
UPDATE metainformation SET value = 0 WHERE name = 'totalTime';
UPDATE metainformation SET value = 0 WHERE name = 'lastRescanTime';
UPDATE metainformation SET value = 0 WHERE name = 'isScanning';

DELETE FROM tracks;
ALTER TABLE tracks AUTO_INCREMENT = 1;

DELETE FROM playlist_track;
ALTER TABLE tracks AUTO_INCREMENT = 1;

DELETE FROM albums;
ALTER TABLE tracks AUTO_INCREMENT = 1;

DELETE FROM contributors;
ALTER TABLE tracks AUTO_INCREMENT = 1;

DELETE FROM contributor_track;

DELETE FROM contributor_album;

DELETE FROM genres;
ALTER TABLE tracks AUTO_INCREMENT = 1;

DELETE FROM genre_track;

DELETE FROM comments;
ALTER TABLE tracks AUTO_INCREMENT = 1;

DELETE FROM pluginversion;
ALTER TABLE tracks AUTO_INCREMENT = 1;

DELETE FROM unreadable_tracks;
ALTER TABLE unreadable_tracks AUTO_INCREMENT = 1;

SET foreign_key_checks = 1;
