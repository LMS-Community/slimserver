ALTER TABLE tracks ADD primary_artist int(10);

ALTER TABLE tracks ADD INDEX (`primary_artist`);
