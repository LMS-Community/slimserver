-- 
--

ALTER TABLE tracks ADD COLUMN multialbumsortkey text;

ALTER TABLE tracks ADD INDEX trackSortKeyIndex (multialbumsortkey(255));

UPDATE metainformation SET version = 6;
