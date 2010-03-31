-- Table to store persistent track information, e.g. ratings and playcounts
-- This data survives a rescan
DROP TABLE IF EXISTS persistentdb.tracks_persistent;
CREATE TABLE persistentdb.tracks_persistent (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  url text NOT NULL,
  musicbrainz_id varchar(40),	-- musicbrainz uuid (36 bytes of text)
  added int(10),
  rating tinyint(1),
  playCount int(10),
  lastPlayed int(10)
);

CREATE INDEX persistentdb.trackMusicBrainzIndex ON tracks_persistent (musicbrainz_id);
CREATE INDEX persistentdb.trackUrlIndex ON tracks_persistent (url);
CREATE INDEX persistentdb.trackAddedIndex ON tracks_persistent (added);
CREATE INDEX persistentdb.trackRatingIndex ON tracks_persistent (rating);
CREATE INDEX persistentdb.trackPlayCountIndex ON tracks_persistent (playCount);
CREATE INDEX persistentdb.trackLastPlayedIndex ON tracks_persistent (lastPlayed);
