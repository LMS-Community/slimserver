DROP TABLE IF EXISTS videos;
DROP TABLE IF EXISTS images;

ALTER TABLE tracks ADD performance blob;
ALTER TABLE tracks ADD discsubtitle blob;
