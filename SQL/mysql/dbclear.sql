SET foreign_key_checks = 0;

UPDATE metainformation set track_count = 0;

UPDATE metainformation set total_time = 0;

DELETE FROM tracks;

DELETE FROM playlist_track;

DELETE FROM albums;

DELETE FROM contributors;

DELETE FROM contributor_track;

DELETE FROM contributor_album;

DELETE FROM genres;

DELETE FROM genre_track;

DELETE FROM comments;

DELETE FROM pluginversion;

SET foreign_key_checks = 1;
