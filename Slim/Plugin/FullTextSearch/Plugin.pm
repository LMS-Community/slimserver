package Slim::Plugin::FullTextSearch::Plugin;

use strict;
use Tie::Cache::LRU::Expires;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Scanner::API;
use Slim::Utils::Strings qw(string);

use constant BUILD_STEPS => 7;
use constant FIRST_COLUMN => 2;
use constant LARGE_RESULTSET => 500;

use constant SQL_CREATE_TRACK_ITEM => q{
	INSERT %s INTO fulltext (id, type, w10, w5, w3, w1)
		SELECT tracks.id, 'track', 
		-- weight 10
		IFNULL(tracks.title, '') || ' ' || IFNULL(tracks.titlesearch, '') || ' ' || IFNULL(tracks.customsearch, '') || ' ' || IFNULL(tracks.musicbrainz_id, ''),
		-- weight 5
		IFNULL(tracks.year, '') || ' ' || GROUP_CONCAT(albums.title, ' ') || ' ' || GROUP_CONCAT(albums.titlesearch, ' ') || ' ' || GROUP_CONCAT(genres.name, ' ') || ' ' || GROUP_CONCAT(genres.namesearch, ' '),
		-- weight 3 - contributors create multiple hits, therefore only w3
		CONCAT_CONTRIBUTOR_ROLE(tracks.id, GROUP_CONCAT(contributor_track.contributor, ','), 'contributor_track') || ' ' || 
		IGNORE_CASE(comments.value) || ' ' || IGNORE_CASE(tracks.lyrics) || ' ' || IFNULL(tracks.content_type, '') || ' ' || CASE WHEN tracks.channels = 1 THEN 'mono' WHEN tracks.channels = 2 THEN 'stereo' END,
		-- weight 1
		printf('%%i', tracks.bitrate) || ' ' || printf('%%ikbps', tracks.bitrate / 1000) || ' ' || IFNULL(tracks.samplerate, '') || ' ' || (round(tracks.samplerate, 0) / 1000) || ' ' || IFNULL(tracks.samplesize, '') || ' ' || replace(replace(tracks.url, '%%20', ' '), 'file://', '')
		 
		FROM tracks
		LEFT JOIN contributor_track ON contributor_track.track = tracks.id
		LEFT JOIN albums ON albums.id = tracks.album
		LEFT JOIN genre_track ON genre_track.track = tracks.id
		LEFT JOIN genres ON genres.id = genre_track.genre
		LEFT JOIN comments ON comments.track = tracks.id
	
		%s
		
		GROUP BY tracks.id;
};

use constant SQL_CREATE_ALBUM_ITEM => q{
	INSERT %s INTO fulltext (id, type, w10, w5, w3, w1)
		SELECT albums.id, 'album', 
		-- weight 10
		IFNULL(albums.title, '') || ' ' || IFNULL(albums.titlesearch, '') || ' ' || IFNULL(albums.customsearch, '') || ' ' || IFNULL(albums.musicbrainz_id, ''),
		-- weight 5
		IFNULL(albums.year, ''),
		-- weight 3
		CONCAT_CONTRIBUTOR_ROLE(albums.id, GROUP_CONCAT(contributor_album.contributor, ','), 'contributor_album'),
		-- weight 1
		CONCAT_ALBUM_TRACKS_INFO(albums.id) || ' ' || CASE WHEN albums.compilation THEN 'compilation' ELSE '' END
		 
		FROM albums
		LEFT JOIN contributor_album ON contributor_album.album = albums.id
		LEFT JOIN contributors ON contributors.id = contributor_album.contributor
	
		%s
		
		GROUP BY albums.id;
};

use constant SQL_CREATE_CONTRIBUTOR_ITEM => q{
	INSERT %s INTO fulltext (id, type, w10, w5, w3, w1)
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
		%s;
};

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.fulltext',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_FULLTEXT',
});

my $scanlog = logger('scan');
my $sqllog  = logger('database.sql');

my $prefs = preferences('plugin.fulltext');

# small cache of search term counts to speed up fulltext search
tie my %ftsCache, 'Tie::Cache::LRU', 100;
my $popularTerms;

sub initPlugin {
	my $class = shift;
	
	return unless $class->canFulltextSearch;

	Slim::Music::Import->addImporter('Slim::Plugin::FullTextSearch::Plugin', {
		'type'         => 'post',
		'weight'       => 90,
		'use'          => 1,
	});

	# register handler to register custom functions used for the FTS indexing
	Slim::Utils::OSDetect->getOS()->sqlHelperClass()->addPostConnectHandler($class);

	# no need to continue in scanner mode
	return if main::SCANNER;

	Slim::Control::Request::subscribe( sub {
		$prefs->remove('popularTerms');
		_initPopularTerms(1);
		%ftsCache = ();
	}, [['rescan'], ['done']] );

	Slim::Utils::Scanner::API->onNewTrack( { cb => \&checkSingleTrack, want_object => 1 } );
	Slim::Utils::Scanner::API->onChangedTrack( { cb => \&checkSingleTrack, want_object => 1 } );

	# don't continue if the library hasn't been initialized yet, or if a schema change is going to trigger a rescan anyway
	return unless Slim::Schema->hasLibrary() && !Slim::Schema->schemaUpdated;

	_initPopularTerms();
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

# create/update index item for single tracks (as found by BMF)
# this won't do any cleanup, might leave stale entries behind
sub checkSingleTrack {
	my ( $trackObj, $url ) = @_;
	
	return if $trackObj->remote || !$trackObj->id;
	
	my $dbh = Slim::Schema->dbh;

	$dbh->do( sprintf(SQL_CREATE_TRACK_ITEM,       'OR REPLACE', 'WHERE tracks.id=?'),       undef, $trackObj->id );
	$dbh->do( sprintf(SQL_CREATE_ALBUM_ITEM,       'OR REPLACE', 'WHERE albums.id=?'),       undef, $trackObj->albumid )  if $trackObj->albumid;
	$dbh->do( sprintf(SQL_CREATE_CONTRIBUTOR_ITEM, 'OR REPLACE', 'WHERE contributors.id=?'), undef, $trackObj->artistid ) if $trackObj->artistid;
}

sub canFulltextSearch {
	# we only support fulltext search with sqlite
	my $sqlVersion = Slim::Utils::OSDetect->getOS->sqlHelperClass->sqlVersion( Slim::Schema->dbh );
	
	return 1 if $sqlVersion =~ /SQLite/i;
	
	$log->error("We don't support fulltext search on your SQL engine: $sqlVersion");
	
	Slim::Utils::PluginManager->disablePlugin('FullTextSearch');
	
	return 0;
}

sub createHelperTable {
	my ($class, $args) = @_;
	
	if (! ($args->{name} && defined $args->{search} && $args->{type}) ) {
		$log->error("Can't create helper table without a name and search terms");
		return;
	}
	
	my $name = $args->{name};
	my $type = $args->{type};

	my ($tokens, $isLarge);
	my $orderOrLimit = '';
	
	if ($args->{checkLargeResultset}) {
		($tokens, $isLarge) = $class->parseSearchTerm($args->{search}, $type);
		$orderOrLimit = $args->{checkLargeResultset}->($isLarge);
	}
	else {
		$tokens = $class->parseSearchTerm($args->{search}, $type);
	}

	my $dbh = Slim::Schema->dbh;
			
	$dbh->do('DROP TABLE IF EXISTS ' . $name);
			
	my $temp = (main::DEBUGLOG && $log->is_debug) ? '' : 'TEMPORARY';
	
	$orderOrLimit = 'LIMIT 0' if !$tokens;
			
	my $searchSQL = "CREATE $temp TABLE $name AS SELECT id, FULLTEXTWEIGHT(matchinfo(fulltext)) AS fulltextweight FROM fulltext WHERE fulltext MATCH 'type:$type $tokens' $orderOrLimit";

	if ( main::DEBUGLOG ) {
		my $log2 = $sqllog->is_debug ? $sqllog : $log;
		$log2->is_debug && $log2->debug( "Fulltext search query ($type): $searchSQL" );
	}

	$dbh->do($searchSQL);
}

sub dropHelperTable {
	return if $log->debug;
	Slim::Schema->dbh->do('DROP TABLE IF EXISTS ' . $_[1]);
}

sub parseSearchTerm {
	my ($class, $search, $type) = @_;

	# Check if we have an open double quote and close it if needed
	my $c = () = $search =~ /"/g;
	if ( $c % 2 == 1 ) {
		$search .= '"';
	}
	
	$search =~ s/""\s*$//;

	# don't pull quoted strings apart!
	my @quoted;
	while ($search =~ s/"(.+?)"//) {
		my $quoted = $1;
		$quoted =~ s/[[:punct:]]/ /g;
		push @quoted, '"' . $quoted . '"';
	}

	my @tokens = grep /\w+/, split(/[\s[:punct:]]/, $search);
	my $noOfTokens = scalar(@tokens) + scalar(@quoted);

	my @tokens = map { 
		my $token = "$_*";

		# if this is the first token, then handle a few keywords which might result in a huge list carefully
		if ($noOfTokens == 1) {
			if ( length $_ == 1 ) {
				$token = "w10:$_"; 
			}
			elsif ( /\d{4}/ ) {
				# nothing to do here: years can be popular, but we want to be able to search for them
				$token = $_;
			}
			# skip "artist" etc. as they appear in the w5+ columns as "artist:elvis" tuples
			# only respect once there is eg. "artist:e*"
			elsif ( $_ !~ /a\w+:\w+/ && $popularTerms =~ /\Q$_\E[^|]*/i ) {
				$token = "w10:$_*";
				
				# log warning about search for popular term (set flag in cache to only warn once)
				$ftsCache{uc($token)}++ || (main::DEBUGLOG && $log->is_debug && $log->debug("Searching for very popular term - limiting to highest weighted column to prevent huge result list: '$token'"));
			}
		}
		# don't search substrings for single digit numbers or single characters
		elsif (length $_ == 1) {
			$token = $_;
		}

		$token;
	} @tokens;
	
	@quoted = map {
		my $token = $_;
		if ($noOfTokens == 1) {
			my ($raw) = $token =~ /"(.*)"/;
			
			if ( $popularTerms =~ /\Q$raw\E[^|]*/i ) {
				$token = "w10:$raw";
				
				# log warning about search for popular term (set flag in cache to only warn once)
				$ftsCache{uc($token)}++ || (main::DEBUGLOG && $log->is_debug && $log->debug("Searching for very popular term - limiting to highest weighted column to prevent huge result list: '$token'"));
			}
		}
		
		$token;
	} @quoted;
	
	my $tokens = join(' AND ', @quoted, @tokens);
	
	# handle exclusions "paul simon -garfunkel"
	$tokens =~ s/ AND -/ NOT /g;

	my $isLargeResultSet;

	# make sure our custom functions are registered
	my $dbh = Slim::Schema->dbh;
	
	if (wantarray && $type && $tokens) {
		my $counts = $ftsCache{ uc($type . '|' . $tokens) };
		
		if (!defined $counts) {
			($counts) = $dbh->selectrow_array(sprintf("SELECT count(1) FROM fulltext WHERE fulltext MATCH 'type:%s %s'", $type, $tokens));
			$ftsCache{ uc($type . '|' . $tokens) } = $counts;
		}

		$isLargeResultSet = LARGE_RESULTSET if $counts && $counts > LARGE_RESULTSET;
	}
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug("Search token ($type): '$tokens'");
		$log->debug("Large resultset? " . ($isLargeResultSet ? 'yes' : 'no'));
	};
	
	return wantarray ? ($tokens, $isLargeResultSet) : $tokens;
}

# Calculate the record's weight: columns are weighed according to their importance
# http://www.sqlite.org/fts3.html#matchinfo
# http://www.sqlite.org/fts3.html#fts4aux - get information about the index and tokens 
sub _getWeight {
	my $v = shift;
	
	my ($phraseCount, $columnCount) = unpack('LL', $v);
	
	my @x = unpack(('x' x 8) . ('L' x (3*$phraseCount*$columnCount)), $v);
	
	my $weight = 0;
	# start at second phrase, as the first is the type (track, album, contributor, playlist)
	for (my $i = 1; $i < $phraseCount; $i++) {
		$weight += ($x[3 * (FIRST_COLUMN + $i * $columnCount)] ? 1 : 0) * 10_000  	# track title etc.
		         + $x[3 * ((FIRST_COLUMN + 1) + $i * $columnCount)] * 5 	# track's album title
		         + $x[3 * ((FIRST_COLUMN + 2) + $i * $columnCount)] * 3 	# comments, lyrics
		         + $x[3 * ((FIRST_COLUMN + 3) + $i * $columnCount)];		# bitrate sample size
	}
	
	return $weight; 
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

sub _getAlbumTracksInfo {
	my ($albumId) = @_;
	
	return '' unless $albumId;
	
	my $dbh = Slim::Schema->dbh;
	# XXX - should we include artist information?
	my $sth = $dbh->prepare_cached(qq{
		SELECT IFNULL(tracks.title, '') || ' ' || IFNULL(tracks.titlesearch, '') || ' ' || IFNULL(tracks.customsearch, '') || ' ' || 
			IFNULL(tracks.musicbrainz_id, '') || ' ' || IGNORE_CASE(tracks.lyrics) || ' ' || IGNORE_CASE(comments.value) 
		FROM tracks 
		LEFT JOIN comments ON comments.track = tracks.id
		WHERE tracks.album = ?
		GROUP BY tracks.id;
	});

	my $trackInfo = join(' ', @{ $dbh->selectcol_arrayref($sth, undef, $albumId) || [] });
	
	$trackInfo =~ s/^ +//;
	$trackInfo =~ s/ +/ /;

	$trackInfo;
}

sub _ignoreCase {
	my ($text) = @_;
	
	return '' unless $text;
	
	return $text . ' ' . Slim::Utils::Text::ignoreCase($text, 1);
}

sub _rebuildIndex {
	my $progress = shift;
	
	$scanlog->error("Starting fulltext index build");

	my $dbh = Slim::Schema->dbh;

	$scanlog->error("Initialize fulltext table");
	
	$dbh->do("DROP TABLE IF EXISTS fulltext;") or $scanlog->error($dbh->errstr);
	$dbh->do("CREATE VIRTUAL TABLE fulltext USING fts3(id, type, w10, w5, w3, w1);") or $scanlog->error($dbh->errstr);
	main::idleStreams() unless main::SCANNER;

	$scanlog->error("Create fulltext index for tracks");
	$progress && $progress->update(string('SONGS'));
	Slim::Schema->forceCommit if main::SCANNER;
	
	my $sql = sprintf(SQL_CREATE_TRACK_ITEM, '', '');

#	main::DEBUGLOG && $scanlog->is_debug && $scanlog->debug($sql);
	$dbh->do($sql) or $scanlog->error($dbh->errstr);
	main::idleStreams() unless main::SCANNER;
		
	$scanlog->error("Create fulltext index for albums");
	$progress && $progress->update(string('ALBUMS'));
	Slim::Schema->forceCommit if main::SCANNER;
	$sql = sprintf(SQL_CREATE_ALBUM_ITEM, '', '');

#	main::DEBUGLOG && $scanlog->is_debug && $scanlog->debug($sql);
	$dbh->do($sql) or $scanlog->error($dbh->errstr);
	main::idleStreams() unless main::SCANNER;
		
	$scanlog->error("Create fulltext index for contributors");
	$progress && $progress->update(string('ARTISTS'));
	Slim::Schema->forceCommit if main::SCANNER;

	$sql = sprintf(SQL_CREATE_CONTRIBUTOR_ITEM, '', '');

#	main::DEBUGLOG && $scanlog->is_debug && $scanlog->debug($sql);
	$dbh->do($sql) or $scanlog->error($dbh->errstr);
	main::idleStreams() unless main::SCANNER;

	$scanlog->error("Create fulltext index for playlists");
	$progress && $progress->update(string('PLAYLISTS'));
	Slim::Schema->forceCommit if main::SCANNER;

	# building fulltext information for playlists is a bit more involved, as we want to have its tracks' information, too
	my $plSql = "SELECT track FROM playlist_track WHERE playlist = ?";
	my $trSql = "SELECT w10 || ' ' || w5 || ' ' || w3 || ' ' || w1 FROM tracks,fulltext WHERE tracks.url = ? AND fulltext MATCH 'id:' || tracks.id || ' type:track'";
	my $inSql = "INSERT INTO fulltext (id, type, w10, w5, w3, w1) VALUES (?, 'playlist', ?, '', '', ?)";

	# use fulltext information for tracks to populate a playlist's record with track information
	# this should allow us to find playlists not only based on the playlist title, but its tracks, too
	foreach my $playlist ( Slim::Schema->rs('Playlist')->getPlaylists('all')->all ) {

		main::DEBUGLOG && $scanlog->is_debug && $scanlog->error( $plSql . ' [' . Data::Dump::dump($playlist->id) .']' );

		my $w1 = '';
		
		foreach my $track ( @{ $dbh->selectcol_arrayref($plSql, undef, $playlist->id) } ) {
			next unless $track =~ /^file:/;

			main::DEBUGLOG && $scanlog->is_debug && $scanlog->debug($trSql . ' - ' . $track);

			$w1 .= join(' ', @{ $dbh->selectcol_arrayref($trSql, undef, $track) });
		}
		
		$w1 =~ s/^ +//;
		$w1 =~ s/ +/ /;
		
		main::DEBUGLOG && $scanlog->is_debug && $scanlog->debug( $inSql . Data::Dump::dump($playlist->id, $playlist->title . ' ' . $playlist->titlesearch,	$w1) );
		$dbh->do($inSql, undef, $playlist->id, $playlist->title . ' ' . $playlist->titlesearch,	$w1) or $scanlog->error($dbh->errstr);

		Slim::Schema->forceCommit if main::SCANNER;
	}
	main::idleStreams() unless main::SCANNER;

	$scanlog->error("Optimize fulltext index");
	$progress && $progress->update(string('DBOPTIMIZE_PROGRESS'));
	Slim::Schema->forceCommit if main::SCANNER;

	$dbh->do("INSERT INTO fulltext(fulltext) VALUES('optimize');") or $scanlog->error($dbh->errstr);

	$progress && $progress->update(string('DBOPTIMIZE_PROGRESS'));
	Slim::Schema->forceCommit if main::SCANNER;

	$dbh->do("DROP TABLE IF EXISTS fulltext_terms;") or $scanlog->error($dbh->errstr);
	$dbh->do("CREATE VIRTUAL TABLE fulltext_terms USING fts4aux(fulltext);") or $scanlog->error($dbh->errstr);
	
	$progress->final(BUILD_STEPS) if $progress;
	Slim::Schema->forceCommit if main::SCANNER;

	$scanlog->error("Fulltext index build done!");
}

sub _initPopularTerms {
	my $scanDone = shift;
	
	return if ($popularTerms = join('|', @{ $prefs->get('popularTerms') || [] }));

	main::DEBUGLOG && $log->is_debug && $log->debug("Analyzing most popular tokens");
		
	my $dbh = Slim::Schema->dbh;
	
	my ($ftExists) = $dbh->selectrow_array( qq{ SELECT name FROM sqlite_master WHERE type='table' AND name='fulltext' } );
	($ftExists) = $dbh->selectrow_array( qq{ SELECT name FROM sqlite_master WHERE type='table' AND name='fulltext_terms' } ) if $ftExists;
	
	if (!$ftExists) {
		$scanlog->error("Fulltext index missing or outdated - re-building");
		
		$prefs->remove('popularTerms');
		_rebuildIndex() unless $scanDone;
	}

	# get a list of terms which occur more than LARGE_RESULTSET times in our database
	my $terms = $dbh->selectcol_arrayref( sprintf(qq{
		SELECT term, d FROM (
			SELECT term, SUM(documents) d 
			FROM fulltext_terms 
			WHERE NOT col IN ('*', 1, 0) AND LENGTH(term) > 1
			GROUP BY term 
			ORDER BY d DESC
		)
		WHERE d > %i
	}, LARGE_RESULTSET) );

	$prefs->set('popularTerms', $terms);
	$popularTerms = join('|', @{$prefs->get('popularTerms')});

	main::DEBUGLOG && $log->is_debug && $log->debug(sprintf("Found %s popular tokens", scalar @$terms));
}

sub postDBConnect {
	my ($class, $dbh) = @_;
	
	# some custom functions to get good data
	$dbh->sqlite_create_function( 'FULLTEXTWEIGHT', 1, \&_getWeight );
	$dbh->sqlite_create_function( 'CONCAT_CONTRIBUTOR_ROLE', 3, \&_getContributorRole );
	$dbh->sqlite_create_function( 'CONCAT_ALBUM_TRACKS_INFO', 1, \&_getAlbumTracksInfo );
	$dbh->sqlite_create_function( 'IGNORE_CASE', 1, \&_ignoreCase);
	
	# XXX - printf is only available in SQLite 3.8.3+
	$dbh->sqlite_create_function( 'printf', 2, sub { sprintf(shift, shift); } );
}

1;
