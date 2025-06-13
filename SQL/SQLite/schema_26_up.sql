DROP TABLE IF EXISTS rescans;
DROP TABLE IF EXISTS pluginversion;
DROP TABLE IF EXISTS unreadable_tracks;

DROP INDEX IF EXISTS trackHashIndex;
-- DROP <column> is only supported in SQLite 3.35.0+
-- ALTER TABLE tracks DROP hash;
