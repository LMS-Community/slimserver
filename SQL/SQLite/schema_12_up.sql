-- Bug 14717, add a urlmd5 key to use as the index between
-- tracks and tracks_persistent, it will also be used for artwork
--
-- Add coverid field to support unique cover art handling
-- Add cover_cached field to better support pre-caching

ALTER TABLE tracks ADD urlmd5 char(32) NOT NULL default '0';
CREATE INDEX urlmd5Index ON tracks (urlmd5);

ALTER TABLE tracks ADD coverid char(8) default NULL;
CREATE INDEX coveridIndex ON tracks (coverid);

ALTER TABLE tracks ADD cover_cached char(1) default NULL;

ALTER TABLE tracks ADD virtual char(1) default NULL;

-- Cannot change albums.artwork to char(8) here, so it's done in schema_1_up

ALTER TABLE persistentdb.tracks_persistent ADD urlmd5 char(32) NOT NULL default '0';
CREATE INDEX persistentdb.urlmd5Index ON tracks_persistent (urlmd5);

UPDATE tracks_persistent SET urlmd5 = MD5(url);
