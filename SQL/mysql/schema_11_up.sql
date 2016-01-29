
DROP TABLE IF EXISTS scanned_files;
CREATE TABLE scanned_files (
  url TEXT NOT NULL,
  timestamp int(10),
  filesize int(10)
) ENGINE=InnoDB CHARACTER SET utf8;
CREATE INDEX scannedUrlIndex ON scanned_files (url(255));
