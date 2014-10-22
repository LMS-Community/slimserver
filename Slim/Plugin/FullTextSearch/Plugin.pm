package Slim::Plugin::FullTextSearch::Plugin;

use Slim::Control::Queries;
use Slim::Control::Request;
use Slim::Utils::Log;

my $log = logger('scan');

use constant FIRST_COLUMN => 2;

sub initPlugin {
	my $class = shift;
	
	return unless $class->canFulltextSearch;
	
	$Slim::Control::Queries::canFulltextSearch = 1;

	my $dbh = Slim::Schema->dbh;
	
	# some custom functions to get good data
	$dbh->sqlite_create_function( 'FULLTEXTWEIGHT', 1, \&_getWeight );
	$dbh->sqlite_create_function( 'CONCAT_CONTRIBUTOR_ROLE', 3, \&_getContributorRole );
	
	# XXX - printf is only available in SQLite 3.8.3
	$dbh->sqlite_create_function( 'printf', 2, sub { sprintf(shift, shift); } );

	Slim::Control::Request::subscribe( sub {
		Slim::Utils::Timers::killTimers( undef, \&_triggerIndexRebuild );
		Slim::Utils::Timers::setTimer(
			undef, 
			time + 30, 
			\&_triggerIndexRebuild
		);
	}, [['rescan'], ['done']] );
	
#	my $d = $dbh->selectall_arrayref( qq{ SELECT TRACK_WEIGHT(matchinfo(fulltext)) w, * FROM fulltext WHERE fulltext MATCH 'love bowie 192kbps' ORDER BY w DESC LIMIT 10 } );
	
	my $sth = $dbh->prepare( qq{ SELECT name FROM sqlite_master WHERE type='table' AND name='fulltext' } );
	$sth->execute();
	my ($ftExists) = $sth->fetchrow_array;
	$sth->finish;
	
	if (!$ftExists) {
		_rebuildIndex();
	}
	
=pod
#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F

    Slim::Control::Request::addDispatch(['fulltextsearch', '_index', '_quantity'], 
        [1, 1, 1, \&fulltextsearchQuery]);
=cut
}


sub canFulltextSearch {
	# we only support fulltext search with sqlite
	my $sqlVersion = Slim::Utils::OSDetect->getOS->sqlHelperClass->sqlVersion( Slim::Schema->dbh );
	
	return 1 if $sqlVersion =~ /SQLite/i;
	
	$log->warn("We don't support fulltext search on your SQL engine: $sqlVersion");
	return 
}

=pod
sub fulltextsearchQuery {
	my $request = shift;

warn Data::Dump::dump('yo');
	# check this is the correct query
	if ($request->isNotQuery([['fulltextsearch', 'search']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $client    = $request->client;
	my $index     = $request->getParam('_index');
	my $quantity  = $request->getParam('_quantity');
	my $query     = $request->getParam('term');
	my $libraryID = $request->getParam('library_id') || Slim::Music::VirtualLibraries->getLibraryIdForClient($client);
	
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
		
	my $total = 0;
	
	my $doSearch = sub {
		my ($type, $name, $w, $p, $c) = @_;

		# contributors first
		my $cols = "me.id, me.$name";
		$cols    = join(', ', $cols, @$c) if $c;
		
		my $sql = "SELECT $cols FROM ${type}s me ";
		
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
		
		my @tokens = map { "*$_*" } split(/\s/, $query);
		# XXX - DBI is getting confused when using the MATCH operator with a placeholder
		unshift @{$w}, "me.id IN (SELECT t.id FROM (SELECT FULLTEXTWEIGHT(matchinfo(fulltext)) w, fulltext.id FROM fulltext WHERE fulltext MATCH 'type:$type " . join(' AND ', @tokens) . "' ORDER BY w) AS t) ";
		
		if ( @{$w} ) {
			$sql .= 'WHERE ';
			my $s = join( ' AND ', @{$w} );
			$s =~ s/\%/\*/g;
			$sql .= $s . ' ';
		}
		
		my $sth = $dbh->prepare( qq{SELECT COUNT(1) FROM ($sql) AS t1} );
		$sth->execute(@$p);
		my ($count) = $sth->fetchrow_array;
		$sth->finish;
	
		$count += 0;
		$total += $count;
	
		my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);
	
		if ($valid) {
			$request->addResult("${type}s_count", $count);
			
			# Limit the real query
			$sql .= "LIMIT ?,?";

#warn $sql;
		
			my $sth = $dbh->prepare_cached($sql);
			$sth->execute( @{$p}, $index, $quantity );
			
			my ($id, $title, %additionalCols);
			$sth->bind_col(1, \$id);
			$sth->bind_col(2, \$title);
			
			if ($c) {
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
				if ($c) {
					foreach (@$c) {
						utf8::decode($additionalCols{$_});
						$request->addResultLoop($loopname, $chunkCount, $_, $additionalCols{$_});
					}
				}
		
				$chunkCount++;
				
				main::idleStreams() if !($chunkCount % 10);
			}
			
			$sth->finish;
		}
	};

	$doSearch->('contributor', 'name');
	$doSearch->('album', 'title', undef, undef, ['artwork']);
	$doSearch->('genre', 'name');
	$doSearch->('track', 'title', ['audio = ?'], ['1'], ['coverid']);
	
	# XXX - should we search for playlists, too?
	
	$request->addResult('count', $total);
	$request->setStatusDone();
}
=cut

sub _getWeight {
	my $v = shift;
	
	my ($p, $c) = unpack('LL', $v);
	
	my @x = unpack(('x' x 8) . ('L' x (3*$p*$c)), $v);
	
	my $w = 0;
	# Calculate the record's weight: columns are weighed according to their importance
	# http://www.sqlite.org/fts3.html#matchinfo
	for (my $i = 0; $i < $p; $i++) {
		$w += $x[3 * (FIRST_COLUMN + $i * $c)] * 10	# track title etc.
			+ $x[3 * ((FIRST_COLUMN + 1) + $i * $c)] * 5		# track's album title
			+ $x[3 * ((FIRST_COLUMN + 2) + $i * $c)] * 3		# comments, lyrics
			+ $x[3 * ((FIRST_COLUMN + 3) + $i * $c)];		# bitrate sample size
	}
	
	return $w; 
}

sub _getContributorRole {
	my ($workId, $contributors, $type) = @_;
	
	my ($col) = $type =~ /contributor_(.*)/;
	
	return '' unless $workId && $contributors && $type && $col;
	
	my $dbh = Slim::Schema->dbh;
	my $sth = $dbh->prepare_cached("SELECT name, namesearch, role FROM contributors, $type WHERE contributors.id = ? AND $type.contributor = ? AND $type.$col = ? GROUP BY role");

	my ($name, $namesearch, $role);
	
	my $tuples = '';
	
	foreach my $contributor ( split /,/, $contributors ) {
		$sth->execute($contributor, $contributor, $workId);
		$sth->bind_columns(\$name, \$namesearch, \$role);

		while ( $sth->fetch ) {
			$role = Slim::Schema::Contributor->roleToType($role);
			my $localized = Slim::Utils::Strings::string($role);

			utf8::decode($name);
			
			$tuples .= "$role:$name $localized:$name " if $name;
			$tuples .= "$role:$namesearch $localized:$namesearch " if $namesearch;
		}
	}

	return $tuples;
}

sub _triggerIndexRebuild {
	
	Slim::Utils::Timers::killTimers( undef, \&_triggerIndexRebuild );
	
	my $pollInterval = 0;

	for my $client (Slim::Player::Client::clients()) {
		if ( $client->isUpgrading() || $client->isPlaying() || (Time::HiRes::time() - $client->lastActivityTime <= INTERVAL) ) {
			$pollInterval = 300;
		}
	}
	
	if ( Slim::Music::Import->stillScanning() || $pollInterval ) {
		$pollInterval ||= 1800;
		Slim::Utils::Timers::setTimer(
			undef, 
			time + $pollInterval, 
			\&_triggerIndexRebuild
		);
	}
	else {
		_rebuildIndex();
	}
}

sub _rebuildIndex {
	main::DEBUGLOG && $log->is_debug && $log->debug("Starting fulltext index build...");

	Slim::Utils::Timers::killTimers( undef, \&_triggerIndexRebuild );

	my $dbh = Slim::Schema->dbh;

	foreach (split /;/sg, qq{
		DROP TABLE IF EXISTS fulltext;
		CREATE VIRTUAL TABLE fulltext USING fts3(id, type, w10, w5, w3, w1); 
		
		-- tracks
		INSERT INTO fulltext (id, type, w10, w5, w3, w1)
			SELECT tracks.id, 'track', 
			-- weight 10
			IFNULL(tracks.title, '') || ' ' || IFNULL(tracks.titlesearch, '') || ' ' || IFNULL(tracks.customsearch, '') || ' ' || IFNULL(tracks.musicbrainz_id, ''),
			-- weight 5
			IFNULL(tracks.year, '') || ' ' || GROUP_CONCAT(albums.title, ' ') || ' ' || GROUP_CONCAT(albums.titlesearch, ' ') || ' ' || GROUP_CONCAT(genres.name, ' ') || ' ' || GROUP_CONCAT(genres.namesearch, ' '),
--			IFNULL(tracks.year, '') || ' ' || GROUP_CONCAT(contributors.name, ' ') || ' ' || GROUP_CONCAT(contributors.namesearch, ' ') || ' ' || GROUP_CONCAT(albums.title, ' ') || ' ' || GROUP_CONCAT(albums.titlesearch, ' ') || ' ' || GROUP_CONCAT(genres.name, ' ') || ' ' || GROUP_CONCAT(genres.namesearch, ' '),
			-- weight 3 - contributors create multiple hits, therefore only w3
			CONCAT_CONTRIBUTOR_ROLE(tracks.id, GROUP_CONCAT(contributor_track.contributor, ','), 'contributor_track') || ' ' || IFNULL(comments.value, '') || ' ' || IFNULL(tracks.lyrics, '') || ' ' || IFNULL(tracks.content_type, '') || ' ' || CASE WHEN tracks.channels = 1 THEN 'mono' WHEN tracks.channels = 2 THEN 'stereo' END,
			-- weight 1
			printf('%i', tracks.bitrate) || ' ' || printf('%ikbps', tracks.bitrate / 1000) || ' ' || IFNULL(tracks.samplerate, '') || ' ' || (round(tracks.samplerate, 0) / 1000) || ' ' || IFNULL(tracks.samplesize, '') || ' ' || tracks.url
			 
			FROM tracks
			LEFT JOIN contributor_track ON contributor_track.track = tracks.id
--			LEFT JOIN contributors ON contributors.id = contributor_track.contributor
			LEFT JOIN albums ON albums.id = tracks.album
			LEFT JOIN genre_track ON genre_track.track = tracks.id
			LEFT JOIN genres ON genres.id = genre_track.genre
			LEFT JOIN comments ON comments.track = tracks.id
		
			GROUP BY tracks.id;
		
		-- albums
		INSERT INTO fulltext (id, type, w10, w5, w3, w1)
			SELECT albums.id, 'album', 
			-- weight 10
			IFNULL(albums.title, '') || ' ' || IFNULL(albums.titlesearch, '') || ' ' || IFNULL(albums.customsearch, '') || ' ' || IFNULL(albums.musicbrainz_id, ''),
			-- weight 5
			IFNULL(albums.year, ''),
--			IFNULL(albums.year, '') || ' ' || GROUP_CONCAT(contributors.name, ' ') || ' ' || GROUP_CONCAT(contributors.namesearch, ' '),
			-- weight 3
			CONCAT_CONTRIBUTOR_ROLE(albums.id, GROUP_CONCAT(contributor_album.contributor, ','), 'contributor_album'),
			-- weight 1
			CASE WHEN albums.compilation THEN 'compilation' ELSE '' END
			 
			FROM albums
			LEFT JOIN contributor_album ON contributor_album.album = albums.id
			LEFT JOIN contributors ON contributors.id = contributor_album.contributor
		
			GROUP BY albums.id;
		
		
		-- contributors
		INSERT INTO fulltext (id, type, w10, w5, w3, w1)
			SELECT contributors.id, 'contributor', 
			-- weight 10
			IFNULL(contributors.name, '') || ' ' || IFNULL(contributors.namesearch, '') || ' ' || IFNULL(contributors.customsearch, '') || ' ' || IFNULL(contributors.musicbrainz_id, ''),
			-- weight 5
			'',
			-- weight 3
			'',
			-- weight 1
			''
			FROM contributors
		;
		
		-- genres
		INSERT INTO fulltext (id, type, w10, w5, w3, w1)
			SELECT genres.id, 'genre', IFNULL(genres.name, '') || ' ' || IFNULL(genres.namesearch, ''), '', '', ''
			FROM genres
			WHERE genres.name != '';
	}) {
		$dbh->do($_) or warn $dbh->errstr;
	};
		
	main::DEBUGLOG && $log->is_debug && $log->debug("Fulltext index build done!");
}

1;