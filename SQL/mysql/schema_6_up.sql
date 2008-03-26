-- Add primary contributor data to tracks, to improve performance
-- of loops where many tracks are displayed, such as playlist and search results

ALTER TABLE tracks ADD primary_contributor int(10) unsigned;

ALTER TABLE tracks ADD num_contributors tinyint(1);

ALTER TABLE tracks ADD INDEX trackPrimaryContributorIndex (primary_contributor);

ALTER TABLE tracks ADD 
	CONSTRAINT `tracks_ibfk_2` 
	FOREIGN KEY (`primary_contributor`)
	REFERENCES `contributors` (`id`)
	ON DELETE CASCADE;
