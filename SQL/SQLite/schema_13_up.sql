
DROP TABLE IF EXISTS videos;
CREATE TABLE videos (
  id INTEGER PRIMARY KEY,
  hash char(8) NOT NULL,
  url text NOT NULL,
  title blob,
  titlesort text,
  titlesearch text,
  video_codec varchar(128),
  audio_codec varchar(128),
  mime_type varchar(32),
  dlna_profile varchar(32),
  width int(10),
  height int(10),
  mtime int(10),
  added_time int(10),
  filesize int(10),
  secs float,
  bitrate float,
  channels tinyint(1)
);
CREATE INDEX videoURLIndex ON videos (url);
CREATE INDEX videoHashIndex ON videos (hash);

DROP TABLE IF EXISTS images;
CREATE TABLE images (
  id INTEGER PRIMARY KEY,
  hash char(8) NOT NULL,
  url text NOT NULL,
  title blob,
  titlesort text,
  titlesearch text,
  image_codec varchar(128),
  mime_type varchar(32),
  dlna_profile varchar(32),
  width int(10),
  height int(10),
  mtime int(10),
  added_time int(10),
  filesize int(10)
);
CREATE INDEX imageURLIndex ON images (url);
CREATE INDEX imageHashIndex ON images (hash);
