DROP TABLE IF EXISTS persistentdb.tracks_persistent;

ALTER TABLE tracks ADD rating tinyint(1) unsigned AFTER drm;
ALTER TABLE tracks ADD INDEX trackRatingIndex (rating);

ALTER TABLE tracks ADD playCount int(10) unsigned AFTER disc;
ALTER TABLE tracks ADD INDEX trackPlayCountIndex (playCount);

ALTER TABLE tracks ADD lastPlayed int(10) unsigned AFTER playCount;
ALTER TABLE tracks ADD INDEX trackLastPlayedIndex (lastPlayed);

