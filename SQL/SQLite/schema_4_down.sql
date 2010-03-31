-- Downgrade the collation to be utf8_unicode_ci

ALTER TABLE metainformation collate utf8_unicode_ci;
ALTER TABLE rescans collate utf8_unicode_ci;
ALTER TABLE unreadable_tracks collate utf8_unicode_ci;
ALTER TABLE tracks collate utf8_unicode_ci;
ALTER TABLE playlist_track collate utf8_unicode_ci;
ALTER TABLE albums collate utf8_unicode_ci;
ALTER TABLE years collate utf8_unicode_ci;
ALTER TABLE contributors collate utf8_unicode_ci;
ALTER TABLE contributor_track collate utf8_unicode_ci;
ALTER TABLE contributor_album collate utf8_unicode_ci;
ALTER TABLE genres collate utf8_unicode_ci;
ALTER TABLE genre_track collate utf8_unicode_ci;
ALTER TABLE comments collate utf8_unicode_ci;
ALTER TABLE pluginversion collate utf8_unicode_ci;
ALTER TABLE years collate utf8_unicode_ci;

-- Add back unused rows

ALTER TABLE tracks ADD thumb blob;
ALTER TABLE tracks ADD moodlogic_id int(10) unsigned;
ALTER TABLE tracks ADD moodlogic_mixable bool;
ALTER TABLE contributors ADD moodlogic_id int(10) unsigned;
ALTER TABLE contributors ADD moodlogic_mixable bool;
ALTER TABLE genres ADD moodlogic_id int(10) unsigned;
ALTER TABLE genres ADD moodlogic_mixable bool;
