SET foreign_key_checks = 0;

TRUNCATE tracks;

OPTIMIZE TABLE tracks;

TRUNCATE playlist_track;

OPTIMIZE TABLE playlist_track;

TRUNCATE albums;

OPTIMIZE TABLE albums;

TRUNCATE years;

OPTIMIZE TABLE years;

TRUNCATE contributors;

OPTIMIZE TABLE contributors;

TRUNCATE contributor_track;

OPTIMIZE TABLE contributor_track;

TRUNCATE contributor_album;

OPTIMIZE TABLE contributor_album;

TRUNCATE genres;

OPTIMIZE TABLE genres;

TRUNCATE genre_track;

OPTIMIZE TABLE genre_track;

TRUNCATE comments;

OPTIMIZE TABLE comments;

TRUNCATE pluginversion;

OPTIMIZE TABLE pluginversion;

TRUNCATE unreadable_tracks;

OPTIMIZE TABLE unreadable_tracks;

UPDATE metainformation SET value = 0 WHERE name = 'lastRescanTime';

-- Clear the migration table so the schema is recreated
TRUNCATE dbix_migration;

SET foreign_key_checks = 1;
