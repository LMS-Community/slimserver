-- unfortunately SQLite doesn't allow to modify a column definition
-- re-build tracks table from scratch to make url case insensitive
DROP TABLE IF EXISTS tracks;
CREATE TABLE tracks (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	url text NOT NULL COLLATE NOCASE,	-- bug 17457: url needs to be case insensitive, or some import actions on Windows might fail
	title blob,
	titlesort text,
	titlesearch text,
	customsearch text,
	album int(10),
	tracknum int(10),
	content_type varchar(255),
	timestamp int(10),
	filesize int(10),
	audio_size int(10),
	audio_offset int(10),
	year smallint(5),
	secs float,
	cover blob,
	vbr_scale varchar(255),
	bitrate float,
	samplerate int(10),
	samplesize int(10),
	channels tinyint(1),
	block_alignment int(10),
	endian bool,
	bpm smallint(5),
	tagversion varchar(255),
	drm bool,
	disc tinyint(1),
	audio bool,
	remote bool,
	lossless bool,
	lyrics text COLLATE NOCASE, -- needs to be text so that searches are case insensitive.
	musicbrainz_id varchar(40),	-- musicbrainz uuid (36 bytes of text)
	musicmagic_mixable bool,
	replay_gain float,
	replay_peak float,
	extid varchar(64), 
	primary_artist int(10), 
	urlmd5 char(32) NOT NULL default '0', 
	coverid char(8) default NULL, 
	cover_cached char(1) default NULL, 
	virtual char(1) default NULL,
	added_time int(10) default NULL,
	updated_time int(10) default NULL,
	FOREIGN KEY (`album`) REFERENCES `albums` (`id`) ON DELETE CASCADE
);
