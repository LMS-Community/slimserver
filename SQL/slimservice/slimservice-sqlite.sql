CREATE TABLE playlist_track (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  position int(10),
  playlist int(10),
  track int(10)
);

CREATE INDEX trackIndex ON playlist_track (track);
CREATE INDEX positionIndex ON playlist_track (position);
CREATE INDEX playlistIndex ON playlist_track (playlist);

CREATE TABLE tracks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  url text NOT NULL,
  title blob,
  tracknum int(10),
  content_type varchar(255),
  filesize int(10),
  secs float,
  vbr_scale varchar(255),
  bitrate float,
  remote tinyint(1)
);

CREATE INDEX urlIndex ON tracks (url);