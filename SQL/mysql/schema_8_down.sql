-- Convert to utf8_unicode_ci COLLATE on all table columns
ALTER TABLE albums CONVERT TO CHARACTER SET utf8 COLLATE utf8_unicode_ci;
ALTER TABLE comments CONVERT TO CHARACTER SET utf8 COLLATE utf8_unicode_ci;
ALTER TABLE contributor_album CONVERT TO CHARACTER SET utf8 COLLATE utf8_unicode_ci;
ALTER TABLE contributor_track CONVERT TO CHARACTER SET utf8 COLLATE utf8_unicode_ci;
ALTER TABLE contributors CONVERT TO CHARACTER SET utf8 COLLATE utf8_unicode_ci;
ALTER TABLE genre_track CONVERT TO CHARACTER SET utf8 COLLATE utf8_unicode_ci;
ALTER TABLE genres CONVERT TO CHARACTER SET utf8 COLLATE utf8_unicode_ci;
ALTER TABLE metainformation CONVERT TO CHARACTER SET utf8 COLLATE utf8_unicode_ci;
ALTER TABLE playlist_track CONVERT TO CHARACTER SET utf8 COLLATE utf8_unicode_ci;
ALTER TABLE pluginversion CONVERT TO CHARACTER SET utf8 COLLATE utf8_unicode_ci;
ALTER TABLE progress CONVERT TO CHARACTER SET utf8 COLLATE utf8_unicode_ci;
ALTER TABLE rescans CONVERT TO CHARACTER SET utf8 COLLATE utf8_unicode_ci;
ALTER TABLE tracks CONVERT TO CHARACTER SET utf8 COLLATE utf8_unicode_ci;
ALTER TABLE tracks_persistent CONVERT TO CHARACTER SET utf8 COLLATE utf8_unicode_ci;
ALTER TABLE unreadable_tracks CONVERT TO CHARACTER SET utf8 COLLATE utf8_unicode_ci;
ALTER TABLE years CONVERT TO CHARACTER SET utf8 COLLATE utf8_unicode_ci;

-- Alter table COLLATE setting to utf8_general_ci on all tables
ALTER TABLE albums COLLATE utf8_general_ci;
ALTER TABLE comments COLLATE utf8_general_ci;
ALTER TABLE contributor_album COLLATE utf8_general_ci;
ALTER TABLE contributor_track COLLATE utf8_general_ci;
ALTER TABLE contributors COLLATE utf8_general_ci;
ALTER TABLE genre_track COLLATE utf8_general_ci;
ALTER TABLE genres COLLATE utf8_general_ci;
ALTER TABLE metainformation COLLATE utf8_general_ci;
ALTER TABLE playlist_track COLLATE utf8_general_ci;
ALTER TABLE pluginversion COLLATE utf8_general_ci;
ALTER TABLE progress COLLATE utf8_general_ci;
ALTER TABLE rescans COLLATE utf8_general_ci;
ALTER TABLE tracks COLLATE utf8_general_ci;
ALTER TABLE tracks_persistent COLLATE utf8_general_ci;
ALTER TABLE unreadable_tracks COLLATE utf8_general_ci;
ALTER TABLE years COLLATE utf8_general_ci;
