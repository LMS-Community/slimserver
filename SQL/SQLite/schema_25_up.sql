ALTER TABLE contributors ADD portrait blob default NULL;

ALTER TABLE contributors ADD portraitid char(8) default NULL;
CREATE INDEX portraitidIndex ON contributors (portraitid);
