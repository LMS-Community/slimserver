-- Increment the version below when you change the schema.
-- You also need to add an Upgrade script to the Upgrades 
-- directory and alter sql.version
--
-- It's important that there is a newline between all 
-- SQL statements, otherwise the parser will skip them.

CREATE TABLE metainformation (
  version integer,        -- version of this schema
  track_count integer,     -- total track count
  total_time integer      -- cumulative play time
);

INSERT INTO metainformation VALUES (19, 0, 0);

CREATE TABLE tracks (
  id integer UNIQUE PRIMARY KEY NOT NULL,
  url varchar UNIQUE NOT NULL,
  title varchar,           -- title
  titlesort varchar,       -- version of title used for sorting
  titlesearch varchar,     -- version of title used for searching
  customsearch varchar,    -- version of title optionally used by plugins
  album integer,           -- album object
  tracknum integer,        -- track number in album
  content_type varchar,    -- content type of track
  tag integer,             -- have we read the tags yet
  timestamp integer,       -- timestamp for listing
  filesize integer,        -- file size in bytes
  audio_size integer,      -- audio size in bytes
  audio_offset integer,    -- offset to start of track
  year integer,            -- year
  secs integer,            -- total seconds
  cover varchar,           -- cover art
  thumb varchar,           -- thumbnail cover art
  vbr_scale varchar,       -- vbr/cbr
  bitrate integer,         -- bitrate
  samplerate integer,      -- sample rate
  samplesize integer,      -- sample size
  channels integer,        -- number of channels
  block_alignment integer, -- block alignment
  endian integer,          -- 0 - little endian, 1 - big endian
  bpm integer,             -- beats per minute
  tagversion varchar,      -- ID3 tag version
  drm integer,             -- DRM enabled
  rating integer,          -- track rating - placeholder
  disc integer,            -- album number in set
  moodlogic_id integer,    -- moodlogic fields - will eventually be created by the plugin
  playCount integer,       -- number of times the track has been played - placeholder
  lastPlayed integer,      -- timestamp of the last play - placeholder
  audio integer,           -- boolean for audio
  lossless integer,        -- boolean for lossless content
  remote integer,          -- boolean for remote
  lyrics text,             -- lyrics for this track
  moodlogic_mixable integer,
  musicbrainz_id varchar,  -- musicbrainz uuid (36 bytes of text)
  musicmagic_mixable integer,
  replay_gain float,       -- per track gain
  replay_peak float,       -- per track peak
  multialbumsortkey varchar -- used for sorting tracks in multi album lists
);

CREATE INDEX trackURLIndex ON tracks (url);

CREATE INDEX trackTitleIndex ON tracks (title);

CREATE INDEX trackAlbumIndex ON tracks (album);

CREATE INDEX ctSortIndex ON tracks (content_type);

CREATE INDEX trackSortIndex ON tracks (titlesort);

CREATE INDEX trackSearchIndex ON tracks (titlesearch);

CREATE INDEX trackCustomSearchIndex ON tracks (customsearch);

CREATE INDEX trackRatingIndex ON tracks (rating);

CREATE INDEX trackPlayCountIndex ON tracks (playCount);

CREATE INDEX trackAudioIndex ON tracks (audio);

CREATE INDEX trackLosslessIndex ON tracks (lossless);

CREATE INDEX trackRemoteIndex ON tracks (remote);

CREATE INDEX trackSortKeyIndex ON tracks (multialbumsortkey);

CREATE TABLE playlist_track (
  id integer UNIQUE PRIMARY KEY NOT NULL,
  position integer,     -- order of track in the playlist
  playlist integer,     -- playlist object
  track integer         -- track object
);

CREATE TABLE albums (
  id integer UNIQUE PRIMARY KEY NOT NULL,
  title varchar,           -- title
  titlesort varchar,       -- version of title used for sorting
  titlesearch varchar,     -- version of title used for searching
  customsearch varchar,    -- version of title optionally used by plugins
  contributor varchar,     -- pointer to the album contributor
  compilation integer,     -- boolean for compilation album
  year integer,            -- year
  artwork integer,         -- pointer to a track id that contains artwork.
  disc integer,            -- album number in set
  discc integer,           -- number of albums in set
  replay_gain float,       -- per album gain
  replay_peak float,       -- per album peak
  musicbrainz_id varchar,  -- musicbrainz uuid (36 bytes of text)
  musicmagic_mixable integer
);

CREATE INDEX albumsTitleIndex ON albums (title);

CREATE INDEX albumsSortIndex ON albums (titlesort);

CREATE INDEX albumsSearchIndex ON albums (titlesearch);

CREATE INDEX albumsCustomSearchIndex ON albums (customsearch);

CREATE INDEX compilationSortIndex ON albums (compilation);

CREATE TABLE contributors (
  id integer UNIQUE PRIMARY KEY NOT NULL,
  name varchar,           -- name of contributor
  namesort varchar,       -- version of name used for sorting 
  namesearch varchar,     -- version of name used for search matching 
  customsearch varchar,   -- version of name optionally used by plugins
  moodlogic_id integer,   -- these will eventually be dynamically created by the plugin
  moodlogic_mixable integer,
  musicbrainz_id varchar,  -- musicbrainz uuid (36 bytes of text)
  musicmagic_mixable integer
);

CREATE INDEX contributorsNameIndex ON contributors (name);

CREATE INDEX contributorsSortIndex ON contributors (namesort);

CREATE INDEX contributorsSearchIndex ON contributors (namesearch);

CREATE INDEX contributorsCustomSearchIndex ON contributors (customsearch);

CREATE TABLE contributor_track (
  role integer,           -- role - enumerated type
  contributor integer,    -- contributor object
  track integer,          -- track object
  UNIQUE (role,contributor,track)
);

CREATE INDEX contributor_trackContribIndex ON contributor_track (contributor);

CREATE INDEX contributor_trackRoleIndex ON contributor_track (role);

CREATE INDEX contributor_trackTrackIndex ON contributor_track (track);

CREATE TABLE contributor_album (
  role integer,           -- role - enumerated type
  contributor integer,    -- contributor object
  album integer,          -- album object
  UNIQUE (role,contributor,album)
);

CREATE INDEX contributor_albumContribIndex ON contributor_album (contributor);

CREATE INDEX contributor_albumRoleIndex ON contributor_album (role);

CREATE INDEX contributor_albumAlbumIndex ON contributor_album (album);

CREATE TABLE genres (
  id integer UNIQUE PRIMARY KEY NOT NULL,
  name varchar,           -- genre name
  namesort varchar,       -- version of name used for sorting 
  namesearch varchar,     -- version of name used for searching 
  customsearch varchar,   -- version of name optionally used by plugins
  moodlogic_id integer,   -- these will eventually be dynamically created by the plugin
  moodlogic_mixable integer,
  musicmagic_mixable integer -- musicmagic fields
);

CREATE INDEX genreNameIndex ON genres (name);

CREATE INDEX genreSortIndex ON genres (namesort);

CREATE INDEX genreSearchIndex ON genres (namesearch);

CREATE INDEX genreCustomSearchIndex ON genres (customsearch);

CREATE TABLE genre_track (
  genre integer,          -- genre object
  track integer,          -- track object
  UNIQUE (genre,track)
);

CREATE INDEX genre_trackGenreIndex ON genre_track (genre);

CREATE INDEX genre_trackTrackIndex ON genre_track (track);

CREATE TABLE comments (
  id integer UNIQUE PRIMARY KEY NOT NULL,
  track integer,          -- track object
  value varchar           -- text of comment
);

CREATE TABLE pluginversion (
  id integer UNIQUE PRIMARY KEY NOT NULL,
  name varchar,		    -- plugin name
  version integer      -- plugin version
);
