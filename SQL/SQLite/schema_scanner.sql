DROP TABLE IF EXISTS scanned_files;
CREATE TABLE scanned_files (
  url text NOT NULL,
  timestamp int(10),
  filesize int(10)
);
CREATE INDEX scannedUrlIndex ON scanned_files (url);

DROP TABLE IF EXISTS scanned_pics;
CREATE TABLE scanned_pics (
  url text NOT NULL,
  timestamp int(10),
  filesize int(10)
);
CREATE INDEX scannedPicUrlIndex ON scanned_pics (url);
