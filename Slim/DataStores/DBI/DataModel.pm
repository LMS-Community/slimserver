package Slim::DataStores::DBI::DataModel;

# $Id: DataModel.pm,v 1.8 2004/12/18 18:57:13 dsully Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base 'Class::DBI';
use DBI;
use SQL::Abstract;
use SQL::Abstract::Limit;
use Tie::Cache::LRU;

use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);
use Slim::Utils::Misc;

my $dbh;
tie my %lru, 'Tie::Cache::LRU', 5000;

sub executeSQLFile {
	my $class = shift;
	my $file  = shift;

	my $driver = Slim::Utils::Prefs::get('dbsource');
	$driver =~ s/dbi:(.*?):(.*)$/$1/;

	my $sqlFile = catdir($Bin, "SQL", $driver, $file);

	$::d_info && Slim::Utils::Misc::msg("Executing SQL file $sqlFile\n");

	open(my $fh, $sqlFile) or do {
		$::d_info && Slim::Utils::Misc::msg("Couldn't open: $sqlFile : $!\n");
		return;
	};

	my $statement   = '';
	my $inStatement = 0;

	for my $line (<$fh>) {
		chomp $line;

		# skip and strip comments & empty lines
		$line =~ s/\s*--.*?$//o;
		$line =~ s/^\s*//o;

		next if $line =~ /^--/;
		next if $line =~ /^\s*$/;

		if ($line =~ /^\s*(?:CREATE|SET|INSERT|UPDATE|DROP|SELECT)\s+/oi) {
			$inStatement = 1;
		}

		if ($line =~ /;/ && $inStatement) {

			$statement .= $line;

			$::d_sql && Slim::Utils::Misc::msg("Executing SQL statement: [$statement]\n");

			$dbh->do($statement) or Slim::Utils::Misc::msg("Couldn't execute SQL statement: [$statement]\n");

			$statement   = '';
			$inStatement = 0;
			next;
		}

		$statement .= $line if $inStatement;
	}

	$dbh->commit();
	close $fh;
}

sub db_Main {
	my $class = shift;

	return $dbh if defined $dbh;

	my $dbname = Slim::Utils::OSDetect::OS() eq 'unix' ? '.slimserversql.db' : 'slimserversql.db';

	$dbname = catdir(Slim::Utils::Prefs::get('cachedir'), $dbname);

	$::d_info && Slim::Utils::Misc::msg("Tag database support is ON, saving into: $dbname\n");

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
	
		for my $table (@tables) {
			if ($table =~ /metainformation/) {
				($version) = $dbh->selectrow_array("SELECT version FROM metainformation");
				last;
			}
		}

		if (defined $version) {

			$nextversion = $class->findUpgrade($version);
			
			if ($nextversion && ($nextversion ne 99999)) {

				my $upgradeFile = catdir("Upgrades", $nextversion.".sql" );
				$::d_info && Slim::Utils::Misc::msg("Upgrading to version ".$nextversion." from version ".$version.".\n");
				$class->executeSQLFile($upgradeFile);

			} elsif ($nextversion && ($nextversion eq 99999)) {

				$::d_info && Slim::Utils::Misc::msg("Database schema out of date and purge required. Purging db.\n");
				$class->executeSQLFile("dbdrop.sql");
				$version = undef;
				$nextversion = 0;
			}
		}

	} while ($nextversion);
	
	if (!defined($version)) {
		$::d_info && Slim::Utils::Misc::msg("Creating new database.\n");
		$class->executeSQLFile("dbcreate.sql");
	}

	$dbh->commit();
	
  	return $dbh;
}

sub findUpgrade {
	my $class       = shift;
	my $currVersion = shift;

	my $driver = Slim::Utils::Prefs::get('dbsource');
	$driver =~ s/dbi:(.*?):(.*)$/$1/;
	my $sqlVerFilePath = catdir($Bin, "SQL", $driver, "sql.version");

	my $versionFile;
	
	open($versionFile, $sqlVerFilePath) or do {
		warn("can't open $sqlVerFilePath\n");
		return 0;
	};
	
	my ($line, $from, $to);

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
	my $class = shift;

	$class->clear_object_index();
	$class->executeSQLFile("dbclear.sql");

	$dbh = undef;
}

sub getMetaInformation {
	my $class = shift;

	$dbh->selectrow_array("SELECT track_count, total_time FROM metainformation");
}

sub setMetaInformation {
	my ($class, $track_count, $total_time) = @_;

	$dbh->do("UPDATE metainformation SET track_count = " . $track_count . ", total_time  = " . $total_time);
}

sub searchPattern {
	my $class = shift;
	my $table = shift;
	my $where = shift;
	my $order = shift;

	my $sql  = SQL::Abstract->new(cmp => 'like');

	my ($stmt, @bind) = $sql->select($table, 'id', $where, $order);

	if ($::d_sql) {
		Slim::Utils::Misc::msg("Running SQL query: [$stmt]\n");
		Slim::Utils::Misc::msg(sprintf("Bind arguments: [%s]\n\n", join(', ', @bind))) if scalar @bind;
	}

 	my $sth = db_Main()->prepare_cached($stmt);

	$sth->execute(@bind);

	return [ $class->sth_to_objects($sth) ];
}

sub getWhereValues {
	my $term = shift;

	return () unless defined $term;

	my @values = ();

	if (ref $term eq 'ARRAY') {

		for my $item (@$term) {

			if (ref $item) {

				push @values, $item->id();

			} elsif (defined($item) && $item ne '') {

				push @values, $item;
			}
		}

	} elsif (ref $term) {

		push @values, $term->id();

	} elsif (defined($term) && $term ne '') {

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
	'track' => ['Slim::DataStores::DBI::Track'],
	'genre' => ['Slim::DataStores::DBI::Genre', 'Slim::DataStores::DBI::GenreTrack'],
	'album' => ['Slim::DataStores::DBI::Album'],
	'artist' => ['Slim::DataStores::DBI::Contributor', 'Slim::DataStores::DBI::ContributorTrack'],
	'contributor' => ['Slim::DataStores::DBI::Contributor', 'Slim::DataStores::DBI::ContributorTrack'],
	'conductor' => ['Slim::DataStores::DBI::Contributor', 'Slim::DataStores::DBI::ContributorTrack'],
	'composer' => ['Slim::DataStores::DBI::Contributor', 'Slim::DataStores::DBI::ContributorTrack'],
	'band' => ['Slim::DataStores::DBI::Contributor', 'Slim::DataStores::DBI::ContributorTrack'],
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
	'album' => ['albums.titlesort','albums.disc'],
	'contributor' => ['contributors.namesort'],
	'artist' => ['contributors.namesort'],
	'track' => ['contributor_track.namesort','albums.titlesort','albums.disc','tracks.tracknum','tracks.titlesort'],
	'tracknum' => ['tracks.tracknum','tracks.titlesort'],
);

my %joinMap = (
	'albums' => 'tracks.album = albums.id',
	'genre_track' => 'genre_track.track = tracks.id',
	'genres' => 'genre_track.genre = genres.id',
	'contributor_track' => 'contributor_track.track = tracks.id',
	'contributors' => 'contributor_track.contributor = contributors.id',
);

sub find {
	my $class = shift;
	my $field = shift;
	my $findCriteria = shift;
	my $sortby = shift;
	my $limit = shift;
	my $offset = shift;
	my $c;

	# Build up a SQL query
	my $columns = "DISTINCT ";

	# The FROM tables involved in the query
	my %tables  = ();
	
	# First the columns to SELECT
	if ($c = $fieldHasClass{$field}) {

		my $table = $c->[0]->table();

		$columns .= join(",", map {$table . '.' . $_ . " AS " . $_} $c->[0]->columns('Essential'));

		# For now, include only the main table from which we're retrieving 
		# columns. If there is a WHERE clause, we may include a secondary
		# (has-many) table.
		$tables{$table} = 1 for @$c;

	} elsif (defined($searchFieldMap{$field})) {

		$columns .= $searchFieldMap{$field};
		$tables{'tracks'} = 1;

	} else {
		$::d_info && msg("Request for unknown field in query\n");
		return undef;
	}
	
	# Then the WHERE clause
	my %whereHash = ();

	while (my ($key, $val) = each %$findCriteria) {

		if (defined($searchFieldMap{$key})) {

			my @values = getWhereValues($val);

			if (scalar(@values)) {
				$whereHash{$searchFieldMap{$key}} = scalar(@values) > 1 ? \@values : $values[0];
			}

			# Include FROM tables of all columns use in the WHERE
			if ($c = $fieldHasClass{$key}) {
				$tables{ $_->table() } = 1 for @$c;
			}
		}
		
		# And all tables (including possibly a has-many table) from the main field.
		if ($c = $fieldHasClass{$field}) {
			$tables{ $_->table } = 1 for @$c;
		}

		$tables{'tracks'} = 1;
	}

	# Now deal with the ORDER BY component
	my $sortFields = [];

	if (defined($sortby) && $sortFieldMap{$sortby}) {
		$sortFields = $sortFieldMap{$sortby};
	}

	for my $sfield (@$sortFields) {
		my ($table) = ($sfield =~ /^(\w+)\./);
		$tables{$table} = 1;
	}

	my $abstract;

	if (defined $limit && defined $offset) {
		# XXX - fix this to use a dynamic dialect.
		$abstract  = SQL::Abstract::Limit->new('limit_dialect' => 'LimitOffset');
	} else {
		$abstract  = SQL::Abstract->new();
	}

	my ($where, @bind) = $abstract->where(\%whereHash, $sortFields, $limit, $offset);

	my $sql = "SELECT $columns ";
	   $sql .= "FROM " . join(", ", keys %tables) . " ";

	if (scalar(keys %tables) > 1) {

		delete $tables{'tracks'};

		$sql .= "WHERE " . join(" AND ", map { $joinMap{$_} } keys %tables ) . " ";

		$where =~ s/WHERE/AND/;
	}

	$sql .= $where;

	if ($::d_sql) {
		Slim::Utils::Misc::bt();
		Slim::Utils::Misc::msg("Running SQL query: [$sql]\n");
		Slim::Utils::Misc::msg(sprintf("Bind arguments: [%s]\n\n", join(', ', @bind))) if scalar @bind;
	}

	# XXX - wrap in eval?
	my $sth = $dbh->prepare_cached($sql);
	   $sth->execute(@bind);

	if ($c = $fieldHasClass{$field}) {
		return [ $c->[0]->sth_to_objects($sth) ];
	}

	my $ref = $sth->fetchall_arrayref;

	return [ grep((defined($_) && $_ ne ''), (map $_->[0], @$ref)) ];
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
