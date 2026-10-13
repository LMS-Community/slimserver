CREATE INDEX IF NOT EXISTS tracksCoverIndex ON tracks (cover);

DROP TABLE IF EXISTS scanned_pics;
CREATE TABLE scanned_pics (
  folder text,
  full_path text UNIQUE NOT NULL,
  timestamp int(10),
  filesize int(10),
  coverid char(8),
  status char(1) CHECK (status IN ('D', 'E', 'N')),
  folder_url text
  	-- D = image deleted (ie used in the database (tracks.cover) but no longer existing on disk)
  	-- E = an existing image present in tracks.cover
  	-- N = a new image (eg on disk but not used in tracks.cover - might actually have been on disk before, but passed over in a previous scan)
  	-- NULL = we'll set status 'E' to NULL if after n&c music files have been processed the image is still being used.
 	--	This improves performance as we'll only process the tracks if there's also a N(ew) image 
);
CREATE INDEX scannedPicsFullPathIndex ON scanned_pics (full_path);
CREATE INDEX scannedPicsFolderIndex ON scanned_pics (folder);
CREATE INDEX scannedPicsStatusIndex ON scanned_pics (status);
CREATE INDEX scannedPicsFolderUrlIndex ON scanned_pics (folder_url);
