ALTER TABLE albums ADD release_type varchar(64);
CREATE INDEX albumsReleaseTypeIndex ON albums (release_type);
