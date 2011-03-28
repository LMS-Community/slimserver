
DROP TABLE IF EXISTS videos;
CREATE TABLE videos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  url text NOT NULL,
  title blob,
  video_codec varchar(128),
  audio_codec varchar(128),
  dlna_profile varchar(32),
  width int(10),
  height int(10),
  mtime int(10),
  added_time int(10),
  filesize int(10),
  secs float,
  cover blob,
  bitrate float,
  channels tinyint(1)
);
CREATE INDEX videoURLIndex ON videos (url);
