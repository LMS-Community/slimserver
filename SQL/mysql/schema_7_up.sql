-- Add extid (external ID) column to tracks, to link with iTunes or other external library
ALTER TABLE tracks ADD extid varchar(64);
ALTER TABLE tracks ADD INDEX trackExtId (extid);
