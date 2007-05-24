-- Update collation back to utf_general_ci as this is faster

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

-- Delete unused rows

ALTER TABLE tracks DROP thumb;
ALTER TABLE tracks DROP moodlogic_id;
ALTER TABLE tracks DROP moodlogic_mixable;
ALTER TABLE contributors DROP moodlogic_id;
ALTER TABLE contributors DROP moodlogic_mixable;
ALTER TABLE genres DROP moodlogic_id;
ALTER TABLE genres DROP moodlogic_mixable;
