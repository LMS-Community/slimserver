ALTER TABLE `tracks` CHANGE `titlesort` `titlesort` TEXT NULL DEFAULT NULL;

ALTER TABLE `tracks` CHANGE `titlesearch` `titlesearch` TEXT NULL DEFAULT NULL;

ALTER TABLE `tracks` CHANGE `customsearch` `customsearch` TEXT NULL DEFAULT NULL;

ALTER TABLE `albums` CHANGE `titlesort` `titlesort` TEXT NULL DEFAULT NULL;

ALTER TABLE `albums` CHANGE `titlesearch` `titlesearch` TEXT NULL DEFAULT NULL;

ALTER TABLE `albums` CHANGE `customsearch` `customsearch` TEXT NULL DEFAULT NULL;

ALTER TABLE `contributors` CHANGE `namesort` `namesort` TEXT NULL DEFAULT NULL;

ALTER TABLE `contributors` CHANGE `namesearch` `namesearch` TEXT NULL DEFAULT NULL;

ALTER TABLE `contributors` CHANGE `customsearch` `customsearch` TEXT NULL DEFAULT NULL;

ALTER TABLE `genres` CHANGE `namesort` `namesort` TEXT NULL DEFAULT NULL;

ALTER TABLE `genres` CHANGE `namesearch` `namesearch` TEXT NULL DEFAULT NULL;

ALTER TABLE `genres` CHANGE `customsearch` `customsearch` TEXT NULL DEFAULT NULL;
