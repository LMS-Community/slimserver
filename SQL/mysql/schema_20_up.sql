-- Schema 19 unfortunately got the order of the columns in the primary key wrong
CREATE INDEX libraryTrackIndex ON library_track (library);


--
-- Table: library_album
--
DROP TABLE IF EXISTS library_album;
CREATE TABLE library_album (
  album int(10) unsigned,
  library char(8),
  PRIMARY KEY (library,album),
  FOREIGN KEY (`album`) REFERENCES `albums` (`id`) ON DELETE CASCADE
);
CREATE INDEX libraryAlbumIndex ON library_album (album);

--
-- Table: library_contributor
--
DROP TABLE IF EXISTS library_contributor;
CREATE TABLE library_contributor (
  contributor int(10) unsigned,
  library char(8),
  PRIMARY KEY (library,contributor),
  FOREIGN KEY (`contributor`) REFERENCES `contributors` (`id`) ON DELETE CASCADE
);
CREATE INDEX libraryContributorIndex ON library_contributor (contributor);

--
-- Table: library_genre
--
DROP TABLE IF EXISTS library_genre;
CREATE TABLE library_genre (
  genre int(10) unsigned,
  library char(8),
  PRIMARY KEY (library,genre),
  FOREIGN KEY (`genre`) REFERENCES `genres` (`id`) ON DELETE CASCADE
);
CREATE INDEX libraryGenreIndex ON library_genre (genre);
