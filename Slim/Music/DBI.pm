package Slim::Music::DBI;

# $Id: DBI.pm,v 1.1 2004/08/13 07:42:31 vidur Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base 'Class::DBI';
use DBI;

use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);
use Slim::Utils::Misc;

my $dbh;
# Increment this version when you change the schema.
my $DBVERSION = 1;

sub executeSQLFile {
    my $driver = Slim::Utils::Prefs::get('dbsource');
	$driver =~ s/dbi:(.*?):(.*)$/$1/;
	my $sqlfilename = catdir($Bin, "SQL", $driver, shift);

	$::d_info && Slim::Utils::Misc::msg("Executing SQL file $sqlfilename\n");
	if (open my $sqlfile, $sqlfilename) {
		my $statement = '';
		for my $line (<$sqlfile>) {
			if ($line =~ /^\s$/ && $statement) {
				$dbh->do($statement);
				$statement = '';
			}
			else {
				$statement .= $line;
			}
		}
		if ($statement) {
			$dbh->do($statement);
		}
		$dbh->commit;
		close $sqlfile;
	}
}

sub db_Main() {
	return $dbh if defined $dbh;

	my $dbname;
	if (Slim::Utils::OSDetect::OS() eq 'unix') {
		$dbname = '.slimserversql.db';
	} else {
		$dbname ='slimserversql.db';
	}

	$dbname = catdir(Slim::Utils::Prefs::get('cachedir'), $dbname);
	$::d_info && Slim::Utils::Misc::msg("ID3 tag database support is ON, saving into: $dbname\n");

	my $source = sprintf(Slim::Utils::Prefs::get('dbsource'), $dbname);
	my $username = Slim::Utils::Prefs::get('dbusername');
	my $password = Slim::Utils::Prefs::get('dbpassword');
	$dbh = DBI->connect($source, $username, $password, { 
		RaiseError => 1,
		AutoCommit => 0,
		PrintError => 1,
		Taint      => 1,
		RootClass  => "DBIx::ContextualFetch"
		});
	$dbh || Slim::Utils::Misc::msg("Couldn't connect to info database\n");

	$::d_info && Slim::Utils::Misc::msg("Connected to database $source\n");

	my @tables = $dbh->tables();
	
	my $version;
	foreach my $table (@tables) {
		if ($table =~ /metainformation/) {
			($version) = $dbh->selectrow_array("SELECT version FROM metainformation");
			last;
		}
	}
	
	if ($version && $version != $DBVERSION) {
		$::d_info && Slim::Utils::Misc::msg("Database schema out of date. Purging db.\n");
		executeSQLFile("dbdrop.sql");
		$version = undef;
	}
	
	if (!defined($version)) {
		$::d_info && Slim::Utils::Misc::msg("Creating new database.\n");
		executeSQLFile("dbcreate.sql");
		my $SQL = "INSERT INTO metainformation VALUES ($DBVERSION, 0, 0)";
		$dbh->do($SQL);
		$dbh->commit;
	}

	return $dbh;
}

sub wipeDB {
	executeSQLFile("dbclear.sql");
	$dbh = undef;
}

sub getMetaInformation {
	$dbh->selectrow_array("SELECT song_count, total_time FROM metainformation");
}

sub setMetaInformation {
	my ($song_count, $total_time) = @_;
	$dbh->do("UPDATE metainformation SET song_count = " . $song_count . ", total_time  = " . $total_time);
}

sub filtersToWhereClause {
	my $column = shift;
	my $clause = '';
	my $first = 1;

	if (!defined($_[0]) || $_[0] eq '' || $_[0] eq '*') {
		return undef;
	}

	my @escaped = map { $dbh->quote($_) } @_;
	my @filters = map { $column . (($_ =~ s/\*/%/g) ? " LIKE " : " = ") . $_ } @escaped;

	return join " OR ", @filters;
}


package Slim::Music::Song;

use base 'Slim::Music::DBI';

my %primaryColumns = (
	'URL' => 'url',
);

my %essentialColumns = (
	'TITLE' => 'title',
	'GENRE_ID' => 'genre_id',
	'ALBUM_ID' => 'album_id',
	'ARTIST_ID' => 'artist_id',
	'CT' => 'content_type',
	'TRACKNUM' => 'tracknum',
	'AGE' => 'timestamp',
	'FS' => 'filesize',
	'TAG' => 'tag',
	'THUMB' => 'thumb',
);

my %otherColumns = (
	'TITLESORT' => 'sortable_title',
	'GENRE' => 'genre',
	'ALBUM' => 'album',
	'ALBUMSORT' => 'sortable_album',
	'ARTIST' => 'artist',
	'ARTISTSORT' => 'sortable_artist',
	'COMPOSER' => 'composer',
	'BAND' => 'band',
	'CONDUCTOR' => 'conductor',
	'SIZE' => 'audio_size',
	'OFFSET' => 'audio_offset',
	'COMMENT' => 'comment',
	'YEAR' => 'year',
	'SECS' => 'secs',
	'VBR_SCALE' => 'vbr_scale',
	'BITRATE' => 'bitrate',
	'TAGVERSION' => 'tagversion',
	'TAGSIZE' => 'tagsize',
	'DISC' => 'disc',
	'DISCC' => 'discc',
	'MOODLOGIC_SONG_ID' => 'moodlogic_song_id',
	'MOODLOGIC_ARTIST_ID' => 'moodlogic_artist_id',
	'MOODLOGIC_GENRE_ID' => 'moodlogic_genre_id',
	'MOODLOGIC_SONG_MIXABLE' => 'moodlogic_song_mixable',
	'MOODLOGIC_ARTIST_MIXABLE' => 'moodlogic_artist_mixable',
	'MOODLOGIC_GENRE_MIXABLE' => 'moodlogic_genre_mixable',
	'COVER' => 'cover',
	'COVERTYPE' => 'covertype',
	'THUMBTYPE' => 'thumbtype',
	'RATE' => 'samplerate',
	'SAMPLESIZE' => 'samplesize',
	'CHANNELS' => 'channels',
	'BLOCKALIGN' => 'block_alignment',
    'ENDIAN' => 'endian',
	'BPM' => 'bpm',
);

my %allColumns = ( %primaryColumns, %essentialColumns, %otherColumns );

__PACKAGE__->table('songs');
__PACKAGE__->columns(Primary => keys %primaryColumns);
__PACKAGE__->columns(Essential => keys %essentialColumns);
__PACKAGE__->columns(Others => keys %otherColumns);
__PACKAGE__->has_a(GENRE_ID => 'Slim::Music::Genre');
__PACKAGE__->has_a(ALBUM_ID => 'Slim::Music::Album');
__PACKAGE__->has_a(ARTIST_ID => 'Slim::Music::Artist');
__PACKAGE__->has_many(tracks => [ 'Slim::Music::Track' => 'track' ] => 'playlist');
__PACKAGE__->add_constructor(externalPlaylists => qq{
	url LIKE 'itunesplaylist:%' OR
	url LIKE 'moodlogicplaylist:%'
});

sub columnNames {
	return \%allColumns;
}

sub accessor_name {
	my ($class, $column) = @_;
	
	return $allColumns{$column};
}

sub songSearch {
	my $genrePatterns = shift;
	my $artistPatterns = shift;
	my $albumPatterns = shift;
	my $songPatterns = shift;
	my $sortbytitle = shift;
	my $count = shift;

	my $multalbums  = (scalar(@$albumPatterns) == 1 && $albumPatterns->[0] !~ /\*/  && (!defined($artistPatterns->[0]) || $artistPatterns->[0] eq '*'));
	my $tracksort   = !$multalbums && !$sortbytitle;

	my $clause = '';
	if (defined($genrePatterns) && scalar(@$genrePatterns)) {
		my $genreClause = Slim::Music::DBI::filtersToWhereClause("GENRE", 
															  @$genrePatterns);
		if ($genreClause) {
			$clause = $genreClause;
		}
	}

	if (defined($artistPatterns) && scalar(@$artistPatterns)) {
		my $artistClause = Slim::Music::DBI::filtersToWhereClause("ARTIST",
															 @$artistPatterns);
		if ($artistClause) {
			$clause .= " AND " if ($clause);
			$clause .= $artistClause;
		}
	}

	if (defined($albumPatterns) && scalar(@$albumPatterns)) {
		my $albumClause = Slim::Music::DBI::filtersToWhereClause("ALBUM",
															   @$albumPatterns);
		if ($albumClause) {
			$clause .= " AND " if ($clause);
			$clause .= $albumClause;
		}
	}

	if (defined($songPatterns) && scalar(@$songPatterns)) {
		my $songClause = Slim::Music::DBI::filtersToWhereClause("TITLE", @$songPatterns);
		if ($songClause) {
			$clause .= " AND " if ($clause);
			$clause .= $songClause;
		}
	}

	my $SQL = '';
	if ($count) {
		$SQL .= "SELECT COUNT(*) FROM(";
	}
	$SQL .= "SELECT DISTINCT " . 
		join(",", __PACKAGE__->columns('Essential')) .
		" FROM songs";
	$SQL .= " WHERE $clause" if $clause;
	if ($count) {
		$SQL .= ")";
	}
	elsif ($sortbytitle) {
		$SQL .= " ORDER BY TITLESORT";
	}
	elsif ($tracksort) {
		$SQL .= " ORDER BY ARTISTSORT, ALBUMSORT, DISC, TRACKNUM, TITLESORT";
	}
	else {
		$SQL .= " ORDER BY ALBUMSORT, DISC, TRACKNUM, TITLESORT";
	}

	$::d_info && Slim::Utils::Misc::msg("Executing SQL statement $SQL\n");
	my $sth = __PACKAGE__->db_Main()->prepare_cached($SQL);
	if ($count) {
		return $sth->select_val;
	}
	return __PACKAGE__->sth_to_objects($sth);
}


package Slim::Music::Genre;

use base 'Slim::Music::DBI';

__PACKAGE__->table('genres');
__PACKAGE__->columns(All => qw/id name/);
__PACKAGE__->set_sql(count_all => "SELECT COUNT(*) FROM __TABLE__");

sub genreSearch {
	my $genrePatterns = shift;
	my $clause;

	if (defined($genrePatterns) && scalar(@$genrePatterns)) {
		$clause = Slim::Music::DBI::filtersToWhereClause("name", 
															 @$genrePatterns);
	}

	if ($clause) {
		$clause .= " ORDER BY sortable_name";
		return __PACKAGE__->retrieve_from_sql($clause);
	}
	
	return __PACKAGE__->retrieve_all;
}

package Slim::Music::Album;

use base 'Slim::Music::DBI';

__PACKAGE__->table('albums');
__PACKAGE__->columns(All => qw/id title sortable_title artwork_path disc discc/);
__PACKAGE__->set_sql(count_all => "SELECT COUNT(*) FROM __TABLE__");
__PACKAGE__->add_constructor('hasArtwork' => 'artwork_path IS NOT NULL');

sub albumSearch {
	my $genrePatterns = shift;
	my $artistPatterns = shift;
	my $albumPatterns = shift;
	my $count = shift;

	my $clause = '';
	if (defined($genrePatterns) && scalar(@$genrePatterns)) {
		my $genreClause = Slim::Music::DBI::filtersToWhereClause("songs.GENRE", @$genrePatterns);
		if ($genreClause) {
			$clause = $genreClause;
		}
	}

	if (defined($artistPatterns) && scalar(@$artistPatterns)) {
		my $artistClause = Slim::Music::DBI::filtersToWhereClause("songs.ARTIST", @$artistPatterns);
		if ($artistClause) {
			$clause .= " AND " if ($clause);
			$clause .= $artistClause;
		}
	}

	if (defined($albumPatterns) && scalar(@$albumPatterns)) {
		my $albumClause = Slim::Music::DBI::filtersToWhereClause("songs.ALBUM", @$albumPatterns);
		if ($albumClause) {
			$clause .= " AND " if ($clause);
			$clause .= $albumClause;
		}
	}

	my $SQL = '';
	if ($count) {
		$SQL .= "SELECT COUNT(*) FROM(";
	}
	$SQL .= "SELECT DISTINCT " .
		join(",", map {"albums.".$_}__PACKAGE__->columns('All')) .
		" FROM albums";
	if ($clause) {
		$SQL .= " JOIN songs ON albums.id=songs.ALBUM_ID WHERE $clause";
	}
	if ($count) {
		$SQL .= ")";
	}
	else {
		$SQL .= " ORDER BY albums.sortable_title";
	}

	$::d_info && Slim::Utils::Misc::msg("Executing SQL statement $SQL\n");
	my $sth = __PACKAGE__->db_Main()->prepare_cached($SQL);
	if ($count) {
		return $sth->select_val;
	}
	return __PACKAGE__->sth_to_objects($sth);
}


package Slim::Music::Artist;

use base 'Slim::Music::DBI';

__PACKAGE__->table('artists');
__PACKAGE__->columns(All => qw/id name sortable_name/);
__PACKAGE__->set_sql(count_all => "SELECT COUNT(*) FROM __TABLE__");

sub artistSearch {
	my $genrePatterns = shift;
	my $artistPatterns = shift;
	my $albumPatterns = shift;
	my $count = shift;

	my $clause = '';
	if (defined($genrePatterns) && scalar(@$genrePatterns)) {
		my $genreClause = Slim::Music::DBI::filtersToWhereClause("songs.GENRE", @$genrePatterns);
		if ($genreClause) {
			$clause = $genreClause;
		}
	}

	if (defined($artistPatterns) && scalar(@$artistPatterns)) {
		my $artistClause = Slim::Music::DBI::filtersToWhereClause("songs.ARTIST", @$artistPatterns);
		if ($artistClause) {
			$clause .= " AND " if ($clause);
			$clause .= $artistClause;
		}
	}

	if (defined($albumPatterns) && scalar(@$albumPatterns)) {
		my $albumClause = Slim::Music::DBI::filtersToWhereClause("songs.ALBUM", @$albumPatterns);
		if ($albumClause) {
			$clause .= " AND " if ($clause);
			$clause .= $albumClause;
		}
	}

	my $SQL = '';
	if ($count) {
		$SQL .= "SELECT COUNT(*) FROM(";
	}
	$SQL .= "SELECT DISTINCT " .
		join(",", map {"artists.".$_} __PACKAGE__->columns('All')) .
		" FROM artists";
	if ($clause) {
		$SQL .= "  JOIN songs ON artists.id=songs.ARTIST_ID WHERE $clause";
	}
	if ($count) {
		$SQL .= ")";
	}
	else {
		$SQL .= " ORDER BY artists.sortable_name";
	}

	$::d_info && Slim::Utils::Misc::msg("Executing SQL statement $SQL\n");
	my $sth = __PACKAGE__->db_Main()->prepare_cached($SQL);
	if ($count) {
		return $sth->select_val;
	}
	return __PACKAGE__->sth_to_objects($sth);
}


package Slim::Music::Track;

use base 'Slim::Music::DBI';

__PACKAGE__->table('playlist_track');
__PACKAGE__->columns(All => qw/id position playlist track/);
__PACKAGE__->has_a(playlist => 'Slim::Music::Song');
__PACKAGE__->has_a(track => 'Slim::Music::Song');
__PACKAGE__->add_constructor('tracksof' => 'playlist=? ORDER BY position');

1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
