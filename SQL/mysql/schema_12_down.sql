ALTER TABLE tracks DROP urlmd5;
ALTER TABLE tracks DROP coverid;
ALTER TABLE tracks DROP cover_cached;
ALTER TABLE tracks DROP `virtual`;

ALTER TABLE albums CHANGE artwork artwork int(10) default NULL;

ALTER TABLE tracks_persistent DROP urlmd5;
