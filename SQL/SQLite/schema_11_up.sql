
DROP TABLE IF EXISTS scanned_files;
CREATE TABLE scanned_files (
  url text NOT NULL COLLATE NOCASE, -- URL must be case insensitive, or we might duplicate tracks if the filename changes case only (https://github.com/Logitech/slimserver/issues/705#issuecomment-1026229542)
  timestamp int(10),
  filesize int(10)
);
CREATE INDEX scannedUrlIndex ON scanned_files (url);
