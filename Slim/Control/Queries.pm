package Slim::Control::Queries;

# $Id:  $
#
# Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

################################################################################

=head1 NAME

Slim::Control::Queries

=head1 DESCRIPTION

L<Slim::Control::Queries> implements most server queries and is designed to
 be exclusively called through Request.pm and the mechanisms it defines.

 Except for subscribe-able queries (such as status and serverstatus), there are no
 important differences between the code for a query and one for
 a command. Please check the commented command in Commands.pm.

=cut

use strict;

use Storable;
use JSON::XS::VersionOneAndTwo;
use Scalar::Util qw(blessed);
use URI::Escape;
use Tie::Cache::LRU::Expires;

use Slim::Utils::Misc qw( specified );
use Slim::Utils::Log;
use Slim::Utils::Unicode;
use Slim::Utils::Prefs;
use Slim::Utils::Text;

{
	if (main::ISWINDOWS) {
		require Slim::Utils::OS::Win32;
	}

	if (main::LOCAL_PLAYERS) {
		require Slim::Control::LocalPlayers::Queries;
	}
}

my $log = logger('control.queries');

my $prefs = preferences('server');

# Frequently used data can be cached in memory, such as the list of albums for Jive
my $cache = {};

# small, short lived cache of folder entries to prevent repeated disk reads on BMF
tie my %bmfCache, 'Tie::Cache::LRU::Expires', EXPIRES => 15, ENTRIES => 5;

sub init {
	my $class = shift;

	# Wipe cached data after rescan
	if ( !main::SLIM_SERVICE && !main::SCANNER ) {
		Slim::Control::Request::subscribe( sub {
			$class->wipeCaches;
		}, [['rescan'], ['done']] );
	}
}

sub albumsQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['albums']])) {
		$request->setStatusBadDispatch();
		return;
	}

	if (!Slim::Schema::hasLibrary()) {
		$request->setStatusNotDispatchable();
		return;
	}

	my $sqllog = main::DEBUGLOG && logger('database.sql');

	# get our parameters
	my $index         = $request->getParam('_index');
	my $quantity      = $request->getParam('_quantity');
	my $tags          = $request->getParam('tags') || 'l';
	my $search        = $request->getParam('search');
	my $compilation   = $request->getParam('compilation');
	my $contributorID = $request->getParam('artist_id');
	my $genreID       = $request->getParam('genre_id');
	my $trackID       = $request->getParam('track_id');
	my $albumID       = $request->getParam('album_id');
	my $year          = $request->getParam('year');
	my $sort          = $request->getParam('sort') || 'album';
	my $to_cache      = $request->getParam('cache');

	# FIXME: missing genrealbum, genreartistalbum
	if ($request->paramNotOneOfIfDefined($sort, ['new', 'album', 'artflow', 'artistalbum', 'yearalbum', 'yearartistalbum' ])) {
		$request->setStatusBadParams();
		return;
	}

	my $collate = Slim::Utils::OSDetect->getOS()->sqlHelperClass()->collate();

	my $sql      = 'SELECT %s FROM albums ';
	my $c        = { 'albums.id' => 1, 'albums.titlesearch' => 1, 'albums.titlesort' => 1 };
	my $w        = [];
	my $p        = [];
	my $order_by = "albums.titlesort $collate, albums.disc"; # XXX old code prepended 0 to titlesort, but not other titlesorts
	my $limit;
	my $page_key = "SUBSTR(albums.titlesort,1,1)";

	# Normalize and add any search parameters
	if ( defined $trackID ) {
		$sql .= 'JOIN tracks ON tracks.album = albums.id ';
		push @{$w}, 'tracks.id = ?';
		push @{$p}, $trackID;
	}
	elsif ( defined $albumID ) {
		push @{$w}, 'albums.id = ?';
		push @{$p}, $albumID;
	}
	# ignore everything if $track_id or $album_id was specified
	else {
		if ( $sort eq 'new' ) {
			$sql .= 'JOIN tracks ON tracks.album = albums.id ';
			$limit = $prefs->get('browseagelimit') || 100;
			$order_by = "tracks.timestamp desc, tracks.disc, tracks.tracknum, tracks.titlesort $collate";

			# Force quantity to not exceed max
			if ( $quantity && $quantity > $limit ) {
				$quantity = $limit;
			}

			$page_key = undef;
		}
		elsif ( $sort eq 'artflow' ) {
			$sql .= 'JOIN contributors ON contributors.id = albums.contributor ';
			$order_by = "contributors.namesort $collate, albums.year, albums.titlesort $collate";
			$c->{'contributors.namesort'} = 1;
			$page_key = "SUBSTR(contributors.namesort,1,1)";
		}
		elsif ( $sort eq 'artistalbum' ) {
			$sql .= 'JOIN contributors ON contributors.id = albums.contributor ';
			$order_by = "contributors.namesort $collate, albums.titlesort $collate";
			$c->{'contributors.namesort'} = 1;
			$page_key = "SUBSTR(contributors.namesort,1,1)";
		}
		elsif ( $sort eq 'yearartistalbum' ) {
			$sql .= 'JOIN contributors ON contributors.id = albums.contributor ';
			$order_by = "albums.year, contributors.namesort $collate, albums.titlesort $collate";
			$page_key = "albums.year";
		}
		elsif ( $sort eq 'yearalbum' ) {
			$order_by = "albums.year, albums.titlesort $collate";
			$page_key = "albums.year";
		}

		if (specified($search)) {
			my $strings = Slim::Utils::Text::searchStringSplit($search);
			if ( ref $strings->[0] eq 'ARRAY' ) {
				push @{$w}, '(' . join( ' OR ', map { 'albums.titlesearch LIKE ?' } @{ $strings->[0] } ) . ')';
				push @{$p}, @{ $strings->[0] };
			}
			else {
				push @{$w}, 'albums.titlesearch LIKE ?';
				push @{$p}, @{$strings};
			}
		}

		if (defined $year) {
			push @{$w}, 'albums.year = ?';
			push @{$p}, $year;
		}

		# Manage joins
		if (defined $contributorID) {
			# handle the case where we're asked for the VA id => return compilations
			if ($contributorID == Slim::Schema->variousArtistsObject->id) {
				$compilation = 1;
			}
			else {

				$sql .= 'JOIN contributor_album ON contributor_album.album = albums.id ';
				push @{$w}, 'contributor_album.contributor = ?';
				push @{$p}, $contributorID;

				my $cond = 'contributor_album.role IN (?, ?, ?';

				push @{$p}, (
					Slim::Schema::Contributor->typeToRole('ARTIST'),
					Slim::Schema::Contributor->typeToRole('TRACKARTIST'),
					Slim::Schema::Contributor->typeToRole('ALBUMARTIST'),
				);

				# Loop through each pref to see if the user wants to show that contributor role.
				foreach (Slim::Schema::Contributor->contributorRoles) {
					if ($prefs->get(lc($_) . 'InArtists')) {
						$cond .= ', ?';
						push @{$p}, Slim::Schema::Contributor->typeToRole($_);
					}
				}

				push @{$w}, ($cond . ')');
			}
		}

		if (defined $genreID) {
			$sql .= 'JOIN tracks ON tracks.album = albums.id ';
			$sql .= 'JOIN genre_track ON genre_track.track = tracks.id ';
			push @{$w}, 'genre_track.genre = ?';
			push @{$p}, $genreID;
		}

		if (defined $compilation) {
			if ($compilation == 1) {
				push @{$w}, 'albums.compilation = 1';
			}
			else {
				push @{$w}, '(albums.compilation IS NULL OR albums.compilation = 0)';
			}
		}
	}

	if ( $tags =~ /l/ ) {
		# title/disc/discc is needed to construct (N of M) title
		map { $c->{$_} = 1 } qw(albums.title albums.disc albums.discc);
	}

	if ( $tags =~ /y/ ) {
		$c->{'albums.year'} = 1;
	}

	if ( $tags =~ /j/ ) {
		$c->{'albums.artwork'} = 1;
	}

	if ( $tags =~ /t/ ) {
		$c->{'albums.title'} = 1;
	}

	if ( $tags =~ /i/ ) {
		$c->{'albums.disc'} = 1;
	}

	if ( $tags =~ /q/ ) {
		$c->{'albums.discc'} = 1;
	}

	if ( $tags =~ /w/ ) {
		$c->{'albums.compilation'} = 1;
	}

	if ( $tags =~ /X/ ) {
		$c->{'albums.replay_gain'} = 1;
	}

	if ( $tags =~ /S/ ) {
		$c->{'albums.contributor'} = 1;
	}

	if ( $tags =~ /a/ ) {
		# If requesting artist data, join contributor
		if ( $sql !~ /JOIN contributors/ ) {
			if ( $sql =~ /JOIN contributor_album/ ) {
				# Bug 17364, if looking for an artist_id value, we need to join contributors via contributor_album
				# or No Album will not be found properly
				$sql .= 'JOIN contributors ON contributors.id = contributor_album.contributor ';
			}
			else {
				$sql .= 'JOIN contributors ON contributors.id = albums.contributor ';
			}
		}
		$c->{'contributors.name'} = 1;

		# if albums for a specific contributor are requested, then we need the album's contributor, too
		$c->{'albums.contributor'} = $contributorID;
	}

	if ( $tags =~ /s/ ) {
		$c->{'albums.titlesort'} = 1;
	}

	if ( @{$w} ) {
		$sql .= 'WHERE ';
		my $s .= join( ' AND ', @{$w} );
		$s =~ s/\%/\%\%/g;
		$sql .= $s . ' ';
	}

	my $dbh = Slim::Schema->dbh;

	if ($page_key && $tags =~ /Z/) {
		my $pageSql = sprintf($sql, "$page_key, count(distinct albums.id)")
			 . "GROUP BY $page_key ORDER BY $order_by ";
		$request->addResult('indexList', $dbh->selectall_arrayref($pageSql, undef, @{$p}));

		if ($tags =~ /ZZ/) {
			$request->setStatusDone();
			return
		}
	}

	$sql .= "GROUP BY albums.id ORDER BY $order_by ";

	# Add selected columns
	# Bug 15997, AS mapping needed for MySQL
	my @cols = keys %{$c};
	$sql = sprintf $sql, join( ', ', map { $_ . " AS '" . $_ . "'" } @cols );

	my $stillScanning = Slim::Music::Import->stillScanning();

	# Get count of all results, the count is cached until the next rescan done event
	my $cacheKey = $sql . join( '', @{$p} );

	my $countsql = $sql;
	$countsql .= ' LIMIT ' . $limit if $limit;
	my ($count) = $cache->{$cacheKey} || $dbh->selectrow_array( qq{
		SELECT COUNT(*) FROM ( $countsql ) AS t1
	}, undef, @{$p} );

	if ( !$stillScanning ) {
		$cache->{$cacheKey} = $count;
	}

	if ($stillScanning) {
		$request->addResult('rescan', 1);
	}

	$count += 0;

	# now build the result
	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

	my $loopname = 'albums_loop';
	my $chunkCount = 0;

	if ($valid) {

		# We need to know the 'No album' name so that those items
		# which have been grouped together under it do not get the
		# album art of the first album.
		# It looks silly to go to Madonna->No album and see the
		# picture of '2 Unlimited'.
		my $noAlbumName = $request->string('NO_ALBUM');

		# Limit the real query
		if ($limit && !$quantity) {
			$quantity = "$limit";
			$index ||= "0";
		}
		if ( $index =~ /^\d+$/ && defined $quantity && $quantity =~ /^\d+$/ ) {
			$sql .= "LIMIT $index, $quantity ";
		}

		if ( main::DEBUGLOG && $sqllog->is_debug ) {
			$sqllog->debug( "Albums query: $sql / " . Data::Dump::dump($p) );
		}

		my $sth = $dbh->prepare_cached($sql);
		$sth->execute( @{$p} );

		# Bind selected columns in order
		my $i = 1;
		for my $col ( @cols ) {
			$sth->bind_col( $i++, \$c->{$col} );
		}

		# Little function to construct nice title from title/disc counts
		my $groupdiscs_pref = $prefs->get('groupdiscs');
		my $construct_title = sub {
			if ( $groupdiscs_pref ) {
				return $c->{'albums.title'};
			}

			return Slim::Music::Info::addDiscNumberToAlbumTitle(
				$c->{'albums.title'}, $c->{'albums.disc'}, $c->{'albums.discc'}
			);
		};

		while ( $sth->fetch ) {

			utf8::decode( $c->{'albums.title'} ) if exists $c->{'albums.title'};
			utf8::decode( $c->{'contributors.name'} ) if exists $c->{'contributors.name'};

			$request->addResultLoop($loopname, $chunkCount, 'id', $c->{'albums.id'});
			$tags =~ /l/ && $request->addResultLoop($loopname, $chunkCount, 'album', $construct_title->());
			$tags =~ /y/ && $request->addResultLoopIfValueDefined($loopname, $chunkCount, 'year', $c->{'albums.year'});
			$tags =~ /j/ && $request->addResultLoopIfValueDefined($loopname, $chunkCount, 'artwork_track_id', $c->{'albums.artwork'});
			$tags =~ /t/ && $request->addResultLoop($loopname, $chunkCount, 'title', $c->{'albums.title'});
			$tags =~ /i/ && $request->addResultLoopIfValueDefined($loopname, $chunkCount, 'disc', $c->{'albums.disc'});
			$tags =~ /q/ && $request->addResultLoopIfValueDefined($loopname, $chunkCount, 'disccount', $c->{'albums.discc'});
			$tags =~ /w/ && $request->addResultLoopIfValueDefined($loopname, $chunkCount, 'compilation', $c->{'albums.compilation'});
			$tags =~ /X/ && $request->addResultLoopIfValueDefined($loopname, $chunkCount, 'album_replay_gain', $c->{'albums.replay_gain'});
			$tags =~ /S/ && $request->addResultLoopIfValueDefined($loopname, $chunkCount, 'artist_id', $c->{'albums.contributor'});
			if ($tags =~ /a/) {
				# Bug 15313, this used to use $eachitem->artists which
				# contains a lot of extra logic.

				# Bug 17542: If the album artist is different from the current track's artist,
				# use the album artist instead of the track artist (if available)
				if ($contributorID && $c->{'albums.contributor'} && $contributorID != $c->{'albums.contributor'}) {
					$c->{'contributors.name'} = Slim::Schema->find('Contributor', $c->{'albums.contributor'})->name || $c->{'contributors.name'};
				}

				$request->addResultLoopIfValueDefined($loopname, $chunkCount, 'artist', $c->{'contributors.name'});
			}
			if ($tags =~ /s/) {
				#FIXME: see if multiple char textkey is doable for year/genre sort
				my $textKey;
				if ($sort eq 'artflow' || $sort eq 'artistalbum') {
					utf8::decode( $c->{'contributors.namesort'} ) if exists $c->{'contributors.namesort'};
					$textKey = substr $c->{'contributors.namesort'}, 0, 1;
				} elsif ( $sort eq 'album' ) {
					utf8::decode( $c->{'albums.titlesort'} ) if exists $c->{'albums.titlesort'};
					$textKey = substr $c->{'albums.titlesort'}, 0, 1;
				}
				$request->addResultLoopIfValueDefined($loopname, $chunkCount, 'textkey', $textKey);
			}

			$chunkCount++;

			main::idleStreams() if !($chunkCount % 5);
		}

	}

	$request->addResult('count', $count);

	$request->setStatusDone();
}

sub artistsQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['artists']])) {
		$request->setStatusBadDispatch();
		return;
	}

	if (!Slim::Schema::hasLibrary()) {
		$request->setStatusNotDispatchable();
		return;
	}

	my $sqllog = main::DEBUGLOG && logger('database.sql');

	# get our parameters
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');
	my $search   = $request->getParam('search');
	my $year     = $request->getParam('year');
	my $genreID  = $request->getParam('genre_id');
	my $genreString  = $request->getParam('genre_string');
	my $trackID  = $request->getParam('track_id');
	my $albumID  = $request->getParam('album_id');
	my $artistID = $request->getParam('artist_id');
	my $to_cache = $request->getParam('cache');
	my $tags     = $request->getParam('tags') || '';

	my $va_pref = $prefs->get('variousArtistAutoIdentification');

	my $sql    = 'SELECT %s FROM contributors ';
	my $sql_va = 'SELECT COUNT(*) FROM albums ';
	my $w      = [];
	my $w_va   = [ 'albums.compilation = 1' ];
	my $p      = [];
	my $p_va   = [];

	my $rs;
	my $cacheKey;

	# Manage joins
	if (defined $trackID) {
		$sql .= 'JOIN contributor_track ON contributor_track.contributor = contributors.id ';
		push @{$w}, 'contributor_track.track = ?';
		push @{$p}, $trackID;
	}
	elsif (defined $artistID) {
		push @{$w}, 'contributors.id = ?';
		push @{$p}, $artistID;
	}
	else {
		my $roles = Slim::Schema->artistOnlyRoles || [];

		if ( defined $genreID ) {
			$sql .= 'JOIN contributor_track ON contributor_track.contributor = contributors.id ';
			$sql .= 'JOIN tracks ON tracks.id = contributor_track.track ';
			$sql .= 'JOIN genre_track ON genre_track.track = tracks.id ';
			push @{$w}, 'genre_track.genre = ?';
			push @{$p}, $genreID;

			# Adjust VA check to check for VA artists in this genre
			$sql_va .= 'JOIN tracks ON tracks.album = albums.id ';
			$sql_va .= 'JOIN genre_track ON genre_track.track = tracks.id ';
			push @{$w_va}, 'genre_track.genre = ?';
			push @{$p_va}, $genreID;
		}

		if ( !defined $search ) {
			if ( $sql !~ /JOIN contributor_track/ ) {
				$sql .= 'JOIN contributor_album ON contributor_album.contributor = contributors.id ';
			}
		}

		if ( !defined $search ) {
			# Filter based on roles unless we're searching
			if ( $sql =~ /JOIN contributor_track/ ) {
				push @{$w}, 'contributor_track.role IN (' . join( ',', @{$roles} ) . ') ';
			}
			else {
				push @{$w}, 'contributor_album.role IN (' . join( ',', @{$roles} ) . ') ';
			}

			if ( $va_pref ) {
				# Don't include artists that only appear on compilations
				if ( $sql =~ /JOIN tracks/ ) {
					# If doing an artists-in-genre query, we are much better off joining through albums
					$sql .= 'JOIN albums ON albums.id = tracks.album ';
				}
				else {
					if ( $sql !~ /JOIN contributor_album/ ) {
						$sql .= 'JOIN contributor_album ON contributor_album.contributor = contributors.id ';
					}
					$sql .= 'JOIN albums ON contributor_album.album = albums.id ';
				}

				push @{$w}, '(albums.compilation IS NULL OR albums.compilation = 0)';
			}
		}

		if (defined $albumID || defined $year) {
			if ( $sql !~ /JOIN contributor_album/ ) {
				$sql .= 'JOIN contributor_album ON contributor_album.contributor = contributors.id ';
			}

			if ( $sql !~ /JOIN albums/ ) {
				$sql .= 'JOIN albums ON contributor_album.album = albums.id ';
			}

			if (defined $albumID) {
				push @{$w}, 'albums.id = ?';
				push @{$p}, $albumID;

				push @{$w_va}, 'albums.id = ?';
				push @{$p_va}, $albumID;
			}

			if (defined $year) {
				push @{$w}, 'albums.year = ?';
				push @{$p}, $year;

				push @{$w_va}, 'albums.year = ?';
				push @{$p_va}, $year;
			}
		}

		if ($search) {
			my $strings = Slim::Utils::Text::searchStringSplit($search);
			if ( ref $strings->[0] eq 'ARRAY' ) {
				push @{$w}, '(' . join( ' OR ', map { 'contributors.namesearch LIKE ?' } @{ $strings->[0] } ) . ')';
				push @{$p}, @{ $strings->[0] };
			}
			else {
				push @{$w}, 'contributors.namesearch LIKE ?';
				push @{$p}, @{$strings};
			}
		}
	}

	if ( @{$w} ) {
		$sql .= 'WHERE ';
		my $s = join( ' AND ', @{$w} );
		$s =~ s/\%/\%\%/g;
		$sql .= $s . ' ';
	}

	my $dbh = Slim::Schema->dbh;

	my $collate = Slim::Utils::OSDetect->getOS()->sqlHelperClass()->collate();

	# Various artist handling. Don't do if pref is off, or if we're
	# searching, or if we have a track
	my $count_va = 0;

	if ( $va_pref && !defined $search && !defined $trackID && !defined $artistID ) {
		# Only show VA item if there are any
		if ( @{$w_va} ) {
			$sql_va .= 'WHERE ';
			$sql_va .= join( ' AND ', @{$w_va} );
			$sql_va .= ' ';
		}

		if ( main::DEBUGLOG && $sqllog->is_debug ) {
			$sqllog->debug( "Artists query VA count: $sql_va / " . Data::Dump::dump($p_va) );
		}

		($count_va) = $dbh->selectrow_array( $sql_va, undef, @{$p_va} );
	}

	my $indexList;
	if ($tags =~ /Z/) {
		my $pageSql = sprintf($sql, "SUBSTR(contributors.namesort,1,1), count(distinct contributors.id)")
			 . "GROUP BY SUBSTR(contributors.namesort,1,1) ORDER BY contributors.namesort $collate";
		$indexList = $dbh->selectall_arrayref($pageSql, undef, @{$p});

		unshift @$indexList, ['#' => 1] if $indexList && $count_va;

		if ($tags =~ /ZZ/) {
			$request->addResult('indexList', $indexList) if $indexList;
			$request->setStatusDone();
			return
		}
	}

	$sql = sprintf($sql, 'contributors.id, contributors.name, contributors.namesort, contributors.musicmagic_mixable')
			. "GROUP BY contributors.id ORDER BY contributors.namesort $collate";

	my $stillScanning = Slim::Music::Import->stillScanning();

	# Get count of all results, the count is cached until the next rescan done event
	$cacheKey = $sql . join( '', @{$p} );

	my ($count) = $cache->{$cacheKey} || $dbh->selectrow_array( qq{
		SELECT COUNT(*) FROM ( $sql ) AS t1
	}, undef, @{$p} );

	if ( !$stillScanning ) {
		$cache->{$cacheKey} = $count;
	}

	my $totalCount = $count || 0;

	if ( $count_va ) {
		# don't add the VA item on subsequent queries
		$count_va = ($count_va && !$index);

		# fix the index and counts if we have to include VA
		$totalCount = _fixCount(1, \$index, \$quantity, $count);
	}

	# now build the result

	if ($stillScanning) {
		$request->addResult('rescan', 1);
	}

	$count += 0;

	# If count is 0 but count_va is 1, set count to 1 because
	# we'll still have a VA item to add to the results
	if ( $count_va && !$count ) {
		$count = 1;
	}

	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

	# XXX for 'artists 0 1' with VA we need to force valid to 1
	if ( $count_va && $index == 0 && $quantity == 0 ) {
		$valid = 1;
	}

	my $loopname = 'artists_loop';
	my $chunkCount = 0;

	if ($valid) {
		# Limit the real query
		if ( $index =~ /^\d+$/ && $quantity =~ /^\d+$/ ) {
			$sql .= "LIMIT $index, $quantity ";
		}

		if ( main::DEBUGLOG && $sqllog->is_debug ) {
			$sqllog->debug( "Artists query: $sql / " . Data::Dump::dump($p) );
		}

		my $sth = $dbh->prepare_cached($sql);
		$sth->execute( @{$p} );

		my ($id, $name, $namesort, $mixable);
		$sth->bind_columns( \$id, \$name, \$namesort, \$mixable );

		my $process = sub {
			$id += 0;

			utf8::decode($name);
			utf8::decode($namesort);

			$request->addResultLoop($loopname, $chunkCount, 'id', $id);
			$request->addResultLoop($loopname, $chunkCount, 'artist', $name);
			if ($tags =~ /s/) {
				# Bug 11070: Don't display large V at beginning of browse Artists
				my $textKey = ($count_va && $chunkCount == 0) ? ' ' : substr($namesort, 0, 1);
				$request->addResultLoop($loopname, $chunkCount, 'textkey', $textKey);
			}

			$chunkCount++;

			main::idleStreams() if !($chunkCount % 10);
		};

		# Add VA item first if necessary
		if ( $count_va ) {
			my $vaObj = Slim::Schema->variousArtistsObject;

			# bug 15328 - get the VA name in the language requested by the client
			#             but only do so if the user isn't using a custom name
			my $vaName     = $vaObj->name;
			my $vaNamesort = $vaObj->namesort;
			if ( $vaName eq Slim::Utils::Strings::string('VARIOUSARTISTS') ) {
				$vaName     = $request->string('VARIOUSARTISTS');
				$vaNamesort = Slim::Utils::Text::ignoreCaseArticles($vaName);
			}

			$id       = $vaObj->id;
			$name     = $vaName;
			$namesort = $vaNamesort;
			$mixable  = 0;

			$process->();
		}

		while ( $sth->fetch ) {
			$process->();
		}

	}

	$request->addResult('indexList', $indexList) if $indexList;

	$request->addResult('count', $totalCount);

	$request->setStatusDone();
}



sub debugQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['debug']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $category = $request->getParam('_debugflag');

	if ( !defined $category || !Slim::Utils::Log->isValidCategory($category) ) {

		$request->setStatusBadParams();
		return;
	}

	my $categories = Slim::Utils::Log->allCategories;

	if (defined $categories->{$category}) {

		$request->addResult('_value', $categories->{$category});

		$request->setStatusDone();

	} else {

		$request->setStatusBadParams();
	}
}


sub genresQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['genres']])) {
		$request->setStatusBadDispatch();
		return;
	}

	if (!Slim::Schema::hasLibrary()) {
		$request->setStatusNotDispatchable();
		return;
	}

	my $sqllog = main::DEBUGLOG && logger('database.sql');

	# get our parameters
	my $index         = $request->getParam('_index');
	my $quantity      = $request->getParam('_quantity');
	my $search        = $request->getParam('search');
	my $year          = $request->getParam('year');
	my $contributorID = $request->getParam('artist_id');
	my $albumID       = $request->getParam('album_id');
	my $trackID       = $request->getParam('track_id');
	my $genreID       = $request->getParam('genre_id');
	my $tags          = $request->getParam('tags') || '';

	my $sql  = 'SELECT %s FROM genres ';
	my $w    = [];
	my $p    = [];

	# Normalize and add any search parameters
	if (specified($search)) {
		my $strings = Slim::Utils::Text::searchStringSplit($search);
		if ( ref $strings->[0] eq 'ARRAY' ) {
			push @{$w}, '(' . join( ' OR ', map { 'genres.namesearch LIKE ?' } @{ $strings->[0] } ) . ')';
			push @{$p}, @{ $strings->[0] };
		}
		else {
			push @{$w}, 'genres.namesearch LIKE ?';
			push @{$p}, @{$strings};
		}
	}

	# Manage joins
	if (defined $trackID) {
		$sql .= 'JOIN genre_track ON genres.id = genre_track.genre ';
		push @{$w}, 'genre_track.track = ?';
		push @{$p}, $trackID;
	}
	elsif (defined $genreID) {
		push @{$w}, 'genres.id = ?';
		push @{$p}, $genreID;
	}
	else {
		# ignore those if we have a track.
		if (defined $contributorID) {

			# handle the case where we're asked for the VA id => return compilations
			if ($contributorID == Slim::Schema->variousArtistsObject->id) {
				$sql .= 'JOIN genre_track ON genres.id = genre_track.genre ';
				$sql .= 'JOIN tracks ON genre_track.track = tracks.id ';
				$sql .= 'JOIN albums ON tracks.album = albums.id ';
				push @{$w}, 'albums.compilation = ?';
				push @{$p}, 1;
			}
			else {
				$sql .= 'JOIN genre_track ON genres.id = genre_track.genre ';
				$sql .= 'JOIN contributor_track ON genre_track.track = contributor_track.track ';
				push @{$w}, 'contributor_track.contributor = ?';
				push @{$p}, $contributorID;
			}
		}

		if (defined $albumID || defined $year) {
			if ( $sql !~ /JOIN genre_track/ ) {
				$sql .= 'JOIN genre_track ON genres.id = genre_track.genre ';
			}
			if ( $sql !~ /JOIN tracks/ ) {
				$sql .= 'JOIN tracks ON genre_track.track = tracks.id ';
			}

			if (defined $albumID) {
				push @{$w}, 'tracks.album = ?';
				push @{$p}, $albumID;
			}
			if (defined $year) {
				push @{$w}, 'tracks.year = ?';
				push @{$p}, $year;
			}
		}
	}

	if ( @{$w} ) {
		$sql .= 'WHERE ';
		my $s = join( ' AND ', @{$w} );
		$s =~ s/\%/\%\%/g;
		$sql .= $s . ' ';
	}

	my $dbh = Slim::Schema->dbh;

	my $collate = Slim::Utils::OSDetect->getOS()->sqlHelperClass()->collate();

	if ($tags =~ /Z/) {
		my $pageSql = sprintf($sql, "SUBSTR(genres.namesort,1,1), count(distinct genres.id)")
			 . "GROUP BY SUBSTR(genres.namesort,1,1) ORDER BY genres.namesort $collate";
		$request->addResult('indexList', $dbh->selectall_arrayref($pageSql, undef, @{$p}));
		if ($tags =~ /ZZ/) {
			$request->setStatusDone();
			return
		}
	}

	$sql = sprintf($sql, 'DISTINCT(genres.id), genres.name, genres.namesort, genres.musicmagic_mixable')
			. "ORDER BY genres.namesort $collate";

	my $stillScanning = Slim::Music::Import->stillScanning();

	# Get count of all results, the count is cached until the next rescan done event
	my $cacheKey = $sql . join( '', @{$p} );

	my ($count) = $cache->{$cacheKey} || $dbh->selectrow_array( qq{
		SELECT COUNT(*) FROM ( $sql ) AS t1
	}, undef, @{$p} );

	if ( !$stillScanning ) {
		$cache->{$cacheKey} = $count;
	}

	# now build the result

	if ($stillScanning) {
		$request->addResult('rescan', 1);
	}

	$count += 0;

	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

	if ($valid) {

		my $loopname = 'genres_loop';
		my $chunkCount = 0;

		# Limit the real query
		if ( $index =~ /^\d+$/ && $quantity =~ /^\d+$/ ) {
			$sql .= "LIMIT $index, $quantity ";
		}

		if ( main::DEBUGLOG && $sqllog->is_debug ) {
			$sqllog->debug( "Genres query: $sql / " . Data::Dump::dump($p) );
		}

		my $sth = $dbh->prepare_cached($sql);
		$sth->execute( @{$p} );

		my ($id, $name, $namesort, $mixable);
		$sth->bind_columns( \$id, \$name, \$namesort, \$mixable );

		while ( $sth->fetch ) {
			$id += 0;

			utf8::decode($name) if $name;
			utf8::decode($namesort) if $namesort;

			my $textKey = substr($namesort, 0, 1);

			$request->addResultLoop($loopname, $chunkCount, 'id', $id);
			$request->addResultLoop($loopname, $chunkCount, 'genre', $name);
			$tags =~ /s/ && $request->addResultLoop($loopname, $chunkCount, 'textkey', $textKey);

			$chunkCount++;

			main::idleStreams() if !($chunkCount % 5);
		}
	}

	$request->addResult('count', $count);

	$request->setStatusDone();
}


sub getStringQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['getstring']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $tokenlist = $request->getParam('_tokens');

	foreach my $token (split (/,/, $tokenlist)) {

		# check whether string exists or not, to prevent stack dumps if
		# client queries inexistent string
		if (Slim::Utils::Strings::stringExists($token)) {

			$request->addResult($token, $request->string($token));
		}

		else {

			$request->addResult($token, '');
		}
	}

	$request->setStatusDone();
}


sub infoTotalQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['info'], ['total'], ['genres', 'artists', 'albums', 'songs']])) {
		$request->setStatusBadDispatch();
		return;
	}

	if (!Slim::Schema::hasLibrary()) {
		$request->setStatusNotDispatchable();
		return;
	}

	my $totals = Slim::Schema->totals;

	# get our parameters
	my $entity = $request->getRequest(2);

	if ($entity eq 'albums') {
		$request->addResult("_$entity", $totals->{album});
	}
	elsif ($entity eq 'artists') {
		$request->addResult("_$entity", $totals->{contributor});
	}
	elsif ($entity eq 'genres') {
		$request->addResult("_$entity", $totals->{genre});
	}
	elsif ($entity eq 'songs') {
		$request->addResult("_$entity", $totals->{track});
	}

	$request->setStatusDone();
}


sub irenableQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['irenable']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client = $request->client();

	$request->addResult('_irenable', $client->irenable());

	$request->setStatusDone();
}


sub musicfolderQuery {
	mediafolderQuery(@_);
}

sub mediafolderQuery {
	my $request = shift;

	main::INFOLOG && $log->info("mediafolderQuery()");

	# check this is the correct query.
	if ($request->isNotQuery([['mediafolder']]) && $request->isNotQuery([['musicfolder']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');
	my $folderId = $request->getParam('folder_id');
	my $want_top = $request->getParam('return_top');
	my $url      = $request->getParam('url');
	my $type     = $request->getParam('type') || '';
	my $tags     = $request->getParam('tags') || '';

	my $sql;

	# Bug 17436, don't allow BMF if a scan is running
	if (Slim::Music::Import->stillScanning()) {
		$request->addResult('rescan', 1);
		$request->addResult('count', 1);

		$request->addResultLoop('folder_loop', 0, 'filename', $request->string('BROWSE_MUSIC_FOLDER_WHILE_SCANNING'));
		$request->addResultLoop('folder_loop', 0, 'type', 'text');

		$request->setStatusDone();
		return;
	}

	# url overrides any folderId
	my $params = ();
	my $mediaDirs = Slim::Utils::Misc::getMediaDirs($type || 'audio');

	my ($topLevelObj, $items, $count, $topPath);

	if ( !defined $url && !defined $folderId && scalar(@$mediaDirs) > 1) {

		$items = $mediaDirs;
		$count = scalar(@$items);
		$topPath = '';

	}

	else {
		if (defined $url) {
			$params->{'url'} = $url;
		}
		elsif ($folderId) {
			$params->{'id'} = $folderId;
		}
		elsif (scalar @$mediaDirs) {
			$params->{'url'} = $mediaDirs->[0];
		}

		if ($type) {
			$params->{typeRegEx} = Slim::Music::Info::validTypeExtensions($type);

			# if we need the artwork, we'll have to look them up in their own tables for videos/images
			if ($tags && $type eq 'image') {
				$sql = 'SELECT * FROM images WHERE url = ?';
			}
			elsif ($tags && $type eq 'video') {
				$sql = 'SELECT * FROM videos WHERE url = ?';
			}
		}

		# if this is a follow up query ($index > 0), try to read from the cache
		if (my $cachedItem = $bmfCache{ $params->{url} || $params->{id} || 0 }) {
			$items       = $cachedItem->{items};
			$topLevelObj = $cachedItem->{topLevelObj};
			$count       = $cachedItem->{count};
		}
		else {
			($topLevelObj, $items, $count) = Slim::Utils::Misc::findAndScanDirectoryTree($params);

			# cache results in case the same folder is queried again shortly
			# should speed up Jive BMF, as only the first chunk needs to run the full loop above
			$bmfCache{ $params->{url} || $params->{id} || 0 } = {
				items       => $items,
				topLevelObj => $topLevelObj,
				count       => $count,
			};
		}

		if ($want_top) {
			$items = [ $topLevelObj->url ];
			$count = 1;
		}

		# create filtered data
		$topPath = $topLevelObj->path if blessed($topLevelObj);
	}

	# now build the result

	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

	if ($valid) {

		my $loopname = 'folder_loop';
		my $chunkCount = 0;

		my $sth = $sql ? Slim::Schema->dbh->prepare_cached($sql) : undef;

		my $x = -1;
		for my $filename (@$items) {

			my $url = Slim::Utils::Misc::fixPath($filename, $topPath) || '';
			my $realName;

			# Amazingly, this just works. :)
			# Do the cheap compare for osName first - so non-windows users
			# won't take the penalty for the lookup.
			if (main::ISWINDOWS && Slim::Music::Info::isWinShortcut($url)) {

				($realName, $url) = Slim::Utils::OS::Win32->getShortcut($url);
			}

			elsif (main::ISMAC) {
				if ( my $alias = Slim::Utils::Misc::pathFromMacAlias($url) ) {
					$url = $alias;
				}
			}

			my $item;

			$item = Slim::Schema->objectForUrl({
				'url'      => $url,
				'create'   => 1,
				'readTags' => 1,
			}) if $url;

			my $id;

			if ( (!blessed($item) || !$item->can('content_type'))
				&& (!$params->{typeRegEx} || $filename !~ $params->{typeRegEx}) )
			{
				$count--;
				next;
			}
			elsif (blessed($item)) {
				$id = $item->id();
			}

			$x++;

			if ($x < $start) {
				next;
			}
			elsif ($x > $end) {
				last;
			}

			$id += 0;

			$realName ||= Slim::Music::Info::fileName($url);

			my $textKey = uc(substr($realName, 0, 1));

			$request->addResultLoop($loopname, $chunkCount, 'id', $id);
			$request->addResultLoop($loopname, $chunkCount, 'filename', $realName);

			if (Slim::Music::Info::isDir($item)) {
				$request->addResultLoop($loopname, $chunkCount, 'type', 'folder');
			} elsif (Slim::Music::Info::isPlaylist($item)) {
				$request->addResultLoop($loopname, $chunkCount, 'type', 'playlist');
			} elsif ($params->{typeRegEx} && $filename =~ $params->{typeRegEx}) {
				$request->addResultLoop($loopname, $chunkCount, 'type', $type);

				# only do this for images & videos where we'll need the hash for the artwork
				if ($sth) {
					$sth->execute($url);

					my $itemDetails = $sth->fetchrow_hashref;

					if ($type eq 'video') {
						foreach my $k (keys %$itemDetails) {
							$itemDetails->{"videos.$k"} = $itemDetails->{$k} unless $k =~ /^videos\./;
						}

						_videoData($request, $loopname, $chunkCount, $tags, $itemDetails);
					}

					elsif ($type eq 'image') {
						utf8::decode( $itemDetails->{'images.title'} ) if exists $itemDetails->{'images.title'};
						utf8::decode( $itemDetails->{'images.album'} ) if exists $itemDetails->{'images.album'};

						foreach my $k (keys %$itemDetails) {
							$itemDetails->{"images.$k"} = $itemDetails->{$k} unless $k =~ /^images\./;
						}
						_imageData($request, $loopname, $chunkCount, $tags, $itemDetails);
					}

				}

			} elsif (Slim::Music::Info::isSong($item) && $type ne 'video') {
				$request->addResultLoop($loopname, $chunkCount, 'type', 'track');
			} elsif (-d Slim::Utils::Misc::pathFromMacAlias($url)) {
				$request->addResultLoop($loopname, $chunkCount, 'type', 'folder');
			} else {
				$request->addResultLoop($loopname, $chunkCount, 'type', 'unknown');
			}

			$tags =~ /s/ && $request->addResultLoop($loopname, $chunkCount, 'textkey', $textKey);
			$tags =~ /u/ && $request->addResultLoop($loopname, $chunkCount, 'url', $url);
			$tags =~ /t/ && $request->addResultLoop($loopname, $chunkCount, 'title', $realName);

			$chunkCount++;
		}

		$sth->finish() if $sth;
	}

	$request->addResult('count', $count);

	# we might have changed - flush to the db to be in sync.
	$topLevelObj->update if blessed($topLevelObj);

	# this is not always needed, but if only single tracks were added through BMF,
	# the caches would get out of sync
	Slim::Schema->wipeCaches;

	$request->setStatusDone();
}


sub playlistPlaylistsinfoQuery {
	my $request = shift;

	# check this is the correct query
	if ($request->isNotQuery([['playlist'], ['playlistsinfo']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client = $request->client();

	my $playlistObj = $client->currentPlaylist();

	if (blessed($playlistObj)) {
		if ($playlistObj->can('id')) {
			$request->addResult("id", $playlistObj->id());
		}

		$request->addResult("name", $playlistObj->title());

		$request->addResult("modified", $client->currentPlaylistModified());

		$request->addResult("url", $playlistObj->url());
	}

	$request->setStatusDone();
}


# XXX TODO: merge SQL-based code from 7.6/trunk
sub playlistsTracksQuery {
	my $request = shift;

	# check this is the correct query.
	# "playlisttracks" is deprecated (July 06).
	if ($request->isNotQuery([['playlisttracks']]) &&
		$request->isNotQuery([['playlists'], ['tracks']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $tags       = 'gald';
	my $index      = $request->getParam('_index');
	my $quantity   = $request->getParam('_quantity');
	my $tagsprm    = $request->getParam('tags');
	my $playlistID = $request->getParam('playlist_id');

	if (!defined $playlistID) {
		$request->setStatusBadParams();
		return;
	}

	# did we have override on the defaults?
	$tags = $tagsprm if defined $tagsprm;

	my $iterator;
	my @tracks;

	my $playlistObj = Slim::Schema->find('Playlist', $playlistID);

	if (blessed($playlistObj) && $playlistObj->can('tracks')) {
		$iterator = $playlistObj->tracks();
		$request->addResult("__playlistTitle", $playlistObj->name) if $playlistObj->name;
	}

	# now build the result

	if (Slim::Music::Import->stillScanning()) {
		$request->addResult("rescan", 1);
	}

	if (defined $iterator) {

		my $count = $iterator->count();
		$count += 0;

		my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

		if ($valid || $start == $end) {


			my $cur = $start;
			my $loopname = 'playlisttracks_loop';
			my $chunkCount = 0;

			my $list_index = 0;
			for my $eachitem ($iterator->slice($start, $end)) {

				_addSong($request, $loopname, $chunkCount, $eachitem, $tags, "playlist index", $cur);

				$cur++;
				$chunkCount++;

				main::idleStreams();
			}
		}
		$request->addResult("count", $count);

	} else {

		$request->addResult("count", 0);
	}

	$request->setStatusDone();
}


sub playlistsQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['playlists']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');
	my $search   = $request->getParam('search');
	my $tags     = $request->getParam('tags') || '';

	# Normalize any search parameters
	if (defined $search) {
		$search = Slim::Utils::Text::searchStringSplit($search);
	}

	my $rs = Slim::Schema->rs('Playlist')->getPlaylists('all', $search);

	# now build the result
	my $count = $rs->count;

	if (Slim::Music::Import->stillScanning()) {
		$request->addResult("rescan", 1);
	}

	if (defined $rs) {

		$count += 0;

		my ($valid, $start, $end) = $request->normalize(
			scalar($index), scalar($quantity), $count);

		if ($valid) {

			my $loopname = 'playlists_loop';
			my $chunkCount = 0;

			for my $eachitem ($rs->slice($start, $end)) {

				my $id = $eachitem->id();
				$id += 0;

				my $textKey = substr($eachitem->namesort, 0, 1);

				$request->addResultLoop($loopname, $chunkCount, "id", $id);
				$request->addResultLoop($loopname, $chunkCount, "playlist", $eachitem->title);
				$tags =~ /u/ && $request->addResultLoop($loopname, $chunkCount, "url", $eachitem->url);
				$tags =~ /s/ && $request->addResultLoop($loopname, $chunkCount, 'textkey', $textKey);

				$chunkCount++;

				main::idleStreams() if !($chunkCount % 5);
			}
		}

		$request->addResult("count", $count);

	} else {
		$request->addResult("count", 0);
	}
	$request->setStatusDone();
}


sub prefQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['pref']]) && $request->isNotQuery([['playerpref']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $client;

	if ($request->isQuery([['playerpref']])) {

		$client = $request->client();

		unless ($client) {
			$request->setStatusBadDispatch();
			return;
		}
	}

	# get the parameters
	my $prefName = $request->getParam('_prefname');

	# split pref name from namespace: name.space.pref:
	my $namespace = 'server';
	if ($prefName =~ /^(.*?):(.+)$/) {
		$namespace = $1;
		$prefName = $2;
	}

	if (!defined $prefName || !defined $namespace) {
		$request->setStatusBadParams();
		return;
	}

	$request->addResult('_p2', $client
		? preferences($namespace)->client($client)->get($prefName)
		: preferences($namespace)->get($prefName)
	);

	$request->setStatusDone();
}


sub prefValidateQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['pref'], ['validate']]) && $request->isNotQuery([['playerpref'], ['validate']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $client = $request->client();

	# get our parameters
	my $prefName = $request->getParam('_prefname');
	my $newValue = $request->getParam('_newvalue');

	# split pref name from namespace: name.space.pref:
	my $namespace = 'server';
	if ($prefName =~ /^(.*?):(.+)$/) {
		$namespace = $1;
		$prefName = $2;
	}

	if (!defined $prefName || !defined $namespace || !defined $newValue) {
		$request->setStatusBadParams();
		return;
	}

	$request->addResult('valid',
		($client
			? preferences($namespace)->client($client)->validate($prefName, $newValue)
			: preferences($namespace)->validate($prefName, $newValue)
		)
		? 1 : 0
	);

	$request->setStatusDone();
}


sub readDirectoryQuery {
	my $request = shift;

	main::INFOLOG && $log->info("readDirectoryQuery");

	# check this is the correct query.
	if ($request->isNotQuery([['readdirectory']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $index      = $request->getParam('_index');
	my $quantity   = $request->getParam('_quantity');
	my $folder     = $request->getParam('folder');
	my $filter     = $request->getParam('filter');

	use File::Spec::Functions qw(catdir);
	my @fsitems;		# raw list of items
	my %fsitems;		# meta data cache

	if (main::ISWINDOWS && $folder eq '/') {
		@fsitems = sort map {
			$fsitems{"$_"} = {
				d => 1,
				f => 0
			};
			"$_";
		} Slim::Utils::OS::Win32->getDrives();
		$folder = '';
	}
	else {
		$filter ||= '';

		my $filterRE = qr/./ unless ($filter eq 'musicfiles');

		# get file system items in $folder
		@fsitems = Slim::Utils::Misc::readDirectory(catdir($folder), $filterRE);
		map {
			$fsitems{$_} = {
				d => -d catdir($folder, $_),
				f => -f _
			}
		} @fsitems;
	}

	if ($filter eq 'foldersonly') {
		@fsitems = grep { $fsitems{$_}->{d} } @fsitems;
	}

	elsif ($filter eq 'filesonly') {
		@fsitems = grep { $fsitems{$_}->{f} } @fsitems;
	}

	# return all folders plus files of type
	elsif ($filter =~ /^filetype:(.*)/) {
		my $filterRE = qr/(?:\.$1)$/i;
		@fsitems = grep { $fsitems{$_}->{d} || $_ =~ $filterRE } @fsitems;
	}

	# search anywhere within path/filename
	elsif ($filter && $filter !~ /^(?:filename|filetype):/) {
		@fsitems = grep { catdir($folder, $_) =~ /$filter/i } @fsitems;
	}

	my $count = @fsitems;
	$count += 0;
	$request->addResult('count', $count);

	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

	if ($valid) {
		my $idx = $start;
		my $cnt = 0;

		if (scalar(@fsitems)) {
			# sort folders < files
			@fsitems = sort {
				if ($fsitems{$a}->{d}) {
					if ($fsitems{$b}->{d}) { uc($a) cmp uc($b) }
					else { -1 }
				}
				else {
					if ($fsitems{$b}->{d}) { 1 }
					else { uc($a) cmp uc($b) }
				}
			} @fsitems;

			my $path;
			for my $item (@fsitems[$start..$end]) {
				$path = ($folder ? catdir($folder, $item) : $item);

				my $name = $item;
				my $decodedName;

				# display full name if we got a Windows 8.3 file name
				if (main::ISWINDOWS && $name =~ /~\d/) {
					$decodedName = Slim::Music::Info::fileName($path);
				} else {
					$decodedName = Slim::Utils::Unicode::utf8decode_locale($name);
				}

				$request->addResultLoop('fsitems_loop', $cnt, 'path', Slim::Utils::Unicode::utf8decode_locale($path));
				$request->addResultLoop('fsitems_loop', $cnt, 'name', $decodedName);

				$request->addResultLoop('fsitems_loop', $cnt, 'isfolder', $fsitems{$item}->{d});

				$idx++;
				$cnt++;
			}
		}
	}

	$request->setStatusDone();
}


sub rescanQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['rescan']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# no params for the rescan query

	$request->addResult('_rescan', Slim::Music::Import->stillScanning() ? 1 : 0);

	$request->setStatusDone();
}


sub rescanprogressQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['rescanprogress']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# no params for the rescanprogress query

	if (Slim::Music::Import->stillScanning) {
		$request->addResult('rescan', 1);

		# get progress from DB
		my $args = {
			'type' => 'importer',
		};

		my @progress = Slim::Schema->rs('Progress')->search( $args, { 'order_by' => 'start,id' } )->all;

		# calculate total elapsed time
		# and indicate % completion for all importers
		my $total_time = 0;
		my @steps;

		for my $p (@progress) {

			my $name = $p->name;
			if ($name =~ /(.*)\|(.*)/) {
				$request->addResult('fullname', $request->string($2 . '_PROGRESS') . $request->string('COLON') . ' ' . $1);
				$name = $2;
			}

			my $percComplete = $p->finish ? 100 : $p->total ? $p->done / $p->total * 100 : -1;
			$request->addResult($name, int($percComplete));

			push @steps, $name;

			$total_time += ($p->finish || time()) - $p->start;

			if ($p->active && $p->info) {

				$request->addResult('info', $p->info);

			}
		}

		$request->addResult('steps', join(',', @steps)) if @steps;

		# report it
		my $hrs  = int($total_time / 3600);
		my $mins = int(($total_time - $hrs * 3600)/60);
		my $sec  = $total_time - (3600 * $hrs) - (60 * $mins);
		$request->addResult('totaltime', sprintf("%02d:%02d:%02d", $hrs, $mins, $sec));

	# if we're not scanning, just say so...
	} else {
		$request->addResult('rescan', 0);

		if (Slim::Schema::hasLibrary()) {
			# inform if the scan has failed
			if (my $p = Slim::Schema->rs('Progress')->search({ 'type' => 'importer', 'name' => 'failure' })->first) {
				_scanFailed($request, $p->info);
			}
		}
	}

	$request->setStatusDone();
}


sub searchQuery {
	my $request = shift;

	# check this is the correct query
	if ($request->isNotQuery([['search']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');
	my $query    = $request->getParam('term');

	# transliterate umlauts and accented characters
	# http://bugs.slimdevices.com/show_bug.cgi?id=8585
	$query = Slim::Utils::Text::matchCase($query);

	if (!defined $query || $query eq '') {
		$request->setStatusBadParams();
		return;
	}

	if (Slim::Music::Import->stillScanning) {
		$request->addResult('rescan', 1);
	}

	my $totalCount = 0;
	my $search     = Slim::Utils::Text::searchStringSplit($query);
	my %results    = ();
	my @types      = Slim::Schema->searchTypes;

	# Ugh - we need two loops here, as "count" needs to come first.

	if (Slim::Schema::hasLibrary()) {
		for my $type (@types) {

			my $rs      = Slim::Schema->rs($type)->searchNames($search);
			my $count   = $rs->count || 0;

			$results{$type}->{'rs'}    = $rs;
			$results{$type}->{'count'} = $count;

			$totalCount += $count;

			main::idleStreams();
		}
	}

	$totalCount += 0;
	$request->addResult('count', $totalCount);

	if (Slim::Schema::hasLibrary()) {
		for my $type (@types) {

			my $count = $results{$type}->{'count'};

			$count += 0;

			my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

			if ($valid) {
				$request->addResult("${type}s_count", $count);

				my $loopName  = "${type}s_loop";
				my $loopCount = 0;

				for my $result ($results{$type}->{'rs'}->slice($start, $end)) {

					# add result to loop
					$request->addResultLoop($loopName, $loopCount, "${type}_id", $result->id);
					$request->addResultLoop($loopName, $loopCount, $type, $result->name);

					$loopCount++;

					main::idleStreams() if !($loopCount % 5);
				}
			}
		}
	}

	$request->setStatusDone();
}


# the filter function decides, based on a notified request, if the serverstatus
# query must be re-executed.
sub serverstatusQuery_filter {
	my $self = shift;
	my $request = shift;

	# we want to know about clients going away as soon as possible
	if ($request->isCommand([['client'], ['forget']]) || $request->isCommand([['connect']])) {
		return 1;
	}

	# we want to know about rescan and all client notifs, as well as power on/off
	# FIXME: wipecache and rescan are synonyms...
	if ($request->isCommand([['wipecache', 'rescan', 'client', 'power']])) {
		return 1.3;
	}

	# FIXME: prefset???
	# we want to know about any pref in our array
	if (defined(my $prefsPtr = $self->privateData()->{'server'})) {
		if ($request->isCommand([['pref']])) {
			if (defined(my $reqpref = $request->getParam('_prefname'))) {
				if (grep($reqpref, @{$prefsPtr})) {
					return 1.3;
				}
			}
		}
	}
	if (defined(my $prefsPtr = $self->privateData()->{'player'})) {
		if ($request->isCommand([['playerpref']])) {
			if (defined(my $reqpref = $request->getParam('_prefname'))) {
				if (grep($reqpref, @{$prefsPtr})) {
					return 1.3;
				}
			}
		}
	}
	if ($request->isCommand([['name']])) {
		return 1.3;
	}

	return 0;
}


sub serverstatusQuery {
	my $request = shift;

	main::INFOLOG && $log->debug("serverstatusQuery()");

	# check this is the correct query
	if ($request->isNotQuery([['serverstatus']])) {
		$request->setStatusBadDispatch();
		return;
	}

	if (Slim::Schema::hasLibrary()) {
		if (Slim::Music::Import->stillScanning()) {
			$request->addResult('rescan', "1");
			if (my $p = Slim::Schema->rs('Progress')->search({ 'type' => 'importer', 'active' => 1 })->first) {

				# remove leading path information from the progress name
				my $name = $p->name;
				$name =~ s/(.*)\|//;

				$request->addResult('progressname', $request->string($name . '_PROGRESS'));
				$request->addResult('progressdone', $p->done);
				$request->addResult('progresstotal', $p->total);
			}
		}
		else {
			$request->addResult( lastscan => Slim::Music::Import->lastScanTime() );

			# XXX This needs to be fixed, failures are not reported
			#if ($p[-1]->name eq 'failure') {
			#	_scanFailed($request, $p[-1]->info);
			#}
		}
	}

	# add version
	$request->addResult('version', $::VERSION);

	# add server_uuid
	$request->addResult('uuid', $prefs->get('server_uuid'));

	if (Slim::Schema::hasLibrary()) {
		# add totals
		my $totals = Slim::Schema->totals;

		$request->addResult("info total albums", $totals->{album});
		$request->addResult("info total artists", $totals->{contributor});
		$request->addResult("info total genres", $totals->{genre});
		$request->addResult("info total songs", $totals->{track});
	}

	my %savePrefs;
	if (main::LOCAL_PLAYERS) {
		if (defined(my $pref_list = $request->getParam('prefs'))) {

			# split on commas
			my @prefs = split(/,/, $pref_list);
			$savePrefs{'server'} = \@prefs;

			for my $pref (@{$savePrefs{'server'}}) {
				if (defined(my $value = $prefs->get($pref))) {
					$request->addResult($pref, $value);
				}
			}
		}
		if (defined(my $pref_list = $request->getParam('playerprefs'))) {

			# split on commas
			my @prefs = split(/,/, $pref_list);
			$savePrefs{'player'} = \@prefs;

		}
	}


	# get our parameters
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');

	if (main::LOCAL_PLAYERS) {
		my $count = Slim::Player::Client::clientCount();
		$count += 0;

		$request->addResult('player count', $count);

		my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

		if ($valid) {

			my $cnt = 0;
			my @players = Slim::Player::Client::clients();

			if (scalar(@players) > 0) {

				for my $eachclient (@players[$start..$end]) {
					$request->addResultLoop('players_loop', $cnt,
						'playerid', $eachclient->id());
					$request->addResultLoop('players_loop', $cnt,
						'uuid', $eachclient->uuid());
					$request->addResultLoop('players_loop', $cnt,
						'ip', $eachclient->ipport());
					$request->addResultLoop('players_loop', $cnt,
						'name', $eachclient->name());
					if (defined $eachclient->sequenceNumber()) {
						$request->addResultLoop('players_loop', $cnt,
							'seq_no', $eachclient->sequenceNumber());
					}
					$request->addResultLoop('players_loop', $cnt,
						'model', $eachclient->model(1));
					$request->addResultLoop('players_loop', $cnt,
						'power', $eachclient->power());
					$request->addResultLoop('players_loop', $cnt,
						'displaytype', $eachclient->vfdmodel())
						unless ($eachclient->model() eq 'http');
					$request->addResultLoop('players_loop', $cnt,
						'canpoweroff', $eachclient->canPowerOff());
					$request->addResultLoop('players_loop', $cnt,
						'connected', ($eachclient->connected() || 0));
					$request->addResultLoop('players_loop', $cnt,
						'isplayer', ($eachclient->isPlayer() || 0));
					$request->addResultLoop('players_loop', $cnt,
						'player_needs_upgrade', "1")
						if ($eachclient->needsUpgrade());
					$request->addResultLoop('players_loop', $cnt,
						'player_is_upgrading', "1")
						if ($eachclient->isUpgrading());

					for my $pref (@{$savePrefs{'player'}}) {
						if (defined(my $value = $prefs->client($eachclient)->get($pref))) {
							$request->addResultLoop('players_loop', $cnt,
								$pref, $value);
						}
					}

					$cnt++;
				}
			}

		}

		# return list of players connected to SN
		my @sn_players = Slim::Networking::SqueezeNetwork::Players->get_players();

		$count = scalar @sn_players || 0;

		$request->addResult('sn player count', $count);

		($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

		if ($valid) {

			my $sn_cnt = 0;

			for my $player ( @sn_players ) {
				$request->addResultLoop(
					'sn_players_loop', $sn_cnt, 'id', $player->{id}
				);

				$request->addResultLoop(
					'sn_players_loop', $sn_cnt, 'name', $player->{name}
				);

				$request->addResultLoop(
					'sn_players_loop', $sn_cnt, 'playerid', $player->{mac}
				);

				$request->addResultLoop(
					'sn_players_loop', $sn_cnt, 'model', $player->{model}
				);

				$sn_cnt++;
			}
		}

		# return list of players connected to other servers
		my $other_players = Slim::Networking::Discovery::Players::getPlayerList();

		$count = scalar keys %{$other_players} || 0;

		$request->addResult('other player count', $count);

		($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

		if ($valid) {

			my $other_cnt = 0;

			for my $player ( keys %{$other_players} ) {
				$request->addResultLoop(
					'other_players_loop', $other_cnt, 'playerid', $player
				);

				$request->addResultLoop(
					'other_players_loop', $other_cnt, 'name', $other_players->{$player}->{name}
				);

				$request->addResultLoop(
					'other_players_loop', $other_cnt, 'model', $other_players->{$player}->{model}
				);

				$request->addResultLoop(
					'other_players_loop', $other_cnt, 'server', $other_players->{$player}->{server}
				);

				$request->addResultLoop(
					'other_players_loop', $other_cnt, 'serverurl',
						Slim::Networking::Discovery::Server::getWebHostAddress($other_players->{$player}->{server})
				);

				$other_cnt++;
			}
		}
	} else {
		$request->addResult('player count', 0);
	}

	# manage the subscription
	if (defined(my $timeout = $request->getParam('subscribe'))) {

		# store the prefs array as private data so our filter above can find it back
		$request->privateData(\%savePrefs);

		# register ourselves to be automatically re-executed on timeout or filter
		$request->registerAutoExecute($timeout, \&serverstatusQuery_filter);
	}

	$request->setStatusDone();
}


sub songinfoQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['songinfo']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $tags  = 'abcdefghijJklmnopqrstvwxyzBCDEFHIJKLMNOQRTUVWXY'; # all letter EXCEPT u, A & S, G & P, Z
	my $track;

	# get our parameters
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');
	my $url	     = $request->getParam('url');
	my $trackID  = $request->getParam('track_id');
	my $tagsprm  = $request->getParam('tags');

	if (!defined $trackID && !defined $url) {
		$request->setStatusBadParams();
		return;
	}

	# did we have override on the defaults?
	$tags = $tagsprm if defined $tagsprm;

	# find the track
	if (defined $trackID){

		$track = Slim::Schema->find('Track', $trackID);

	} else {

		if ( defined $url ){

			$track = Slim::Schema->objectForUrl($url);
		}
	}

	# now build the result

	if (Slim::Music::Import->stillScanning()) {
		$request->addResult("rescan", 1);
	}

	if (blessed($track) && $track->can('id')) {

		my $trackId = $track->id();
		$trackId += 0;

		my $hashRef = _songData($request, $track, $tags);
		my $count = scalar (keys %{$hashRef});

		$count += 0;

		my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

		my $loopname = 'songinfo_loop';
		my $chunkCount = 0;

		if ($valid) {

			# this is where we construct the nowplaying menu
			my $idx = 0;

			while (my ($key, $val) = each %{$hashRef}) {
				if ($idx >= $start && $idx <= $end) {

					$request->addResultLoop($loopname, $chunkCount, $key, $val);

					$chunkCount++;
				}
				$idx++;
			}
		}
	}

	$request->setStatusDone();
}


# this query is to provide a list of tracks for a given artist/album etc.

sub titlesQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['titles', 'tracks', 'songs']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $tags = 'gald';

	# get our parameters
	my $index         = $request->getParam('_index');
	my $quantity      = $request->getParam('_quantity');
	my $tagsprm       = $request->getParam('tags');
	my $sort          = $request->getParam('sort');
	my $search        = $request->getParam('search');
	my $genreID       = $request->getParam('genre_id');
	my $contributorID = $request->getParam('artist_id');
	my $albumID       = $request->getParam('album_id');
	my $trackID       = $request->getParam('track_id');
	my $year          = $request->getParam('year');
	my $menuStyle     = $request->getParam('menuStyle') || 'item';


	# did we have override on the defaults?
	# note that this is not equivalent to
	# $val = $param || $default;
	# since when $default eq '' -> $val eq $param
	$tags = $tagsprm if defined $tagsprm;

	my $collate  = Slim::Utils::OSDetect->getOS()->sqlHelperClass()->collate();
	my $where    = '(tracks.content_type != "cpl" AND tracks.content_type != "src" AND tracks.content_type != "ssp" AND tracks.content_type != "dir")';
	my $order_by = "tracks.titlesort $collate";

	if ($sort) {
		if ($sort eq 'tracknum') {
			$tags .= 't';
			$order_by = "tracks.disc, tracks.tracknum, tracks.titlesort $collate"; # XXX titlesort had prepended 0
		}
		elsif ( $sort =~ /^sql=(.+)/ ) {
			$order_by = $1;
			$order_by =~ s/;//g; # strip out any attempt at combining SQL statements
		}
		elsif ($sort eq 'albumtrack') {
			$tags .= 'tl';
			$order_by = "albums.titlesort, tracks.disc, tracks.tracknum, tracks.titlesort $collate"; # XXX titlesort had prepended 0
		}
	}

	my $stillScanning = Slim::Music::Import->stillScanning();

	my $count;
	my $start;
	my $end;

	my ($items, $itemOrder, $totalCount) = _getTagDataForTracks( $tags, {
		where         => $where,
		sort          => $order_by,
		search        => $search,
		albumId       => $albumID,
		year          => $year,
		genreId       => $genreID,
		contributorId => $contributorID,
		trackId       => $trackID,
		limit         => sub {
			$count = shift;

			my $valid;

			($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

			return ($valid, $index, $quantity);
		},
	} );

	if ($stillScanning) {
		$request->addResult("rescan", 1);
	}

	$count += 0;

	my $loopname = 'titles_loop';
	# this is the count of items in this part of the request (e.g., menu 100 200)
	# not to be confused with $count, which is the count of the entire list
	my $chunkCount = 0;

	if ( scalar @{$itemOrder} ) {

		for my $trackId ( @{$itemOrder} ) {
			my $item = $items->{$trackId};

			_addSong($request, $loopname, $chunkCount, $item, $tags);

			$chunkCount++;
		}

	}

	$request->addResult('count', $totalCount);

	$request->setStatusDone();
}


sub versionQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['version']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# no params for the version query

	$request->addResult('_version', $::VERSION);

	$request->setStatusDone();
}


sub yearsQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['years']])) {
		$request->setStatusBadDispatch();
		return;
	}

	if (!Slim::Schema::hasLibrary()) {
		$request->setStatusNotDispatchable();
		return;
	}

	my $sqllog = main::DEBUGLOG && logger('database.sql');

	# get our parameters
	my $index         = $request->getParam('_index');
	my $quantity      = $request->getParam('_quantity');
	my $year          = $request->getParam('year');
	my $hasAlbums     = $request->getParam('hasAlbums');

	# get them all by default
	my $where = {};

	my ($key, $table) = $hasAlbums ? ('year', 'albums') : ('id', 'years');

	my $sql = "SELECT DISTINCT $key FROM $table ";
	my $w   = ["$key != '0'"];
	my $p   = [];

	if (defined $year) {
		push @{$w}, "$key = ?";
		push @{$p}, $year;
	}

	if ( @{$w} ) {
		$sql .= 'WHERE ';
		$sql .= join( ' AND ', @{$w} );
		$sql .= ' ';
	}

	my $dbh = Slim::Schema->dbh;

	# Get count of all results, the count is cached until the next rescan done event
	my $cacheKey = $sql . join( '', @{$p} );

	my ($count) = $cache->{$cacheKey} || $dbh->selectrow_array( qq{
		SELECT COUNT(*) FROM ( $sql ) AS t1
	}, undef, @{$p} );

	$sql .= "ORDER BY $key";

	# now build the result

	if (Slim::Music::Import->stillScanning()) {
		$request->addResult('rescan', 1);
	}

	$count += 0;

	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

	if ($valid) {

		my $loopname = 'years_loop';
		my $chunkCount = 0;


		# Limit the real query
		if ( $index =~ /^\d+$/ && $quantity =~ /^\d+$/ ) {
			$sql .= " LIMIT $index, $quantity ";
		}

		if ( main::DEBUGLOG && $sqllog->is_debug ) {
			$sqllog->debug( "Years query: $sql / " . Data::Dump::dump($p) );
		}

		my $sth = $dbh->prepare_cached($sql);
		$sth->execute( @{$p} );

		my $id;
		$sth->bind_columns(\$id);

		while ( $sth->fetch ) {
			$id += 0;

			$request->addResultLoop($loopname, $chunkCount, 'year', $id);

			$chunkCount++;
		}
	}

	$request->addResult('count', $count);

	$request->setStatusDone();
}

################################################################################
# Special queries
################################################################################

=head2 dynamicAutoQuery( $request, $query, $funcptr, $data )

 This function is a helper function for any query that needs to poll enabled
 plugins. In particular, this is used to implement the CLI radios query,
 that returns all enabled radios plugins. This function is best understood
 by looking as well in the code used in the plugins.

 Each plugins does in initPlugin (edited for clarity):

    $funcptr = addDispatch(['radios'], [0, 1, 1, \&cli_radiosQuery]);

 For the first plugin, $funcptr will be undef. For all the subsequent ones
 $funcptr will point to the preceding plugin cli_radiosQuery() function.

 The cli_radiosQuery function looks like:

    sub cli_radiosQuery {
      my $request = shift;

      my $data = {
         #...
      };

      dynamicAutoQuery($request, 'radios', $funcptr, $data);
    }

 The plugin only defines a hash with its own data and calls dynamicAutoQuery.

 dynamicAutoQuery will call each plugin function recursively and add the
 data to the request results. It checks $funcptr for undefined to know if
 more plugins are to be called or not.

=cut

sub dynamicAutoQuery {
	my $request = shift;                       # the request we're handling
	my $query   = shift || return;             # query name
	my $funcptr = shift;                       # data returned by addDispatch
	my $data    = shift || return;             # data to add to results

	# check this is the correct query.
	if ($request->isNotQuery([[$query]])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity') || 0;
	my $sort     = $request->getParam('sort');
	my $menu     = $request->getParam('menu');

	my $menuMode = defined $menu;

	# we have multiple times the same resultset, so we need a loop, named
	# after the query name (this is never printed, it's just used to distinguish
	# loops in the same request results.
	my $loop = $menuMode?'item_loop':$query . 's_loop';

	# if the caller asked for results in the query ("radios 0 0" returns
	# immediately)
	if ($quantity) {

		# add the data to the results
		my $cnt = $request->getResultLoopCount($loop) || 0;

		if ( ref $data eq 'HASH' && scalar keys %{$data} ) {
			$data->{weight} = $data->{weight} || 1000;
			$request->setResultLoopHash($loop, $cnt, $data);
		}

		# more to jump to?
		# note we carefully check $funcptr is not a lemon
		if (defined $funcptr && ref($funcptr) eq 'CODE') {

			eval { &{$funcptr}($request) };

			# arrange for some useful logging if we fail
			if ($@) {

				logError("While trying to run function coderef: [$@]");
				$request->setStatusBadDispatch();
				$request->dump('Request');

				if ( main::SLIM_SERVICE ) {
					my $name = Slim::Utils::PerlRunTime::realNameForCodeRef($funcptr);
					$@ =~ s/"/'/g;
					SDI::Util::Syslog::error("service=SS-Queries method=${name} error=\"$@\"");
				}
			}
		}

		# $funcptr is undefined, we have everybody, now slice & count
		else {

			# sort if requested to do so
			if ($sort) {
				$request->sortResultLoop($loop, $sort);
			}

			# slice as needed
			my $count = $request->getResultLoopCount($loop);
			$request->sliceResultLoop($loop, $index, $quantity);
			$request->addResult('offset', $request->getParam('_index')) if $menuMode;
			$count += 0;
			$request->setResultFirst('count', $count);

			# don't forget to call that to trigger notifications, if any
			$request->setStatusDone();
		}
	}
	else {
		$request->setStatusDone();
	}
}

################################################################################
# Helper functions
################################################################################

sub _addSong {
	my $request   = shift; # request
	my $loop      = shift; # loop
	my $index     = shift; # loop index
	my $pathOrObj = shift; # song path or object, or hash from titlesQuery
	my $tags      = shift; # tags to use
	my $prefixKey = shift; # prefix key, if any
	my $prefixVal = shift; # prefix value, if any

	# get the hash with the data
	my $hashRef = _songData($request, $pathOrObj, $tags);

	# add the prefix in the first position, use a fancy feature of
	# Tie::LLHash
	if (defined $prefixKey && defined $hashRef) {
		(tied %{$hashRef})->Unshift($prefixKey => $prefixVal);
	}

	# add it directly to the result loop
	$request->setResultLoopHash($loop, $index, $hashRef);
}

my %tagMap = (
	# Tag    Tag name             Token            Track method         Track field
	#------------------------------------------------------------------------------
	  'u' => ['url',              'LOCATION',      'url'],              #url
	  'o' => ['type',             'TYPE',          'content_type'],     #content_type
	                                                                    #titlesort
	                                                                    #titlesearch
	  'a' => ['artist',           'ARTIST',        'artistName'],       #->contributors
	  'e' => ['album_id',         '',              'albumid'],          #album
	  'l' => ['album',            'ALBUM',         'albumname'],        #->album.title
	  't' => ['tracknum',         'TRACK',         'tracknum'],         #tracknum
	  'n' => ['modificationTime', 'MODTIME',       'modificationTime'], #timestamp
	  'D' => ['addedTime',        'ADDTIME',       'addedTime'],        #added_time
	  'U' => ['lastUpdated',      'UPDTIME',       'lastUpdated'],      #updated_time
	  'f' => ['filesize',         'FILELENGTH',    'filesize'],         #filesize
	                                                                    #tag
	  'i' => ['disc',             'DISC',          'disc'],             #disc
	  'j' => ['coverart',         'SHOW_ARTWORK',  'coverArtExists'],   #cover
	  'x' => ['remote',           '',              'remote'],           #remote
	                                                                    #audio
	                                                                    #audio_size
	                                                                    #audio_offset
	  'y' => ['year',             'YEAR',          'year'],             #year
	  'd' => ['duration',         'LENGTH',        'secs'],             #secs
	                                                                    #vbr_scale
	  'r' => ['bitrate',          'BITRATE',       'prettyBitRate'],    #bitrate
	  'T' => ['samplerate',       'SAMPLERATE',    'samplerate'],       #samplerate
	  'I' => ['samplesize',       'SAMPLESIZE',    'samplesize'],       #samplesize
	  'H' => ['channels',         'CHANNELS',      'channels'],         #channels
	  'F' => ['dlna_profile',     'DLNA_PROFILE',  'dlna_profile'],     #dlna_profile
	                                                                    #block_alignment
	  'E' => ['endian',           'ENDIAN',        'endian'],           #endian
	  'm' => ['bpm',              'BPM',           'bpm'],              #bpm
	  'v' => ['tagversion',       'TAGVERSION',    'tagversion'],       #tagversion
	# 'z' => ['drm',              '',              'drm'],              #drm
	  'M' => ['musicmagic_mixable', '',            'musicmagic_mixable'], #musicmagic_mixable
	                                                                    #musicbrainz_id
	                                                                    #playcount
	                                                                    #lastplayed
	                                                                    #lossless
	  'w' => ['lyrics',           'LYRICS',        'lyrics'],           #lyrics
	  'R' => ['rating',           'RATING',        'rating'],           #rating
	  'Y' => ['replay_gain',      'REPLAYGAIN',    'replay_gain'],      #replay_gain
	                                                                    #replay_peak

	  'c' => ['coverid',          'COVERID',       'coverid'],          # coverid
	  'K' => ['artwork_url',      '',              'coverurl'],         # artwork URL, not in db
	  'O' => ['icon',             '',              'icon'],             # music service's icon (not the track's artwork!)
	  'B' => ['buttons',          '',              'buttons'],          # radio stream special buttons
	  'L' => ['info_link',        '',              'info_link'],        # special trackinfo link for i.e. Pandora
	  'N' => ['remote_title'],                                          # remote stream title


	# Tag    Tag name              Token              Relationship     Method          Track relationship
	#--------------------------------------------------------------------------------------------------
	  's' => ['artist_id',         '',                'artist',        'id'],           #->contributors
	  'A' => ['<role>',            '<ROLE>',          'contributors',  'name'],         #->contributors[role].name
	  'S' => ['<role>_ids',        '',                'contributors',  'id'],           #->contributors[role].id

	  'q' => ['disccount',         '',                'album',         'discc'],        #->album.discc
	  'J' => ['artwork_track_id',  'COVERART',        'album',         'artwork'],      #->album.artwork
	  'C' => ['compilation',       'COMPILATION',     'album',         'compilation'],  #->album.compilation
	  'X' => ['album_replay_gain', 'ALBUMREPLAYGAIN', 'album',         'replay_gain'],  #->album.replay_gain

	  'g' => ['genre',             'GENRE',           'genre',         'name'],         #->genre_track->genre.name
	  'p' => ['genre_id',          '',                'genre',         'id'],           #->genre_track->genre.id
	  'G' => ['genres',            'GENRE',           'genres',        'name'],         #->genre_track->genres.name
	  'P' => ['genre_ids',         '',                'genres',        'id'],           #->genre_track->genres.id

	  'k' => ['comment',           'COMMENT',         'comment'],                       #->comment_object

);

# Map tag -> column to avoid a huge if-else structure
my %colMap = (
	g => 'genres.name',
	G => 'genres',
	p => 'genres.id',
	P => 'genre_ids',
	a => 'contributors.name',
	's' => 'contributors.id',
	l => 'albums.title',
	e => 'tracks.album',
	d => 'tracks.secs',
	i => 'tracks.disc',
	q => 'albums.discc',
	t => 'tracks.tracknum',
	y => 'tracks.year',
	m => 'tracks.bpm',
	M => sub { $_[0]->{'tracks.musicmagic_mixable'} ? 1 : 0 },
	k => 'comment',
	o => 'tracks.content_type',
	v => 'tracks.tagversion',
	r => sub { Slim::Schema::Track->buildPrettyBitRate( $_[0]->{'tracks.bitrate'}, $_[0]->{'tracks.vbr_scale'} ) },
	f => 'tracks.filesize',
	j => sub { $_[0]->{'tracks.cover'} ? 1 : 0 },
	J => 'albums.artwork',
	n => 'tracks.timestamp',
	F => 'tracks.dlna_profile',
	D => 'tracks.added_time',
	U => 'tracks.updated_time',
	C => sub { $_[0]->{'albums.compilation'} ? 1 : 0 },
	Y => 'tracks.replay_gain',
	X => 'albums.replay_gain',
	R => 'tracks_persistent.rating',
	T => 'tracks.samplerate',
	I => 'tracks.samplesize',
	u => 'tracks.url',
	w => 'tracks.lyrics',
	x => sub { $_[0]->{'tracks.remote'} ? 1 : 0 },
	c => 'tracks.coverid',
	H => 'tracks.channels',
	E => 'tracks.endian',
);

sub _songDataFromHash {
	my ( $request, $res, $tags ) = @_;

	# define an ordered hash for our results
	tie (my %returnHash, "Tie::IxHash");

	$returnHash{id}    = $res->{'tracks.id'};
	$returnHash{title} = $res->{'tracks.title'};

	# loop so that stuff is returned in the order given...
	for my $tag (split (//, $tags)) {
		my $tagref = $tagMap{$tag} or next;

		# Special case for A/S which return multiple keys
		if ( $tag eq 'A' ) {
			for my $role ( Slim::Schema::Contributor->contributorRoles ) {
				$role = lc $role;
				if ( defined $res->{$role} ) {
					$returnHash{$role} = $res->{$role};
				}
			}
		}
		elsif ( $tag eq 'S' ) {
			for my $role ( Slim::Schema::Contributor->contributorRoles ) {
				$role = lc $role;
				if ( defined $res->{"${role}_ids"} ) {
					$returnHash{"${role}_ids"} = $res->{"${role}_ids"};
				}
			}
		}
		# eg. the web UI is requesting some tags which are only available for remote tracks,
		# such as 'B' (custom button handler). They would return empty here - ignore them.
		elsif ( my $map = $colMap{$tag} ) {
			my $value = ref $map eq 'CODE' ? $map->($res) : $res->{$map};

			if (defined $value && $value ne '') {
				$returnHash{ $tagref->[0] } = $value;
			}
		}
	}

	return \%returnHash;
}

sub _songData {
	my $request   = shift; # current request object
	my $pathOrObj = shift; # song path or object
	my $tags      = shift; # tags to use

	if ( ref $pathOrObj eq 'HASH' ) {
		# Hash from direct DBI query in titlesQuery
		return _songDataFromHash($request, $pathOrObj, $tags);
	}

	# figure out the track object
	my $track     = Slim::Schema->objectForUrl($pathOrObj);

	if (!blessed($track) || !$track->can('id')) {

		logError("Called with invalid object or path: $pathOrObj!");

		# For some reason, $pathOrObj may be an id... try that before giving up...
		if ($pathOrObj =~ /^\d+$/) {
			$track = Slim::Schema->find('Track', $pathOrObj);
		}

		if (!blessed($track) || !$track->can('id')) {

			logError("Can't make track from: $pathOrObj!");
			return;
		}
	}

	# If we have a remote track, check if a plugin can provide metadata
	my $remoteMeta = {};
	my $isRemote = $track->remote;
	my $url = $track->url;

	if ( $isRemote ) {
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL($url);

		if ( $handler && $handler->can('getMetadataFor') ) {
			# Don't modify source data
			$remoteMeta = Storable::dclone(
				$handler->getMetadataFor( $request->client, $url )
			);

			$remoteMeta->{a} = $remoteMeta->{artist};
			$remoteMeta->{A} = $remoteMeta->{artist};
			$remoteMeta->{l} = $remoteMeta->{album};
			$remoteMeta->{K} = $remoteMeta->{cover};
			$remoteMeta->{d} = ( $remoteMeta->{duration} || 0 ) + 0;
			$remoteMeta->{Y} = $remoteMeta->{replay_gain};
			$remoteMeta->{o} = $remoteMeta->{type};
			$remoteMeta->{r} = $remoteMeta->{bitrate};
			$remoteMeta->{B} = $remoteMeta->{buttons};
			$remoteMeta->{L} = $remoteMeta->{info_link};
			$remoteMeta->{O} = $remoteMeta->{icon};
		}

		if (my $migrationData = Slim::Formats::RemoteMetadata->getMigrationInfoData($request->client)) {
			$remoteMeta->{cover} = $remoteMeta->{K} = $remoteMeta->{icon} = $migrationData->{icon};
			$remoteMeta->{artist} = $remoteMeta->{A} = $remoteMeta->{a} = $migrationData->{artist};
			$remoteMeta->{album} = $remoteMeta->{l} = $$migrationData->{album};
			$remoteMeta->{title} = $migrationData->{title};
		}

		# warn Data::Dump::dump($remoteMeta);
	}

	my $parentTrack;
	if (main::LOCAL_PLAYERS) {
		if ( my $client = $request->client ) { # Bug 13062, songinfo may be called without a client
			if (my $song = $client->currentSongForUrl($url)) {
				my $t = $song->currentTrack();
				if ($t->url ne $url) {
					$parentTrack = $track;
					$track = $t;
					$isRemote = $track->remote;
				}
			}
		}
	}

	# define an ordered hash for our results
	tie (my %returnHash, "Tie::IxHash");

	$returnHash{'id'}    = $track->id;
	$returnHash{'title'} = $remoteMeta->{title} || $track->title;

	# loop so that stuff is returned in the order given...
	for my $tag (split (//, $tags)) {

		my $tagref = $tagMap{$tag} or next;

		# special case, remote stream name
		if ($tag eq 'N') {
			if ($parentTrack) {
				$returnHash{$tagref->[0]} = $parentTrack->title;
			} elsif ( $isRemote && !$track->secs && $remoteMeta->{title} && !$remoteMeta->{album} ) {
				if (my $meta = $track->title) {
					$returnHash{$tagref->[0]} = $meta;
				}
			}
		}

		# special case for remote flag, since we had to evaluate it anyway
		# only include it if it is true
		elsif ($tag eq 'x' && $isRemote) {
			$returnHash{$tagref->[0]} = 1;
		}

		# service icon
		elsif ($tag eq 'O' && $remoteMeta->{O}) {
			$returnHash{$tagref->[0]} = $remoteMeta->{O};
		}

		# special case artists (tag A and S)
		elsif ($tag eq 'A' || $tag eq 'S') {
			if ( my $meta = $remoteMeta->{$tag} ) {
				$returnHash{artist} = $meta;
				next;
			}

			if ( defined(my $submethod = $tagref->[3]) && !main::SLIM_SERVICE ) {

				my $postfix = ($tag eq 'S')?"_ids":"";

				foreach my $type (Slim::Schema::Contributor::contributorRoles()) {

					my $key = lc($type) . $postfix;
					my $contributors = $track->contributorsOfType($type) or next;
					my @values = map { $_ = $_->$submethod() } $contributors->all;
					my $value = join(', ', @values);

					if (defined $value && $value ne '') {

						# add the tag to the result
						$returnHash{$key} = $value;
					}
				}
			}
		}

		# if we have a method/relationship for the tag
		elsif (defined(my $method = $tagref->[2])) {

			my $value;
			my $key = $tagref->[0];

			# Override with remote track metadata if available
			if ( defined $remoteMeta->{$tag} ) {
				$value = $remoteMeta->{$tag};
			}

			elsif ($method eq '' || !$track->can($method)) {
				next;
			}

			# tag with submethod
			elsif (defined(my $submethod = $tagref->[3])) {

				# call submethod
				if (defined(my $related = $track->$method)) {

					# array returned/genre
					if ( blessed($related) && $related->isa('Slim::Schema::ResultSet::Genre')) {
						$value = join(', ', map { $_ = $_->$submethod() } $related->all);
					} else {
						$value = $related->$submethod();
					}
				}
			}

			# simple track method
			else {
				$value = $track->$method();
			}

			# correct values
			if (($tag eq 'R' || $tag eq 'x') && $value == 0) {
				$value = undef;
			}

			# if we have a value
			if (defined $value && $value ne '') {

				# add the tag to the result
				$returnHash{$key} = $value;
			}
		}
	}

	return \%returnHash;
}

# this is a silly little sub that allows jive cover art to be rendered in a large window
sub showArtwork {

	main::INFOLOG && $log->info("Begin showArtwork Function");
	my $request = shift;

	# get our parameters
	my $id = $request->getParam('_artworkid');

	if ($id =~ /:\/\//) {
		$request->addResult('artworkUrl'  => $id);
	} else {
		$request->addResult('artworkId'  => $id);
	}

	$request->addResult('offset', 0);
	$request->setStatusDone();

}

# Wipe cached data, called after a rescan
sub wipeCaches {
	$cache = {};
}

# fix the count in case we're adding additional items
# (VA etc.) to the resultset
sub _fixCount {
	my $insertItem = shift;
	my $index      = shift;
	my $quantity   = shift;
	my $count      = shift;

	my $totalCount = $count || 0;

	if ($insertItem) {
		$totalCount++;

		# return one less result as we only add the additional item in the first chunk
		if ( !$$index ) {
			$$quantity--;
		}

		# decrease the index in subsequent queries
		else {
			$$index--;
		}
	}

	return $totalCount;
}

sub _scanFailed {
	my ($request, $info) = @_;

	if ($info && $info eq 'SCAN_ABORTED') {
		$info = $request->string($info);
	}
	elsif ($info) {
		$info = $request->string('FAILURE_PROGRESS', $request->string($info . '_PROGRESS') || '?');
	}

	$request->addResult('lastscanfailed', $info || '?');
}

=pod
This method is used by both titlesQuery and statusQuery, it tries to get a bunch of data
about tracks as efficiently as possible.

	$tags - String of tags, see songinfo docs
	$args - {
		where         => additional raw SQL to be used in WHERE clause
		sort          => string to be used with ORDER BY
		search        => titlesearch
		albumId       => return tracks for this album ID
		year          => return tracks for this year
		genreId       => return tracks for this genre ID
		contributorId => return tracks for this contributor ID
		trackIds      => arrayref of track IDs to fetch
		limit         => a coderef that is passed the count and returns (valid, start, end)
		                 If valid is not true, the request is aborted.
		                 This is messy but the only way to support the use of _fixCount, etc
	}

Returns arrayref of hashes.
=cut

sub _getTagDataForTracks {
	my ( $tags, $args ) = @_;

	my $sqllog = main::DEBUGLOG && logger('database.sql');

	my $collate = Slim::Utils::OSDetect->getOS()->sqlHelperClass()->collate();

	my $sql      = 'SELECT %s FROM tracks ';
	my $c        = { 'tracks.id' => 1, 'tracks.title' => 1 };
	my $w        = [];
	my $p        = [];
	my $total    = 0;

	if ( $args->{where} ) {
		push @{$w}, $args->{where};
	}

	my $sort = $args->{sort};

	# Normalize any search parameters
	my $search = $args->{search};
	if ( $search && specified($search) ) {
		if ( $search =~ s/^sql=// ) {
			# Raw SQL search query
			$search =~ s/;//g; # strip out any attempt at combining SQL statements
			push @{$w}, $search;
		}
		else {
			my $strings = Slim::Utils::Text::searchStringSplit($search);
			if ( ref $strings->[0] eq 'ARRAY' ) {
				push @{$w}, '(' . join( ' OR ', map { 'tracks.titlesearch LIKE ?' } @{ $strings->[0] } ) . ')';
				push @{$p}, @{ $strings->[0] };
			}
			else {
				push @{$w}, 'tracks.titlesearch LIKE ?';
				push @{$p}, @{$strings};
			}
		}
	}

	if ( my $albumId = $args->{albumId} ) {
		push @{$w}, 'tracks.album = ?';
		push @{$p}, $albumId;
	}

	if ( my $trackId = $args->{trackId} ) {
		push @{$w}, 'tracks.id = ?';
		push @{$p}, $trackId;
	}

	if ( my $year = $args->{year} ) {
		push @{$w}, 'tracks.year = ?';
		push @{$p}, $year;
	}

	# Some helper functions to setup joins with less code
	my $join_genre_track = sub {
		if ( $sql !~ /JOIN genre_track/ ) {
			$sql .= 'JOIN genre_track ON genre_track.track = tracks.id ';
		}
	};

	my $join_genres = sub {
		$join_genre_track->();

		if ( $sql !~ /JOIN genres/ ) {
			$sql .= 'JOIN genres ON genres.id = genre_track.genre ';
		}
	};

	my $join_contributor_tracks = sub {
		if ( $sql !~ /JOIN contributor_track/ ) {
			$sql .= 'JOIN contributor_track ON contributor_track.track = tracks.id ';
		}
	};

	my $join_contributors = sub {
		$join_contributor_tracks->();

		if ( $sql !~ /JOIN contributors/ ) {
			$sql .= 'JOIN contributors ON contributors.id = contributor_track.contributor ';
		}
	};

	my $join_albums = sub {
		if ( $sql !~ /JOIN albums/ ) {
			$sql .= 'JOIN albums ON albums.id = tracks.album ';
		}
	};

	my $join_tracks_persistent = sub {
		if ( main::STATISTICS ) {
			$sql .= 'JOIN tracks_persistent ON tracks_persistent.urlmd5 = tracks.urlmd5 ';
		}
	};

	my $join_playlist_track = sub {
		if ( $sql !~ /JOIN playlist_track/ ) {
			$sql .= 'JOIN playlist_track ON playlist_track.track = tracks.url ';
		}
	};

	if ( my $genreId = $args->{genreId} ) {
		$join_genre_track->();
		push @{$w}, 'genre_track.genre = ?';
		push @{$p}, $genreId;
	}

	if ( my $contributorId = $args->{contributorId} ) {
		# handle the case where we're asked for the VA id => return compilations
		if ($contributorId == Slim::Schema->variousArtistsObject->id) {
			$join_albums->();
			push @{$w}, 'albums.compilation = 1';
		}
		else {
			$join_contributor_tracks->();
			push @{$w}, 'contributor_track.contributor = ?';
			push @{$p}, $contributorId;
		}
	}

	if ( my $playlistId = $args->{playlistId} ) {
		$join_playlist_track->();
		push @{$w}, 'playlist_track.playlist = ?';
		push @{$p}, $playlistId;
	}

	if ( my $trackIds = $args->{trackIds} ) {
		# Filter out negative tracks (remote tracks)
		push @{$w}, 'tracks.id IN (' . join( ',', grep { $_ > 0 } @{$trackIds} ) . ')';
	}

	# Process tags and add columns/joins as needed
	$tags =~ /e/ && do { $c->{'tracks.album'} = 1 };
	$tags =~ /d/ && do { $c->{'tracks.secs'} = 1 };
	$tags =~ /t/ && do { $c->{'tracks.tracknum'} = 1 };
	$tags =~ /y/ && do { $c->{'tracks.year'} = 1 };
	$tags =~ /m/ && do { $c->{'tracks.bpm'} = 1 };
	$tags =~ /M/ && do { $c->{'tracks.musicmagic_mixable'} = 1 };
	$tags =~ /o/ && do { $c->{'tracks.content_type'} = 1 };
	$tags =~ /v/ && do { $c->{'tracks.tagversion'} = 1 };
	$tags =~ /r/ && do { $c->{'tracks.bitrate'} = 1; $c->{'tracks.vbr_scale'} = 1 };
	$tags =~ /f/ && do { $c->{'tracks.filesize'} = 1 };
	$tags =~ /j/ && do { $c->{'tracks.cover'} = 1 };
	$tags =~ /n/ && do { $c->{'tracks.timestamp'} = 1 };
	$tags =~ /F/ && do { $c->{'tracks.dlna_profile'} = 1 };
	$tags =~ /D/ && do { $c->{'tracks.added_time'} = 1 };
	$tags =~ /U/ && do { $c->{'tracks.updated_time'} = 1 };
	$tags =~ /T/ && do { $c->{'tracks.samplerate'} = 1 };
	$tags =~ /H/ && do { $c->{'tracks.channels'} = 1 };
	$tags =~ /I/ && do { $c->{'tracks.samplesize'} = 1 };
	$tags =~ /u/ && do { $c->{'tracks.url'} = 1 };
	$tags =~ /w/ && do { $c->{'tracks.lyrics'} = 1 };
	$tags =~ /x/ && do { $c->{'tracks.remote'} = 1 };
	$tags =~ /c/ && do { $c->{'tracks.coverid'} = 1 };
	$tags =~ /Y/ && do { $c->{'tracks.replay_gain'} = 1 };
	$tags =~ /i/ && do { $c->{'tracks.disc'} = 1 };
	$tags =~ /E/ && do { $c->{'tracks.endian'} = 1 };
	$tags =~ /g/ && do {
		$join_genres->();
		$c->{'genres.name'} = 1;

		# XXX there is a bug here if a track has multiple genres, the genre
		# returned will be a random genre, not sure how to solve this -Andy
	};

	$tags =~ /p/ && do {
		$join_genres->();
		$c->{'genres.id'} = 1;
	};

	$tags =~ /a/ && do {
		$join_contributors->();
		$c->{'contributors.name'} = 1;

		my $cond = 'contributor_track.role IN (?, ?, ?';

		# Tag 'a' returns either ARTIST or TRACKARTIST role
		# Bug 16791: Need to include ALBUMARTIST too
		push @{$p}, (
			Slim::Schema::Contributor->typeToRole('ARTIST'),
			Slim::Schema::Contributor->typeToRole('TRACKARTIST'),
			Slim::Schema::Contributor->typeToRole('ALBUMARTIST'),
		);

		# Loop through each pref to see if the user wants to show that contributor role.
		foreach (Slim::Schema::Contributor->contributorRoles) {
			if ($prefs->get(lc($_) . 'InArtists')) {
				$cond .= ', ?';
				push @{$p}, Slim::Schema::Contributor->typeToRole($_);
			}
		}

		push @{$w}, ($cond . ')');
	};

	$tags =~ /s/ && do {
		$join_contributors->();
		$c->{'contributors.id'} = 1;
	};

	$tags =~ /l/ && do {
		$join_albums->();
		$c->{'albums.title'} = 1;
	};

	$tags =~ /q/ && do {
		$join_albums->();
		$c->{'albums.discc'} = 1;
	};

	$tags =~ /J/ && do {
		$join_albums->();
		$c->{'albums.artwork'} = 1;
	};

	$tags =~ /C/ && do {
		$join_albums->();
		$c->{'albums.compilation'} = 1;
	};

	$tags =~ /X/ && do {
		$join_albums->();
		$c->{'albums.replay_gain'} = 1;
	};

	$tags =~ /R/ && do {
		if ( main::STATISTICS ) {
			$join_tracks_persistent->();
			$c->{'tracks_persistent.rating'} = 1;
		}
	};

	if ( scalar @{$w} ) {
		$sql .= 'WHERE ';
		my $s = join( ' AND ', @{$w} );
		$s =~ s/\%/\%\%/g;
		$sql .= $s . ' ';
	}
	$sql .= 'GROUP BY tracks.id ';

	if ( $sort ) {
		$sql .= "ORDER BY $sort ";
	}

	# Add selected columns
	# Bug 15997, AS mapping needed for MySQL
	my @cols = keys %{$c};
	$sql = sprintf $sql, join( ', ', map { $_ . " AS '" . $_ . "'" } @cols );

	my $dbh = Slim::Schema->dbh;

	if ( my $limit = $args->{limit} ) {
		# Let the caller worry about the limit values

		($total) = $dbh->selectrow_array( qq{
			SELECT COUNT(*) FROM ( $sql ) AS t1
		}, undef, @{$p} );

		my ($valid, $start, $end) = $limit->($total);

		if ( !$valid ) {
			return wantarray ? ( {}, [], $total ) : {};
		}

		# Limit the real query
		if ( $start =~ /^\d+$/ && defined $end && $end =~ /^\d+$/ ) {
			$sql .= "LIMIT $start, $end ";
		}
	}

	if ( main::DEBUGLOG && $sqllog->is_debug ) {
		$sqllog->debug( "_getTagDataForTracks query: $sql / " . Data::Dump::dump($p) );
	}

	my $sth = $dbh->prepare_cached($sql);
	$sth->execute( @{$p} );

	# Bind selected columns in order
	my $i = 1;
	for my $col ( @cols ) {
		# Adjust column names that are sub-queries to be stored using the AS value
		if ( $col =~ /SELECT/ ) {
			my ($newcol) = $col =~ /AS (\w+)/;
			$c->{$newcol} = 1;
			$col = $newcol;
		}

		$sth->bind_col( $i++, \$c->{$col} );
	}

	# Results are stored in a hash keyed by track ID, and we
	# also store the order the data is returned in, titlesQuery
	# needs this to provide correctly sorted results, and I don't
	# want to make %results an IxHash.
	my %results;
	my @resultOrder;

	while ( $sth->fetch ) {
		utf8::decode( $c->{'tracks.title'} ) if exists $c->{'tracks.title'};
		utf8::decode( $c->{'tracks.lyrics'} ) if exists $c->{'tracks.lyrics'};
		utf8::decode( $c->{'albums.title'} ) if exists $c->{'albums.title'};
		utf8::decode( $c->{'contributors.name'} ) if exists $c->{'contributors.name'};
		utf8::decode( $c->{'genres.name'} ) if exists $c->{'genres.name'};
		utf8::decode( $c->{'comments.value'} ) if exists $c->{'comments.value'};

		$results{ $c->{'tracks.id'} } = { map { $_ => $c->{$_} } keys %{$c} };
		push @resultOrder, $c->{'tracks.id'};
	}

	# For tag A/S we have to run 1 additional query
	if ( $tags =~ /[AS]/ ) {
		my $sql = sprintf qq{
			SELECT contributors.id, contributors.name, contributor_track.track, contributor_track.role
			FROM contributor_track
			JOIN contributors ON contributors.id = contributor_track.contributor
			WHERE contributor_track.track IN (%s)
			ORDER BY contributor_track.role DESC
		}, join( ',', @resultOrder );

		my $contrib_sth = $dbh->prepare($sql);

		if ( main::DEBUGLOG && $sqllog->is_debug ) {
			$sqllog->debug( "Tag A/S (contributor) query: $sql" );
		}

		$contrib_sth->execute;

		my %values;
		while ( my ($id, $name, $track, $role) = $contrib_sth->fetchrow_array ) {
			$values{$track} ||= {};
			my $role_info = $values{$track}->{$role} ||= {};

			# XXX: what if name has ", " in it?
			utf8::decode($name);
			$role_info->{ids}   .= $role_info->{ids} ? ', ' . $id : $id;
			$role_info->{names} .= $role_info->{names} ? ', ' . $name : $name;
		}

		my $want_names = $tags =~ /A/;
		my $want_ids   = $tags =~ /S/;

		while ( my ($id, $role) = each %values ) {
			my $track = $results{$id};

			while ( my ($role_id, $role_info) = each %{$role} ) {
				my $role = lc( Slim::Schema::Contributor->roleToType($role_id) );

				$track->{"${role}_ids"} = $role_info->{ids}   if $want_ids;
				$track->{$role}         = $role_info->{names} if $want_names;
			}
		}
	}

	# Same thing for G/P, multiple genres requires another query
	if ( $tags =~ /[GP]/ ) {
		my $sql = sprintf qq{
			SELECT genres.id, genres.name, genre_track.track
			FROM genre_track
			JOIN genres ON genres.id = genre_track.genre
			WHERE genre_track.track IN (%s)
			ORDER BY genres.namesort $collate
		}, join( ',', @resultOrder );

		my $genre_sth = $dbh->prepare($sql);

		if ( main::DEBUGLOG && $sqllog->is_debug ) {
			$sqllog->debug( "Tag G/P (genre) query: $sql" );
		}

		$genre_sth->execute;

		my %values;
		while ( my ($id, $name, $track) = $genre_sth->fetchrow_array ) {
			my $genre_info = $values{$track} ||= {};

			utf8::decode($name);
			$genre_info->{ids}   .= $genre_info->{ids} ? ', ' . $id : $id;
			$genre_info->{names} .= $genre_info->{names} ? ', ' . $name : $name;
		}

		my $want_names = $tags =~ /G/;
		my $want_ids   = $tags =~ /P/;

		while ( my ($id, $genre_info) = each %values ) {
			my $track = $results{$id};
			$track->{genre_ids} = $genre_info->{ids}   if $want_ids;
			$track->{genres}    = $genre_info->{names} if $want_names;
		}
	}

	# And same for comments
	if ( $tags =~ /k/ ) {
		my $sql = sprintf qq{
			SELECT track, value
			FROM comments
			WHERE track IN (%s)
			ORDER BY id
		}, join( ',', @resultOrder );

		my $comment_sth = $dbh->prepare($sql);

		if ( main::DEBUGLOG && $sqllog->is_debug ) {
			$sqllog->debug( "Tag k (comment) query: $sql" );
		}

		$comment_sth->execute();

		my %values;
		while ( my ($track, $value) = $comment_sth->fetchrow_array ) {
			$values{$track} .= $values{$track} ? ' / ' . $value : $value;
		}

		while ( my ($id, $comment) = each %values ) {
			utf8::decode($comment);
			$results{$id}->{comment} = $comment;
		}
	}

	# If the query wasn't limited, get total from results
	if ( !$total ) {
		$total = scalar @resultOrder;
	}

	return wantarray ? ( \%results, \@resultOrder, $total ) : \%results;
}

# Helper for DelegatedPlaylist support

sub getTagDataForTracks {
	my ($request, $tags, $tracks) = @_;

	my @trackIds = grep (defined $_, map { (!defined $_ || $_->remote) ? undef : $_->id } @$tracks);

	# get hash of tagged data for all tracks
	my $songData = _getTagDataForTracks( $tags, {
		trackIds => \@trackIds,
	} ) if scalar @trackIds;

	my @items;

	foreach (@$tracks) {
		# Use songData for track, if remote use the object directly
		if (my $data = $_->remote ? $_ : $songData->{$_->id}) {
			push @items, _songData($request, $data, $tags);
		}
	}

	return \@items;
}

### Video support

# XXX needs to be more like titlesQuery, was originally copied from albumsQuery
sub videoTitlesQuery {
	my $request = shift;

	if (!main::VIDEO || !Slim::Schema::hasLibrary()) {
		$request->setStatusNotDispatchable();
		return;
	}

	my $sqllog = main::DEBUGLOG && logger('database.sql');

	# get our parameters
	my $index         = $request->getParam('_index');
	my $quantity      = $request->getParam('_quantity');
	my $tags          = $request->getParam('tags') || 't';
	my $search        = $request->getParam('search');
	my $sort          = $request->getParam('sort');
	my $videoHash     = $request->getParam('video_id');

	#if ($sort && $request->paramNotOneOfIfDefined($sort, ['new'])) {
	#	$request->setStatusBadParams();
	#	return;
	#}

	my $collate = Slim::Utils::OSDetect->getOS()->sqlHelperClass()->collate();

	my $sql      = 'SELECT %s FROM videos ';
	my $c        = { 'videos.hash' => 1, 'videos.titlesearch' => 1, 'videos.titlesort' => 1 };
	my $w        = [];
	my $p        = [];
	my $order_by = "videos.titlesort $collate";
	my $limit;

	# Normalize and add any search parameters
	if ( defined $videoHash ) {
		push @{$w}, 'videos.hash = ?';
		push @{$p}, $videoHash;
	}
	# ignore everything if $videoID was specified
	else {
		if ($sort) {
			if ( $sort eq 'new' ) {
				$limit = $prefs->get('browseagelimit') || 100;
				$order_by = "videos.added_time desc";

				# Force quantity to not exceed max
				if ( $quantity && $quantity > $limit ) {
					$quantity = $limit;
				}
			}
			elsif ( $sort =~ /^sql=(.+)/ ) {
				$order_by = $1;
				$order_by =~ s/;//g; # strip out any attempt at combining SQL statements
			}
		}

		if ( $search && specified($search) ) {
			if ( $search =~ s/^sql=// ) {
				# Raw SQL search query
				$search =~ s/;//g; # strip out any attempt at combining SQL statements
				push @{$w}, $search;
			}
			else {
				my $strings = Slim::Utils::Text::searchStringSplit($search);
				if ( ref $strings->[0] eq 'ARRAY' ) {
					push @{$w}, '(' . join( ' OR ', map { 'videos.titlesearch LIKE ?' } @{ $strings->[0] } ) . ')';
					push @{$p}, @{ $strings->[0] };
				}
				else {
					push @{$w}, 'videos.titlesearch LIKE ?';
					push @{$p}, @{$strings};
				}
			}
		}
	}

	$tags =~ /t/ && do { $c->{'videos.title'} = 1 };
	$tags =~ /d/ && do { $c->{'videos.secs'} = 1 };
	$tags =~ /o/ && do { $c->{'videos.mime_type'} = 1 };
	$tags =~ /r/ && do { $c->{'videos.bitrate'} = 1 };
	$tags =~ /f/ && do { $c->{'videos.filesize'} = 1 };
	$tags =~ /w/ && do { $c->{'videos.width'} = 1 };
	$tags =~ /h/ && do { $c->{'videos.height'} = 1 };
	$tags =~ /n/ && do { $c->{'videos.mtime'} = 1 };
	$tags =~ /F/ && do { $c->{'videos.dlna_profile'} = 1 };
	$tags =~ /D/ && do { $c->{'videos.added_time'} = 1 };
	$tags =~ /U/ && do { $c->{'videos.updated_time'} = 1 };
	$tags =~ /l/ && do { $c->{'videos.album'} = 1 };

	if ( @{$w} ) {
		$sql .= 'WHERE ';
		$sql .= join( ' AND ', @{$w} );
		$sql .= ' ';
	}
	$sql .= "GROUP BY videos.hash ORDER BY $order_by ";

	# Add selected columns
	# Bug 15997, AS mapping needed for MySQL
	my @cols = keys %{$c};
	$sql = sprintf $sql, join( ', ', map { $_ . " AS '" . $_ . "'" } @cols );

	my $stillScanning = Slim::Music::Import->stillScanning();

	my $dbh = Slim::Schema->dbh;

	# Get count of all results, the count is cached until the next rescan done event
	my $cacheKey = $sql . join( '', @{$p} );

	my ($count) = $cache->{$cacheKey} || $dbh->selectrow_array( qq{
		SELECT COUNT(*) FROM ( $sql ) AS t1
	}, undef, @{$p} );

	if ( !$stillScanning ) {
		$cache->{$cacheKey} = $count;
	}

	if ($stillScanning) {
		$request->addResult('rescan', 1);
	}

	$count += 0;

	my $totalCount = $count;

	# now build the result
	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

	my $loopname = 'videos_loop';
	my $chunkCount = 0;

	if ($valid) {
		# Limit the real query
		if ( $index =~ /^\d+$/ && $quantity =~ /^\d+$/ ) {
			$sql .= "LIMIT $index, $quantity ";
		}

		if ( main::DEBUGLOG && $sqllog->is_debug ) {
			$sqllog->debug( "Video Titles query: $sql / " . Data::Dump::dump($p) );
		}

		my $sth = $dbh->prepare_cached($sql);
		$sth->execute( @{$p} );

		# Bind selected columns in order
		my $i = 1;
		for my $col ( @cols ) {
			$sth->bind_col( $i++, \$c->{$col} );
		}

		while ( $sth->fetch ) {
			if ( $sort ne 'new' ) {
				utf8::decode( $c->{'videos.titlesort'} ) if exists $c->{'videos.titlesort'};
			}

			# "raw" result formatting (for CLI or JSON RPC)
			$request->addResultLoop($loopname, $chunkCount, 'id', $c->{'videos.hash'});

			_videoData($request, $loopname, $chunkCount, $tags, $c);

			$chunkCount++;

			main::idleStreams() if !($chunkCount % 5);
		}
	}

	$request->addResult('count', $totalCount);

	$request->setStatusDone();
}

sub _videoData {
	my ($request, $loopname, $chunkCount, $tags, $c) = @_;

	utf8::decode( $c->{'videos.title'} ) if exists $c->{'videos.title'};
	utf8::decode( $c->{'videos.album'} ) if exists $c->{'videos.album'};

	$tags =~ /t/ && $request->addResultLoop($loopname, $chunkCount, 'title', $c->{'videos.title'});
	$tags =~ /d/ && $request->addResultLoop($loopname, $chunkCount, 'duration', $c->{'videos.secs'});
	$tags =~ /o/ && $request->addResultLoop($loopname, $chunkCount, 'mime_type', $c->{'videos.mime_type'});
	$tags =~ /r/ && $request->addResultLoop($loopname, $chunkCount, 'bitrate', $c->{'videos.bitrate'} / 1000);
	$tags =~ /f/ && $request->addResultLoop($loopname, $chunkCount, 'filesize', $c->{'videos.filesize'});
	$tags =~ /w/ && $request->addResultLoop($loopname, $chunkCount, 'width', $c->{'videos.width'});
	$tags =~ /h/ && $request->addResultLoop($loopname, $chunkCount, 'height', $c->{'videos.height'});
	$tags =~ /n/ && $request->addResultLoop($loopname, $chunkCount, 'mtime', $c->{'videos.mtime'});
	$tags =~ /F/ && $request->addResultLoop($loopname, $chunkCount, 'dlna_profile', $c->{'videos.dlna_profile'});
	$tags =~ /D/ && $request->addResultLoop($loopname, $chunkCount, 'added_time', $c->{'videos.added_time'});
	$tags =~ /U/ && $request->addResultLoop($loopname, $chunkCount, 'updated_time', $c->{'videos.updated_time'});
	$tags =~ /l/ && $request->addResultLoop($loopname, $chunkCount, 'album', $c->{'videos.album'});
	$tags =~ /J/ && $request->addResultLoop($loopname, $chunkCount, 'hash', $c->{'videos.hash'});
}

# XXX needs to be more like titlesQuery, was originally copied from albumsQuery
sub imageTitlesQuery {
	my $request = shift;

	if (!main::IMAGE || !Slim::Schema::hasLibrary()) {
		$request->setStatusNotDispatchable();
		return;
	}

	my $sqllog = main::DEBUGLOG && logger('database.sql');

	# get our parameters
	my $index         = $request->getParam('_index');
	my $quantity      = $request->getParam('_quantity');
	my $tags          = $request->getParam('tags') || 't';
	my $search        = $request->getParam('search');
	my $timeline      = $request->getParam('timeline');
	my $albums        = $request->getParam('albums');
	my $sort          = $request->getParam('sort');
	my $imageHash     = $request->getParam('image_id');

	#if ($sort && $request->paramNotOneOfIfDefined($sort, ['new'])) {
	#	$request->setStatusBadParams();
	#	return;
	#}

	my $collate = Slim::Utils::OSDetect->getOS()->sqlHelperClass()->collate();

	my $sql      = 'SELECT %s FROM images ';
	my $c        = { 'images.hash' => 1, 'images.titlesearch' => 1, 'images.titlesort' => 1 };	# columns
	my $w        = [];																			# where
	my $p        = [];																			# parameters
	my $group_by = "images.hash";
	my $order_by = "images.titlesort $collate";
	my $id_col   = 'images.hash';
	my $title_col= 'images.title';
	my $limit;

	# Normalize and add any search parameters
	if ( defined $imageHash ) {
		push @{$w}, 'images.hash = ?';
		push @{$p}, $imageHash;
	}
	# ignore everything if $imageHash was specified
	else {
		if ($sort) {
			if ( $sort eq 'new' ) {
				$limit = $prefs->get('browseagelimit') || 100;
				$order_by = "images.added_time desc";

				# Force quantity to not exceed max
				if ( $quantity && $quantity > $limit ) {
					$quantity = $limit;
				}
			}
			elsif ( $sort =~ /^sql=(.+)/ ) {
				$order_by = $1;
				$order_by =~ s/;//g; # strip out any attempt at combining SQL statements
			}
		}

		if ( $timeline ) {
			$search ||= '';
			my ($year, $month, $day) = split('-', $search);

			$tags = 't' if $timeline !~ /^(?:day|albums)$/;

			if ( $timeline eq 'years' ) {
				$sql = sprintf $sql, "strftime('%Y', date(original_time, 'unixepoch')) AS 'year'";
				$id_col = $order_by = $group_by = $title_col = 'year';
				$c = { year => 1 };
			}

			elsif ( $timeline eq 'months' && $year ) {
				$sql = sprintf $sql, "strftime('%m', date(original_time, 'unixepoch')) AS 'month'";
				push @{$w}, "strftime('%Y', date(original_time, 'unixepoch')) == '$year'";
				$id_col = $order_by = $group_by = $title_col = 'month';
				$c = { month => 1 };
			}

			elsif ( $timeline eq 'days' && $year && $month ) {
				$sql = sprintf $sql, "strftime('%d', date(original_time, 'unixepoch')) AS 'day'";
				push @{$w}, "strftime('%Y', date(original_time, 'unixepoch')) == '$year'";
				push @{$w}, "strftime('%m', date(original_time, 'unixepoch')) == '$month'";
				$id_col = $order_by = $group_by = $title_col = 'day';
				$c = { day => 1 };
			}

			elsif ( $timeline eq 'dates' ) {
				my $dateFormat = $prefs->get('shortdateFormat');
				# only a subset of strftime is supported in SQLite, eg. no two letter years
				$dateFormat =~ s/%y/%Y/;

				$sql = sprintf $sql, "strftime('$dateFormat', date(original_time, 'unixepoch')) AS 'date', strftime('%Y/%m/%d', date(original_time, 'unixepoch')) AS 'd'";
				$id_col = $order_by = $group_by = 'd';
				$title_col = 'date';
				$c = { date => 1, d => 1 };
			}

			elsif ( $timeline eq 'day' && $year && $month && $day ) {
				push @{$w}, "date(original_time, 'unixepoch') == '$year-$month-$day'";
				$timeline = '';
			}
		}

		elsif ( $albums ) {
			if ( $search ) {
				$search = URI::Escape::uri_unescape($search);
				utf8::decode($search);

				$c->{'images.album'} = 1;
				push @{$w}, "images.album == ?";
				push @{$p}, $search;
			}
			else {
				$c = { 'images.album' => 1 };
				$id_col = $order_by = $group_by = $title_col = 'images.album';
				$tags = 't';
			}
		}

		elsif ( $search && specified($search) ) {
			if ( $search =~ s/^sql=// ) {
				# Raw SQL search query
				$search =~ s/;//g; # strip out any attempt at combining SQL statements
				push @{$w}, $search;
			}
			else {
				my $strings = Slim::Utils::Text::searchStringSplit($search);
				if ( ref $strings->[0] eq 'ARRAY' ) {
					push @{$w}, '(' . join( ' OR ', map { 'images.titlesearch LIKE ?' } @{ $strings->[0] } ) . ')';
					push @{$p}, @{ $strings->[0] };
				}
				else {
					push @{$w}, 'images.titlesearch LIKE ?';
					push @{$p}, @{$strings};
				}
			}
		}
	}

	$tags =~ /t/ && do { $c->{$title_col} = 1 };
	$tags =~ /o/ && do { $c->{'images.mime_type'} = 1 };
	$tags =~ /f/ && do { $c->{'images.filesize'} = 1 };
	$tags =~ /w/ && do { $c->{'images.width'} = 1 };
	$tags =~ /h/ && do { $c->{'images.height'} = 1 };
	$tags =~ /O/ && do { $c->{'images.orientation'} = 1 };
	$tags =~ /n/ && do { $c->{'images.original_time'} = 1 };
	$tags =~ /F/ && do { $c->{'images.dlna_profile'} = 1 };
	$tags =~ /D/ && do { $c->{'images.added_time'} = 1 };
	$tags =~ /U/ && do { $c->{'images.updated_time'} = 1 };
	$tags =~ /l/ && do { $c->{'images.album'} = 1 };

	if ( @{$w} ) {
		$sql .= 'WHERE ';
		$sql .= join( ' AND ', @{$w} );
		$sql .= ' ';
	}
	$sql .= "GROUP BY $group_by " if $group_by;
	$sql .= "ORDER BY $order_by " if $order_by;

	# Add selected columns
	# Bug 15997, AS mapping needed for MySQL
	my @cols = keys %{$c};
	$sql = sprintf $sql, join( ', ', map { $_ . " AS '" . $_ . "'" } @cols ) unless $timeline;

	my $stillScanning = Slim::Music::Import->stillScanning();

	my $dbh = Slim::Schema->dbh;

	# Get count of all results, the count is cached until the next rescan done event
	my $cacheKey = $sql . join( '', @{$p} );

	my ($count) = $cache->{$cacheKey} || $dbh->selectrow_array( qq{
		SELECT COUNT(*) FROM ( $sql ) AS t1
	}, undef, @{$p} );

	if ( !$stillScanning ) {
		$cache->{$cacheKey} = $count;
	}

	if ($stillScanning) {
		$request->addResult('rescan', 1);
	}

	$count += 0;

	my $totalCount = $count;

	# now build the result
	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

	my $loopname = 'images_loop';
	my $chunkCount = 0;

	if ($valid) {
		# Limit the real query
		if ( $index =~ /^\d+$/ && $quantity =~ /^\d+$/ ) {
			$sql .= "LIMIT $index, $quantity ";
		}

		if ( main::DEBUGLOG && $sqllog->is_debug ) {
			$sqllog->debug( "Image Titles query: $sql / " . Data::Dump::dump($p) );
		}

		my $sth = $dbh->prepare_cached($sql);
		$sth->execute( @{$p} );

		# Bind selected columns in order
		my $i = 1;
		for my $col ( @cols ) {
			$sth->bind_col( $i++, \$c->{$col} );
		}

		while ( $sth->fetch ) {
			utf8::decode( $c->{'images.title'} ) if exists $c->{'images.title'};
			utf8::decode( $c->{'images.album'} ) if exists $c->{'images.album'};

			if ( $sort ne 'new' ) {
				utf8::decode( $c->{'images.titlesort'} ) if exists $c->{'images.titlesort'};
			}

			# "raw" result formatting (for CLI or JSON RPC)
			$request->addResultLoop($loopname, $chunkCount, 'id', $c->{$id_col});

			$c->{title} = $c->{$title_col};

			_imageData($request, $loopname, $chunkCount, $tags, $c);

			$chunkCount++;

			main::idleStreams() if !($chunkCount % 5);
		}
	}

	$request->addResult('count', $totalCount);

	$request->setStatusDone();
}


sub _imageData {
	my ($request, $loopname, $chunkCount, $tags, $c) = @_;

	$tags =~ /t/ && $request->addResultLoop($loopname, $chunkCount, 'title', $c->{'title'});
	$tags =~ /o/ && $request->addResultLoop($loopname, $chunkCount, 'mime_type', $c->{'images.mime_type'});
	$tags =~ /f/ && $request->addResultLoop($loopname, $chunkCount, 'filesize', $c->{'images.filesize'});
	$tags =~ /w/ && $request->addResultLoop($loopname, $chunkCount, 'width', $c->{'images.width'});
	$tags =~ /h/ && $request->addResultLoop($loopname, $chunkCount, 'height', $c->{'images.height'});
	$tags =~ /O/ && $request->addResultLoop($loopname, $chunkCount, 'orientation', $c->{'images.orientation'});
	$tags =~ /n/ && $request->addResultLoop($loopname, $chunkCount, 'original_time', $c->{'images.original_time'});
	$tags =~ /F/ && $request->addResultLoop($loopname, $chunkCount, 'dlna_profile', $c->{'images.dlna_profile'});
	$tags =~ /D/ && $request->addResultLoop($loopname, $chunkCount, 'added_time', $c->{'images.added_time'});
	$tags =~ /U/ && $request->addResultLoop($loopname, $chunkCount, 'updated_time', $c->{'images.updated_time'});
	$tags =~ /l/ && $request->addResultLoop($loopname, $chunkCount, 'album', $c->{'images.album'});
	$tags =~ /J/ && $request->addResultLoop($loopname, $chunkCount, 'hash', $c->{'images.hash'});

	# browsing images by timeline Year -> Month -> Day
	$c->{year} && $request->addResultLoop($loopname, $chunkCount, 'year', $c->{'year'});
	$c->{month} && $request->addResultLoop($loopname, $chunkCount, 'month', $c->{'month'});
	$c->{day} && $request->addResultLoop($loopname, $chunkCount, 'day', $c->{'day'});
}


=head1 SEE ALSO

L<Slim::Control::Request.pm>

=cut


1;

__END__
