package Slim::DataStores::DBI::DataModel;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base 'Class::DBI';
use DBI;
use File::Basename;
use File::Path;
use SQL::Abstract;
use SQL::Abstract::Limit;
use Tie::Cache::LRU;
use UNIVERSAL;

use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);
use Slim::Utils::Misc;

our $dbh;
our $dirtyCount = 0;
our $cleanupIterator;

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

		if ($line =~ /^\s*(?:CREATE|SET|INSERT|UPDATE|DELETE|DROP|SELECT)\s+/oi) {
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
	my $class  = shift;

	return $dbh if defined $dbh;

	my $dbname = Slim::Utils::OSDetect::OS() eq 'unix' ? '.slimserversql.db' : 'slimserversql.db';

	$dbname = catdir(Slim::Utils::Prefs::get('cachedir'), $dbname);

	# Check and see if we need to create the path.
	unless (-d dirname($dbname)) {
		mkpath(dirname($dbname)) or do {
			Slim::Utils::Misc::bt();
			Slim::Utils::Misc::msg("Couldn't create directory for $dbname : $!\n");
			return;
		};
	}

	$::d_info && Slim::Utils::Misc::msg("Tag database support is ON, saving into: $dbname\n");

	my $source = sprintf(Slim::Utils::Prefs::get('dbsource'), $dbname);
	my $username = Slim::Utils::Prefs::get('dbusername');
	my $password = Slim::Utils::Prefs::get('dbpassword');

	$dbh = DBI->connect_cached($source, $username, $password, { 
		RaiseError => 1,
		AutoCommit => 0,
		PrintError => 1,
		Taint      => 1,
		RootClass  => "DBIx::ContextualFetch"
	});

	# Not much we can do if there's no DB.
	unless ($dbh) {
		Slim::Utils::Misc::msg("Couldn't connect to info database! Error: [$!] Exiting!\n");
		Slim::Utils::Misc::bt();
		exit;
	}

	$::d_info && Slim::Utils::Misc::msg("Connected to database $source\n");

	my $version;
	my $nextversion;
	do {
	
		if (grep { /metainformation/ } $dbh->tables()) {
			($version) = $dbh->selectrow_array("SELECT version FROM metainformation");
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

	$dbh->commit();
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

sub getWhereValues {
	my $term = shift;

	return () unless defined $term;

	my @values = ();

	if (ref $term eq 'ARRAY') {

		for my $item (@$term) {

			if (ref $item eq 'ARRAY') {

				# recurse if needed
				push @values, getWhereValues($item);

			} elsif (ref $item && UNIVERSAL::isa($item, 'Slim::DataStores::DBI::DataModel')) {

				push @values, $item->id();

			} elsif (defined($item) && $item ne '') {

				push @values, $item;
			}
		}

	} elsif (ref $term && UNIVERSAL::isa($term, 'Slim::DataStores::DBI::DataModel')) {

		push @values, $term->id();

	} elsif (defined($term) && $term ne '') {

		push @values, $term;
	}

	return @values;
}

our %fieldHasClass = (
	'track' => 'Slim::DataStores::DBI::Track',
	'lightweighttrack' => 'Slim::DataStores::DBI::LightWeightTrack',
	'genre' => 'Slim::DataStores::DBI::Genre',
	'album' => 'Slim::DataStores::DBI::Album',
	'artist' => 'Slim::DataStores::DBI::Contributor',
	'contributor' => 'Slim::DataStores::DBI::Contributor',
	'conductor' => 'Slim::DataStores::DBI::Contributor',
	'composer' => 'Slim::DataStores::DBI::Contributor',
	'band' => 'Slim::DataStores::DBI::Contributor',
	'comment' => 'Slim::DataStores::DBI::Comment',
);

our %searchFieldMap = (
	'id' => 'tracks.id',
	'url' => 'tracks.url', 
	'title' => 'tracks.titlesort', 
	'track' => 'tracks.id', 
	'track.title' => 'tracks.title', 
	'track.titlesort' => 'tracks.titlesort', 
	'tracknum' => 'tracks.tracknum', 
	'ct' => 'tracks.ct', 
	'age' => 'tracks.age', 
	'size' => 'tracks.size', 
	'year' => 'tracks.year', 
	'secs' => 'tracks.secs', 
	'vbr_scale' => 'tracks.vbr_scale',
	'bitrate' => 'tracks.bitrate', 
	'rate' => 'tracks.rate', 
	'samplesize' => 'tracks.samplesize', 
	'channels' => 'tracks.channels', 
	'bpm' => 'tracks.bpm', 
	'lastPlayed' => 'tracks.lastPlayed',
	'playCount' => 'tracks.playCount',
	'album' => 'tracks.album',
	'album.title' => 'albums.title',
	'album.titlesort' => 'albums.titlesort',
	'genre' => 'genre_track.genre', 
	'genre.name' => 'genres.name', 
	'genre.namesort' => 'genres.namesort', 
	'contributor' => 'contributor_track.contributor', 
	'contributor.name' => 'contributors.name', 
	'contributor.namesort' => 'contributors.namesort', 
	'artist' => 'contributor_track.contributor', 
	'artist.name' => 'contributors.name', 
	'artist.namesort' => 'contributors.namesort', 
	'conductor' => 'contributor_track.contributor', 
	'conductor.name' => 'contributors.name', 
	'composer' => 'contributor_track.contributor', 
	'composer.name' => 'contributors.name', 
	'band' => 'contributor_track.contributor', 
	'band.name' => 'contributors.name', 
	'comment' => 'comments.value', 
	'contributor.role' => 'contributor_track.role',
);

our %cmpFields = (
	'contributor.namesort' => 1,
	'genre.namesort' => 1,
	'album.titlesort' => 1,
	'track.titlesort' => 1,
	'comment' => 1,
	'comment.value' => 1,
);

our %sortFieldMap = (
	'title' => ['tracks.titlesort'],
	'genre' => ['genres.namesort'],
	'album' => ['albums.titlesort','albums.disc'],
	'contributor' => ['contributors.namesort'],
	'artist' => ['contributors.namesort'],
	'track' => ['tracks.multialbumsortkey', 'tracks.disc','tracks.tracknum','tracks.titlesort'],
	'tracknum' => ['tracks.disc','tracks.tracknum','tracks.titlesort'],
	'year' => ['tracks.year'],
	'lastPlayed' => ['tracks.lastPlayed'],
	'playCount' => ['tracks.playCount'],
	'age' => ['tracks.age desc', 'tracks.disc', 'tracks.tracknum', 'tracks.titlesort'],
);

# This is a weight table which allows us to do some basic table reordering,
# resulting in a more optimized query. EXPLAIN should tell you more.
our %tableSort = (
	'albums' => 0.6,
	'contributors' => 0.7,
	'contributor_track' => 0.9,
	'genres' => 0.1,
	'genre_track' => 1.0,
	'tracks' => 0.8,
);

# The joinGraph represents a bi-directional graph where tables are
# nodes and columns that can be used to join tables are named
# arcs between the corresponding table nodes. This graph is similar
# to the entity-relationship graph, but not exactly the same.
# In the hash table below, the keys are tables and the values are
# the arcs describing the relationship.
our %joinGraph = (
	'genres' => {
		'genre_track' => 'genres.id = genre_track.genre',
	},

	'genre_track' => {
		'genres' => 'genres.id = genre_track.genre',
		'contributor_track' => 'genre_track.track = contributor_track.track',
		'tracks' => 'genre_track.track = tracks.id',
	},

	'contributors' => {
		'contributor_track' => 'contributors.id = contributor_track.contributor',
	},

	'contributor_track' => {
		'contributors' => 'contributors.id = contributor_track.contributor',
		'genre_track' => 'genre_track.track = contributor_track.track',
		'tracks' => 'contributor_track.track = tracks.id',
	},

	'tracks' => {
		'contributor_track' => 'contributor_track.track = tracks.id',
		'genre_track' => 'genre_track.track = tracks.id',
		'albums' => 'albums.id = tracks.album',
	},

	'albums' => {
		'tracks' => 'albums.id = tracks.album',
	},

	'comments' => {
		'tracks' => 'comments.track = tracks.id',
	},

);

# The hash below represents the shortest paths between nodes in the
# joinGraph above. The keys of this hash are tuples representing the
# start node (the field used in the findCriteria) and the end node
# (the field that we are querying for). The shortest path in the 
# joinGraph represents the smallest number of joins we need to do
# to be able to formulate our query.
# Note that while the paths below are hardcoded, for a larger graph we
# could compute the shortest path algorithmically, using Dijkstra's
# (or other) shortest path algorithm.
our %queryPath = (
	'genre:album' => ['genre_track', 'tracks', 'albums'],
	'genre:genre' => ['genre_track', 'genres'],
	'genre:contributor' => ['genre_track', 'contributor_track', 'contributors'],
	'genre:default' => ['genres', 'genre_track', 'tracks'],
	'contributor:album' => ['contributor_track', 'tracks', 'albums'],
	'contributor:genre' => ['contributor_track', 'genre_track', 'genres'],
	'contributor:contributor' => ['contributor_track', 'contributors'],
	'contributor:default' => ['contributors', 'contributor_track', 'tracks'],
	'album:album' => ['albums', 'tracks'],
	'album:genre' => ['albums', 'tracks', 'genre_track', 'genres'],
	'album:contributor' => ['albums', 'tracks', 'contributor_track', 'contributors'],
	'album:default' => ['albums', 'tracks'],
	'default:album' => ['tracks', 'albums'],
	'default:genre' => ['tracks', 'genre_track', 'genres'],
	'album:contributor' => ['tracks', 'contributor_track', 'contributors'],
	'comment:default' => ['comments', 'tracks'],
	'default:default' => ['tracks'],
);

our %fieldToNodeMap = (
	'album' => 'album',
	'genre' => 'genre',
	'contributor' => 'contributor',
	'artist' => 'contributor',
	'conductor' => 'contributor',
	'composer' => 'contributor',
	'band' => 'contributor',
	'comment' => 'comment',
);

sub find {
	my $class = shift;
	my $field = shift;
	my $findCriteria = shift;
	my $sortby = shift;
	my $limit = shift;
	my $offset = shift;
	my $count = shift;
	my $c;

	# Build up a SQL query
	my $columns = "DISTINCT ";

	# The FROM tables involved in the query
	my %tables  = ();

	# The joins for the query
	my %joins = ();
	
	my $fieldTable;

	# First the columns to SELECT
	if ($c = $fieldHasClass{$field}) {

		$fieldTable = $c->table();

		$columns .= join(",", map {$fieldTable . '.' . $_ . " AS " . $_} $c->columns('Essential'));

	} elsif (defined($searchFieldMap{$field})) {

		$fieldTable = 'tracks';

		$columns .= $searchFieldMap{$field};

	} else {
		$::d_info && Slim::Utils::Misc::msg("Request for unknown field in query\n");
		return undef;
	}

	# Include the table containing the data we're selecting
	$tables{$fieldTable} = $tableSort{$fieldTable};

	# Then the WHERE clause
	my %whereHash = ();

	my $endNode = $fieldToNodeMap{$field} || 'default';

	while (my ($key, $val) = each %$findCriteria) {

		if (defined($searchFieldMap{$key})) {

			my @values = getWhereValues($val);

			if (scalar(@values)) {

				# Turn wildcards into SQL wildcards
				s/\*/%/g for @values;

				# Try to optimize and use the IN SQL
				# statement, instead of creating a massive OR
				#
				# Alternatively, create a multiple OR
				# statement for a LIKE clause
				if (scalar(@values) > 1) {

					if ($cmpFields{$key}) {

						for my $value (@values) {

							# Don't bother with a like if there's no wildcard.
							if ($value =~ /%/) {
								push @{$whereHash{$searchFieldMap{$key}}}, { 'like', $value };
							} else {
								push @{$whereHash{$searchFieldMap{$key}}}, { '=', $value };
							}
						}

					} else {

						$whereHash{$searchFieldMap{$key}} = { 'in', \@values };
					}

				} else {

					# Otherwise - we're a single value -
					# check to see if a LIKE compare is needed.
					if ($cmpFields{$key}) {

						# Don't bother with a like if there's no wildcard.
						if ($values[0] =~ /%/) {
							$whereHash{$searchFieldMap{$key}} = { 'like', $values[0] };
						} else {
							$whereHash{$searchFieldMap{$key}} = $values[0];
						}

					} else {

						$whereHash{$searchFieldMap{$key}} = $values[0];
					}
				}

			} else {

				if (ref $val && ref $val eq 'ARRAY' && scalar @$val > 0) {

					$whereHash{$searchFieldMap{$key}} = $val;

				} elsif (ref $val && ref $val eq 'HASH' && scalar keys %$val > 0) {

					$whereHash{$searchFieldMap{$key}} = $val;
				}
			}

			# if our $key is something like contributor.name -
			# strip off the name so that our join is correctly optimized.
			$key =~ s/\.\w+$//o;

			my $startNode = $fieldToNodeMap{$key} || 'default';

			# Find the query path that gives us the tables
			# we need to join across to fulfill the query.
			my $path = $queryPath{"$startNode:$endNode"};

			$::d_sql && Slim::Utils::Misc::msg("Start and End node: [$startNode:$endNode]\n");

			for my $i (0..$#{$path}) {

				my $table = $path->[$i];
				$tables{$table} = $tableSort{$table};
				
				if ($i < $#{$path}) {
					my $nextTable = $path->[$i + 1];
					my $join = $joinGraph{$table}{$nextTable};
					$joins{$join} = 1;
				}
			}
		}
	}

	# Now deal with the ORDER BY component
	my $sortFields = [];

	if (defined($sortby) && $sortFieldMap{$sortby}) {
		$sortFields = $sortFieldMap{$sortby};
	}

	for my $sfield (@$sortFields) {
		my ($table) = ($sfield =~ /^(\w+)\./);
		$tables{$table} = $tableSort{$table};

		# See if we need to do a join to allow the sortfield
		if ($table ne $fieldTable) {
			my $join = $joinGraph{$table}{$fieldTable};
			if (defined($join)) {
				$joins{$join} = 1;
			}
		}
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
	   $sql .= "FROM " . join(", ", sort { $tables{$b} <=> $tables{$a} } keys %tables) . " ";

	if (scalar(keys %joins)) {

		$sql .= "WHERE " . join(" AND ", keys %joins ) . " ";

		$where =~ s/WHERE/AND/;
	}

	$sql .= $where;

	if ($::d_sql) {
		Slim::Utils::Misc::bt();
		Slim::Utils::Misc::msg("Running SQL query: [$sql]\n");
		Slim::Utils::Misc::msg(sprintf("Bind arguments: [%s]\n\n", join(', ', @bind))) if scalar @bind;
	}

	# XXX - wrap in eval?
	my $sth;

	eval {
		$sth = $dbh->prepare_cached($sql);
	   	$sth->execute(@bind);
	};

	if ($@) {
		Slim::Utils::Misc::msg("Whoops! prepare_cached() or execute() failed on sql: [$sql] - [$@]\n");
		Slim::Utils::Misc::bt();

		# Try to return a graceful value.
		return 0 if $count;
		return [];
	}

	# Don't instansiate any objects if we're just counting.
	if ($count) {
		$count = scalar @{$sth->fetchall_arrayref()};

		$sth->finish();

		return $count;
	}

	# Always remember to finish() the statement handle, otherwise DBI will complain.
	if ($c = $fieldHasClass{$field}) {

		my $objects = [ $c->sth_to_objects($sth) ];

		$sth->finish();
	
		return $objects;
	}

	my $ref = $sth->fetchall_arrayref();

	my $objects = [ grep((defined($_) && $_ ne ''), (map $_->[0], @$ref)) ];

	$sth->finish();

	return $objects;
}

sub print {
	my $self   = shift;
	my $fh	   = shift || *STDOUT;

	my $class  = ref($self);

	# array context lets us handle multi-column primary keys.
	print $fh join('.', $self->id()) . "\n";

	# XXX - handle meta_info here, and recurse.
	for my $column (sort ($class->columns('All'))) {

		# this is needed if the accessor was mutated.
		$column = $class->accessor_name($column) || next;

		my $value = defined($self->$column()) ? $self->$column() : '';

		next unless defined $value && $value !~ /^\s*$/;

		print $fh "\t$column: ";

		if (ref($value) && $value->isa('Slim::DataStores::DBI::DataModel') && $value->can('id')) {

			print $fh $value->id();

		} else {

			print $fh $value if defined $value;
		}

		print $fh "\n";
	}
}

# overload Class::DBI's get, because DBI doesn't support auto-flagging of utf8
# data retrieved from the db, we need to do it ourselves.
sub get {
	my $self = shift;
	my $attr = shift;

	my $data = $self->SUPER::get($attr, @_);

	# I don't like the hardcoded list - but we don't want to flag
	# everything. url's will get munged otherwise. - dsully
	if ($] > 5.007 && $attr =~ /^(?:(?:name|title)(?:sort)?|item|value|text)$/o) {
		Encode::_utf8_on($data);
	}

	return $data;
}

# Walk any table and check for foreign rows that still exist.
sub removeStaleDBEntries {
	my $class   = shift;
	my $foreign = shift;

	unless ($cleanupIterator) {

		$::d_info && Slim::Utils::Misc::msg("Starting stale cleanup for class $class / $foreign\n");

		$cleanupIterator = $class->retrieve_all();
	}

	my $item = $cleanupIterator->next() || do {

		$::d_info && Slim::Utils::Misc::msg("Finished stale cleanup for class $class / $foreign\n");

		$cleanupIterator = undef;

		return 0;
	};

	if ($item && $item->$foreign()->count() == 0) {

		$::d_info && Slim::Utils::Misc::msg("DB garbage collection - removing $class: $item - no more tracks!\n");

		$item->delete();

		$dirtyCount++;
	}

	return 1;
}

# overload update() to maintain $dirtyCount
sub update {
	my $self = shift;

	if ($self->is_changed()) {

		$self->SUPER::update();
		$dirtyCount++;
	}
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
