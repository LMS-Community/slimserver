-- Downgrade back to utf8_general

ALTER TABLE metainformation collate utf8_general_ci;
ALTER TABLE rescans collate utf8_general_ci;
ALTER TABLE unreadable_tracks collate utf8_general_ci;
ALTER TABLE tracks collate utf8_general_ci;
ALTER TABLE playlist_track collate utf8_general_ci;
ALTER TABLE albums collate utf8_general_ci;
ALTER TABLE years collate utf8_general_ci;
ALTER TABLE contributors collate utf8_general_ci;
ALTER TABLE contributor_track collate utf8_general_ci;
ALTER TABLE contributor_album collate utf8_general_ci;
ALTER TABLE genres collate utf8_general_ci;
ALTER TABLE genre_track collate utf8_general_ci;
ALTER TABLE comments collate utf8_general_ci;
ALTER TABLE pluginversion collate utf8_general_ci;
ALTER TABLE years collate utf8_general_ci;
