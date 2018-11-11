package Slim::Control::Queries;

# TODO: move all library related queries here

# Logitech Media Server Copyright 2001-2011 Logitech.
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

Slim::Control::Queries - the library related code

=head1 DESCRIPTION

L<Slim::Control::Queries> implements most Logitech Media Server queries and is designed to
 be exclusively called through Request.pm and the mechanisms it defines.

 Except for subscribe-able queries (such as status and serverstatus), there are no
 important differences between the code for a query and one for
 a command. Please check the commented command in Commands.pm.

=cut

use strict;

use Slim::Music::VirtualLibraries;
use Slim::Utils::Log;
use Slim::Utils::Misc qw( specified );
use Slim::Utils::Prefs;

my $log = logger('control.queries');
my $prefs = preferences('server');


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
	my $cache = $Slim::Control::Queries::cache;

	# get our parameters
	my $client        = $request->client();
	my $index         = $request->getParam('_index');
	my $quantity      = $request->getParam('_quantity');
	my $tags          = $request->getParam('tags') || 'l';
	my $search        = $request->getParam('search');
	my $compilation   = $request->getParam('compilation');
	my $contributorID = $request->getParam('artist_id');
	my $genreID       = $request->getParam('genre_id');
	my $trackID       = $request->getParam('track_id');
	my $albumID       = $request->getParam('album_id');
	my $roleID        = $request->getParam('role_id');
	my $libraryID     = Slim::Music::VirtualLibraries->getRealId($request->getParam('library_id'));
	my $year          = $request->getParam('year');
	my $sort          = $request->getParam('sort') || ($roleID ? 'artistalbum' : 'album');

	my $ignoreNewAlbumsCache = $search || $compilation || $contributorID || $genreID || $trackID || $albumID || $year || Slim::Music::Import->stillScanning();

	# FIXME: missing genrealbum, genreartistalbum
	if ($request->paramNotOneOfIfDefined($sort, ['new', 'album', 'artflow', 'artistalbum', 'yearalbum', 'yearartistalbum', 'random' ])) {
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
	my $newAlbumsCacheKey = 'newAlbumIds' . Slim::Music::Import->lastScanTime . Slim::Music::VirtualLibraries->getLibraryIdForClient($client);

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
		if (specified($search)) {
			if ( Slim::Schema->canFulltextSearch ) {
				Slim::Plugin::FullTextSearch::Plugin->createHelperTable({
					name   => 'albumsSearch',
					search => $search,
					type   => 'album',
				});

				$sql = 'SELECT %s FROM albumsSearch, albums ';
				unshift @{$w}, "albums.id = albumsSearch.id";

				if ($tags ne 'CC') {
					$order_by = $sort = "albumsSearch.fulltextweight DESC, LENGTH(albums.titlesearch)";
				}
			}
			else {
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
		}

		my @roles;
		if (defined $contributorID) {
			# handle the case where we're asked for the VA id => return compilations
			if ($contributorID == Slim::Schema->variousArtistsObject->id) {
				$compilation = 1;
			}
			else {

				$sql .= 'JOIN contributor_album ON contributor_album.album = albums.id ';
				push @{$w}, 'contributor_album.contributor = ?';
				push @{$p}, $contributorID;

				# only albums on which the contributor has a specific role?
				if ($roleID) {
					@roles = split /,/, $roleID;
					push @roles, 'ARTIST' if $roleID eq 'ALBUMARTIST' && !$prefs->get('useUnifiedArtistsList');
				}
				elsif ($prefs->get('useUnifiedArtistsList')) {
					@roles = ( 'ARTIST', 'TRACKARTIST', 'ALBUMARTIST' );

					# Loop through each pref to see if the user wants to show that contributor role.
					foreach (Slim::Schema::Contributor->contributorRoles) {
						if ($prefs->get(lc($_) . 'InArtists')) {
							push @roles, $_;
						}
					}
				}
				else {
					@roles = Slim::Schema::Contributor->contributorRoles();
				}
			}
		}
		elsif ($roleID) {
			$sql .= 'JOIN contributor_album ON contributor_album.album = albums.id ';

			@roles = split /,/, $roleID;
			push @roles, 'ARTIST' if $roleID eq 'ALBUMARTIST' && !$prefs->get('useUnifiedArtistsList');
		}

		if (scalar @roles) {
			push @{$p}, map { Slim::Schema::Contributor->typeToRole($_) } @roles;
			push @{$w}, 'contributor_album.role IN (' . join(', ', map {'?'} @roles) . ')';

			$sql .= 'JOIN contributors ON contributors.id = contributor_album.contributor ';
		}
		elsif ( $sort =~ /artflow|artistalbum/) {
			$sql .= 'JOIN contributors ON contributors.id = albums.contributor ';
		}

		if ( $sort eq 'new' ) {
			$sql .= 'JOIN tracks ON tracks.album = albums.id ';
			$limit = $prefs->get('browseagelimit') || 100;
			$order_by = "tracks.timestamp desc";

			# Force quantity to not exceed max
			if ( $quantity && $quantity > $limit ) {
				$quantity = $limit;
			}

			# cache the most recent album IDs - need to query the tracks table, which is expensive
			if ( !$ignoreNewAlbumsCache ) {
				my $ids = $cache->{$newAlbumsCacheKey} || [];

				if (!scalar @$ids) {
					my $_cache = Slim::Utils::Cache->new;
					$ids = $_cache->get($newAlbumsCacheKey) || [];

					# get rid of stale cache entries
					my @oldCacheKeys = grep /newAlbumIds/, keys %$cache;
					foreach (@oldCacheKeys) {
						next if $_ eq $newAlbumsCacheKey;
						$_cache->remove($_);
						delete $cache->{$_};
					}

					my $countSQL = qq{
						SELECT tracks.album
						FROM tracks } . ($libraryID ? qq{
							JOIN library_track ON library_track.library = '$libraryID' AND tracks.id = library_track.track
						} : '') . qq{
						WHERE tracks.album > 0
						GROUP BY tracks.album
						ORDER BY tracks.timestamp DESC
					};

					# get the list of album IDs ordered by timestamp
					$ids = Slim::Schema->dbh->selectcol_arrayref( $countSQL, { Slice => {} } ) unless scalar @$ids;

					$cache->{$newAlbumsCacheKey} = $ids;
					$_cache->set($newAlbumsCacheKey, $ids, 86400 * 7) if scalar @$ids;
				}

				my $start = scalar($index);
				my $end   = $start + scalar($quantity || scalar($limit)-1);
				if ($end >= scalar @$ids) {
					$end = scalar(@$ids) - 1;
				}
				push @{$w}, 'albums.id IN (' . join(',', @$ids[$start..$end]) . ')';

				# reset $index, as we're already limiting results using the id list
				$index = 0;
			}

			$page_key = undef;
		}
		elsif ( $sort eq 'artflow' ) {
			$order_by = "contributors.namesort $collate, albums.year, albums.titlesort $collate";
			$c->{'contributors.namesort'} = 1;
			$page_key = "SUBSTR(contributors.namesort,1,1)";
		}
		elsif ( $sort eq 'artistalbum' ) {
			$order_by = "contributors.namesort $collate, albums.titlesort $collate";
			$c->{'contributors.namesort'} = 1;
			$page_key = "SUBSTR(contributors.namesort,1,1)";
		}
		elsif ( $sort eq 'yearartistalbum' ) {
			$order_by = "albums.year, contributors.namesort $collate, albums.titlesort $collate";
			$page_key = "albums.year";
		}
		elsif ( $sort eq 'yearalbum' ) {
			$order_by = "albums.year, albums.titlesort $collate";
			$page_key = "albums.year";
		}
		elsif ( $sort eq 'random' ) {
			$limit = $prefs->get('itemsPerPage');

			# Force quantity to not exceed max
			if ( $quantity && $quantity > $limit ) {
				$quantity = $limit;
			}

			$order_by = Slim::Utils::OSDetect->getOS()->sqlHelperClass()->randomFunction();
			$page_key = undef;
		}

		if (defined $libraryID) {
			push @{$w}, 'albums.id IN (SELECT library_album.album FROM library_album WHERE library_album.library = ?)';
			push @{$p}, $libraryID;
		}

		if (defined $year) {
			push @{$w}, 'albums.year = ?';
			push @{$p}, $year;
		}

		if (defined $genreID) {
			my @genreIDs = split(/,/, $genreID);
			$sql .= 'JOIN tracks ON tracks.album = albums.id ' unless $sql =~ /JOIN tracks/;
			$sql .= 'JOIN genre_track ON genre_track.track = tracks.id ';
			push @{$w}, 'genre_track.genre IN (' . join(', ', map {'?'} @genreIDs) . ')';
			push @{$p}, @genreIDs;
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

	$sql .= "GROUP BY albums.id ";

	if ($page_key && $tags =~ /Z/) {
		my $pageSql = "SELECT n, count(1) FROM ("
			. sprintf($sql, "$page_key AS n")
			. ") AS pk GROUP BY n ORDER BY n " . ($sort !~ /year/ ? "$collate " : '');

		if ( main::DEBUGLOG && $sqllog->is_debug ) {
			$sqllog->debug( "Albums indexList query: $pageSql / " . Data::Dump::dump($p) );
		}

		$request->addResult('indexList', [
			map {
				utf8::decode($_->[0]);
				$_;
			} @{ $dbh->selectall_arrayref($pageSql, undef, @{$p}) }
		]);

		if ($tags =~ /ZZ/) {
			$request->setStatusDone();
			return
		}
	}

	$sql .= "ORDER BY $order_by " unless $tags eq 'CC';

	# Add selected columns
	# Bug 15997, AS mapping needed for MySQL
	my @cols = sort keys %{$c};
	$sql = sprintf $sql, join( ', ', map { $_ . " AS '" . $_ . "'" } @cols );

	my $stillScanning = Slim::Music::Import->stillScanning();

	# Get count of all results, the count is cached until the next rescan done event
	my $cacheKey = md5_hex($sql . join( '', @{$p} ) . Slim::Music::VirtualLibraries->getLibraryIdForClient($client) . (Slim::Utils::Text::ignoreCase($search, 1) || ''));

	if ( $sort eq 'new' && $cache->{$newAlbumsCacheKey} && !$ignoreNewAlbumsCache ) {
		my $albumCount = scalar @{$cache->{$newAlbumsCacheKey}};
		$albumCount    = $limit if ($limit && $limit < $albumCount);
		$cache->{$cacheKey} ||= $albumCount;
		$limit = undef;
	}

	my $countsql = $sql;
	$countsql .= ' LIMIT ' . $limit if $limit;

	my $count = $cache->{$cacheKey};

	if ( !$count ) {
		my $total_sth = $dbh->prepare_cached( qq{
			SELECT COUNT(1) FROM ( $countsql ) AS t1
		} );

		if ( main::DEBUGLOG && $sqllog->is_debug ) {
			$sqllog->debug( "Albums totals query: $countsql / " . Data::Dump::dump($p) );
		}

		$total_sth->execute( @{$p} );
		($count) = $total_sth->fetchrow_array();
		$total_sth->finish;
	}

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

	if ($valid && $tags ne 'CC') {

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
			$sql .= "LIMIT ?,? ";
			push @$p, $index, $quantity;
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
		my $construct_title = $groupdiscs_pref ? sub {
			return $c->{'albums.title'};
		} : sub {
			return Slim::Music::Info::addDiscNumberToAlbumTitle(
				$c->{'albums.title'}, $c->{'albums.disc'}, $c->{'albums.discc'}
			);
		};

		my ($contributorSql, $contributorSth, $contributorNameSth);
		if ( $tags =~ /(?:aa|SS)/ ) {
			my @roles = ( 'ARTIST', 'ALBUMARTIST' );

			if ($prefs->get('useUnifiedArtistsList')) {
				# Loop through each pref to see if the user wants to show that contributor role.
				foreach (Slim::Schema::Contributor->contributorRoles) {
					if ($prefs->get(lc($_) . 'InArtists')) {
						push @roles, $_;
					}
				}
			}

			$contributorSql = sprintf( qq{
				SELECT GROUP_CONCAT(contributors.name, ',') AS name, GROUP_CONCAT(contributors.id, ',') AS id
				FROM contributor_album
				JOIN contributors ON contributors.id = contributor_album.contributor
				WHERE contributor_album.album = ? AND contributor_album.role IN (%s) 
				GROUP BY contributor_album.role
				ORDER BY contributor_album.role DESC
			}, join(',', map { Slim::Schema::Contributor->typeToRole($_) } @roles) );
		}

		my $vaObjId = Slim::Schema->variousArtistsObject->id;

		while ( $sth->fetch ) {

			utf8::decode( $c->{'albums.title'} ) if exists $c->{'albums.title'};

			$request->addResultLoop($loopname, $chunkCount, 'id', $c->{'albums.id'});
			$tags =~ /l/ && $request->addResultLoop($loopname, $chunkCount, 'album', $construct_title->());
			$tags =~ /y/ && $request->addResultLoopIfValueDefined($loopname, $chunkCount, 'year', $c->{'albums.year'});
			$tags =~ /j/ && $request->addResultLoopIfValueDefined($loopname, $chunkCount, 'artwork_track_id', $c->{'albums.artwork'});
			$tags =~ /t/ && $request->addResultLoop($loopname, $chunkCount, 'title', $c->{'albums.title'});
			$tags =~ /i/ && $request->addResultLoopIfValueDefined($loopname, $chunkCount, 'disc', $c->{'albums.disc'});
			$tags =~ /q/ && $request->addResultLoopIfValueDefined($loopname, $chunkCount, 'disccount', $c->{'albums.discc'});
			$tags =~ /w/ && $request->addResultLoopIfValueDefined($loopname, $chunkCount, 'compilation', $c->{'albums.compilation'});
			$tags =~ /X/ && $request->addResultLoopIfValueDefined($loopname, $chunkCount, 'album_replay_gain', $c->{'albums.replay_gain'});
			$tags =~ /S/ && $request->addResultLoopIfValueDefined($loopname, $chunkCount, 'artist_id', $contributorID || $c->{'albums.contributor'});

			if ($tags =~ /a/) {
				# Bug 15313, this used to use $eachitem->artists which
				# contains a lot of extra logic.

				# Bug 17542: If the album artist is different from the current track's artist,
				# use the album artist instead of the track artist (if available)
				if ($contributorID && $c->{'albums.contributor'} && $contributorID != $c->{'albums.contributor'}) {
					$contributorNameSth ||= $dbh->prepare_cached('SELECT name FROM contributors WHERE id = ?');
					my ($name) = @{ $dbh->selectcol_arrayref($contributorNameSth, undef, $c->{'albums.contributor'}) };
					$c->{'contributors.name'} = $name if $name;
				}

				utf8::decode( $c->{'contributors.name'} ) if exists $c->{'contributors.name'};

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

			# want multiple artists?
			if ( $contributorSql && $c->{'albums.contributor'} != $vaObjId && !$c->{'albums.compilation'} ) {
				$contributorSth ||= $dbh->prepare_cached($contributorSql);
				$contributorSth->execute($c->{'albums.id'});

				my $contributor = $contributorSth->fetchrow_hashref;
				$contributorSth->finish;

				# XXX - what if the artist name itself contains ','?
				if ( $tags =~ /aa/ && $contributor->{name} ) {
					utf8::decode($contributor->{name});
					$request->addResultLoopIfValueDefined($loopname, $chunkCount, 'artists', $contributor->{name});
				}

				if ( $tags =~ /SS/ && $contributor->{id} ) {
					$request->addResultLoopIfValueDefined($loopname, $chunkCount, 'artist_ids', $contributor->{id});
				}
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
	my $cache = $Slim::Control::Queries::cache;

	# get our parameters
	my $client   = $request->client();
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');
	my $search   = $request->getParam('search');
	my $year     = $request->getParam('year');
	my $genreID  = $request->getParam('genre_id');
	my $genreString  = $request->getParam('genre_string');
	my $trackID  = $request->getParam('track_id');
	my $albumID  = $request->getParam('album_id');
	my $artistID = $request->getParam('artist_id');
	my $roleID   = $request->getParam('role_id');
	my $libraryID= Slim::Music::VirtualLibraries->getRealId($request->getParam('library_id'));
	my $tags     = $request->getParam('tags') || '';

	# treat contributors for albums with only one ARTIST but no ALBUMARTIST the same
	my $aa_merge = $roleID && $roleID eq 'ALBUMARTIST' && !$prefs->get('useUnifiedArtistsList');

	my $va_pref  = $prefs->get('variousArtistAutoIdentification') && $prefs->get('useUnifiedArtistsList');

	my $sql    = 'SELECT %s FROM contributors ';
	my $sql_va = 'SELECT COUNT(*) FROM albums ';
	my $w      = [];
	my $w_va   = [ 'albums.compilation = 1' ];
	my $p      = [];
	my $p_va   = [];

	my $rs;
	my $cacheKey;

	my $collate = Slim::Utils::OSDetect->getOS()->sqlHelperClass()->collate();
	my $sort    = "contributors.namesort $collate";

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
		if ( $search && Slim::Schema->canFulltextSearch ) {
			Slim::Plugin::FullTextSearch::Plugin->createHelperTable({
				name   => 'artistsSearch',
				search => $search,
				type   => 'contributor',
			});

			$sql = 'SELECT %s FROM artistsSearch, contributors ';
			unshift @{$w}, "contributors.id = artistsSearch.id";

			if ($tags ne 'CC') {
				$sort = "artistsSearch.fulltextweight DESC, LENGTH(contributors.name), $sort";
			}
		}

		my $roles;
		if ($roleID) {
			$roleID .= ',ARTIST' if $aa_merge;
			$roles = [ map { Slim::Schema::Contributor->typeToRole($_) } split(/,/, $roleID ) ];
		}
		elsif ($prefs->get('useUnifiedArtistsList')) {
			$roles = Slim::Schema->artistOnlyRoles();
		}
		else {
			$roles = [ map { Slim::Schema::Contributor->typeToRole($_) } Slim::Schema::Contributor->contributorRoles() ];
		}

		if ( defined $genreID ) {
			my @genreIDs = split(/,/, $genreID);

			$sql .= 'JOIN contributor_track ON contributor_track.contributor = contributors.id ';
			$sql .= 'JOIN tracks ON tracks.id = contributor_track.track ';
			$sql .= 'JOIN genre_track ON genre_track.track = tracks.id ';
			push @{$w}, 'genre_track.genre IN (' . join(', ', map {'?'} @genreIDs) . ')';
			push @{$p}, @genreIDs;

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

		# XXX - why would we not filter by role, as drilling down would filter anyway, potentially leading to empty resultsets?
		#       make sure we don't miss the VA object, as it might not have any of the roles we're looking for -mh
		#if ( !defined $search ) {
			if ( $sql =~ /JOIN contributor_track/ ) {
				push @{$w}, '(contributor_track.role IN (' . join( ',', @{$roles} ) . ') ' . ($search ? 'OR contributors.id = ? ' : '') . ') ';
			}
			else {
				if ( $sql !~ /JOIN contributor_album/ ) {
					$sql .= ($search ? 'LEFT ' : '') . 'JOIN contributor_album ON contributor_album.contributor = contributors.id ';
				}
				push @{$w}, '(contributor_album.role IN (' . join( ',', @{$roles} ) . ') ' . ($search ? 'OR contributors.id = ? ' : '') . ') ';
			}

			push @{$p}, Slim::Schema->variousArtistsObject->id if $search;

			if ( $va_pref || $aa_merge ) {
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

				push @{$w}, '(albums.compilation IS NULL OR albums.compilation = 0' . ($va_pref ? '' : ' OR contributors.id = ' . Slim::Schema->variousArtistsObject->id) . ')';
			}
		#}

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

		if ( $search && !Slim::Schema->canFulltextSearch ) {
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

		if (defined $libraryID) {
			$sql .= 'JOIN library_contributor ON library_contributor.contributor = contributors.id ';
			push @{$w}, 'library_contributor.library = ?';
			push @{$p}, $libraryID;
		}
	}

	if ( @{$w} ) {
		$sql .= 'WHERE ';
		my $s = join( ' AND ', @{$w} );
		$s =~ s/\%/\%\%/g;
		$sql .= $s . ' ';
	}

	my $dbh = Slim::Schema->dbh;

	# Various artist handling. Don't do if pref is off, or if we're
	# searching, or if we have a track
	my $count_va = 0;

	if ( $va_pref && !defined $search && !defined $trackID && !defined $artistID && !$roleID ) {
		# Only show VA item if there are any
		if ( @{$w_va} ) {
			$sql_va .= 'WHERE ';
			$sql_va .= join( ' AND ', @{$w_va} );
			$sql_va .= ' ';
		}

		if ( main::DEBUGLOG && $sqllog->is_debug ) {
			$sqllog->debug( "Artists query VA count: $sql_va / " . Data::Dump::dump($p_va) );
		}

		my $total_sth = $dbh->prepare_cached( $sql_va );

		$total_sth->execute( @{$p_va} );
		($count_va) = $total_sth->fetchrow_array();
		$total_sth->finish;
	}

	my $indexList;
	if ($tags =~ /Z/) {
		my $pageSql = sprintf($sql, "SUBSTR(contributors.namesort,1,1), count(distinct contributors.id)")
			 . "GROUP BY SUBSTR(contributors.namesort,1,1) ORDER BY contributors.namesort $collate";
		$indexList = $dbh->selectall_arrayref($pageSql, undef, @{$p});
		foreach (@$indexList) {
			utf8::decode($_->[0])
		}

		unshift @$indexList, ['#' => 1] if $indexList && $count_va;

		if ($tags =~ /ZZ/) {
			$request->addResult('indexList', $indexList) if $indexList;
			$request->setStatusDone();
			return
		}
	}

	$sql = sprintf($sql, 'contributors.id, contributors.name, contributors.namesort')
			. 'GROUP BY contributors.id ';

	$sql .= "ORDER BY $sort " unless $tags eq 'CC';

	my $stillScanning = Slim::Music::Import->stillScanning();

	# Get count of all results, the count is cached until the next rescan done event
	$cacheKey = md5_hex($sql . join( '', @{$p} ) . Slim::Music::VirtualLibraries->getLibraryIdForClient($client) . (Slim::Utils::Text::ignoreCase($search, 1) || ''));

	my $count = $cache->{$cacheKey};

	if ( !$count ) {
		my $total_sth = $dbh->prepare_cached( qq{
			SELECT COUNT(1) FROM ( $sql ) AS t1
		} );

		if ( main::DEBUGLOG && $sqllog->is_debug ) {
			$sqllog->debug( "Artists totals query: $sql / " . Data::Dump::dump($p) );
		}

		$total_sth->execute( @{$p} );
		($count) = $total_sth->fetchrow_array();
		$total_sth->finish;
	}

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

	if ($valid && $tags ne 'CC') {
		# Limit the real query
		if ( $index =~ /^\d+$/ && $quantity =~ /^\d+$/ ) {
			$sql .= "LIMIT ?,? ";
			push @$p, $index, $quantity;
		}

		if ( main::DEBUGLOG && $sqllog->is_debug ) {
			$sqllog->debug( "Artists query: $sql / " . Data::Dump::dump($p) );
		}

		my $sth = $dbh->prepare_cached($sql);
		$sth->execute( @{$p} );

		my ($id, $name, $namesort);
		$sth->bind_columns( \$id, \$name, \$namesort );

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
	my $cache = $Slim::Control::Queries::cache;

	# get our parameters
	my $client        = $request->client();
	my $index         = $request->getParam('_index');
	my $quantity      = $request->getParam('_quantity');
	my $search        = $request->getParam('search');
	my $year          = $request->getParam('year');
	my $contributorID = $request->getParam('artist_id');
	my $albumID       = $request->getParam('album_id');
	my $trackID       = $request->getParam('track_id');
	my $genreID       = $request->getParam('genre_id');
	my $libraryID     = Slim::Music::VirtualLibraries->getRealId($request->getParam('library_id'));
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
		my @genreIDs = split(/,/, $genreID);
		push @{$w}, 'genre_track.genre IN (' . join(', ', map {'?'} @genreIDs) . ')';
		push @{$p}, @genreIDs;
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

		if ( $libraryID ) {
			$sql .= 'JOIN library_genre ON library_genre.genre = genres.id ';
			push @{$w}, 'library_genre.library = ?';
			push @{$p}, $libraryID;
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
		$request->addResult('indexList', [
			map {
				utf8::decode($_->[0]);
				$_;
			} @{ $dbh->selectall_arrayref($pageSql, undef, @{$p}) }
		]);
		if ($tags =~ /ZZ/) {
			$request->setStatusDone();
			return
		}
	}

	$sql = sprintf($sql, 'DISTINCT(genres.id), genres.name, genres.namesort');
	$sql .= "ORDER BY genres.namesort $collate" unless $tags eq 'CC';

	my $stillScanning = Slim::Music::Import->stillScanning();

	# Get count of all results, the count is cached until the next rescan done event
	my $cacheKey = md5_hex($sql . join( '', @{$p} ) . Slim::Music::VirtualLibraries->getLibraryIdForClient($client));

	my $count = $cache->{$cacheKey};
	if ( !$count ) {
		my $total_sth = $dbh->prepare_cached( qq{
			SELECT COUNT(1) FROM ( $sql ) AS t1
		} );

		$total_sth->execute( @{$p} );
		($count) = $total_sth->fetchrow_array();
		$total_sth->finish;
	}

	if ( !$stillScanning ) {
		$cache->{$cacheKey} = $count;
	}

	# now build the result

	if ($stillScanning) {
		$request->addResult('rescan', 1);
	}

	$count += 0;

	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

	if ($valid && $tags ne 'CC') {

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

		my ($id, $name, $namesort);
		$sth->bind_columns( \$id, \$name, \$namesort );

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


sub infoTotalQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['info'], ['total'], ['genres', 'artists', 'albums', 'songs', 'duration']])) {
		$request->setStatusBadDispatch();
		return;
	}

	if (!Slim::Schema::hasLibrary()) {
		$request->setStatusNotDispatchable();
		return;
	}

	# get our parameters
	my $entity = $request->getRequest(2);

	my $totals = Slim::Schema->totals($request->client) if $entity ne 'duration';

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
	elsif ($entity eq 'duration') {
		$request->addResult("_$entity", Slim::Schema->totalTime($request->client));
	}

	$request->setStatusDone();
}


sub librariesQuery {
	my $request = shift;

	if ($request->isNotQuery([['libraries']])) {
		$request->setStatusBadDispatch();
		return;
	}

	if ( $request->isQuery([['libraries'], ['getid']]) && (my $client = $request->client) ) {
		my $id = Slim::Music::VirtualLibraries->getLibraryIdForClient($client) || 0;
		$request->addResult('id', $id);
		$request->addResult('name', Slim::Music::VirtualLibraries->getNameForId($id, $client)) if $id;
	}
	else {
		my $i = 0;
		while ( my ($id, $args) = each %{ Slim::Music::VirtualLibraries->getLibraries() } ) {
			$request->addResultLoop('folder_loop', $i, 'id', $id);
			$request->addResultLoop('folder_loop', $i, 'name', $args->{name});
			$i++;
		}
	}

	$request->setStatusDone();
}


# XXX TODO: merge SQL-based code from 7.6/trunk
# Can't use _getTagDataForTracks as is, as we have to deal with remote URLs, too
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
	my $libraryId  = Slim::Music::VirtualLibraries->getRealId($request->getParam('library_id'));

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
		$iterator = $playlistObj->tracks($libraryId);
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
	my $libraryId= Slim::Music::VirtualLibraries->getRealId($request->getParam('library_id'));

	# Normalize any search parameters
	if (defined $search && !Slim::Schema->canFulltextSearch) {
		$search = Slim::Utils::Text::searchStringSplit($search);
	}

	my $rs = Slim::Schema->rs('Playlist')->getPlaylists('all', $search, $libraryId);

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

	if (!Slim::Schema::hasLibrary()) {
		$request->setStatusNotDispatchable();
		return;
	}

	my $client   = $request->client;
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');
	my $query    = $request->getParam('term');
	my $extended = $request->getParam('extended');
	my $libraryID= Slim::Music::VirtualLibraries->getRealId($request->getParam('library_id')) || Slim::Music::VirtualLibraries->getLibraryIdForClient($client);

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
	my $search = Slim::Schema->canFulltextSearch ? $query : Slim::Utils::Text::searchStringSplit($query);

	my $dbh = Slim::Schema->dbh;

	my $total = 0;

	my $doSearch = sub {
		my ($type, $name, $w, $p, $c) = @_;

		# contributors first
		my $cols = "me.id, me.$name";
		$cols    = join(', ', $cols, @$c) if $extended && $c && @$c;

		my $sql;

		# we don't have a full text index for genres
		my $canFulltextSearch = $type ne 'genre' && Slim::Schema->canFulltextSearch;

		if ( $canFulltextSearch ) {
			Slim::Plugin::FullTextSearch::Plugin->createHelperTable({
				name   => 'quickSearch',
				search => $search,
				type   => $type,
				checkLargeResultset => sub {
					my $isLarge = shift;
					return ($isLarge && $isLarge > ($index + $quantity)) ? ('ORDER BY fulltextweight DESC LIMIT ' . $isLarge) : '';
				},
			});

			$sql = "SELECT $cols, quickSearch.fulltextweight FROM quickSearch, ${type}s me ";
			unshift @{$w}, "me.id = quickSearch.id";
		}
		else {
			$sql = "SELECT $cols FROM ${type}s me ";
		}

		if ( $libraryID ) {
			if ( $type eq 'contributor') {
				$sql .= 'JOIN contributor_track ON contributor_track.contributor = me.id ';
				$sql .= 'JOIN library_track ON library_track.track = contributor_track.track ';
			}
			elsif ( $type eq 'album' ) {
				$sql .= 'JOIN tracks ON tracks.album = me.id ';
				$sql .= 'JOIN library_track ON library_track.track = tracks.id ';
			}
			elsif ( $type eq 'genre' ) {
				$sql .= 'JOIN genre_track ON genre_track.genre = me.id ';
				$sql .= 'JOIN library_track ON library_track.track = genre_track.track ';
			}
			elsif ( $type eq 'track' ) {
				$sql .= 'JOIN library_track ON library_track.track = me.id ';
			}

			push @{$w}, 'library_track.library = ?';
			push @{$p}, $libraryID;
		}

		if ( !$canFulltextSearch ) {
			my $s = ref $search ? $search : [ $search ];

			if ( ref $s->[0] eq 'ARRAY' ) {
				push @{$w}, '(' . join( ' OR ', map { "me.${name}search LIKE ?" } @{ $s->[0] } ) . ')';
				push @{$p}, @{ $s->[0] };
			}
			else {
				push @{$w}, "me.${name}search LIKE ?";
				push @{$p}, @{$s};
			}
		}

		if ( $w && @{$w} ) {
			$sql .= 'WHERE ';
			my $s = join( ' AND ', @{$w} );
			$s =~ s/\%/\%\%/g;
			$sql .= $s . ' ';
		}

		$sql .= "GROUP BY me.id " if $libraryID;

		my $sth = $dbh->prepare_cached( qq{SELECT COUNT(1) FROM ($sql) AS t1} );
		$sth->execute(@$p);
		my ($count) = $sth->fetchrow_array;
		$sth->finish;

		$count += 0;
		$total += $count;

		my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

		if ($valid) {
			$request->addResult("${type}s_count", $count);

			$sql .= "ORDER BY quickSearch.fulltextweight DESC " if $canFulltextSearch;

			# Limit the real query
			$sql .= "LIMIT ?,?";

			my $sth = $dbh->prepare_cached($sql);
			$sth->execute( @{$p}, $index, $quantity );

			my ($id, $title, %additionalCols);
			$sth->bind_col(1, \$id);
			$sth->bind_col(2, \$title);

			if ($extended && $c) {
				my $i = 2;
				foreach (@$c) {
					$sth->bind_col(++$i, \$additionalCols{$_});
				}
			}

			my $chunkCount = 0;
			my $loopname   = "${type}s_loop";
			while ( $sth->fetch ) {

				last if $chunkCount >= $quantity;

				$request->addResultLoop($loopname, $chunkCount, "${type}_id", $id+0);

				utf8::decode($title);
				$request->addResultLoop($loopname, $chunkCount, "${type}", $title);

				# any additional column
				if ($extended && $c) {
					foreach (@$c) {
						my $col = $_;

						my $value = $additionalCols{$_};
						utf8::decode($value);

						$col =~ s/me\.//;
						$request->addResultLoop($loopname, $chunkCount, $col, $value);
					}
				}

				$chunkCount++;

				main::idleStreams() if !($chunkCount % 10);
			}

			$sth->finish;
		}
	};

	$doSearch->('contributor', 'name');
	$doSearch->('album', 'title', undef, undef, ['me.artwork']);
	$doSearch->('genre', 'name');
	$doSearch->('track', 'title', ['me.audio = ?'], ['1'], ['me.coverid', 'me.audio']);

	# XXX - should we search for playlists, too?

	$request->addResult('count', $total);
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
	my $roleID        = $request->getParam('role_id');
	my $libraryID     = Slim::Music::VirtualLibraries->getRealId($request->getParam('library_id'));
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

	$tags .= 'R' if $search && $search =~ /tracks_persistent\.rating/ && $tags !~ /R/;
	$tags .= 'O' if $search && $search =~ /tracks_persistent\.playcount/ && $tags !~ /O/;

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
		roleId        => $roleID,
		libraryId     => $libraryID,
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
	my $cache = $Slim::Control::Queries::cache;

	# get our parameters
	my $client        = $request->client();
	my $index         = $request->getParam('_index');
	my $quantity      = $request->getParam('_quantity');
	my $year          = $request->getParam('year');
	my $libraryID     = Slim::Music::VirtualLibraries->getRealId($request->getParam('library_id'));
	my $hasAlbums     = $request->getParam('hasAlbums');

	# get them all by default
	my $where = {};

	my ($key, $table) = ($hasAlbums || $libraryID) ? ('albums.year', 'albums') : ('id', 'years');

	my $sql = "SELECT DISTINCT $key FROM $table ";
	my $w   = ["$key != '0'"];
	my $p   = [];

	if (defined $year) {
		push @{$w}, "$key = ?";
		push @{$p}, $year;
	}

	if (defined $libraryID) {
		$sql .= 'JOIN tracks ON tracks.album = albums.id ';
		$sql .= 'JOIN library_track ON library_track.track = tracks.id ';
		push @{$w}, 'library_track.library = ?';
		push @{$p}, $libraryID;
	}

	if ( @{$w} ) {
		$sql .= 'WHERE ';
		$sql .= join( ' AND ', @{$w} );
		$sql .= ' ';
	}

	my $dbh = Slim::Schema->dbh;

	# Get count of all results, the count is cached until the next rescan done event
	my $cacheKey = md5_hex($sql . join( '', @{$p} ) . Slim::Music::VirtualLibraries->getLibraryIdForClient($client));

	my $count = $cache->{$cacheKey};
	if ( !$count ) {
		my $total_sth = $dbh->prepare_cached( qq{
			SELECT COUNT(1) FROM ( $sql ) AS t1
		} );

		$total_sth->execute( @{$p} );
		($count) = $total_sth->fetchrow_array();
		$total_sth->finish;
	}

	$sql .= "ORDER BY $key DESC";

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
# Helper functions
################################################################################

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

	# return count only?
	my $count_only;
	if ($tags eq 'CC') {
		$count_only = 1;
		$tags = $sort = '';
	}

	# return IDs only
	my $ids_only;
	if ($tags eq 'II') {
		$ids_only = 1;
		$tags = $sort = '';
	}

	# Normalize any search parameters
	my $search = $args->{search};
	if ( $search && specified($search) ) {
		if ( $search =~ s/^sql=// ) {
			# Raw SQL search query
			$search =~ s/;//g; # strip out any attempt at combining SQL statements
			unshift @{$w}, $search;
		}
		# we need to adjust SQL when using fulltext search
		elsif ( Slim::Schema->canFulltextSearch ) {
			Slim::Plugin::FullTextSearch::Plugin->createHelperTable({
				name   => 'tracksSearch',
				search => $search,
				type   => 'track',
				checkLargeResultset => sub {
					my $isLarge = shift;
					return $isLarge ? "LIMIT $isLarge" : 'ORDER BY fulltextweight'
				},
			});

			$sql = 'SELECT %s FROM tracksSearch, tracks ';
			unshift @{$w}, "tracks.id = tracksSearch.id";

			if (!$count_only) {
				$sort = "tracksSearch.fulltextweight DESC" . ($sort ? ", $sort" : '');
			}
		}
		else {
			my $strings = Slim::Utils::Text::searchStringSplit($search);
			if ( ref $strings->[0] eq 'ARRAY' ) {
				unshift @{$w}, '(' . join( ' OR ', map { 'tracks.titlesearch LIKE ?' } @{ $strings->[0] } ) . ')';
				unshift @{$p}, @{ $strings->[0] };
			}
			else {
				unshift @{$w}, 'tracks.titlesearch LIKE ?';
				unshift @{$p}, @{$strings};
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

	if ( my $libraryId = $args->{libraryId} ) {
		$sql .= 'JOIN library_track ON library_track.track = tracks.id ';
		push @{$w}, 'library_track.library = ?';
		push @{$p}, $libraryId;
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
		if ( main::STATISTICS && $sql !~ /JOIN tracks_persistent/ ) {
			$sql .= 'JOIN tracks_persistent ON tracks_persistent.urlmd5 = tracks.urlmd5 ';
		}
	};

	if ( my $genreId = $args->{genreId} ) {
		$join_genre_track->();

		my @genreIDs = split(/,/, $genreId);

		push @{$w}, 'genre_track.genre IN (' . join(', ', map {'?'} @genreIDs) . ')';
		push @{$p}, @genreIDs;
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

		# only albums on which the contributor has a specific role?
		my @roles;
		if ($args->{roleId}) {
			@roles = split /,/, $args->{roleId};
			push @roles, 'ARTIST' if $args->{roleId} eq 'ALBUMARTIST' && !$prefs->get('useUnifiedArtistsList');
		}
		elsif ($prefs->get('useUnifiedArtistsList')) {
			# Tag 'a' returns either ARTIST or TRACKARTIST role
			# Bug 16791: Need to include ALBUMARTIST too
			@roles = ( 'ARTIST', 'TRACKARTIST', 'ALBUMARTIST' );

			# Loop through each pref to see if the user wants to show that contributor role.
			foreach (Slim::Schema::Contributor->contributorRoles) {
				if ($prefs->get(lc($_) . 'InArtists')) {
					push @roles, $_;
				}
			}
		}
		else {
			@roles = Slim::Schema::Contributor->contributorRoles();
		}

		push @{$p}, map { Slim::Schema::Contributor->typeToRole($_) } @roles;
		push @{$w}, '(contributors.id = tracks.primary_artist OR tracks.primary_artist IS NULL)' if $args->{trackIds};
		push @{$w}, 'contributor_track.role IN (' . join(', ', map {'?'} @roles) . ')';
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

	$tags =~ /O/ && do {
		if ( main::STATISTICS ) {
			$join_tracks_persistent->();
			$c->{'tracks_persistent.playcount'} = 1;
		}
	};

	if ( scalar @{$w} ) {
		$sql .= 'WHERE ';
		my $s = join( ' AND ', @{$w} );
		$s =~ s/\%/\%\%/g;
		$sql .= $s . ' ';
	}
	$sql .= 'GROUP BY tracks.id ' if $sql =~ /JOIN /;

	if ( $sort ) {
		$sql .= "ORDER BY $sort ";
	}

	# Add selected columns
	# Bug 15997, AS mapping needed for MySQL
	my @cols = sort keys %{$c};
	$sql = sprintf $sql, join( ', ', map { $_ . " AS '" . $_ . "'" } @cols );

	my $dbh = Slim::Schema->dbh;

	if ( $count_only || (my $limit = $args->{limit}) ) {
		# Let the caller worry about the limit values

		my $cacheKey = md5_hex($sql . join( '', @{$p}, @$w ) . (Slim::Utils::Text::ignoreCase($search, 1) || ''));

		# use short lived cache, as we might be dealing with changing data (eg. playcount)
		if ( my $cached = $Slim::Control::Queries::bmfCache{$cacheKey} ) {
			$total = $cached;
		}
		else {
			my $total_sth = $dbh->prepare_cached( qq{
				SELECT COUNT(1) FROM ( $sql ) AS t1
			} );

			if ( main::DEBUGLOG && $sqllog->is_debug ) {
				$sqllog->debug( "Titles totals query: SELECT COUNT(1) FROM ($sql) / " . Data::Dump::dump($p) );
			}

			$total_sth->execute( @{$p} );
			($total) = $total_sth->fetchrow_array();
			$total_sth->finish;

			$Slim::Control::Queries::bmfCache{$cacheKey} = $total;
		}

		my ($valid, $start, $end);
		($valid, $start, $end) = $limit->($total) unless $count_only;

		if ( $count_only || !$valid ) {
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
		if (!$ids_only) {
			utf8::decode( $c->{'tracks.title'} ) if exists $c->{'tracks.title'};
			utf8::decode( $c->{'tracks.lyrics'} ) if exists $c->{'tracks.lyrics'};
			utf8::decode( $c->{'albums.title'} ) if exists $c->{'albums.title'};
			utf8::decode( $c->{'contributors.name'} ) if exists $c->{'contributors.name'};
			utf8::decode( $c->{'genres.name'} ) if exists $c->{'genres.name'};
			utf8::decode( $c->{'comments.value'} ) if exists $c->{'comments.value'};
		}

		my $id = $c->{'tracks.id'};

		$results{ $id } = { map { $_ => $c->{$_} } keys %{$c} };
		push @resultOrder, $id;
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

	# delete the temporary table, as it's stored in memory and can be rather large
	Slim::Plugin::FullTextSearch::Plugin->dropHelperTable('tracksSearch') if $search && Slim::Schema->canFulltextSearch;

	return wantarray ? ( \%results, \@resultOrder, $total ) : \%results;
}


### Video support

# XXX needs to be more like titlesQuery, was originally copied from albumsQuery
sub videoTitlesQuery { if (main::VIDEO && main::MEDIASUPPORT) {
	my $request = shift;

	if (!Slim::Schema::hasLibrary()) {
		$request->setStatusNotDispatchable();
		return;
	}

	my $sqllog = main::DEBUGLOG && logger('database.sql');
	my $cache = $Slim::Control::Queries::cache;

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
	my $cacheKey = md5_hex($sql . join( '', @{$p} ) . (Slim::Utils::Text::ignoreCase($search, 1) || ''));

	my $count = $cache->{$cacheKey};
	if ( !$count ) {
		my $total_sth = $dbh->prepare_cached( qq{
			SELECT COUNT(1) FROM ( $sql ) AS t1
		} );

		$total_sth->execute( @{$p} );
		($count) = $total_sth->fetchrow_array();
		$total_sth->finish;
	}

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
} }

sub _videoData { if (main::VIDEO && main::MEDIASUPPORT) {
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
} }

# XXX needs to be more like titlesQuery, was originally copied from albumsQuery
sub imageTitlesQuery { if (main::IMAGE && main::MEDIASUPPORT) {
	my $request = shift;

	if (!Slim::Schema::hasLibrary()) {
		$request->setStatusNotDispatchable();
		return;
	}

	my $sqllog = main::DEBUGLOG && logger('database.sql');
	my $cache = $Slim::Control::Queries::cache;

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
	my $cacheKey = md5_hex($sql . join( '', @{$p} ) . (Slim::Utils::Text::ignoreCase($search, 1) || ''));

	my $count = $cache->{$cacheKey};
	if ( !$count ) {
		my $total_sth = $dbh->prepare_cached( qq{
			SELECT COUNT(1) FROM ( $sql ) AS t1
		} );

		$total_sth->execute( @{$p} );
		($count) = $total_sth->fetchrow_array();
		$total_sth->finish;
	}

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
} }


sub _imageData { if (main::IMAGE && main::MEDIASUPPORT) {
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
} }


1;