-- Bug 13600, sort and search columns need to be BLOB instead of TEXT 
-- in order to correctly store UTF-8 data

ALTER TABLE `tracks` CHANGE `titlesort` `titlesort` BLOB NULL DEFAULT NULL;

ALTER TABLE `tracks` CHANGE `titlesearch` `titlesearch` BLOB NULL DEFAULT NULL;

ALTER TABLE `tracks` CHANGE `customsearch` `customsearch` BLOB NULL DEFAULT NULL;

ALTER TABLE `albums` CHANGE `titlesort` `titlesort` BLOB NULL DEFAULT NULL;

ALTER TABLE `albums` CHANGE `titlesearch` `titlesearch` BLOB NULL DEFAULT NULL;

ALTER TABLE `albums` CHANGE `customsearch` `customsearch` BLOB NULL DEFAULT NULL;

ALTER TABLE `contributors` CHANGE `namesort` `namesort` BLOB NULL DEFAULT NULL;

ALTER TABLE `contributors` CHANGE `namesearch` `namesearch` BLOB NULL DEFAULT NULL;

ALTER TABLE `contributors` CHANGE `customsearch` `customsearch` BLOB NULL DEFAULT NULL;

ALTER TABLE `genres` CHANGE `namesort` `namesort` BLOB NULL DEFAULT NULL;

ALTER TABLE `genres` CHANGE `namesearch` `namesearch` BLOB NULL DEFAULT NULL;

ALTER TABLE `genres` CHANGE `customsearch` `customsearch` BLOB NULL DEFAULT NULL;
