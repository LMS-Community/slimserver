-- full relational solution for display_artist. commented out for now

--DROP TABLE IF EXISTS contributor_display;
--CREATE TABLE contributor_display (
--  id INTEGER PRIMARY KEY AUTOINCREMENT,
--  name blob);
--ALTER TABLE albums ADD display_contributor integer;

--DROP TABLE IF EXISTS contributor_album_display;
--CREATE TABLE contributor_album_display (
--  contributor_display  int(10),
--  contributor  int(10),
--  album  int(10),
--  PRIMARY KEY (contributor_display,contributor,album),
--  FOREIGN KEY (`album`) REFERENCES `albums` (`id`) ON DELETE CASCADE,
--  FOREIGN KEY (`contributor`) REFERENCES `contributors` (`id`) ON DELETE CASCADE
--);
--CREATE INDEX contributor_album_displayContribIndex ON contributor_album_display (contributor);
--CREATE INDEX contributor_album_displayAlbumIndex ON contributor_album_display (album);
--CREATE INDEX contributor_album_displayContributorDisplayIndex ON contributor_album_display (contributor_display);

--ALTER TABLE tracks ADD display_contributor integer;

--DROP TABLE IF EXISTS contributor_track_display;
--CREATE TABLE contributor_track_display (
--  contributor_display  int(10),
--  contributor  int(10),
--  track int(10),
--  PRIMARY KEY (contributor_display,contributor,track),
--  FOREIGN KEY (`track`) REFERENCES `tracks` (`id`) ON DELETE CASCADE,
--  FOREIGN KEY (`contributor`) REFERENCES `contributors` (`id`) ON DELETE CASCADE
--);
--CREATE INDEX contributor_track_displayContribIndex ON contributor_track_display (contributor);
--CREATE INDEX contributor_track_displayTrackIndex ON contributor_track_display (track);
--CREATE INDEX contributor_track_displayContributorDisplayIndex ON contributor_track_display (contributor_display);

