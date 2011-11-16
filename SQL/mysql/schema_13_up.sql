DROP TABLE IF EXISTS videos;
CREATE TABLE videos (
  id int(10) unsigned NOT NULL auto_increment,
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
  channels tinyint(1),
  INDEX videoURLIndex (url(255)),
  INDEX videoHashIndex (hash),
  PRIMARY KEY (id)
) ENGINE=InnoDB CHARACTER SET utf8 COLLATE utf8_unicode_ci;

DROP TABLE IF EXISTS images;
CREATE TABLE images (
  id int(10) unsigned NOT NULL auto_increment,
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
  filesize int(10),
  INDEX imageURLIndex (url(255)),
  INDEX imageHashIndex (hash),
  PRIMARY KEY (id)
) ENGINE=InnoDB CHARACTER SET utf8 COLLATE utf8_unicode_ci;
