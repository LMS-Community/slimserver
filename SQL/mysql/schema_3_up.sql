-- Add contributor column to albums to enable sorting by artist (bug3255)

ALTER TABLE albums ADD contributor int(10) unsigned;
