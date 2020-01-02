-- add columns for an external ID, to be used by albums/contributors from music services

ALTER TABLE albums ADD extid varchar(64);
ALTER TABLE contributors ADD extid varchar(512);
