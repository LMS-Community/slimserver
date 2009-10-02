-- Table to store persistent track information, e.g. ratings and playcounts
-- This data survives a rescan
DROP TABLE IF EXISTS tracks_persistent;
CREATE TABLE tracks_persistent (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  url text NOT NULL,
  musicbrainz_id varchar(40),	-- musicbrainz uuid (36 bytes of text)
  added int(10),
  rating tinyint(1),
  playCount int(10),
  lastPlayed int(10)
);

CREATE INDEX trackMusicBrainzIndex ON tracks_persistent (musicbrainz_id);
CREATE INDEX trackUrlIndex ON tracks_persistent (url);
CREATE INDEX trackAddedIndex ON tracks_persistent (added);
CREATE INDEX trackRatingIndex ON tracks_persistent (rating);
CREATE INDEX trackPlayCountIndex ON tracks_persistent (playCount);
CREATE INDEX trackLastPlayedIndex ON tracks_persistent (lastPlayed);
