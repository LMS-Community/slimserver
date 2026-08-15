DROP TABLE IF EXISTS scanned_files;
CREATE TABLE scanned_files (
  url text NOT NULL COLLATE NOCASE, -- URL must be case insensitive, or we might duplicate tracks if the filename changes case only (https://github.com/LMS-Community/slimserver/issues/705#issuecomment-1026229542)
  timestamp int(10),
  filesize int(10)
);
CREATE INDEX scannedUrlIndex ON scanned_files (url);

DROP TABLE IF EXISTS scanned_pics;
CREATE TABLE scanned_pics (
  dir text,
  path text NOT NULL,
  timestamp int(10),
  filesize int(10),
  coverid char(8),
  status char(1)
);
CREATE INDEX scannedPicUrlIndex ON scanned_pics (path);
CREATE INDEX scannedPicDirIndex ON scanned_pics (dir);
create index scannedPicStatusidx on scanned_pics(status);

CREATE INDEX IF NOT EXISTS trackscoveridx ON tracks(cover);
