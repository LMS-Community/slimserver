ALTER TABLE contributors ADD picture blob default NULL;

ALTER TABLE contributors ADD pictureid char(8) default NULL;
CREATE INDEX pictureidIndex ON contributors (pictureid);
