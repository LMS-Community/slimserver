package Slim::DataStores::DBI::DataModel;

# $Id: DataModel.pm,v 1.3 2004/12/13 19:46:01 vidur Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base 'Class::DBI';
use DBI;
use SQL::Abstract;

use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);
use Slim::Utils::Misc;

my $dbh;

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

	my $version;
	my $nextversion;
	do {
		my @tables = $dbh->tables();
	
		foreach my $table (@tables) {
			if ($table =~ /metainformation/) {
				($version) = $dbh->selectrow_array("SELECT version FROM metainformation");
				last;
			}
		}

		if (defined($version)) {
			$nextversion=findUpgrade($version);
			
			if ($nextversion && ($nextversion ne 99999)) {
				my $upgradeFile = catdir("Upgrades", $nextversion.".sql" );
				$::d_info && Slim::Utils::Misc::msg("Upgrading to version ".$nextversion." from version ".$version.".\n");
				executeSQLFile($upgradeFile);
			}
			elsif ($nextversion && ($nextversion eq 99999)) {
				$::d_info && Slim::Utils::Misc::msg("Database schema out of date and purge required. Purging db.\n");
				executeSQLFile("dbdrop.sql");
				$version = undef;
				$nextversion=0;
			}
		}
	} while ($nextversion);
	
	if (!defined($version)) {
		$::d_info && Slim::Utils::Misc::msg("Creating new database.\n");
		executeSQLFile("dbcreate.sql");
	}
	$dbh->commit;
	
  	return $dbh;
}

sub findUpgrade {
	my $currVersion = shift;
	my $driver = Slim::Utils::Prefs::get('dbsource');
	$driver =~ s/dbi:(.*?):(.*)$/$1/;
	my $sqlVerFilePath = catdir($Bin, "SQL", $driver, "sql.version" );
	my $versionFile;
	
	if (!open($versionFile, "<$sqlVerFilePath")) {
		warn("can't open $sqlVerFilePath\n");
		return 0;
	}
	
	my $line;
	my ($from, $to);
	while ($line = <$versionFile>) {
		$line=~/^(\d+)\s+(\d+)\s*$/ || next;
		($from, $to) = ($1, $2);
		$from == $currVersion && last;
	}
	
	close($versionFile);
	
	if ((!defined $from) || ($from != $currVersion)) {
		$::d_info && Slim::Utils::Misc::msg ("No upgrades found for database v. ". $currVersion."\n");
		return 0;
	}
	
	my $file = shift || catdir($Bin, "SQL", $driver, "Upgrades", "$to.sql");
	
	if (!-f $file && ($to != 99999)) {
		$::d_info && Slim::Utils::Misc::msg ("database v. ".$currVersion." should be upgraded to v. $to but the files does not exist!\n");
		return 0;
	}
	
	$::d_info && Slim::Utils::Misc::msg ("database v. ".$currVersion." requires upgrade to $to\n");
	return $to;
}


sub wipeDB {
	Slim::DataStores::DBI::DataModel->clear_object_index();
	executeSQLFile("dbclear.sql");
	$dbh = undef;
}

sub getMetaInformation {
	$dbh->selectrow_array("SELECT track_count, total_time FROM metainformation");
}

sub setMetaInformation {
	my ($track_count, $total_time) = @_;
	$dbh->do("UPDATE metainformation SET track_count = " . $track_count . ", total_time  = " . $total_time);
}

sub searchPattern {
	my $class = shift;
	my $tableName = shift;
	my $where = shift;
	my $order = shift;
	my $package = shift;

	my $sql  = SQL::Abstract->new(cmp => 'like');

    my($stmt, @bind) = $sql->select($tableName, 'id', $where, $order);

 	my $sth = db_Main()->prepare($stmt);
    $sth->execute(@bind);
	my @objs = $package->sth_to_objects($sth);
	return \@objs;
}

sub getWhereValues {
	my $term = shift;

	if (!defined($term)) {
		return ();
	}

	my @values = ();
	if (ref $term eq 'ARRAY') {
		for my $item (@$term) {
			if (ref $item) {
				push @values, $item->id;
			}
			elsif (defined($item) && $item ne '') {
				push @values, $item;
			}
		}
	}
	elsif (ref $term) {
		push @values, $term->id;
	}
	elsif (defined($term) && $term ne '') {
		push @values, $term;
	}

	return @values;
}

sub findTermsToWhereClause {
	my $column = shift;
	my $term = shift;
	my $clause = '';

	my @values = getWhereValues($term);

	return $column . " IN (" . join(",", @values) . ")" if scalar(@values);
	return undef;
}

my %fieldHasClass = (
	'track' => 'Slim::DataStores::DBI::Track',
	'genre' => 'Slim::DataStores::DBI::Genre',
	'album' => 'Slim::DataStores::DBI::Album',
	'artist' => 'Slim::DataStores::DBI::Contributor',
	'contributor' => 'Slim::DataStores::DBI::Contributor',
	'conductor' => 'Slim::DataStores::DBI::Contributor',
	'composer' => 'Slim::DataStores::DBI::Contributor',
	'band' => 'Slim::DataStores::DBI::Contributor',
);

my %searchFieldMap = (
	'id' => 'tracks.id',
	'url' => 'tracks.url', 
	'title' => 'tracks.title', 
	'track' => 'tracks.id', 
	'tracknum' => 'tracks.tracknum', 
	'ct' => 'tracks.ct', 
	'size' => 'tracks.size', 
	'year' => 'tracks.year', 
	'secs' => 'tracks.secs', 
	'vbr_scale' => 'tracks.vbr_scale',
	'bitrate' => 'tracks.bitrate', 
	'rate' => 'tracks.rate', 
	'samplesize' => 'tracks.samplesize', 
	'channels' => 'tracks.channels', 
	'bpm' => 'tracks.bpm', 
	'album' => 'tracks.album',
	'genre' => 'genre_track.genre', 
	'contributor' => 'contributor_track.contributor', 
	'artist' => 'contributor_track.contributor', 
	'conductor' => 'contributor_track.contributor', 
	'composer' => 'contributor_track.contributor', 
	'band' => 'contributor_track.contributor', 
);

my %sortFieldMap = (
  'title' => ['tracks.titlesort'],
  'genre' => ['genres.name'],
  'album' => ['albums.titlesort','albums.disc','tracks.tracknum','tracks.titlesort'],
  'contributor' => ['contributors.namesort'],
  'artist' => ['contributors.namesort'],
  'track' => ['contributor_track.namesort','albums.titlesort','albums.disc','tracks.tracknum','tracks.titlesort'],
  'tracknum' => ['tracks.tracknum','tracks.titlesort'],
);  

sub find {
	my $class = shift;
	my $field = shift;
	my $findCriteria = shift;
	my $sortby = shift;
	my $c;

	my $columns = "DISTINCT ";
	if ($c = $fieldHasClass{$field}) {
		my $table = $c->table;
		$columns .= join(",", map {$table . '.' . $_ . " AS " . $_} $c->columns('Essential'));
	}
	elsif (defined($searchFieldMap{$field})) {
		$columns .= $searchFieldMap{$field};
	}
	else {
		$::d_info && msg("Request for unknown field in query\n");
		return undef;
	}
	
	my %whereHash =();
	while (my ($key, $val) = each %$findCriteria) {
		if (defined($searchFieldMap{$key})) {
			my @values = getWhereValues($val);
			if (scalar(@values)) {
				$whereHash{$searchFieldMap{$key}} = scalar(@values) > 1 ?
					\@values : $values[0];
			}
		}
	}

	my $sortFields;
	if (defined($sortby) && $sortFieldMap{$sortby}) {
		$sortFields = $sortFieldMap{$sortby};
	}
	else {
		$sortFields = [$searchFieldMap{$field}];
	}

	my $sql  = SQL::Abstract->new;
	my ($where, @bind) = $sql->where(\%whereHash, $sortFields);
	$where =~ s/WHERE/AND/;

	my $sth=$class->sql_find($columns, $where);
	$sth->execute(@bind);

	if ($c = $fieldHasClass{$field}) {
		my @objs = $c->sth_to_objects($sth);
		return \@objs;
	}

	my $ref = $sth->fetchall_arrayref;
	my @results = grep((defined($_) && $_ ne ''), (map $_->[0], @$ref));
	return \@results;
}

__PACKAGE__->set_sql(find => <<"");
SELECT %s
FROM   __TABLE(Slim::DataStores::DBI::Track)__,
       __TABLE(Slim::DataStores::DBI::GenreTrack)__,
       __TABLE(Slim::DataStores::DBI::Genre)__,
       __TABLE(Slim::DataStores::DBI::ContributorTrack)__,
       __TABLE(Slim::DataStores::DBI::Contributor)__,
       __TABLE(Slim::DataStores::DBI::Album)__
WHERE  __JOIN(tracks genre_track)__ 
AND    __JOIN(genre_track genres)__
AND    __JOIN(tracks contributor_track)__
AND    __JOIN(contributor_track contributors)__
AND    __JOIN(tracks albums)__
       %s


######################################################
#
# Track class
#
######################################################
package Slim::DataStores::DBI::Track;

use base 'Slim::DataStores::DBI::DataModel';

use Slim::Utils::Misc;

my %primaryColumns = (
	'id' => 'id',
);

my %essentialColumns = (
	'url' => 'url',
	'ct' => 'content_type',
	'title' => 'title',
	'titlesort' => 'titlesort',
	'album' => 'album',
	'tracknum' => 'tracknum',
	'age' => 'timestamp',
	'fs' => 'filesize',
	'tag' => 'tag',
	'thumb' => 'thumb',
);

my %otherColumns = (
	'size' => 'audio_size',
	'offset' => 'audio_offset',
	'year' => 'year',
	'secs' => 'secs',
	'cover' => 'cover',
	'covertype' => 'covertype',
	'thumbtype' => 'thumbtype',
	'vbr_scale' => 'vbr_scale',
	'bitrate' => 'bitrate',
	'rate' => 'samplerate',
	'samplesize' => 'samplesize',
	'channels' => 'channels',
	'blockalign' => 'block_alignment',
    'endian' => 'endian',
	'bpm' => 'bpm',
	'tagversion' => 'tagversion',
	'tagsize' => 'tagsize',
	'drm' => 'drm',
	'moodlogic_song_id' => 'moodlogic_song_id',
	'moodlogic_artist_id' => 'moodlogic_artist_id',
	'moodlogic_genre_id' => 'moodlogic_genre_id',
	'moodlogic_song_mixable' => 'moodlogic_song_mixable',
	'moodlogic_artist_mixable' => 'moodlogic_artist_mixable',
	'moodlogic_genre_mixable' => 'moodlogic_genre_mixable',
	'musicmagic_genre_mixable' => 'musicmagic_genre_mixable',
	'musicmagic_artist_mixable' => 'musicmagic_artist_mixable',
	'musicmagic_album_mixable' => 'musicmagic_album_mixable',
	'musicmagic_song_mixable' => 'musicmagic_song_mixable',
);

my %allColumns = ( %primaryColumns, %essentialColumns, %otherColumns );

__PACKAGE__->table('tracks');
__PACKAGE__->columns(Primary => keys %primaryColumns);
__PACKAGE__->columns(Essential => keys %allColumns);
# Combine essential and other for now for performance, at the price of
# larger in-memory object size
#__PACKAGE__->columns(Others => keys %otherColumns);
__PACKAGE__->columns(Stringify => qw/url/);

__PACKAGE__->has_a(album => 'Slim::DataStores::DBI::Album');
__PACKAGE__->has_many(genres => ['Slim::DataStores::DBI::GenreTrack' => 'genre'] => 'track');
__PACKAGE__->has_many(comments => ['Slim::DataStores::DBI::Comment' => 'value'] => 'track');
__PACKAGE__->has_many(contributors => ['Slim::DataStores::DBI::ContributorTrack' => 'contributor'] => 'track');
__PACKAGE__->has_many(tracks => [ 'Slim::DataStores::DBI::PlaylistTrack' => 'track' ] => 'playlist');
__PACKAGE__->has_many(diritems => [ 'Slim::DataStores::DBI::DirlistTrack' => 'item' ] => 'dirlist');
__PACKAGE__->add_constructor(externalPlaylists => qq{
	url LIKE 'itunesplaylist:%' OR
	url LIKE 'moodlogicplaylist:%' OR
	url LIKE 'musicmagicplaylist:%'
});


my $loader;

sub setLoader {
	$loader = shift;
}

sub attributes {
	return \%allColumns;
}

sub accessor_name {
	my ($class, $column) = @_;
	
	return $allColumns{$column};
}

# For now, only allow one attribute to be fetched at a time
sub get {
	my $self = shift;
	my $attr = shift;

	my $item = $self->SUPER::get($attr);
	if (!defined($item)) {
		if ($attr =~ /^(COVER|COVERTYPE)$/) {
			$loader->updateCoverArt($self->SUPER::get('url'), 'cover');
		# defer thumb information until needed
		} elsif ($attr =~ /^(THUMB|THUMBTYPE)$/) {
			$loader->updateCoverArt($self->SUPER::get('url'), 'thumb');
		} elsif (!$self->SUPER::get('tag')) {
			$loader->readTags($self);
		}
		$item = $self->SUPER::get($attr);
	}

	return $item;
}

sub getCached {
	my $self = shift;
	my $attr = shift;

	return $self->SUPER::get($attr);
}

# String version of contributors list
sub artist {
	my $self = shift;
	my @contributors = $self->contributors;

	return join(", ", map { $_->name } @contributors);
}

sub artistsort {
	my $self = shift;
	my @contributors = $self->contributors;

	return join(", ", map { $_->namesort } @contributors);
}

sub albumsort {
	my $self = shift;
	my $album = $self->album;

	return $album->titlesort;
}

# String version of genre list
sub genre {
	my $self = shift;
	my @genres = $self->genres;

	return join(", ", map { $_->name } @genres);
}

sub setTracks {
	my $self = shift;

	my @tracks = Slim::DataStores::DBI::PlaylistTrack->tracksof($self);
	for my $track (@tracks) {
		$track->delete;
	}

	my $i = 0;
	for my $track (@_) {
		Slim::DataStores::DBI::PlaylistTrack->create({
			playlist => $self,
			track => $track,
			position => $i});
		$i++;
	}
}

sub setDirItems {
	my $self = shift;
	
	my @items = Slim::DataStores::DBI::DirlistTrack->tracksof($self);
	for my $item (@items) {
		$item->delete;
	}

	my $i = 0;
	for my $item (@_) {
		Slim::DataStores::DBI::DirlistTrack->create({
			dirlist => $self,
			item => $item,
			position => $i});
		$i++;
	}
}

sub contributorsOfType {
	my $self = shift;
	my $type = shift;

	my $contributorKeys = Slim::DataStores::DBI::Contributors->contributorFields();
	return () unless grep { $type eq $_ } @$contributorKeys;

	$type .= 'sfor';
	my @contribs = Slim::DataStores::DBI::ContributorTrack->$type($self);
	return map { $_->contributor } @contribs;
}

sub searchTitle {
	my $class = shift;
	my $pattern = shift;

	s/\*/%/g for @$pattern;

    my %where = ( title => $pattern, );

    return Slim::DataStores::DBI::DataModel->searchPattern('tracks', \%where, 
													 ['titlesort'], $class);
}

sub searchColumn {
	my $class = shift;
	my $pattern = shift;
	my $column = shift;

	s/\*/%/g for @$pattern;

    my %where = ( $column => $pattern, );

    return Slim::DataStores::DBI::DataModel->searchPattern('tracks', \%where, 
													 ['titlesort'], $class);
}
	
######################################################
#
# Genre class
#
######################################################
package Slim::DataStores::DBI::Genre;

use base 'Slim::DataStores::DBI::DataModel';

__PACKAGE__->table('genres');
__PACKAGE__->columns(Essential => qw/id name/);
__PACKAGE__->columns(Stringify => qw/name/);
__PACKAGE__->set_sql(count_all => "SELECT COUNT(*) FROM __TABLE__");

sub count {
	return __PACKAGE__->sql_count_all->select_val;
}

sub searchName {
	my $class = shift;
	my $pattern = shift;

	s/\*/%/g for @$pattern;

    my %where = ( name => $pattern, );

    return Slim::DataStores::DBI::DataModel->searchPattern('genres', \%where, 
													 ['name'], $class);
}

######################################################
#
# Album class
#
######################################################
package Slim::DataStores::DBI::Album;

use base 'Slim::DataStores::DBI::DataModel';

__PACKAGE__->table('albums');
__PACKAGE__->columns(Essential => qw/id title titlesort artwork_path disc discc/);
__PACKAGE__->columns(Stringify => qw/title/);
__PACKAGE__->set_sql(count_all => "SELECT COUNT(*) FROM __TABLE__");
__PACKAGE__->add_constructor('hasArtwork' => 'artwork_path IS NOT NULL');

sub count {
	return __PACKAGE__->sql_count_all->select_val;
}

sub searchTitle {
	my $class = shift;
	my $pattern = shift;

	s/\*/%/g for @$pattern;

    my %where = ( title => $pattern, );

    return Slim::DataStores::DBI::DataModel->searchPattern('albums', \%where, 
													 ['titlesort'], $class);
}

######################################################
#
# Contributor class
#
######################################################
package Slim::DataStores::DBI::Contributor;

use base 'Slim::DataStores::DBI::DataModel';

__PACKAGE__->table('contributors');
__PACKAGE__->columns(Essential => qw/id name namesort/);
__PACKAGE__->columns(Stringify => qw/name/);
__PACKAGE__->set_sql(count_all => "SELECT COUNT(*) FROM __TABLE__");

my @fields = ('contributor', 'artist', 'composer', 'conductor', 'band');

sub contributorFields {
	return \@fields;
}

sub count {
	return __PACKAGE__->sql_count_all->select_val;
}

sub searchName {
	my $class = shift;
	my $pattern = shift;
	my $role = shift; #FIXME

	s/\*/%/g for @$pattern;

    my %where = ( name => $pattern, );

    return Slim::DataStores::DBI::DataModel->searchPattern('contributors', \%where, 
													 ['namesort'], $class);
}


######################################################
#
# Playlist to track mapping class
#
######################################################
package Slim::DataStores::DBI::PlaylistTrack;

use base 'Slim::DataStores::DBI::DataModel';

__PACKAGE__->table('playlist_track');
__PACKAGE__->columns(Essential => qw/id position playlist track/);
__PACKAGE__->has_a(playlist => 'Slim::DataStores::DBI::Track');
__PACKAGE__->has_a(track => 'Slim::DataStores::DBI::Track');
__PACKAGE__->add_constructor('tracksof' => 'playlist=? ORDER BY position');

######################################################
#
# Directory to track mapping class
#
######################################################
package Slim::DataStores::DBI::DirlistTrack;

use base 'Slim::DataStores::DBI::DataModel';

__PACKAGE__->table('dirlist_track');
__PACKAGE__->columns(Essential => qw/id position dirlist item/);
__PACKAGE__->has_a(dirlist => 'Slim::DataStores::DBI::Track');
__PACKAGE__->add_constructor('tracksof' => 'dirlist=? ORDER BY position');

######################################################
#
# Contributor to track mapping class
#
######################################################
package Slim::DataStores::DBI::ContributorTrack;

use base 'Slim::DataStores::DBI::DataModel';

use constant ROLE_ARTIST => 1;
use constant ROLE_COMPOSER => 2;
use constant ROLE_CONDUCTOR => 3;
use constant ROLE_BAND => 4;

__PACKAGE__->table('contributor_track');
__PACKAGE__->columns(Essential => qw/id role contributor track album namesort/);
__PACKAGE__->has_a(contributor => 'Slim::DataStores::DBI::Contributor');
__PACKAGE__->has_a(track => 'Slim::DataStores::DBI::Track');
__PACKAGE__->has_a(album => 'Slim::DataStores::DBI::Album');
__PACKAGE__->add_constructor('contributorsfor' => 'track=?');
__PACKAGE__->add_constructor('artistsfor' => "track=? AND role=".ROLE_ARTIST);
__PACKAGE__->add_constructor('composersfor' => "track=? AND role=".ROLE_COMPOSER);
__PACKAGE__->add_constructor('conductorsfor' => "track=? AND role=".ROLE_CONDUCTOR);
__PACKAGE__->add_constructor('bandsfor' => "track=? AND role=".ROLE_BAND);

sub add {
	my $artist=shift;
	my $role=shift;
	my $track=shift;
	my $artistSort=shift;
	
	foreach my $artistSub (Slim::Music::Info::splitTag($artist)) {
		$artistSub=~s/^\s*//;
		$artistSub=~s/\s*$//;

		my $sortable_name = $artistSort || 
		  Slim::Utils::Text::ignoreCaseArticles($artist);
			
		my $artistObj = Slim::DataStores::DBI::Contributor->find_or_create({ 
			name => $artist,
		});
		$artistObj->namesort($sortable_name);
		$artistObj->update;

		Slim::DataStores::DBI::ContributorTrack->find_or_create({
			track => $track,
			contributor => $artistObj,
			role => $role,
			album => $track->album,
			namesort => $sortable_name,
		});
	}
}

######################################################
#
# Genre to track mapping class
#
######################################################
package Slim::DataStores::DBI::GenreTrack;

use base 'Slim::DataStores::DBI::DataModel';

__PACKAGE__->table('genre_track');
__PACKAGE__->columns(Essential => qw/id genre track/);
__PACKAGE__->has_a(genre => 'Slim::DataStores::DBI::Genre');
__PACKAGE__->has_a(track => 'Slim::DataStores::DBI::Track');
__PACKAGE__->add_constructor('genresfor' => 'track=?');

sub add {
	my $genre=shift;
	my $track=shift;

	foreach my $genreSub (Slim::Music::Info::splitTag($genre)) {
		$genreSub=~s/^\s*//;
		$genreSub=~s/\s*$//;

		my $genreObj = Slim::DataStores::DBI::Genre->find_or_create({ 
			name => $genreSub,
		});
		
		Slim::DataStores::DBI::GenreTrack->find_or_create({
			track => $track,
			genre => $genreObj,
		});
	}
}

######################################################
#
# Comment class
#
######################################################
package Slim::DataStores::DBI::Comment;

use base 'Slim::DataStores::DBI::DataModel';

__PACKAGE__->table('comments');
__PACKAGE__->columns(Essential => qw/id track value/);
__PACKAGE__->has_a(track => 'Slim::DataStores::DBI::Track');
__PACKAGE__->add_constructor('commentsof' => 'track=?');

1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
