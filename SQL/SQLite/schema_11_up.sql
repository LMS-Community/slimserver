
DROP TABLE IF EXISTS scanned_files;
CREATE TABLE scanned_files (
  url text NOT NULL,
  timestamp int(10),
  filesize int(10)
);
CREATE INDEX scannedUrlIndex ON scanned_files (url);
