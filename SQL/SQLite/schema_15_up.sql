
-- to be set to EXIF DateTimeOriginal or similar
ALTER TABLE images ADD original_time int(10) default NULL;
CREATE INDEX imageDateTimeOriginal ON images (original_time);

ALTER TABLE images ADD orientation int(10) default NULL;

ALTER TABLE images ADD album blob default NULL;

ALTER TABLE videos ADD album blob default NULL;
