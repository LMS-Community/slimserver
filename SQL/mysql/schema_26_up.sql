DROP TABLE IF EXISTS rescans;
DROP TABLE IF EXISTS pluginversion;
DROP TABLE IF EXISTS unreadable_tracks;

DROP INDEX IF EXISTS trackHashIndex;
ALTER TABLE tracks DROP hash;
