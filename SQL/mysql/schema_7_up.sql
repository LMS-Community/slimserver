-- Bug 9423, incorrect collate was placed on tracks_persistent
ALTER TABLE tracks_persistent CONVERT TO CHARACTER SET utf8 COLLATE utf8_general_ci;

-- Add extid (external ID) column to tracks, to link with iTunes or other external library
ALTER TABLE tracks ADD extid varchar(64);
ALTER TABLE tracks ADD INDEX trackExtId (extid);