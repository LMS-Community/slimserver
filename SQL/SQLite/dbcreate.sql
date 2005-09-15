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

INSERT INTO metainformation VALUES (15, 0, 0);

CREATE TABLE tracks (
  id integer UNIQUE PRIMARY KEY NOT NULL,
  url varchar UNIQUE NOT NULL,
  title varchar,           -- title
  titlesort varchar,       -- version of title used for sorting
  titlesearch varchar,     -- version of title used for searching
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
  disc integer,            -- album number in set
  moodlogic_id integer,    -- moodlogic fields - will eventually be created by the plugin
  playCount integer,       -- number of times the track has been played - placeholder
  lastPlayed integer,      -- timestamp of the last play - placeholder
  audio integer,           -- boolean for audio
  lossless integer,        -- boolean for lossless content
  remote integer,          -- boolean for remote
  lyrics text,             -- lyrics for this track
  moodlogic_mixable integer,
  musicmagic_mixable integer,
  replay_gain float,       -- per track gain
  replay_peak float,       -- per track peak
  multialbumsortkey varchar -- used for sorting tracks in multi album lists
);

CREATE INDEX trackURLIndex ON tracks (url);

CREATE INDEX trackTitleIndex ON tracks (title);

CREATE INDEX trackAlbumIndex ON tracks (album);

CREATE INDEX ctSortIndex ON tracks (ct);

CREATE INDEX trackSortIndex ON tracks (titlesort);

CREATE INDEX trackSearchIndex ON tracks (titlesearch);

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

CREATE TABLE dirlist_track (
  id integer UNIQUE PRIMARY KEY NOT NULL,
  position integer,     -- order of item in the dirlist
  dirlist integer,      -- dirlist object
  item varchar          -- dirlist item
);

CREATE TABLE albums (
  id integer UNIQUE PRIMARY KEY NOT NULL,
  title varchar,           -- title
  titlesort varchar,       -- version of title used for sorting
  titlesearch varchar,     -- version of title used for searching
  contributor varchar,     -- pointer to the album contributor
  compilation integer,     -- boolean for compilation album
  year integer,            -- year
  artwork_path varchar,    -- path to cover art
  disc integer,            -- album number in set
  discc integer,           -- number of albums in set
  replay_gain float,       -- per album gain
  replay_peak float,       -- per album peak
  musicmagic_mixable integer
);

CREATE INDEX albumsTitleIndex ON albums (title);

CREATE INDEX albumsSortIndex ON albums (titlesort);

CREATE INDEX albumsSearchIndex ON albums (titlesearch);

CREATE INDEX compilationSortIndex ON albums (compilation);

CREATE TABLE contributors (
  id integer UNIQUE PRIMARY KEY NOT NULL,
  name varchar,           -- name of contributor
  namesort varchar,       -- version of name used for sorting 
  namesearch varchar,     -- version of name used for search matching 
  moodlogic_id integer,   -- these will eventually be dynamically created by the plugin
  moodlogic_mixable integer,
  musicmagic_mixable integer
);

CREATE INDEX contributorsNameIndex ON contributors (name);

CREATE INDEX contributorsSortIndex ON contributors (namesort);

CREATE INDEX contributorsSearchIndex ON contributors (namesearch);

CREATE TABLE contributor_track (
  id integer UNIQUE PRIMARY KEY NOT NULL,
  role integer,           -- role - enumerated type
  contributor integer,    -- contributor object
  track integer,          -- track object
  namesort varchar        -- convenience for sorting, no longer used
);

CREATE INDEX contributor_trackContribIndex ON contributor_track (contributor);

CREATE INDEX contributor_trackRoleIndex ON contributor_track (role);

CREATE INDEX contributor_trackTrackIndex ON contributor_track (track);

CREATE INDEX contributor_trackSortIndex ON contributor_track (namesort);

CREATE TABLE contributor_album (
  id integer UNIQUE PRIMARY KEY NOT NULL,
  role integer,           -- role - enumerated type
  contributor integer,    -- contributor object
  album integer          -- album object
);

CREATE INDEX contributor_albumContribIndex ON contributor_album (contributor);

CREATE INDEX contributor_albumRoleIndex ON contributor_album (role);

CREATE INDEX contributor_albumAlbumIndex ON contributor_album (album);

CREATE TABLE genres (
  id integer UNIQUE PRIMARY KEY NOT NULL,
  name varchar,           -- genre name
  namesort varchar,       -- version of name used for sorting 
  namesearch varchar,     -- version of name used for searching 
  moodlogic_id integer,   -- these will eventually be dynamically created by the plugin
  moodlogic_mixable integer,
  musicmagic_mixable integer -- musicmagic fields
);

CREATE INDEX genreNameIndex ON genres (name);

CREATE INDEX genreSortIndex ON genres (namesort);

CREATE INDEX genreSearchIndex ON genres (namesearch);

CREATE TABLE genre_track (
  id integer UNIQUE PRIMARY KEY NOT NULL,
  genre integer,          -- genre object
  track integer           -- track object
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
