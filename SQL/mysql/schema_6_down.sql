ALTER TABLE tracks DROP FOREIGN KEY `tracks_ibfk_2`;

ALTER TABLE tracks DROP INDEX trackPrimaryContributorIndex;

ALTER TABLE tracks DROP primary_contributor;

ALTER TABLE tracks DROP num_contributors;