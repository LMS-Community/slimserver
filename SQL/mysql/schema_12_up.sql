-- Bug 14717, add a urlmd5 key to use as the index between
-- tracks and tracks_persistent, it will also be used for artwork
--
-- Add coverid field to support unique cover art handling
-- Add cover_cached field to better support pre-caching
-- Change albums.artwork to char(8) to contain coverid
--
-- Add virtual field to indicate if a track is real or from a cue sheet

ALTER TABLE tracks ADD urlmd5 char(32) NOT NULL default '0';
CREATE INDEX urlmd5Index ON tracks (urlmd5);

ALTER TABLE tracks ADD coverid char(8) default NULL;
CREATE INDEX coveridIndex ON tracks (coverid);

ALTER TABLE tracks ADD cover_cached tinyint(1) default NULL;

ALTER TABLE tracks ADD `virtual` tinyint(1) default NULL;

ALTER TABLE albums CHANGE artwork artwork char(8) default NULL;

ALTER TABLE tracks_persistent ADD urlmd5 char(32) NOT NULL default '0';
CREATE INDEX tp_urlmd5Index ON tracks_persistent (urlmd5);

UPDATE tracks_persistent SET urlmd5 = MD5(url);
