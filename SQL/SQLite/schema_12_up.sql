-- Bug 14717, add a urlmd5 key to use as the index between
-- tracks and tracks_persistent, it will also be used for artwork

ALTER TABLE tracks ADD urlmd5 char(32) NOT NULL default '0';
CREATE UNIQUE INDEX urlmd5Index ON tracks (urlmd5);

ALTER TABLE persistentdb.tracks_persistent ADD urlmd5 char(32) NOT NULL default '0';
CREATE UNIQUE INDEX persistentdb.urlmd5Index ON tracks_persistent (urlmd5);

UPDATE tracks_persistent SET urlmd5 = MD5(url);
