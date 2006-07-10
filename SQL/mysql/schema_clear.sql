SET foreign_key_checks = 0;

DELETE FROM tracks;

ALTER TABLE tracks AUTO_INCREMENT = 1;

OPTIMIZE TABLE tracks;

DELETE FROM playlist_track;

ALTER TABLE playlist_track AUTO_INCREMENT = 1;

OPTIMIZE TABLE playlist_track;

DELETE FROM albums;

ALTER TABLE albums AUTO_INCREMENT = 1;

OPTIMIZE TABLE albums;

DELETE FROM contributors;

ALTER TABLE contributors AUTO_INCREMENT = 1;

OPTIMIZE TABLE contributors;

DELETE FROM contributor_track;

OPTIMIZE TABLE contributor_track;

DELETE FROM contributor_album;

OPTIMIZE TABLE contributor_album;

DELETE FROM genres;

ALTER TABLE genres AUTO_INCREMENT = 1;

OPTIMIZE TABLE genres;

DELETE FROM genre_track;

OPTIMIZE TABLE genre_track;

DELETE FROM comments;

ALTER TABLE comments AUTO_INCREMENT = 1;

OPTIMIZE TABLE comments;

DELETE FROM pluginversion;

ALTER TABLE pluginversion AUTO_INCREMENT = 1;

OPTIMIZE TABLE pluginversion;

DELETE FROM unreadable_tracks;

ALTER TABLE unreadable_tracks AUTO_INCREMENT = 1;

OPTIMIZE TABLE unreadable_tracks;

UPDATE metainformation SET value = 0 WHERE name = 'lastRescanTime';

UPDATE metainformation SET value = 0 WHERE name = 'isScanning';

SET foreign_key_checks = 1;
