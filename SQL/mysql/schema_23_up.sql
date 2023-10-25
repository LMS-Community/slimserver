ALTER TABLE tracks ADD work varchar(512);
CREATE INDEX tracksWorkIndex ON tracks (work);
