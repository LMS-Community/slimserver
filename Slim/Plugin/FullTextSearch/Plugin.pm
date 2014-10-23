package Slim::Plugin::FullTextSearch::Plugin;

use strict;

use Slim::Control::Queries;
use Slim::Control::Request;
use Slim::Utils::Log;

use constant BUILD_STEPS => 5;

my $log = logger('scan');

use constant FIRST_COLUMN => 2;

sub initPlugin {
	my $class = shift;
	
	return unless $class->canFulltextSearch;

	Slim::Music::Import->addImporter('Slim::Plugin::FullTextSearch::Plugin', {
		'type'         => 'post',
		'weight'       => 90,
		'use'          => 1,
	});

	my $dbh = Slim::Schema->dbh;
	
	# some custom functions to get good data
	$dbh->sqlite_create_function( 'FULLTEXTWEIGHT', 1, \&_getWeight );
	$dbh->sqlite_create_function( 'CONCAT_CONTRIBUTOR_ROLE', 3, \&_getContributorRole );
	
	# XXX - printf is only available in SQLite 3.8.3
	$dbh->sqlite_create_function( 'printf', 2, sub { sprintf(shift, shift); } );

	# no need to continue in scanner mode
	return if main::SCANNER;

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
	
	# trigger rescan if our index is older than the last scan
	my $lastIndex = Slim::Schema->rs('MetaInformation')->find_or_create( {
		'name' => 'lastFulltextIndex'
	} );
	
	if (!$ftExists || ($lastIndex->value && $lastIndex->value < Slim::Music::Import->lastScanTime) ) {
		$log->warn("Fulltext index missing or outdated - re-building");
		
		_rebuildIndex();
		$lastIndex->value(time);
		$lastIndex->update();
	}
}

# importer modules, run in the scanner
sub startScan { 
	my $class = shift;

	my $progress = Slim::Utils::Progress->new({ 
		'type'  => 'importer',
		'name'  => 'plugin_fulltext',
		'total' => BUILD_STEPS,		# number of SQL queries - to be adjusted if there are more
		'bar'   => 1
	});

	_rebuildIndex($progress);

	Slim::Music::Import->endImporter(__PACKAGE__);
}


sub canFulltextSearch {
	# we only support fulltext search with sqlite
	my $sqlVersion = Slim::Utils::OSDetect->getOS->sqlHelperClass->sqlVersion( Slim::Schema->dbh );
	
	return 1 if $sqlVersion =~ /SQLite/i;
	
	$log->warn("We don't support fulltext search on your SQL engine: $sqlVersion");
	
	return 0;
}


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
		if ( $client->isUpgrading() || $client->isPlaying() ) {
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
	my $progress = shift;
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Starting fulltext index build...");

	Slim::Utils::Timers::killTimers( undef, \&_triggerIndexRebuild );

	my $dbh = Slim::Schema->dbh;

	main::DEBUGLOG && $log->is_debug && $log->debug("Initialize fulltext table...");
	
	$dbh->do("DROP TABLE IF EXISTS fulltext;") or $log->error($dbh->errstr);
	$dbh->do("CREATE VIRTUAL TABLE fulltext USING fts3(id, type, w10, w5, w3, w1);") or $log->error($dbh->errstr);
	Slim::Schema->forceCommit if main::SCANNER;

	main::DEBUGLOG && $log->is_debug && $log->debug("Create fulltext index for tracks...");
	$dbh->do(qq{
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
	}) or $log->error($dbh->errstr);
	Slim::Schema->forceCommit if main::SCANNER;
		
	main::DEBUGLOG && $log->is_debug && $log->debug("Create fulltext index for albums...");
	$dbh->do(qq{
		INSERT INTO fulltext (id, type, w10, w5, w3, w1)
			SELECT albums.id, 'album', 
			-- weight 10
			IFNULL(albums.title, '') || ' ' || IFNULL(albums.titlesearch, '') || ' ' || IFNULL(albums.customsearch, '') || ' ' || IFNULL(albums.musicbrainz_id, ''),
			-- weight 5
			IFNULL(albums.year, ''),
			-- weight 3
			CONCAT_CONTRIBUTOR_ROLE(albums.id, GROUP_CONCAT(contributor_album.contributor, ','), 'contributor_album'),
			-- weight 1
			CASE WHEN albums.compilation THEN 'compilation' ELSE '' END
			 
			FROM albums
			LEFT JOIN contributor_album ON contributor_album.album = albums.id
			LEFT JOIN contributors ON contributors.id = contributor_album.contributor
		
			GROUP BY albums.id;
	}) or $log->error($dbh->errstr);
	Slim::Schema->forceCommit if main::SCANNER;
		
	main::DEBUGLOG && $log->is_debug && $log->debug("Create fulltext index for contributors...");
	$dbh->do(qq{
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
			FROM contributors;
	}) or $log->error($dbh->errstr);
	Slim::Schema->forceCommit if main::SCANNER;

	main::DEBUGLOG && $log->is_debug && $log->debug("Create fulltext index for playlists...");

	# building fulltext information for playlists is a bit more involved, as we want to have its tracks' information, too
	my $plSth = $dbh->prepare_cached("SELECT track FROM playlist_track WHERE playlist = ?");
	my $sth   = $dbh->prepare_cached("SELECT w10, w5, w3, w1 FROM tracks,fulltext WHERE tracks.url = ? AND fulltext MATCH 'type:track' AND fulltext.id = tracks.id");
	my $inSth = $dbh->prepare_cached("INSERT INTO fulltext (id, type, w10, w5, w3, w1) VALUES (?, 'playlist', ?, '', '', ?)");

	# use fulltext information for tracks to populate a playlist's record with track information
	# this should allow us to find playlists not only based on the playlist title, but its tracks, too
	foreach my $playlist ( Slim::Schema->rs('Playlist')->getPlaylists('all')->all ) {
		$plSth->execute($playlist->id);
		my $tracks = $plSth->fetchall_arrayref;
		
		my $w1 = '';
		
		foreach my $track ( map { $_->[0] } @$tracks ) {
			$sth->execute($track);
			my $trackInfo = $sth->fetchall_arrayref;
			
			$w1 .= $trackInfo->[0]->[0] . ' ';
			$w1 .= $trackInfo->[0]->[1] . ' ';
			$w1 .= $trackInfo->[0]->[2] . ' ';
			$w1 .= $trackInfo->[0]->[3] . ' ';
		}
		
		$inSth->execute($playlist->id, $playlist->title . ' ' . $playlist->titlesearch,	$w1) or $log->error($dbh->errstr);
	}
	
	$progress->final(BUILD_STEPS) if $progress;
	Slim::Schema->forceCommit if main::SCANNER;

	main::DEBUGLOG && $log->is_debug && $log->debug("Fulltext index build done!");
}

1;