
-- Create a temporary tracks table to add new columns.
-- http://www.sqlite.org/faq.html
--

BEGIN TRANSACTION;

CREATE TEMPORARY TABLE tracks_backup(
  id integer UNIQUE PRIMARY KEY NOT NULL,
  url varchar UNIQUE NOT NULL,
  title varchar,           -- title
  titlesort varchar,       -- version of title used for sorting
  album integer,           -- album object
  tracknum integer,        -- track number in album
  ct varchar,              -- content type of track
  tag integer,             -- have we read the tags yet
  age integer,             -- timestamp for listing
  fs integer,              -- file size in bytes
  size integer,            -- audio size in bytes
  offset integer,          -- offset to start of track
  year integer,            -- year
  secs integer,            -- total seconds
  cover varchar,           -- cover art
  covertype varchar,       -- cover art content type
  thumb varchar,           -- thumbnail cover art
  thumbtype varchar,       -- thumbnail content type
  vbr_scale varchar,       -- vbr/cbr
  bitrate integer,         -- bitrate
  rate integer,            -- sample rate
  samplesize integer,      -- sample size
  channels integer,        -- number of channels
  blockalign integer,      -- block alignment
  endian integer,          -- 0 - little endian, 1 - big endian
  bpm integer,             -- beats per minute
  tagversion varchar,      -- ID3 tag version
  tagsize integer,         -- tagsize
  drm integer,             -- DRM enabled
  moodlogic_song_id integer, -- moodlogic fields
  moodlogic_artist_id integer,
  moodlogic_genre_id integer,
  moodlogic_song_mixable integer,
  moodlogic_artist_mixable integer,
  moodlogic_genre_mixable integer,
  musicmagic_genre_mixable integer, -- musicmagic fields
  musicmagic_artist_mixable integer,
  musicmagic_album_mixable integer,
  musicmagic_song_mixable integer
);

-- do the copy

INSERT INTO tracks_backup SELECT * FROM tracks;
DROP TABLE tracks;

-- recreate with the new columns

CREATE TABLE tracks (
  id integer UNIQUE PRIMARY KEY NOT NULL,
  url varchar UNIQUE NOT NULL,
  title varchar,           -- title
  titlesort varchar,       -- version of title used for sorting
  album integer,           -- album object
  tracknum integer,        -- track number in album
  ct varchar,              -- content type of track
  tag integer,             -- have we read the tags yet
  age integer,             -- timestamp for listing
  fs integer,              -- file size in bytes
  size integer,            -- audio size in bytes
  offset integer,          -- offset to start of track
  year integer,            -- year
  secs integer,            -- total seconds
  cover varchar,           -- cover art
  covertype varchar,       -- cover art content type
  thumb varchar,           -- thumbnail cover art
  thumbtype varchar,       -- thumbnail content type
  vbr_scale varchar,       -- vbr/cbr
  bitrate integer,         -- bitrate
  rate integer,            -- sample rate
  samplesize integer,      -- sample size
  channels integer,        -- number of channels
  blockalign integer,      -- block alignment
  endian integer,          -- 0 - little endian, 1 - big endian
  bpm integer,             -- beats per minute
  tagversion varchar,      -- ID3 tag version
  tagsize integer,         -- tagsize
  drm integer,             -- DRM enabled
  rating integer,          -- track rating - placeholder
  playCount integer,       -- number of times the track has been played - placeholder
  lastPlayed integer,      -- timestamp of the last play - placeholder
  moodlogic_song_id integer, -- moodlogic fields
  moodlogic_artist_id integer,
  moodlogic_genre_id integer,
  moodlogic_song_mixable integer,
  moodlogic_artist_mixable integer,
  moodlogic_genre_mixable integer,
  musicmagic_genre_mixable integer, -- musicmagic fields
  musicmagic_artist_mixable integer,
  musicmagic_album_mixable integer,
  musicmagic_song_mixable integer
);

CREATE INDEX trackURLIndex ON tracks (url);

CREATE INDEX trackTitleIndex ON tracks (title);

CREATE INDEX trackAlbumIndex ON tracks (album);

CREATE INDEX trackSortIndex ON tracks (titlesort);

CREATE INDEX trackRatingIndex ON tracks (rating);

CREATE INDEX trackPlayCountIndex ON tracks (playCount);

INSERT INTO tracks SELECT * FROM tracks_backup;

DROP TABLE tracks_backup;

UPDATE metainformation SET version = 4;

COMMIT;
