package Plugins::MusicMagic::Plugin;

# $Id$

use strict;

use File::Spec::Functions qw(catfile);
use Scalar::Util qw(blessed);

use Slim::Player::ProtocolHandlers;
use Slim::Player::Protocols::HTTP;
use Slim::Utils::Misc;
use Slim::Utils::Strings;

use Plugins::MusicMagic::Settings;

my $isScanning = 0;
my $initialized = 0;
my $last_error = 0;
my $export = '';
my $count = 0;
my $playlistindex = 0;
my @playlists;
my $moodindex = 0;
my @moods;
my $scan = 0;
my $MMSHost;
my $MMSport;

our %artwork = ();

our %mixMap  = (
	'add.single' => 'play_1',
	'add.hold'   => 'play_2'
);

our %mixFunctions = ();

our %validMixTypes = (
	'track'    => 'song',
	'album'    => 'album',
	'artist'   => 'artist',
	'genre'    => 'genre',
	'mood'     => 'mood',
	'playlist' => 'playlist',
);

sub strings {
	return '';
}

sub getFunctions {
	return '';
}

sub useMusicMagic {
	my $newValue = shift;
	my $can = canUseMusicMagic();
	
	if (defined($newValue)) {
		if (!$can) {
			Slim::Utils::Prefs::set('musicmagic', 0);
		} else {
			Slim::Utils::Prefs::set('musicmagic', $newValue);
		}
	}
	
	my $use = Slim::Utils::Prefs::get('musicmagic');
	
	if (!defined($use) && $can) { 
		Slim::Utils::Prefs::set('musicmagic', 1);
	} elsif (!defined($use) && !$can) {
		Slim::Utils::Prefs::set('musicmagic', 0);
	}
	
	$use = Slim::Utils::Prefs::get('musicmagic') && $can;
	Slim::Music::Import::useImporter('MUSICMAGIC',$use);

	$::d_musicmagic && msg("MusicMagic: using musicmagic: $use\n");
	
	return $use;
}

sub canUseMusicMagic {
	return $initialized || initPlugin();
}

sub getDisplayName {
	return 'SETUP_MUSICMAGIC';
}

sub enabled {
	return ($::VERSION ge '6.1') && initPlugin();
}

sub shutdownPlugin {
	# turn off checker
	Slim::Utils::Timers::killTimers(0, \&checker);
	
	# remove playlists
	
	# disable protocol handler?
	#Slim::Player::ProtocolHandlers->registerHandler('musicmaglaylist', 0);
	
	# reset last scan time

	Slim::Utils::Prefs::set('MMMlastMusicLibraryFinishTime',undef);


	$initialized = 0;

	# delGroups, categories and prefs
	Slim::Web::Setup::delCategory('MUSICMAGIC');
	Slim::Web::Setup::delGroup('SERVER_SETTINGS','musicmagic',1);
	
	# set importer to not use, but only for this session.
	# leave server pref as is to support reenabling the features, 
	# without needing a forced rescan
	Slim::Music::Import::useImporter('MUSICMAGIC',0);
}

sub initPlugin {
	return 1 if $initialized;
	
	checkDefaults();
	
	if (grep {$_ eq 'MusicMagic::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins')) {
		$::d_musicmagic && msg("MusicMagic: don't initialize, it's disabled\n");
		$initialized = 0;
		
		my ($groupRef,$prefRef) = &setupPort();
		Slim::Web::Setup::addGroup('PLUGINS', 'musicmagic_connect', $groupRef, undef, $prefRef);
		return 0;		
	}

	$MMSport = Slim::Utils::Prefs::get('MMSport');
	$MMSHost = Slim::Utils::Prefs::get('MMSHost');

	$::d_musicmagic && msg("MusicMagic: Testing for API on $MMSHost:$MMSport\n");

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/version",
		'create' => 0,
		'timeout' => 5,
	});

	unless ($http) {

		$initialized = 0;
		$::d_musicmagic && msg("MusicMagic: Cannot Connect\n");
		
		my ($groupRef,$prefRef) = &setupPort();
		Slim::Web::Setup::addGroup('PLUGINS', 'musicmagic_connect', $groupRef, undef, $prefRef);

	} else {

		my $content = $http->content;
		$::d_musicmagic && msg("MusicMagic: $content\n");
		$http->close;
		
		Plugins::MusicMagic::Settings::init();
		
		# Note: Check version restrictions if any
		$initialized = $content;

		checker($initialized);

		Slim::Music::Import::addImporter('MUSICMAGIC', {
			'scan'      => \&startScan,
			'mixer'     => \&mixerFunction,
			'setup'     => \&addGroups,
			'mixerlink' => \&mixerlink,
		});

		Slim::Music::Import::useImporter('MUSICMAGIC', Slim::Utils::Prefs::get('musicmagic'));

		Slim::Player::ProtocolHandlers->registerHandler('musicmagicplaylist', 0);

		addGroups();
		if (scalar @{grabMoods()}) {
			Slim::Buttons::Common::addMode('musicmagic_moods', {}, \&setMoodMode);
			Slim::Buttons::Home::addMenuOption('MUSICMAGIC_MOODS', {
				'useMode'  => 'musicmagic_moods',
				'mood'     => 'none',
			});
			Slim::Web::Pages->addPageLinks("browse", {
				'MUSICMAGIC_MOODS' => "plugins/MusicMagic/musicmagic_moods.html"
			});
		}
	}
	
	$mixFunctions{'play'} = \&playMix;

	Slim::Buttons::Common::addMode('musicmagic_mix', \%mixFunctions);
	Slim::Hardware::IR::addModeDefaultMapping('musicmagic_mix',\%mixMap);
	
	return $initialized;
}

sub defaultMap {
	#Slim::Buttons::Common::addMode('musicmagic_mix', \%mixFunctions);
	Slim::Hardware::IR::addModeDefaultMapping('musicmagic_mix',\%mixMap);
	return undef;
}

sub playMix {
	my $client = shift;
	my $button = shift;
	my $append = shift || 0;

	my $line1;
	my $playAddInsert;
	
	if ($append == 1) {
		$line1 = $client->string('ADDING_TO_PLAYLIST');
		$playAddInsert = 'addtracks';
	} elsif ($append == 2) {
		$line1 = $client->string('INSERT_TO_PLAYLIST');
		$playAddInsert = 'inserttracks';
	} elsif (Slim::Player::Playlist::shuffle($client)) {
		$line1 = $client->string('PLAYING_RANDOMLY_FROM');
		$playAddInsert = 'playtracks';
	} else {
		$line1 = $client->string('NOW_PLAYING_FROM');
		$playAddInsert = 'playtracks';
	}

	my $line2 = $client->param('stringHeader') ? $client->string($client->param('header')) : $client->param('header');
	
	$client->showBriefly( {
		'line1'   => $line1,
		'line2'   => $line2,
		'overlay2'=> $client->symbols('notesymbol'),
	});

	$client->execute(["playlist", $playAddInsert, "listref", $client->param('listRef')]);
}

sub addGroups {
	my $category = &setupCategory;

	Slim::Web::Setup::addCategory('MUSICMAGIC',$category);
	
	my ($groupRef,$prefRef) = &setupUse();
	Slim::Web::Setup::addGroup('SERVER_SETTINGS', 'musicmagic', $groupRef, undef, $prefRef);

	Slim::Web::Setup::addChildren('SERVER_SETTINGS', 'MUSICMAGIC');
}

sub isMusicLibraryFileChanged {

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/cacheid?contents",
		'create' => 0,
		'timeout' => 5,
	}) || return 0;

	my $fileMTime = $http->content;
	
	$::d_musicmagic && msg("MusicMagic: read cacheid of $fileMTime");

	$http->close;

	$http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/getStatus",
		'create' => 0,
		'timeout' => 5,
	}) || return 0;
	
	my $MMMstatus = $http->content;
	
	$::d_musicmagic && msg("MusicMagic: got status - $MMMstatus");

	$http->close;

	# Only say "yes" if it has been more than one minute since we last finished scanning
	# and the file mod time has changed since we last scanned. Note that if we are
	# just starting, $lastMusicLibraryDate is undef, so both $fileMTime
	# will be greater than 0 and time()-0 will be greater than 180 :-)
	my $oldTime = Slim::Utils::Prefs::get('MMMlastMusicMagicLibraryDate') || 0;
	my $lastMusicLibraryFinishTime = Slim::Utils::Prefs::get('MMMlastMusicLibraryFinishTime') || 0;

	if ($fileMTime > $oldTime) {

		my $musicmagicscaninterval = Slim::Utils::Prefs::get('musicmagicscaninterval');

		$::d_musicmagic && msg("MusicMagic: music library has changed!\n");
		
		$::d_musicmagic && msg("	MusicMagic Details: \n\t\tCacheid - $fileMTime\t\tLastCacheid - $oldTime\n\t\tReload Interval - $musicmagicscaninterval\n\t\tLast Scan - $lastMusicLibraryFinishTime\n");
		
		unless ($musicmagicscaninterval) {
			
			# only scan if musicmagicscaninterval is non-zero.
			$::d_musicmagic && msg("MusicMagic: Scan Interval set to 0, rescanning disabled\n");

			return 0;
		}
		
		if (time - $lastMusicLibraryFinishTime > $musicmagicscaninterval) {

			return 1;
		}

		$::d_musicmagic && msg("MusicMagic: waiting for $musicmagicscaninterval seconds to pass before rescanning\n");
	}
	
	return 0;
}

sub checker {
	my $firstTime = shift || 0;
	
	return unless (Slim::Utils::Prefs::get('musicmagic'));
	
	my $change = 0;
	if (!$firstTime && !stillScanning() && isMusicLibraryFileChanged()) {
		startScan();
	}

	# make sure we aren't doing this more than once...
	Slim::Utils::Timers::killTimers(0, \&checker);

	# Call ourselves again after 60 seconds
	Slim::Utils::Timers::setTimer(0, (Time::HiRes::time() + 120), \&checker);
}

sub startScan {
	
	if (!useMusicMagic()) {
		return;
	}
		
	$::d_musicmagic && msg("MusicMagic: start export\n");
	stopScan();

	if (Slim::Music::Import::scanPlaylistsOnly()) {
		$export = 'playlists';
	} else {
		$export = 'start';
	}

	$scan = 0;
	
	Slim::Utils::Scheduler::add_task(\&exportFunction);
} 

sub stopScan {
	if (stillScanning()) {
		
		$::d_musicmagic && msg("MusicMagic: Scan already in progress. Restarting\n");
		Slim::Utils::Scheduler::remove_task(\&exportFunction);
		$isScanning = 0;
	}
}

sub stillScanning {
	return $isScanning;
}

sub doneScanning {
	$::d_musicmagic && msg("MusicMagic: done Scanning\n");

	$isScanning = 0;
	$scan = 0;
	
	Slim::Utils::Prefs::set('MMMlastMusicLibraryFinishTime',time);

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/cacheid?contents",
		'create' => 0,
	}) || return 0;

	if ($http) {

		Slim::Utils::Prefs::set('MMMlastMusicMagicLibraryDate', $http->content);

		$http->close;
	}
	
	Slim::Music::Import::endImporter('MUSICMAGIC');
}

sub convertPath {
	my $mmsPath = shift;
	
	return $mmsPath if (Slim::Utils::Prefs::get('MMSHost') eq 'localhost');
	
	my $remoteRoot = Slim::Utils::Prefs::get('MMSremoteRoot');
	my $nativeRoot = Slim::Utils::Prefs::get('audiodir');
	my $original   = $mmsPath;
	my $winPath    = $mmsPath =~ m/\\/; # test if this is a windows path

	if (Slim::Utils::OSDetect::OS() eq 'unix') {

		# we are unix
		if ($winPath) {

			# we are running music magic on winders but
			# slim server is running on unix

			# convert any windozes paths to unix style
			$remoteRoot =~ tr/\\/\//;
			$::d_musicmagic &&  msg("MusicMagic: $remoteRoot :: $nativeRoot \n");

			# convert windozes paths to unix style
			$mmsPath =~ tr/\\/\//;
			# convert remote root to native root
			$mmsPath =~ s/$remoteRoot/$nativeRoot/;
		}

	} else {

		# we are windows
		if (!$winPath) {

			# we recieved a unix path from music match
			# convert any unix paths to windows style
			# convert windows native to unix first
			# cuz matching dont work unless we do
			$nativeRoot =~ tr/\\/\//;
			$::d_musicmagic &&  msg("MusicMagic: $remoteRoot :: $nativeRoot \n");

			# convert unix root to windows root
			$mmsPath =~ s/$remoteRoot/$nativeRoot/;
			# convert unix paths to windows
			$mmsPath =~ tr/\//\\/;
		}
	}

	$::d_musicmagic && msg("MusicMagic: $original is now $mmsPath\n");

	return $mmsPath
}

sub grabFilters {
	my @filters;
	my %filterHash;
	
	return unless $initialized;
	
	if (grep {$_ eq 'MusicMagic::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins')) {
		$::d_musicmagic && msg("MusicMagic: don't get filters list, it's disabled\n");
		return %filterHash;
	}
	
	$MMSport = Slim::Utils::Prefs::get('MMSport') unless $MMSport;
	$MMSHost = Slim::Utils::Prefs::get('MMSHost') unless $MMSHost;

	$::d_musicmagic && msg("MusicMagic: get filters list\n");

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/filters",
		'create' => 0,
	});

	if ($http) {

		@filters = split(/\n/, $http->content);
		$http->close;

		if ($::d_musicmagic && scalar @filters) {

			msg("MusicMagic: found filters:\n");

			for my $filter (@filters) {
				msg("MusicMagic:\t$filter\n");
			}
		}
	}

	my $none = sprintf('(%s)', Slim::Utils::Strings::string('NONE'));

	push @filters, $none;

	foreach my $filter ( @filters ) {

		if ($filter eq $none) {

			$filterHash{0} = $filter;
			next
		}

		$filterHash{$filter} = $filter;
	}

	return %filterHash;
}

sub grabMoods {
	my @moods;
	my %moodHash;
	
	return unless $initialized;
	
	if (grep {$_ eq 'MusicMagic::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins')) {
		$::d_musicmagic && msg("MusicMagic: don't get moods list, it's disabled\n");
		return %moodHash;
	}
	
	$MMSport = Slim::Utils::Prefs::get('MMSport') unless $MMSport;
	$MMSHost = Slim::Utils::Prefs::get('MMSHost') unless $MMSHost;

	$::d_musicmagic && msg("MusicMagic: get moods list\n");

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/moods",
		'create' => 0,
	});

	if ($http) {

		@moods = split(/\n/, $http->content);
		$http->close;

		if ($::d_musicmagic && scalar @moods) {

			msg("MusicMagic: found moods:\n");

			for my $mood (@moods) {
				msg("MusicMagic:\t$mood\n");
			}
		}
	}

	return \@moods;
}

sub setMoodMode {
	my $client = shift;
	my $method = shift;
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	
	my %params = (
		'header'         => $client->string('MUSICMAGIC_MOODS'),
		'listRef'        => &grabMoods,
		'headerAddCount' => 1,
		'overlayRef'     => sub {return (undef, $client->symbols('rightarrow'));},
		'mood'           => 'none',
		'callback'       => sub {
			my $client = shift;
			my $method = shift;

			if ($method eq 'right') {
				
				mixerFunction($client);
			}
			elsif ($method eq 'left') {
				Slim::Buttons::Common::popModeRight($client);
			}
		},
	);

	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', \%params);
}

sub exportFunction {
	my $playlist;

	my $http;
	my @lines;
	
	return 0 if $export eq 'done';

	$isScanning = 1;

	# We need to use the datastore to get at our id's
	my $ds = Slim::Music::Info::getCurrentDataStore();
	
	$MMSport = Slim::Utils::Prefs::get('MMSport') unless $MMSport;
	$MMSHost = Slim::Utils::Prefs::get('MMSHost') unless $MMSHost;

	$::d_musicmagic && msg("MusicMagic: export mode is: $export\n");

	if ($export eq 'start') {

		$http = Slim::Player::Protocols::HTTP->new({
			'url'    => "http://$MMSHost:$MMSport/api/getSongCount",
			'create' => 0,
		});

		if ($http) {
			# convert to integer
			chomp($count = $http->content);

			$http->close;
		}

		$count += 0;

		$::d_musicmagic && msg("MusicMagic: Got $count song(s).\n");
		
		$scan = 0;
		$export = 'songs';
		return 1;
	}
	
	while ($export eq 'songs' && $scan <= $count) {
		my %cacheEntry = ();
		my %songInfo = ();
		
		$http = Slim::Player::Protocols::HTTP->new({
			'url'    => "http://$MMSHost:$MMSport/api/getSong?index=$scan",
			'create' => 0,
		}) || next;

		if ($http) {

			$scan++;
			@lines = split(/\n/, $http->content);
			my $count2 = scalar @lines;

			$http->close;

			for (my $j = 0; $j < $count2; $j++) {
				my ($song_field, $song_value) = $lines[$j] =~ /(\w+) (.*)/;
				$songInfo{$song_field} = $song_value;
			}
		
			$cacheEntry{'TRACKNUM'} = $songInfo{'track'};

			if ($songInfo{'bitrate'}) {
				$cacheEntry{'BITRATE'} = $songInfo{'bitrate'} * 1000;
			}

			$cacheEntry{'YEAR'}  = $songInfo{'year'};
			$cacheEntry{'CT'}    = Slim::Music::Info::typeFromPath($songInfo{'file'},'mp3');
			$cacheEntry{'TAG'}   = 1;
			$cacheEntry{'VALID'} = 1;
			$cacheEntry{'SECS'}  = $songInfo{'seconds'} if $songInfo{'seconds'};
		
			if ($songInfo{'active'} eq 'yes') {
				$cacheEntry{'MUSICMAGIC_MIXABLE'} = 1;
			}

			$::d_musicmagic && msg("MusicMagic: Exporting song $scan: $songInfo{'file'}\n");

			# Both Linux & Windows need conversion to the current charset.
			if (Slim::Utils::OSDetect::OS() ne 'mac') {
				$songInfo{'file'} = Slim::Utils::Unicode::utf8encode_locale($songInfo{'file'});
			}

			for my $key (qw(album artist genre name)) {

				my $enc = Slim::Utils::Unicode::encodingFromString($songInfo{$key});

				$songInfo{$key} = Slim::Utils::Unicode::utf8decode_guess($songInfo{$key}, $enc);
			}

			# Assign these after they may have been verified as UTF-8
			$cacheEntry{'ALBUM'}  = $songInfo{'album'};
			$cacheEntry{'TITLE'}  = $songInfo{'name'};
			$cacheEntry{'ARTIST'} = $songInfo{'artist'};
			$cacheEntry{'GENRE'}  = $songInfo{'genre'};
			if (defined $songInfo{'rating'}) {
				$cacheEntry{'RATING'} = $songInfo{'rating'} * 20; #make rating out of 100, MMM uses scale of 5
			}
		
			my $fileurl = Slim::Utils::Misc::fileURLFromPath($songInfo{'file'});

			my $track = $ds->updateOrCreate({

				'url'        => $fileurl,
				'attributes' => \%cacheEntry,
				'readTags'   => 1,

			}) || do {

				$::d_musicmagic && msg("MusicMagic: Couldn't create track for $fileurl!\n");
				next;
			};

			my $albumObj = $track->album;

			# NYI: MMM has more ways to access artwork...
			if (Slim::Utils::Prefs::get('lookForArtwork') && defined $albumObj) {

				if (!Slim::Music::Import::artwork($albumObj) && !defined $track->thumb) {

					Slim::Music::Import::artwork($albumObj, $track);
				}
			}

			if ($songInfo{'active'} eq 'yes') {

				if (defined $albumObj) {
					$albumObj->musicmagic_mixable(1);
					$albumObj->update;
				}

				for my $artistObj ($track->contributors) {
					$artistObj->musicmagic_mixable(1);
					$artistObj->update;
				}
				
				for my $genreObj ($track->genres) {
					$genreObj->musicmagic_mixable(1);
					$genreObj->update;
				}
			}
		}

		if ($scan == $count) {
			$export = 'playlists';
		}
		
		# would be nice to chunk this in groups.  One at a time is slow, 
		# but doing it all at once breaks audio up when its a full scan.
		return 1 if !($scan % 1);
	}

	if ($export eq 'genres') {

		$http = Slim::Player::Protocols::HTTP->new({
			'url'    => "http://$MMSHost:$MMSport/api/genres?active",
			'create' => 0,
		}) || return 1;

		@lines = split(/\n/, $http->content);
		$count = scalar @lines;
		$::d_musicmagic && msg("MusicMagic: Got $count active genre(s).\n");

		$http->close;
	
		for (my $i = 0; $i < $count; $i++) {

			my ($obj) = $ds->find({
				'field' => 'genre',
				'find'  => { 'genre.name' => $lines[$i] },
			});

			if ($obj) {
				$obj->musicmagic_mixable(1);
				$obj->update;
			}
		}

		$export = 'artists';

		return 1;
	}

	if ($export eq 'artists') {

		$http = Slim::Player::Protocols::HTTP->new({
			'url'    => "http://$MMSHost:$MMSport/api/artists?active",
			'create' => 0,
		}) || return 1;

		@lines = split(/\n/, $http->content);
		$count = scalar @lines;
		$::d_musicmagic && msg("MusicMagic: Got $count active artist(s).\n");

		$http->close;

		for (my $i = 0; $i < $count; $i++) {

			my ($obj) = $ds->find({
				'field' => 'contributor',
				'find'  => { 'contributor.name' => $lines[$i] },
			});

			if ($obj) {
				$obj->musicmagic_mixable(1);
				$obj->update;
			}
		}

		$export = 'playlists';
		return 1;
	}
	
	if ($export eq 'playlists') {

		if (@playlists) {
			my $i = $playlistindex -1;
			my %cacheEntry = ();
			my @songs = ();
			
			$http = Slim::Player::Protocols::HTTP->new({
				'url'    => "http://$MMSHost:$MMSport/api/getPlaylist?index=$playlistindex",
				'create' => 0,
			});

			if ($http) {
				@songs = split(/\n/, $http->content);
				my $count2 = scalar @songs;
				$http->close;
			
				my $name = shift @playlists;
				my $url = 'musicmagicplaylist:' . Slim::Utils::Misc::escape($name);
				$url = Slim::Utils::Misc::fixPath($url);

				# add this playlist to our playlist library
				$cacheEntry{'TITLE'} = join('', 
					Slim::Utils::Prefs::get('MusicMagicplaylistprefix'),
					$name,
					Slim::Utils::Prefs::get('MusicMagicplaylistsuffix'),
				);
				
				my @list = ();

				for (my $j = 0; $j < $count2; $j++) {
					push @list, Slim::Utils::Misc::fileURLFromPath(convertPath($songs[$j]));
				}

				$::d_musicmagic && msg("MusicMagic: got playlist $name with " .scalar @list." items.\n");

				$cacheEntry{'LIST'} = \@list;
				$cacheEntry{'CT'} = 'mmp';
				$cacheEntry{'TAG'} = 1;
				$cacheEntry{'VALID'} = '1';

				Slim::Music::Info::updateCacheEntry($url, \%cacheEntry);
				$playlistindex ++;
				
				# are we done with playlists?
				if (!@playlists) {
					$export = 'duplicates';
					$playlistindex = 0;
				}
			}
		} else {
			$http = Slim::Player::Protocols::HTTP->new({
				'url'    => "http://$MMSHost:$MMSport/api/playlists",
				'create' => 0,
			});
	
	
			if ($http) {
				@playlists = split(/\n/, $http->content);
				$playlistindex = 0;
				$http->close;
				$export = 'duplicates' unless @playlists;
			} else {
				$export = 'duplicates';
			}
		}
		
		return 1;
	}
	
	#check for dupes, but not with 1.1.3
	if ($export eq 'duplicates' && $initialized !~ m/1\.1\.3$/) {
		
		my %cacheEntry = ();
		my @songs = ();
		$::d_musicmagic && msg("MusicMagic: Checking for duplicates.\n");
		
		$http = Slim::Player::Protocols::HTTP->new({
			'url'    => "http://$MMSHost:$MMSport/api/duplicates",
			'create' => 0,
		});

		if ($http) {

			@songs = split(/\n/, $http->content);
			my $count = scalar @songs;
			$http->close;
		
			my $name = "Duplicates";
			my $url = 'musicmagicplaylist:' . Slim::Utils::Misc::escape($name);

			# add this list of duplicates to our playlist library
			$cacheEntry{'TITLE'} = join('', 
				Slim::Utils::Prefs::get('MusicMagicplaylistprefix'),
				$name,
				Slim::Utils::Prefs::get('MusicMagicplaylistsuffix'),
			);
			
			my @list;
			for (my $j = 0; $j < $count; $j++) {
				push @list, Slim::Utils::Misc::fileURLFromPath(convertPath($songs[$j]));
			}

			$cacheEntry{'LIST'} = \@list;
			$cacheEntry{'CT'} = 'mmp';
			$cacheEntry{'TAG'} = 1;
			$cacheEntry{'VALID'} = '1';

			Slim::Music::Info::updateCacheEntry($url, \%cacheEntry);
		}
	}

	$::d_musicmagic && msgf("MusicMagic: finished export (%d records)\n",$scan - 1);

	doneScanning();

	$export = 'done';
	
	return 0;
}

sub specialPushLeft {
	my $client   = shift;
	my $step     = shift;

	my $now  = Time::HiRes::time();
	my $when = $now + 0.5;
	
	my $mixer  = Slim::Utils::Strings::string('MUSICMAGIC_MIXING');

	if ($step == 0) {

		Slim::Buttons::Common::pushMode($client, 'block');
		$client->pushLeft(undef, { 'line1' => $mixer });
		Slim::Utils::Timers::setTimer($client,$when,\&specialPushLeft,$step+1);

	} elsif ($step == 3) {

		Slim::Buttons::Common::popMode($client);
		$client->pushLeft( { 'line1' => $mixer."..." }, undef);

	} else {

		$client->update( { 'line1' => $mixer.("." x $step) });
		Slim::Utils::Timers::setTimer($client,$when,\&specialPushLeft,$step+1);
	}
}

sub mixerFunction {
	my ($client, $noSettings) = @_;

	# look for parentParams (needed when multiple mixers have been used)
	my $paramref = defined $client->param('parentParams') ? $client->param('parentParams') : $client->modeParameterStack(-1);
	
	# if prefs say to offer player settings, and we're not already in that mode, then go into settings.
	if (Slim::Utils::Prefs::get('MMMPlayerSettings') && !$noSettings) {

		Slim::Buttons::Common::pushModeLeft($client, 'MMMsettings', { 'parentParams' => $paramref });
		return;

	}

	my $listIndex = $paramref->{'listIndex'};
	my $items     = $paramref->{'listRef'};
	my $hierarchy = $paramref->{'hierarchy'};
	my $level     = $paramref->{'level'} || 0;
	my $descend   = $paramref->{'descend'};

	my @levels    = split(",", $hierarchy);
	my $ds        = Slim::Music::Info::getCurrentDataStore();
	my $mix       = [];
	my $mixSeed   = '';

	my $currentItem = $items->[$listIndex];

	# start by checking for moods
	if ($paramref->{'mood'}) {
		$mixSeed = $currentItem;
		$levels[$level] = 'mood';
	
	# if we've chosen a particular song
	} elsif (!$descend || $levels[$level] eq 'track') {

		$mixSeed = $currentItem->path;

	} elsif ($levels[$level] eq 'album') {

		$mixSeed = $currentItem->tracks->next->path;

	} elsif ($levels[$level] eq 'artist' || $levels[$level] eq 'genre') {

		$mixSeed = $currentItem->name;
	}

	if ($currentItem && ($paramref->{'mood'} || $currentItem->musicmagic_mixable)) {

		# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
		$mix = getMix($client, $mixSeed, $levels[$level]);
	}

	if (defined $mix && ref($mix) eq 'ARRAY' && scalar @$mix) {

		my %params = (
			'listRef'        => $mix,
			'externRef'      => \&Slim::Music::Info::standardTitle,
			'header'         => 'MUSICMAGIC_MIX',
			'headerAddCount' => 1,
			'stringHeader'   => 1,
			'callback'       => \&mixExitHandler,
			'overlayRef'     => sub { return (undef, Slim::Display::Display::symbol('rightarrow')) },
			'overlayRefArgs' => '',
			'parentMode'     => 'musicmagic_mix',
		);
		
		Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);

		specialPushLeft($client, 0);

	} else {

		# don't do anything if nothing is mixable
		$client->bumpRight;
	}
}

sub mixerlink {
	my $item = shift;
	my $form = shift;
	my $descend = shift;

	if ($descend) {
		$form->{'mmmixable_descend'} = 1;
	} else {
		$form->{'mmmixable_not_descend'} = 1;
	}

	if ($item->musicmagic_mixable && canUseMusicMagic() && Slim::Utils::Prefs::get('musicmagic')) {
		#set up a musicmagic link
		#Slim::Web::Pages->addPageLinks("mixer", {'MUSICMAGIC' => "plugins/MusicMagic/mixerlink.html"}, 1);
		$form->{'mixerlinks'}{'MUSICMAGIC'} = "plugins/MusicMagic/mixerlink.html";
	} else {
		#Slim::Web::Pages->addPageLinks("mixer", {'MUSICMAGIC' => undef});
	}

	return $form;
}

sub mixExitHandler {
	my ($client,$exittype) = @_;
	
	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {

		my $valueref = $client->param('valueRef');

		Slim::Buttons::Common::pushMode($client, 'trackinfo', { 'track' => $$valueref });

		$client->pushLeft();
	}
}

sub getMix {
	my $client = shift;
	my $id = shift;
	my $for = shift;

	my @mix = ();
	my $req;
	my $res;
	my @type = qw(tracks min mbytes);
	
	my %args;
	 
	if (defined $client) {
		%args = (
			# Set the size of the list (default 12)
			size	   => $client->prefGet('MMMSize') || Slim::Utils::Prefs::get('MMMSize'),
	
			# (tracks|min|mb) Set the units for size (default tracks)
			sizetype   => $type[$client->prefGet('MMMMixType') || Slim::Utils::Prefs::get('MMMMixType')],
	
			# Set the style slider (default 20)
			style	   => $client->prefGet('MMMStyle') || Slim::Utils::Prefs::get('MMMStyle'),
	
			# Set the variety slider (default 0)
			variety	   => $client->prefGet('MMMVariety') || Slim::Utils::Prefs::get('MMMVariety'),

			# mix genres or stick with that of the seed. (Default: match seed)
			mixgenre   => $client->prefGet('MMMMixGenre') || Slim::Utils::Prefs::get('MMMMixGenre'),
	
			# Set the number of songs before allowing dupes (default 12)
			rejectsize => $client->prefGet('MMMRejectSize') || Slim::Utils::Prefs::get('MMMRejectSize'),
	
			# (tracks|min|mb) Set the units for rejecting dupes (default tracks)
			rejecttype => $type[$client->prefGet('MMMRejectType') || Slim::Utils::Prefs::get('MMMRejectType')],
		);
	} else {
		%args = (
			# Set the size of the list (default 12)
			size	   => Slim::Utils::Prefs::get('MMMSize') || 12,
	
			# (tracks|min|mb) Set the units for size (default tracks)
			sizetype   => $type[Slim::Utils::Prefs::get('MMMMixType') || 0],
	
			# Set the style slider (default 20)
			style	   => Slim::Utils::Prefs::get('MMMStyle') || 20,
	
			# Set the variety slider (default 0)
			variety	   => Slim::Utils::Prefs::get('MMMVariety') || 0,

			# mix genres or stick with that of the seed. (Default: match seed)
			mixgenre   => Slim::Utils::Prefs::get('MMMMixGenre') || 0,
	
			# Set the number of songs before allowing dupes (default 12)
			rejectsize => Slim::Utils::Prefs::get('MMMRejectSize') || 12,
	
			# (tracks|min|mb) Set the units for rejecting dupes (default tracks)
			rejecttype => $type[Slim::Utils::Prefs::get('MMMRejectType') || 0],
		);
	}

	my $filter = defined $client ? $client->prefGet('MMMFilter') || Slim::Utils::Prefs::get('MMMFilter') : Slim::Utils::Prefs::get('MMMFilter');

	if ($filter) {
		$::d_musicmagic && msg("MusicMagic: filter $filter in use.\n");

		$args{'filter'} = Slim::Utils::Misc::escape($filter);
	}

	my $argString = join( '&', map { "$_=$args{$_}" } keys %args );

	unless ($validMixTypes{$for}) {

		$::d_musicmagic && msg("MusicMagic: no valid type specified for mix\n");
		return undef;
	}

	# Not sure if this is correct yet.
	if ($validMixTypes{$for} ne 'song' && $validMixTypes{$for} ne 'album') {

		$id = Slim::Utils::Unicode::utf8encode_locale($id);
	}

	$::d_musicmagic && msg("MusicMagic: Creating mix for: $validMixTypes{$for} using: $id as seed.\n");

	my $mixArgs = "$validMixTypes{$for}=$id";

	# url encode the request, but not the argstring
	# Bug: 1938 - Don't encode to UTF-8 before escaping on Mac & Win
	# We might need to do the same on Linux, but I can't get UTF-8 files
	# to show up properly in MMM right now.
	if (Slim::Utils::OSDetect::OS() eq 'win' || Slim::Utils::OSDetect::OS() eq 'mac') {

		$mixArgs = URI::Escape::uri_escape($mixArgs);
	} else {
		$mixArgs = Slim::Utils::Misc::escape($mixArgs);
	}
	
	$::d_musicmagic && msg("Musicmagic: request http://$MMSHost:$MMSport/api/mix?$mixArgs\&$argString\n");

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/mix?$mixArgs\&$argString",
		'create' => 0,
	});

	unless ($http) {
		# NYI
		$::d_musicmagic && msg("Musicmagic Error - Couldn't get mix: $mixArgs\&$argString\n");
		return @mix;
	}

	my @songs = split(/\n/, $http->content);
	my $count = scalar @songs;

	$http->close;

	for (my $j = 0; $j < $count; $j++) {
		my $newPath = convertPath($songs[$j]);

		$::d_musicmagic && msg("MusicMagic: Original $songs[$j] : New $newPath\n");

		push @mix, Slim::Utils::Misc::fileURLFromPath($newPath);
	}

	return \@mix;
}

sub webPages {
	my %pages = (
		"musicmagic_mix\.(?:htm|xml)" => \&musicmagic_mix,
		"musicmagic_moods\.(?:htm|xml)" => \&musicmagic_moods,
	);

	return (\%pages);
}

sub musicmagic_moods {
	my ($client, $params) = @_;

	my $items = "";

	$items = grabMoods();

	$params->{'mood_list'} = $items;

	return Slim::Web::HTTP::filltemplatefile("plugins/MusicMagic/musicmagic_moods.html", $params);
}

sub musicmagic_mix {
	my ($client, $params) = @_;

	my $output = "";
	my $mix;

	my $song     = $params->{'song'};
	my $artist   = $params->{'artist'};
	my $album    = $params->{'album'};
	my $genre    = $params->{'genre'};
	my $mood     = $params->{'mood'};
	my $player   = $params->{'player'};
	my $playlist = $params->{'playlist'};
	my $p0       = $params->{'p0'};

	my $itemnumber = 0;
	my $ds = Slim::Music::Info::getCurrentDataStore();
	$params->{'browse_items'} = [];
	$params->{'levelName'} = "track";

	if ($mood) {
		$mix = getMix($client, $mood, 'mood');
		$params->{'src_mix'} = Slim::Music::Info::standardTitle(undef, $mood);

	} elsif ($playlist) {
		my ($obj) = $ds->objectForUrl($playlist);

		if (blessed($obj) && $obj->can('musicmagic_mixable')) {

			if ($obj->musicmagic_mixable) {

				# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
				$mix = getMix($client, $playlist, 'playlist');
			}

			$params->{'src_mix'} = Slim::Music::Info::standardTitle(undef, $obj);
		}
	} elsif ($song) {

		my ($obj) = $ds->objectForId('track', $song);

		if (blessed($obj) && $obj->can('musicmagic_mixable')) {

			if ($obj->musicmagic_mixable) {

				# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
				$mix = getMix($client, $obj->path, 'track');
			}

			$params->{'src_mix'} = Slim::Music::Info::standardTitle(undef, $obj);
		}

	} elsif ($artist && !$album) {

		my ($obj) = $ds->objectForId('contributor', $artist);

		if (blessed($obj) && $obj->can('musicmagic_mixable') && $obj->musicmagic_mixable) {

			# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
			$mix = getMix($client, $obj->name, 'artist');
		}

	} elsif ($album) {

		my ($obj) = $ds->objectForId('album', $album);
		
		if (blessed($obj) && $obj->can('musicmagic_mixable') && $obj->musicmagic_mixable) {

			my $trackObj = $obj->tracks->next;

			# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
			if ($trackObj) {

				$mix = getMix($client, $trackObj->path, 'album');
			}
		}
		
	} elsif ($genre && $genre ne "*") {

		my ($obj) = $ds->objectForId('genre', $genre);

		if (blessed($obj) && $obj->can('musicmagic_mixable') && $obj->musicmagic_mixable) {

			# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
			$mix = getMix($client, $obj->name, 'genre');
		}
	
	} else {

		$::d_musicmagic && msg('MusicMagic: no/unknown type specified for mix\n');
		return 1;
	}

	if (defined $mix && ref $mix eq "ARRAY" && defined $client) {
		# We'll be using this to play the entire mix using 
		# playlist (add|play|load|insert)tracks listref=musicmagic_mix
		$client->param('musicmagic_mix',$mix);
	} else {
		$mix = [];
	}

	$params->{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("plugins/MusicMagic/musicmagic_pwdlist.html", $params)};

	if (scalar @$mix) {

		push @{$params->{'browse_items'}}, {

			'text'         => Slim::Utils::Strings::string('THIS_ENTIRE_PLAYLIST'),
			'attributes'   => "&listRef=musicmagic_mix",
			'odd'          => ($itemnumber + 1) % 2,
			'webroot'      => $params->{'webroot'},
			'skinOverride' => $params->{'skinOverride'},
			'player'       => $params->{'player'},
		};

		$itemnumber++;
	}

	for my $item (@$mix) {

		my %list_form = %$params;
		my $fieldInfo = Slim::DataStores::Base->fieldInfo;

		# If we can't get an object for this url, skip it, as the
		# user's database is likely out of date. Bug 863
		my $trackObj  = $ds->objectForUrl($item);

		if (!blessed($trackObj) || !$trackObj->can('id')) {

			next;
		}
		
		my $itemname = &{$fieldInfo->{'track'}->{'resultToName'}}($trackObj);

		&{$fieldInfo->{'track'}->{'listItem'}}($ds, \%list_form, $trackObj, $itemname, 0);

		$list_form{'attributes'} = '&track=' . Slim::Utils::Misc::escape($trackObj->id);

		$list_form{'odd'}        = ($itemnumber + 1) % 2;

		$itemnumber++;

		push @{$params->{'browse_items'}}, \%list_form;
	}

	if (defined $p0 && defined $client) {
		$client->execute(["playlist", $p0 eq "append" ? "addtracks" : "playtracks", "listref=musicmagic_mix"]);
	}

	return Slim::Web::HTTP::filltemplatefile("plugins/MusicMagic/musicmagic_mix.html", $params);
}

sub playerGroup {

	my %group = (
		'Groups' => {
			'Default' => {
				'PrefOrder' => [qw(MMMSize MMMMixType MMMStyle MMMVariety MMMFilter MMMMixGenre MMMRejectType MMMRejectSize)]
			},
		},
	);
	
	return \%group;
}

sub setupUse {
	my $client = shift;

	my %setupGroup = (
		'PrefOrder'         => ['musicmagic'],
		'PrefsInTable'      => 1,
		'Suppress_PrefLine' => 1,
		'Suppress_PrefSub'  => 1,
		'GroupLine'         => 1,
		'GroupSub'          => 1,
	);

	my %setupPrefs = (

		'musicmagic'  => {
			'validate'    => \&Slim::Utils::Validate::trueFalse,
			'changeIntro' => "",

			'options' => {
				'1' => Slim::Utils::Strings::string('USE_MUSICMAGIC'),
				'0' => Slim::Utils::Strings::string('DONT_USE_MUSICMAGIC'),
			},

			'onChange' => sub {
				my ($client,$changeref,$paramref,$pageref) = @_;
				
				foreach my $client (Slim::Player::Client::clients()) {
					Slim::Buttons::Home::updateMenu($client);
				}

				Slim::Music::Import::useImporter('MUSICMAGIC',$changeref->{'musicmagic'}{'new'});
				Slim::Music::Info::clearPlaylists('musicmagicplaylist:');
				Slim::Music::Import::startScan('MUSICMAGIC');
			},

			'optionSort' => 'KR',
			'inputTemplate' => 'setup_input_radio.html',
		}
	);

	return (\%setupGroup,\%setupPrefs);
}

sub setupGroup {
	my $category = &setupCategory;

	$category->{'parent'}     = 'PLAYER_SETTINGS';
	$category->{'GroupOrder'} = ['Default'];
	$category->{'Groups'}     = &playerGroup->{'Groups'};

	return ($category->{'Groups'}->{'Default'}, $category->{'Prefs'},1);
}


sub setupPort {

	my $client = shift;

	my %setupGroup = (
			'PrefOrder' => [qw(MMSport)]
		);

	my %setupPrefs;
	$setupPrefs{'MMSport'} = &setupCategory->{'Prefs'}->{'MMSport'};

	return (\%setupGroup,\%setupPrefs);
};

sub setupCategory {
	
	my %setupCategory = (

		'title' => Slim::Utils::Strings::string('SETUP_MUSICMAGIC'),
		'parent' => 'SERVER_SETTINGS',
		'GroupOrder' => ['Default','MusicMagicPlaylistFormat'],
		'Groups' => {

			'Default' => {
				'PrefOrder' => [qw(MMMPlayerSettings MMMSize MMMMixType MMMStyle MMMVariety MMMMixGenre MMMRejectType MMMRejectSize MMMFilter musicmagicscaninterval MMSport)]
				
				# disable remote host access, its confusing and only works in specific cases
				# leave it here for hackers who really want to try it
				#'PrefOrder' => [qw(MMMSize MMMMixType MMMStyle MMMVariety musicmagicscaninterval MMSport MMSHost MMSremoteRoot)]
			},

			'MusicMagicPlaylistFormat' => {
				'PrefOrder'         => ['MusicMagicplaylistprefix','MusicMagicplaylistsuffix'],
				'PrefsInTable'      => 1,
				'Suppress_PrefHead' => 1,
				'Suppress_PrefDesc' => 1,
				'Suppress_PrefLine' => 1,
				'Suppress_PrefSub'  => 1,
				'GroupHead'         => Slim::Utils::Strings::string('SETUP_MUSICMAGICPLAYLISTFORMAT'),
				'GroupDesc'         => Slim::Utils::Strings::string('SETUP_MUSICMAGICPLAYLISTFORMAT_DESC'),
				'GroupLine'         => 1,
				'GroupSub'          => 1,
			}
		},

		'Prefs' => {
			'MMMPlayerSettings' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				,'options' => {
						'1'  => Slim::Utils::Strings::string('YES')
						,'0' => Slim::Utils::Strings::string('NO')
					}
			},

			'MusicMagicplaylistprefix' => {
				'validate' => \&Slim::Utils::Validate::acceptAll,
				'PrefSize' => 'large',
			},

			'MusicMagicplaylistsuffix' => {
				'validate' => \&Slim::Utils::Validate::acceptAll,
				'PrefSize' => 'large',
			},

			'musicmagicscaninterval' => {
				'validate'     => \&Slim::Utils::Validate::number,
				'validateArgs' => [0,undef,1000],
			},

			,'MMMFilter' => {
				'validate'      => \&Slim::Utils::Validate::inHash
				,'validateArgs' => [\&grabFilters]
				,'options'      => {grabFilters()}
			},
			
			'MMMSize' => {
				'validate'     => \&Slim::Utils::Validate::isInt,
				'validateArgs' => [1,undef,1]
			},
			
			'MMMRejectSize' => {
				'validate'     => \&Slim::Utils::Validate::isInt,
				'validateArgs' => [1,undef,1]
			},
			
			'MMMMixType' => {
				'validate'     => \&Slim::Utils::Validate::inList,
				'validateArgs' => [0,1,2],
				'options'      => {
					'0' => Slim::Utils::Strings::string('MMMMIXTYPE_TRACKS'),
					'1' => Slim::Utils::Strings::string('MMMMIXTYPE_MIN'),
					'2' => Slim::Utils::Strings::string('MMMMIXTYPE_MBYTES'),
				}
			},
			
			'MMMRejectType' => {
				'validate'     => \&Slim::Utils::Validate::inList,
				'validateArgs' => [0,1,2],
				'options'      => {
					'0' => Slim::Utils::Strings::string('MMMMIXTYPE_TRACKS'),
					'1' => Slim::Utils::Strings::string('MMMMIXTYPE_MIN'),
					'2' => Slim::Utils::Strings::string('MMMMIXTYPE_MBYTES'),
				}
			},
			
			'MMMMixGenre' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				,'options' => {
						'1'  => Slim::Utils::Strings::string('YES')
						,'0' => Slim::Utils::Strings::string('NO')
					}
			},
			
			'MMMStyle' => {
				'validate'     => \&Slim::Utils::Validate::isInt,
				'validateArgs' => [0,200,1,1],
			},

			'MMMVariety' => {
				'validate'     => \&Slim::Utils::Validate::isInt,
				'validateArgs' => [0,9,1,1],
			},

			'MMSport' => {
				'validate'     => \&Slim::Utils::Validate::isInt,
				'validateArgs' => [1025,65535,undef,1],
			},

			'MMSHost' => {
				'validate' => \&Slim::Utils::Validate::acceptAll,
				'PrefSize' => 'large'
			},

			'MMSremoteRoot'=> {
				'validate' =>  \&Slim::Utils::Validate::acceptAll,
				'PrefSize' => 'large'
			}
		}
	);

	return (\%setupCategory);
};

sub checkDefaults {

	if (!Slim::Utils::Prefs::isDefined('musicmagic')) {
		Slim::Utils::Prefs::set('musicmagic',0)
	}

	if (!Slim::Utils::Prefs::isDefined('MMMMixType')) {
		Slim::Utils::Prefs::set('MMMMixType',0)
	}

	if (!Slim::Utils::Prefs::isDefined('MMMStyle')) {
		Slim::Utils::Prefs::set('MMMStyle',0);
	}

	if (!Slim::Utils::Prefs::isDefined('MMMVariety')) {
		Slim::Utils::Prefs::set('MMMVariety',0);
	}

	if (!Slim::Utils::Prefs::isDefined('MMMSize')) {
		Slim::Utils::Prefs::set('MMMSize',12);
	}

	if (!Slim::Utils::Prefs::isDefined('MMMMixGenre')) {
		Slim::Utils::Prefs::set('MMMMixGenre',0);
	}

	if (!Slim::Utils::Prefs::isDefined('MMMRejectSize')) {
		Slim::Utils::Prefs::set('MMMRejectSize',12);
	}

	if (!Slim::Utils::Prefs::isDefined('MMMRejectType')) {
		Slim::Utils::Prefs::set('MMMRejectType',0);
	}

	if (!Slim::Utils::Prefs::isDefined('MusicMagicplaylistprefix')) {
		Slim::Utils::Prefs::set('MusicMagicplaylistprefix','MusicMagic: ');
	}

	if (!Slim::Utils::Prefs::isDefined('MusicMagicplaylistsuffix')) {
		Slim::Utils::Prefs::set('MusicMagicplaylistsuffix','');
	}

	if (!Slim::Utils::Prefs::isDefined('musicmagicscaninterval')) {
		Slim::Utils::Prefs::set('musicmagicscaninterval',60);
	}

	if (!Slim::Utils::Prefs::isDefined('MMSport')) {
		Slim::Utils::Prefs::set('MMSport',10002);
	}

	if (!Slim::Utils::Prefs::isDefined('MMSHost')) {
		Slim::Utils::Prefs::set('MMSHost','localhost');
	}
}

1;

__END__
