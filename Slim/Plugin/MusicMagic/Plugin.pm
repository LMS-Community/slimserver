package Slim::Plugin::MusicMagic::Plugin;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Scalar::Util qw(blessed);
use LWP::UserAgent;

use Slim::Player::ProtocolHandlers;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(cstring);
use Slim::Utils::Prefs;

use Slim::Plugin::MusicMagic::Settings;
use Slim::Plugin::MusicMagic::ClientSettings;

use Slim::Plugin::MusicMagic::Common;
use Slim::Plugin::MusicMagic::PlayerSettings;

use Slim::Utils::Favorites;

my $initialized = 0;
my $MMSHost;
my $MMSport;
my $canPowerSearch;

my $isWin = Slim::Utils::OSDetect::isWindows();

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.musicip',
	'defaultLevel' => 'ERROR',
});

my $prefs = preferences('plugin.musicip');

our %mixMap  = (
	'add.single' => 'play_1',
	'add.hold'   => 'play_2'
);

our %mixFunctions = ();

our %validMixTypes = (
	'track'    => 'song',
	'album'    => 'album',
	'age'      => 'album',
	'artist'   => 'artist',
	'genre'    => 'filter',
	'mood'     => 'mood',
	'playlist' => 'playlist',
	'year'     => 'filter=?year',
);

sub getFunctions {
	return '';
}

sub useMusicMagic {
	my $newValue = shift;
	my $can = canUseMusicMagic();
	
	if (defined($newValue)) {
		if (!$can) {
			$prefs->set('musicip', 0);
		} else {
			$prefs->set('musicip', $newValue);
		}
	}
	
	my $use = $prefs->get('musicip');
	
	if (!defined($use) && $can) { 
		$prefs->set('musicip', 1);
	} elsif (!defined($use) && !$can) {
		$prefs->set('musicip', 0);
	}
	
	$use = $prefs->get('musicip') && $can;

	$log->info("Using musicip: $use");

	return $use;
}

sub isRunning {
	return $initialized;
}

sub canUseMusicMagic {
	return $initialized || __PACKAGE__->initPlugin();
}

sub getDisplayName {
	return 'SETUP_MUSICMAGIC';
}

sub enabled {
	return ($::VERSION ge '6.1') && __PACKAGE__->initPlugin();
}

sub shutdownPlugin {

	# turn off checker
	Slim::Utils::Timers::killTimers(undef, \&checker);

	# disable protocol handler?
	Slim::Player::ProtocolHandlers->registerHandler('musicipplaylist', 0);

	$initialized = 0;

	# set importer to not use, but only for this session. leave server
	# pref as is to support reenabling the features, without needing a
	# forced rescan
	Slim::Music::Import->useImporter('Slim::Plugin::MusicMagic::Plugin', 0);
}

sub initPlugin {
	my $class = shift;

	return 1 if $initialized;

	# read enabled status before checkDefaults to ensure a first time initialization
	my $enabled = $prefs->get('musicip');
	
	Slim::Plugin::MusicMagic::Common::checkDefaults();
	Slim::Plugin::MusicMagic::Settings->new;

	# don't test the connection if MIP integration is disabled
	# but continue if it had never been initialized
	return unless $enabled || !defined $enabled;

	my $response = _syncHTTPRequest("/api/version");

	$log->info("Testing for API on $MMSHost:$MMSport");

	if ($response->is_error) {

		$initialized = 0;
		
		$prefs->set('musicip', 0) if !defined $enabled;

		$log->error("Can't connect to port $MMSport - MusicIP disabled.");

	} else {

		my $content = $response->content;

		if ( $log->is_info ) {
			$log->info($content);
		}

		# if this is the first time MIP is initialized, have it use
		# - faster mixable status only scan (2) if a music folder is defined
		# - slower full metadata import (1) if no music folder is defined
		$prefs->set('musicip', preferences('server')->get('audiodir') ? 2 : 1)  if !defined $enabled;

		# this query should return an API error if Power Search is not available
		$response = _syncHTTPRequest("/api/mix?filter=?length>120&length=1");

		if ($response->is_success && $response->content !~ /MusicIP API error/i) {
			$canPowerSearch = 1;

			$log->info('Power Search enabled');
		}

		Slim::Plugin::MusicMagic::PlayerSettings::init();

		# Note: Check version restrictions if any
		$initialized = $content;

		checker($initialized);

		# addImporter for Plugins, may include mixer function, setup function, mixerlink reference and use on/off.
		Slim::Music::Import->addImporter($class, {
			'mixer'     => \&mixerFunction,
			'mixerlink' => \&mixerlink,
			'use'       => $prefs->get('musicip'),
			'cliBase'   => {
					player => 0,
					cmd    => ['musicip', 'mix'],
					params => {
						menu => '1',
					},
					itemsParams => 'params',
			},
			'contextToken' => 'MUSICMAGIC_MIX',
		});

		Slim::Player::ProtocolHandlers->registerHandler('musicipplaylist', 0);

		# initialize the filter list
		Slim::Plugin::MusicMagic::Settings->grabFilters();
		
		Slim::Plugin::MusicMagic::ClientSettings->new;

		Slim::Control::Request::addDispatch(['musicip', 'mix'],
			[1, 1, 1, \&cliMix]);

		Slim::Control::Request::addDispatch(['musicip', 'moods'],
			[1, 1, 1, \&cliMoods]);

		Slim::Control::Request::addDispatch(['musicip', 'play'],
			[1, 0, 0, \&cliPlayMix]);

		Slim::Control::Request::addDispatch(['musicip', 'add'],
			[1, 0, 0, \&cliPlayMix]);

		Slim::Control::Request::addDispatch(['musicip', 'insert'],
			[1, 0, 0, \&cliPlayMix]);

		Slim::Player::ProtocolHandlers->registerHandler(
			mood => 'Slim::Plugin::MusicMagic::ProtocolHandler'
		);

		# Track Info handler
		Slim::Menu::TrackInfo->registerInfoProvider( musicmagic => (
			#menuMode => 1,
			above    => 'favorites',
			func     => \&trackInfoHandler,
		) );

		if (scalar @{grabMoods()}) {

			Slim::Buttons::Common::addMode('musicmagic_moods', {}, \&setMoodMode);

			my $params = {
				'useMode'  => 'musicmagic_moods',
				'mood'     => 'none',
			}; 
			Slim::Buttons::Home::addMenuOption('MUSICMAGIC_MOODS', $params);
			Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC', 'MUSICMAGIC_MOODS', $params);

			Slim::Web::Pages->addPageLinks("browse", {
				'MUSICMAGIC_MOODS' => "plugins/MusicMagic/musicmagic_moods.html"
			});

			Slim::Web::Pages->addPageLinks("icons", {
				'MUSICMAGIC_MOODS' => "plugins/MusicMagic/html/images/icon.png"
			});
			
			Slim::Control::Jive::registerPluginMenu([{
				stringToken    => 'MUSICMAGIC_MOODS',
				weight         => 95,
				id             => 'moods',
				node           => 'myMusic',
				actions => {
					go => {
						player => 0,
						cmd    => [ 'musicip', 'moods' ],
						params => {
							menu     => 1,
						},
					},
				},
				window         => { titleStyle => 'moods' },
			}]);
		}
	}

	$mixFunctions{'play'} = \&playMix;

	Slim::Buttons::Common::addMode('musicmagic_mix', \%mixFunctions, \&setMixMode);
	Slim::Hardware::IR::addModeDefaultMapping('musicmagic_mix',\%mixMap);

	Slim::Web::HTTP::addPageFunction("musicmagic_mix.html" => \&musicmagic_mix);
	Slim::Web::HTTP::addPageFunction("musicmagic_moods.html" => \&musicmagic_moods);

	return $initialized;
}

sub defaultMap {
	#Slim::Buttons::Common::addMode('musicmagic_mix', \%mixFunctions);

	Slim::Hardware::IR::addModeDefaultMapping('musicmagic_mix', \%mixMap);
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

	my $line2 = $client->modeParam('stringHeader') ? $client->string($client->modeParam('header')) : $client->modeParam('header');
	
	$client->showBriefly({
		'line'    => [ $line1, $line2] ,
		'overlay' => [ $client->symbols('notesymbol'),],
	}, { 'duration' => 2});

	$client->execute(["playlist", $playAddInsert, "listref", $client->modeParam('listRef')]);
}

sub isMusicLibraryFileChanged {

	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&_cacheidOK,
		\&_musicipError,
		{
			timeout => 30,
		},
	);
	
	$http->get( "http://$MMSHost:$MMSport/api/cacheid?contents" );
}

sub _statusOK {
	my $http   = shift;
	my $params = $http->params('params');
	
	my $content = $http->content;
	chomp($content);
	
	$log->debug( "Read status $content" );
		
	my $fileMTime = $params->{fileMTime};

	# Only say "yes" if it has been more than one minute since we last finished scanning
	# and the file mod time has changed since we last scanned. Note that if we are
	# just starting, $lastMMMChange is undef, so both $fileMTime
	# will be greater than 0 and time()-0 will be greater than 180 :-)
	my $lastScanTime  = Slim::Music::Import->lastScanTime;
	my $lastMMMChange = Slim::Music::Import->lastScanTime('MMMLastLibraryChange');

	if ($fileMTime > $lastMMMChange) {

		my $scanInterval = $prefs->get('scan_interval');

		if ( $log->is_debug ) {
			$log->debug("MusicIP: music library has changed!");
			$log->debug("Details:");
			$log->debug("\tCurrCacheID  - $fileMTime");
			$log->debug("\tLastCacheID  - $lastMMMChange");
			$log->debug("\tInterval     - $scanInterval");
			$log->debug("\tLastScanTime - $lastScanTime");
		}

		if (!$scanInterval) {

			# only scan if scaninterval is non-zero.
			$log->info("Scan Interval set to 0, rescanning disabled");

			return 0;
		}

		if ($content !~ /idle/i) {

			# only scan if MIP is idle, not while it's analyzing
			$log->info("MusicIP is busy analyzing your music, skipping rescan");

			return 0;
		}

		if ((time - $lastScanTime) > $scanInterval) {

			Slim::Control::Request::executeRequest(undef, ['rescan']);
		}

		$log->info("Waiting for $scanInterval seconds to pass before rescanning");
	}

	return 0;
}

sub checker {
	my $firstTime = shift || 0;
	
	if (!$prefs->get('musicip')) {
		return;
	}

	if (!$firstTime && !Slim::Music::Import->stillScanning) {
	
		isMusicLibraryFileChanged();
	}

	# make sure we aren't doing this more than once...
	Slim::Utils::Timers::killTimers(undef, \&checker);

	# Call ourselves again after 120 seconds
	Slim::Utils::Timers::setTimer(undef, (Time::HiRes::time() + 120), \&checker);
}

sub _cacheidOK {
	my $http   = shift;
	my $params = $http->params('params');
	
	my $content = $http->content;
	chomp($content);
	
	$log->debug( "Read cacheid of $content" );
		
	$params->{fileMTime} = $content;
	
	#do status check
	$http = Slim::Networking::SimpleAsyncHTTP->new(
		\&_statusOK,
		\&_musicipError,
		{
			params  => $params,
			timeout => 30,
			error   => "Can't read status",
		},
	);
	
	$http->get( "http://$MMSHost:$MMSport/api/getStatus" );
}

sub _musicipError {
	my $http   = shift;
	my $error  = $http->params('error');
	my $params = $http->params('params');

	$log->error( $error || "MusicIP: http error, no response.");
}

sub prefName {
	my $class = shift;

	return lc($class->title);
}

sub title {
	my $class = shift;

	return 'MUSICMAGIC';
}

sub mixable {
	my $class = shift;
	my $item  = shift;
	
	if ($prefs->get('musicip') && blessed($item) && $item->can('musicmagic_mixable')) {

		return $item->musicmagic_mixable;
	}
}

sub grabMoods {
	my @moods    = ();
	my %moodHash = ();

	if (!$initialized) {
		return;
	}

	my $response = _syncHTTPRequest('/api/moods');

	if ($response->is_success) {

		@moods = split(/\n/, Slim::Utils::Unicode::utf8encode_locale($response->content));

		if ($log->is_debug && scalar @moods) {

			$log->debug("Found moods:");

			for my $mood (@moods) {

				$log->debug("\t$mood");
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

sub setMixMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	mixerFunction($client, $prefs->get('player_settings') ? 1 : 0);
}

sub specialPushLeft {
	my $client   = shift;
	my $step     = shift;

	my $now  = Time::HiRes::time();
	my $when = $now + 0.5;
	
	my $mixer  = Slim::Utils::Strings::string('MUSICMAGIC_MIXING');

	if ($step == 0) {

		Slim::Buttons::Common::pushMode($client, 'block');
		$client->pushLeft(undef, { 'line' => [$mixer,''] });
		Slim::Utils::Timers::setTimer($client,$when,\&specialPushLeft,$step+1);

	} elsif ($step == 3) {

		Slim::Buttons::Common::popMode($client);
		$client->pushLeft( { 'line' => [$mixer."...",''] }, undef);

	} else {

		$client->update( { 'line' => [$mixer.("." x $step),''] });
		Slim::Utils::Timers::setTimer($client,$when,\&specialPushLeft,$step+1);
	}
}

sub mixerFunction {
	my ($client, $noSettings, $track) = @_;

	# look for parentParams (needed when multiple mixers have been used)
	my $paramref = defined $client->modeParam('parentParams') ? $client->modeParam('parentParams') : $client->modeParameterStack->[-1];
	# if prefs say to offer player settings, and we're not already in that mode, then go into settings.
	if ($prefs->get('player_settings') && !$noSettings) {

		Slim::Buttons::Common::pushModeLeft($client, 'MMMsettings', { 'parentParams' => $paramref });
		return;

	}

	$track ||= $paramref->{'track'};
	my $trackinfo = ( defined($track) && blessed($track) && $track->path ) ? 1 : 0;

	my $listIndex = $paramref->{'listIndex'};
	my $items     = $paramref->{'listRef'};
	my $hierarchy = $paramref->{'hierarchy'};
	my $level     = $paramref->{'level'} || 0;
	my $descend   = $paramref->{'descend'};

	my @levels    = split(",", $hierarchy);
	my $mix       = [];
	my $mixSeed   = '';

	my $currentItem = $items->[$listIndex];

	# start by checking for a passed track (trackinfo)
	if ( $trackinfo ) {
		$currentItem = $track;
		$levels[$level] = 'track';
	# then moods
	} elsif ($paramref->{'mood'}) {
		$mixSeed = $currentItem;
		$levels[$level] = 'mood';
	
	# if we've chosen a particular song
	} elsif (!$descend || $levels[$level] eq 'track') {

		$mixSeed = $currentItem->path;

	} elsif ($levels[$level] eq 'album' || $levels[$level] eq 'age') {

		$mixSeed = $currentItem->tracks->next->path;

	} elsif ($levels[$level] eq 'contributor') {
		
		# MusicIP uses artist instead of contributor.
		$levels[$level] = 'artist';
		$mixSeed = $currentItem->name;
	
	} elsif ($levels[$level] eq 'genre') {
		
		$mixSeed = $currentItem->name;
	}

	# Bug: 7478: special handling for playlist tracks.
	if ($levels[$level] eq 'playlistTrack' || $trackinfo ) {

		$mixSeed = $currentItem->path;
		$mix = getMix($client, $mixSeed, 'track');

	} elsif ($currentItem && ($paramref->{'mood'} || $currentItem->musicmagic_mixable)) {

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
			'overlayRef'     => sub { return (undef, shift->symbols('rightarrow')) },
			'overlayRefArgs' => 'C',
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

	Slim::Web::HTTP::protectURI('plugins/MusicMagic/.*\.html');
	# only add link if enabled and usable
	if (canUseMusicMagic() && $prefs->get('musicip')) {

		# set up a musicip link
		$form->{'mixerlinks'}{Slim::Plugin::MusicMagic::Plugin->title()} = "plugins/MusicMagic/mixerlink.html";
		
		# flag if mixable
		if (($item->can('musicmagic_mixable') && $item->musicmagic_mixable) ||
			($canPowerSearch && defined $form->{'levelName'} && $form->{'levelName'} eq 'year')) {

			$form->{'musicmagic_mixable'} = 1;
		}
	}

	return $form;
}

sub mixExitHandler {
	my ($client,$exittype) = @_;
	
	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {

		my $valueref = $client->modeParam('valueRef');

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
			'size'       => $prefs->client($client)->get('mix_size') || $prefs->get('mix_size'),
	
			# (tracks|min|mb) Set the units for size (default tracks)
			'sizetype'   => $type[$prefs->client($client)->get('mix_type') || $prefs->get('mix_type')],
	
			# Set the style slider (default 20)
			'style'      => $prefs->client($client)->get('mix_style') || $prefs->get('mix_style'),
	
			# Set the variety slider (default 0)
			'variety'    => $prefs->client($client)->get('mix_variety') || $prefs->get('mix_variety'),

			# mix genres or stick with that of the seed. (Default: match seed)
			'mixgenre'   => $prefs->client($client)->get('mix_genre') || $prefs->get('mix_genre'),
	
			# Set the number of songs before allowing dupes (default 12)
			'rejectsize' => $prefs->client($client)->get('reject_size') || $prefs->get('reject_size'),
		);
	} else {
		%args = (
			# Set the size of the list (default 12)
			'size'       => $prefs->get('mix_size') || 12,
	
			# (tracks|min|mb) Set the units for size (default tracks)
			'sizetype'   => $type[$prefs->get('mix_type') || 0],
	
			# Set the style slider (default 20)
			'style'      => $prefs->get('mix_style') || 20,
	
			# Set the variety slider (default 0)
			'variety'    => $prefs->get('mix_variety') || 0,

			# mix genres or stick with that of the seed. (Default: match seed)
			'mixgenre'   => $prefs->get('mix_genre') || 0,
	
			# Set the number of songs before allowing dupes (default 12)
			'rejectsize' => $prefs->get('reject_size') || 12,
		);
	}

	# (tracks|min|mb) Set the units for rejecting dupes (default tracks)
	my $rejectType = defined $client ?
		($prefs->client($client)->get('reject_type') || $prefs->get('reject_type')) : 
		($prefs->get('reject_type') || 0);
	
	# assign only if a rejectType found.  suppresses a warning when trying to access the array with no value.
	if ($rejectType) {
		$args{'rejecttype'} = $type[$rejectType];
	}

	my $filter = defined $client ? $prefs->client($client)->get('mix_filter') || $prefs->get('mix_filter') : $prefs->get('mix_filter');

	if ($filter) {

		$filter = Slim::Utils::Unicode::utf8decode_locale($filter);

		$log->debug("Filter $filter in use.");

		$args{'filter'} = Slim::Plugin::MusicMagic::Common::escape($filter);
	}

	my $argString = join( '&', map { "$_=$args{$_}" } keys %args );

	if (!$validMixTypes{$for}) {

		$log->debug("No valid type specified for mix");

		return undef;
	}

	$log->debug("Creating mix for: $validMixTypes{$for} using: $id as seed.");

	if (!$isWin && ($validMixTypes{$for} eq 'song' || $validMixTypes{$for} eq 'album') ) {

		# need to decode the file path when a file is used as seed
		$id = Slim::Utils::Unicode::utf8decode_locale($id);
	}

	my $mixArgs = "$validMixTypes{$for}=$id";

	# url encode the request, but not the argstring
	$mixArgs = Slim::Plugin::MusicMagic::Common::escape($mixArgs);
	
	$log->debug("Request http://$MMSHost:$MMSport/api/mix?$mixArgs\&$argString");

	my $response = _syncHTTPRequest("/api/mix?$mixArgs\&$argString");

	if ($response->is_error) {

		if ($response->code == 500 && $filter) {
			
			::idleStreams();

			# try again without the filter

			$log->warn("No mix returned with filter involved - we might want to try without it");
			$argString =~ s/filter=/xfilter=/;
			$response = _syncHTTPRequest("/api/mix?$mixArgs\&$argString");

			Slim::Plugin::MusicMagic::Settings->grabFilters();
		}

		if ($response->is_error) {
			
			$log->warn("Warning: Couldn't get mix: $mixArgs\&$argString");
			$log->debug($response->as_string);
	
			return \@mix;
		}
	}

	my @songs = split(/\n/, $response->content);
	my $count = scalar @songs;

	for (my $j = 0; $j < $count; $j++) {

		# Bug 4281 - need to convert from UTF-8 on Windows.
		if ($isWin) {

			my $enc = Slim::Utils::Unicode::encodingFromString($songs[$j]);

			$songs[$j] = Slim::Utils::Unicode::utf8decode_guess($songs[$j], $enc);
		}

		my $newPath = Slim::Plugin::MusicMagic::Common::convertPath($songs[$j]);

		$log->debug("Original $songs[$j] : New $newPath");

		if ( -e $newPath || -e Slim::Utils::Unicode::utf8encode_locale($newPath) ) {
			push @mix, Slim::Utils::Misc::fileURLFromPath($newPath);
		} else {
			$log->error('MIP attempted to mix in a song at ' . $newPath . ' that can\'t be found at that location');
		}
	}

	return \@mix;
}

sub musicmagic_moods {
	my ($client, $params) = @_;

	my $mood_list;
	map { $mood_list->{$_}->{isFavorite} = defined Slim::Utils::Favorites->new($client)->findUrl("mood://$_") } @{ grabMoods() };

	$params->{'mood_list'} = $mood_list;

	return Slim::Web::HTTP::filltemplatefile("plugins/MusicMagic/musicmagic_moods.html", $params);
}

sub musicmagic_mix {
	my ($client, $params) = @_;

	my $output = "";
	my $mix = _prepare_mix($client, $params);

	my $p0       = $params->{'p0'};

	my $itemnumber = 0;
	$params->{'browse_items'} = [];
	$params->{'levelName'} = "playlisttrack";

	$params->{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("plugins/MusicMagic/musicmagic_pwdlist.html", $params)};

	if (scalar @$mix) {

		push @{$params->{'browse_items'}}, {

			'text'         => Slim::Utils::Strings::string('ALL_SONGS'),
			'attributes'   => "&listRef=musicmagic_mix",
			'odd'          => ($itemnumber + 1) % 2,
			'webroot'      => $params->{'webroot'},
			'skinOverride' => $params->{'skinOverride'},
			'player'       => $params->{'player'},
		};

		$itemnumber++;

	} else {
		
		# no mixed items, report empty.
		$params->{'warn'} = Slim::Utils::Strings::string('EMPTY');
	}

	for my $item (@$mix) {

		my %form = %$params;

		# If we can't get an object for this url, skip it, as the
		# user's database is likely out of date. Bug 863
		my $trackObj = Slim::Schema->rs('Track')->objectForUrl($item);

		if (!blessed($trackObj) || !$trackObj->can('id')) {

			next;
		}
		
		$trackObj->displayAsHTML(\%form, 0);

		$form{'attributes'} = join('=', '&track.id', $trackObj->id);
		$form{'odd'}        = ($itemnumber + 1) % 2;

		$itemnumber++;

		push @{$params->{'browse_items'}}, \%form;
	}

	if (defined $p0 && defined $client) {
		$client->execute(["playlist", $p0 eq "append" ? "addtracks" : "playtracks", "listref=musicmagic_mix"]);
	}

	return Slim::Web::HTTP::filltemplatefile("plugins/MusicMagic/musicmagic_mix.html", $params);
}

sub cliMoods {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['musicip', 'moods']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client = $request->client();	

	my $moods = grabMoods();

	# menu/jive mgmt
	my $menu     = $request->getParam('menu');
	my $menuMode = defined $menu;

	my $loopname = $menuMode ? 'item_loop' : 'titles_loop';
	my $chunkCount = 0;

	if ($menuMode) {
		$request->addResult('offset', 0);

		$request->addResult('window', {
			'titleStyle' => 'playlist',
			'text'       => $request->string('MUSICMAGIC_MIX'),
		});
	}

	for my $item (@$moods) {
		if ($menuMode) {
			$request->addResultLoop($loopname, $chunkCount, 'actions', {
				go => {
					player => 0,
					cmd    => [ 'musicip', 'mix' ],
					params => {
						menu     => 1,
						mood => $item,
					},
				},
			});
			$request->addResultLoop($loopname, $chunkCount, 'text', $item);
		}
		else {
			$request->addResultLoop($loopname, $chunkCount, 'name', $item);
		}
		$chunkCount++;
	}

	$request->addResult('count', $chunkCount);
}


sub cliMix {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['musicip', 'mix']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client = $request->client();
	my $tags   = $request->getParam('tags') || 'al';

	my $params = {
		song        => $request->getParam('song_id'), 
		track       => $request->getParam('track_id'),
		artist      => $request->getParam('artist_id'),
		contributor => $request->getParam('contributor_id'),
		album       => $request->getParam('album_id'),
		genre       => $request->getParam('genre_id'),
		year        => $request->getParam('year'),
		mood        => $request->getParam('mood'),
		playlist    => $request->getParam('playlist'),
	};

	my $mix = _prepare_mix($client, $params);

	# menu/jive mgmt
	my $menu     = $request->getParam('menu');
	my $menuMode = defined $menu;

	my $loopname = $menuMode ? 'item_loop' : 'titles_loop';
	my $chunkCount = 0;

	if ($menuMode) {
		my $base = {
			actions => {
				go => {
					cmd => ['trackinfo', 'items'],
					params => {
						menu => 'nowhere',
					},
					itemsParams => 'params',
				},
				play => {
					cmd => ['playlistcontrol'],
					params => {
						cmd  => 'load',
						menu => 'nowhere',
					},
					itemsParams => 'params',
				},
				add =>  {
					cmd => ['playlistcontrol'],
					params => {
						cmd  => 'add',
						menu => 'nowhere',
					},
					itemsParams => 'params',
				},
				'add-hold' =>  {
					cmd => ['playlistcontrol'],
					params => {
						cmd  => 'insert',
						menu => 'nowhere',
					},
					itemsParams => 'params',
				},
			},
		};
		$request->addResult('base', $base);
		
		$request->addResult('offset', 0);
		#$request->addResult('text', $request->string('MUSICMAGIX_MIX'));
		my $thisWindow = {
				'titleStyle' => 'playlist',
				'menuStyle'  => 'album',
				'text'       => $request->string('MUSICMAGIC_MIX'),
		};
		$request->addResult('window', $thisWindow);

		# add an item for "play this mix"
		$request->addResultLoop($loopname, $chunkCount, 'nextWindow', 'playlist');
		$request->addResultLoop($loopname, $chunkCount, 'text', $request->string('MUSICIP_PLAYTHISMIX'));
		$request->addResultLoop($loopname, $chunkCount, 'icon-id', '/html/images/playall.png');
		my $actions = {
			'go' => {
				'cmd' => ['musicip', 'play'],
			},
			'play' => {
				'cmd' => ['musicip', 'play'],
			},
			'add' => {
				'cmd' => ['musicip', 'add'],
			},
			'add-hold' => {
				'cmd' => ['musicip', 'insert'],
			},
		};
		$request->addResultLoop($loopname, $chunkCount, 'actions', $actions);
		$chunkCount++;
		
	}
	
	
	for my $item (@$mix) {

		# If we can't get an object for this url, skip it, as the
		# user's database is likely out of date. Bug 863
		my $trackObj = Slim::Schema->rs('Track')->objectForUrl($item);

		if (!blessed($trackObj) || !$trackObj->can('id')) {

			next;
		}

		if ($menuMode) {
			Slim::Control::Queries::_addJiveSong($request, $loopname, $chunkCount, 0, $trackObj);
		} else {
			Slim::Control::Queries::_addSong($request, $loopname, $chunkCount, $trackObj, $tags);
		}
		$chunkCount++;
	}

	$request->addResult('count', $chunkCount);
	$request->setStatusDone();
}

sub cliPlayMix {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotCommand([['musicip'], ['play', 'add', 'insert']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client = $request->client();
	my $add    = !$request->isNotCommand([['musicip'], ['add']]);
	my $insert = !$request->isNotCommand([['musicip'], ['insert']]);

	$client->execute(["playlist",	$add ? "addtracks" 
					: $insert ? "inserttracks"
					: "playtracks", 
			"listref=musicmagic_mix"]);
}

sub _prepare_mix {
	my ($client, $params) = @_;

	my $mix;
	my $song     = $params->{'song'} || $params->{'track'};
	my $artist   = $params->{'artist'} || $params->{'contributor'};
	my $album    = $params->{'album'};
	my $genre    = $params->{'genre'};
	my $year     = $params->{'year'};
	my $mood     = $params->{'mood'};
	my $playlist = $params->{'playlist'};

	if ($mood) {
		$mix = getMix($client, $mood, 'mood');
		$params->{'src_mix'} = $mood;

	} elsif ($playlist) {

		my ($obj) = Slim::Schema->find('Playlist', $playlist);

		if (blessed($obj) && $obj->can('musicmagic_mixable')) {

			if ($obj->musicmagic_mixable) {

				my $playlist = $obj->path;
				if ($obj->url =~ /musicipplaylist:(.*?)$/) {
					$playlist = Slim::Utils::Misc::unescape($1);
				}

				$mix = getMix($client, $playlist, 'playlist');
			}

			$params->{'src_mix'} = $obj->title;
		}

	} elsif ($song) {

		my ($obj) = Slim::Schema->find('Track', $song);

		if (blessed($obj) && $obj->can('musicmagic_mixable')) {

			if ($obj->musicmagic_mixable) {

				# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
				$mix = getMix($client, $obj->path, 'track');
			}

			$params->{'src_mix'} = Slim::Music::Info::standardTitle(undef, $obj);
		}

	} elsif ($artist && !$album) {

		my ($obj) = Slim::Schema->find('Contributor', $artist);

		if (blessed($obj) && $obj->can('musicmagic_mixable') && $obj->musicmagic_mixable) {

			# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
			$mix = getMix($client, $obj->name, 'artist');
			
			$params->{'src_mix'} = $obj->name;
		}

	} elsif ($album) {

		my ($obj) = Slim::Schema->find('Album', $album);
		
		if (blessed($obj) && $obj->can('musicmagic_mixable') && $obj->musicmagic_mixable) {

			my $trackObj = $obj->tracks->next;

			if ($trackObj) {

				$mix = getMix($client, $trackObj->path, 'album');
				
				$params->{'src_mix'} = $obj->title;
			}
		}
		
	} elsif ($genre && $genre ne "*") {

		my ($obj) = Slim::Schema->find('Genre', $genre);

		if (blessed($obj) && $obj->can('musicmagic_mixable') && $obj->musicmagic_mixable) {

			# For the moment, skip straight to InstantMix mode. (See VarietyCombo)
			$mix = getMix($client, $obj->name, 'genre');
			
			$params->{'src_mix'} = $obj->name;
		}
	
	} elsif (defined $year) {
		
		$mix = getMix($client, $year, 'year');
		$params->{'src_mix'} = $year;
		
	} else {

		$log->debug("No/unknown type specified for mix");

		# allow a valid page return, but report an empty mix
		$params->{'warn'} = Slim::Utils::Strings::string('EMPTY');
	}

	if (defined $mix && ref $mix eq "ARRAY" && defined $client) {
		# We'll be using this to play the entire mix using 
		# playlist (add|play|load|insert)tracks listref=musicmagic_mix
		$client->modeParam('musicmagic_mix', $mix);
	} elsif (!defined $mix || ref $mix ne "ARRAY") {
		$mix = [];
	}
	
	return $mix;
}

sub trackInfoHandler {
	my ( $client, $url, $track, $remoteMeta, $tags ) = @_;
	$tags ||= {};
	
	my $mixable = $track->musicmagic_mixable;

	my $jive = {};
	if ( $tags->{menuMode} ) {
		my $actions;
		if ( $mixable ) {
			$actions = {
				go => {
					player => 0,
					cmd    => [ 'musicip', 'mix' ],
					params => {
						menu     => 1,
						track_id => $track->id,
					},
				},
			};
		} else {
			$actions = {
				do => {
					player => 0,
					cmd    => [ 'jiveunmixable' ],
					params => {
						contextToken => 'MUSICMAGIC_MIX',
					},
				},
			};

		}

		$jive->{actions} = $actions;
	}

	if ( $mixable ) {
		return {
			type      => 'redirect',
			jive      => $jive,
			name      => cstring($client, 'MUSICIP_CREATEMIX'),
			favorites => 0,

			player => {
				mode => 'musicmagic_mix',
				modeParams => {
					track => $track,
				},
			},

			web  => {
				group => 'mixers',
				url   => 'plugins/MusicMagic/musicmagic_mix.html?song=' . $track->id,
				item  => mixerlink($track),
			},
		};
	}

	return;

}

sub _syncHTTPRequest {
	my $url = shift;
	
	$MMSport = $prefs->get('port') unless $MMSport;
	$MMSHost = $prefs->get('host') unless $MMSHost;
	
	my $http = LWP::UserAgent->new;

	$http->timeout(5);

	return $http->get("http://$MMSHost:$MMSport$url");
}

1;

__END__
