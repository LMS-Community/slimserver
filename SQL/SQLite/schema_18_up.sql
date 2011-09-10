ALTER TABLE tracks ADD dlna_profile varchar(32);
ALTER TABLE tracks ADD hash char(8);
CREATE INDEX trackHashIndex ON tracks (hash);
