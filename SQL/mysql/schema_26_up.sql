DROP TABLE IF EXISTS rescans;
DROP TABLE IF EXISTS pluginversion;
DROP TABLE IF EXISTS unreadable_tracks;

ALTER TABLE tracks DROP hash;
DROP INDEX IF EXISTS trackHashIndex;
