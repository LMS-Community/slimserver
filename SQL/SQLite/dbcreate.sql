-- Increment $DBVERSION in Info.pm when you change the schema
CREATE TABLE metainformation (
  version integer,        -- version of this schema
  song_count integer,     -- total song count
  total_time integer      -- cumulative play time
);

CREATE TABLE songs (
  URL varchar UNIQUE PRIMARY KEY NOT NULL,
  TITLE varchar,           -- title
  TITLESORT varchar,       -- version of title used for sorting
  GENRE varchar,           -- genre
  GENRE_ID integer,        -- genre object
  ALBUM varchar,           -- album
  ALBUM_ID varchar,        -- album object
  ALBUMSORT varchar,       -- version of album used for sorting
  ARTIST varchar,          -- artist
  ARTIST_ID integer,       -- artist
  ARTISTSORT varchar,      -- version of artist used for sorting
  COMPOSER varchar,        -- composer 
  BAND varchar,            -- band
  CONDUCTOR varchar,       -- conductor
  CT varchar,              -- content type of song
  TRACKNUM integer,        -- track number in album
  AGE integer,             -- timestamp for listing
  FS integer,              -- file size in bytes
  SIZE integer,            -- audio size in bytes
  OFFSET integer,          -- offset to start of song
  COMMENT varchar,         -- ID3 comment
  YEAR integer,            -- year
  SECS integer,            -- total seconds
  VBR_SCALE varchar,       -- vbr/cbr
  BITRATE integer,         -- bitrate
  TAGVERSION varchar,      -- ID3 tag version
  TAGSIZE integer,         -- tagsize
  DISC integer,            -- album number in set
  DISCC integer,           -- number of albums in set
  MOODLOGIC_SONG_ID integer, -- moodlogic fields
  MOODLOGIC_ARTIST_ID integer,
  MOODLOGIC_GENRE_ID integer,
  MOODLOGIC_SONG_MIXABLE integer,
  MOODLOGIC_ARTIST_MIXABLE integer,
  MOODLOGIC_GENRE_MIXABLE integer,
  COVER varchar,           -- cover art
  COVERTYPE varchar,       -- cover art content type
  THUMB varchar,           -- thumbnail cover art
  THUMBTYPE varchar,       -- thumbnail content type
  TAG integer,             -- have we read the tags yet
  RATE integer,            -- sample rate
  SAMPLESIZE integer,      -- sample size
  CHANNELS integer,        -- number of channels
  BLOCKALIGN integer,      -- block alignment
  ENDIAN integer,          -- 0 - little endian, 1 - big endian
  BPM integer              -- beats per minute
);

CREATE INDEX songURLIndex ON songs (URL);

CREATE INDEX songSearchIndex ON songs (GENRE, ALBUM, ARTIST);

CREATE TABLE genres (
  id integer UNIQUE PRIMARY KEY,
  name varchar
);

CREATE TABLE albums (
  id integer UNIQUE PRIMARY KEY,
  title varchar,
  sortable_title varchar,
  artwork_path varchar,    -- path to cover art
  disc integer,            -- album number in set
  discc integer            -- number of albums in set
);

CREATE TABLE artists (
  id integer UNIQUE PRIMARY KEY,
  name varchar,
  sortable_name varchar
);

CREATE TABLE playlist_track ( 
  id integer UNIQUE PRIMARY KEY,
  position integer,     -- ordering in the playlist
  playlist url,         -- url of playlist
  track url             -- url of contained track
);
