--
-- Recreate the contributor_album table to ensure it is accurate (bug 4882).
-- This is done here as it is faster to do in sql than in the server.
--

-- XXX This appears to not be needed anymore as contributors are properly
-- removed by the new scanner

--DELETE FROM contributor_album;

--INSERT INTO contributor_album (role,contributor,album) SELECT DISTINCT role,contributor,album FROM contributor_track,tracks where tracks.id=contributor_track.track;

--
-- Optimise the schema
--

OPTIMIZE TABLE tracks;

OPTIMIZE TABLE playlist_track;

OPTIMIZE TABLE albums;

OPTIMIZE TABLE years;

OPTIMIZE TABLE contributors;

OPTIMIZE TABLE contributor_track;

OPTIMIZE TABLE contributor_album;

OPTIMIZE TABLE genres;

OPTIMIZE TABLE genre_track;

OPTIMIZE TABLE comments;

OPTIMIZE TABLE pluginversion;

OPTIMIZE TABLE unreadable_tracks;
