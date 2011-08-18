-- schema_16 recreated tracks but forgot to recreate all the indicies

CREATE INDEX trackTitleIndex ON tracks (title);
CREATE INDEX trackAlbumIndex ON tracks (album);
CREATE INDEX ctSortIndex ON tracks (content_type);
CREATE INDEX trackSortIndex ON tracks (titlesort);
CREATE INDEX trackSearchIndex ON tracks (titlesearch);
CREATE INDEX trackCustomSearchIndex ON tracks (customsearch);
CREATE INDEX trackBitrateIndex ON tracks (bitrate);
CREATE INDEX trackDiscIndex ON tracks (disc);
CREATE INDEX trackFilesizeIndex ON tracks (filesize);
CREATE INDEX trackTimestampIndex ON tracks (timestamp);
CREATE INDEX trackTracknumIndex ON tracks (tracknum);
CREATE INDEX trackAudioIndex ON tracks (audio);
CREATE INDEX trackLyricsIndex ON tracks (lyrics);
CREATE INDEX trackRemoteIndex ON tracks (remote);
CREATE INDEX trackLosslessIndex ON tracks (lossless);
CREATE INDEX urlIndex ON tracks (url);
CREATE INDEX trackExtId ON tracks (extid);
CREATE INDEX urlmd5Index ON tracks (urlmd5);
CREATE INDEX coveridIndex ON tracks (coverid);
