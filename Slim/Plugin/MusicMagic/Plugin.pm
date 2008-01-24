package Slim::Plugin::MusicMagic::Plugin;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Scalar::Util qw(blessed);

use Slim::Player::ProtocolHandlers;
use Slim::Player::Protocols::HTTP;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings;
use Slim::Utils::Prefs;

use Slim::Plugin::MusicMagic::Settings;
use Slim::Plugin::MusicMagic::ClientSettings;

use Slim::Plugin::MusicMagic::Common;
use Slim::Plugin::MusicMagic::PlayerSettings;

my $initialized = 0;
my $MMSHost;
my $MMSport;

my $OS  = Slim::Utils::OSDetect::OS();

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.musicip',
	'defaultLevel' => 'ERROR',
});

my $prefs = preferences('plugin.musicmagic');

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
			$prefs->set('musicmagic', 0);
		} else {
			$prefs->set('musicmagic', $newValue);
		}
	}
	
	my $use = $prefs->get('musicmagic');
	
	if (!defined($use) && $can) { 
		$prefs->set('musicmagic', 1);
	} elsif (!defined($use) && !$can) {
		$prefs->set('musicmagic', 0);
	}
	
	$use = $prefs->get('musicmagic') && $can;

	$log->info("Using musicip: $use");

	return $use;
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
	Slim::Player::ProtocolHandlers->registerHandler('musicmagicplaylist', 0);

	$initialized = 0;

	# set importer to not use, but only for this session. leave server
	# pref as is to support reenabling the features, without needing a
	# forced rescan
	Slim::Music::Import->useImporter('Slim::Plugin::MusicMagic::Plugin', 0);
}

sub initPlugin {
	my $class = shift;

	return 1 if $initialized;
	
	Slim::Plugin::MusicMagic::Common::checkDefaults();
	
	$MMSport = $prefs->get('port');
	$MMSHost = $prefs->get('host');

	Slim::Plugin::MusicMagic::Settings->new;

	# don't test the connection if MIP integration is disabled
	return unless $prefs->get('musicmagic'); 

	$log->info("Testing for API on $MMSHost:$MMSport");

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'     => "http://$MMSHost:$MMSport/api/version",
		'create'  => 0,
		'timeout' => 5,
	});

	if (!$http) {

		$initialized = 0;

		$log->error("Can't connect to port $MMSport - MusicMagic disabled.");

	} else {

		my $content = $http->content;

		if ( $log->is_info ) {
			$log->info($content);
		}

		$http->close;

		Slim::Plugin::MusicMagic::PlayerSettings::init();

		# Note: Check version restrictions if any
		$initialized = $content;

		checker($initialized);

		# addImporter for Plugins, may include mixer function, setup function, mixerlink reference and use on/off.
		Slim::Music::Import->addImporter($class, {
			'mixer'     => \&mixerFunction,
			'mixerlink' => \&mixerlink,
			'use'       => $prefs->get($class->prefName),
		});

		Slim::Player::ProtocolHandlers->registerHandler('musicmagicplaylist', 0);

		Slim::Plugin::MusicMagic::ClientSettings->new;

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

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/cacheid?contents",
		'create' => 0,
		'timeout' => 5,
	}) || return 0;

	my $fileMTime = $http->content;

	chomp($fileMTime);

	$log->info("Read cacheid of $fileMTime");

	$http->close;

	$http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/getStatus",
		'create' => 0,
		'timeout' => 5,
	}) || return 0;

	if ( $log->is_info ) {
		$log->info("Got status: ", $http->content);
	}

	$http->close;

	# Only say "yes" if it has been more than one minute since we last finished scanning
	# and the file mod time has changed since we last scanned. Note that if we are
	# just starting, $lastMMMChange is undef, so both $fileMTime
	# will be greater than 0 and time()-0 will be greater than 180 :-)
	my $lastScanTime  = Slim::Music::Import->lastScanTime;
	my $lastMMMChange = Slim::Music::Import->lastScanTime('MMMLastLibraryChange');

	if ($fileMTime > $lastMMMChange) {

		my $scanInterval = $prefs->get('scan_interval');

		if ( $log->is_debug ) {
			$log->debug("MusicMagic: music library has changed!");
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

		if ((time - $lastScanTime) > $scanInterval) {

			return 1;
		}

		$log->info("Waiting for $scanInterval seconds to pass before rescanning");
	}

	return 0;
}

sub checker {
	my $firstTime = shift || 0;
	
	if (!$prefs->get('musicmagic')) {
		return;
	}

	if (!$firstTime && !Slim::Music::Import->stillScanning && isMusicLibraryFileChanged()) {

		Slim::Control::Request::executeRequest(undef, ['rescan']);
	}

	# make sure we aren't doing this more than once...
	Slim::Utils::Timers::killTimers(undef, \&checker);

	# Call ourselves again after 120 seconds
	Slim::Utils::Timers::setTimer(undef, (Time::HiRes::time() + 120), \&checker);
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
	
	if (blessed($item) && $item->can('musicmagic_mixable')) {

		return $item->musicmagic_mixable;
	}
}

sub grabMoods {
	my @moods    = ();
	my %moodHash = ();

	if (!$initialized) {
		return;
	}

	$MMSport = $prefs->get('port') unless $MMSport;
	$MMSHost = $prefs->get('host') unless $MMSHost;

	$log->debug("Get moods list");

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/moods",
		'create' => 0,
	});

	if ($http) {

		@moods = split(/\n/, $http->content);
		$http->close;

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
	my ($client, $noSettings) = @_;

	# look for parentParams (needed when multiple mixers have been used)
	my $paramref = defined $client->modeParam('parentParams') ? $client->modeParam('parentParams') : $client->modeParameterStack(-1);
	
	# if prefs say to offer player settings, and we're not already in that mode, then go into settings.
	if ($prefs->get('player_settings') && !$noSettings) {

		Slim::Buttons::Common::pushModeLeft($client, 'MMMsettings', { 'parentParams' => $paramref });
		return;

	}

	my $listIndex = $paramref->{'listIndex'};
	my $items     = $paramref->{'listRef'};
	my $hierarchy = $paramref->{'hierarchy'};
	my $level     = $paramref->{'level'} || 0;
	my $descend   = $paramref->{'descend'};

	my @levels    = split(",", $hierarchy);
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

	} elsif ($levels[$level] eq 'contributor') {
		
		# MusicMagic uses artist instead of contributor.
		$levels[$level] = 'artist';
		$mixSeed = $currentItem->name;
	
	} elsif ($levels[$level] eq 'genre') {
		
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
	if (canUseMusicMagic() && $prefs->get('musicmagic')) {

		# set up a musicmagic link
		$form->{'mixerlinks'}{Slim::Plugin::MusicMagic::Plugin->title()} = "plugins/MusicMagic/mixerlink.html";
		
		# flag if mixable
		if (($item->can('musicmagic_mixable') && $item->musicmagic_mixable) ||
			(defined $form->{'levelName'} && $form->{'levelName'} eq 'year')) {

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

		$log->debug("Filter $filter in use.");

		$args{'filter'} = Slim::Utils::Misc::escape($filter);
	}

	my $argString = join( '&', map { "$_=$args{$_}" } keys %args );

	if (!$validMixTypes{$for}) {

		$log->debug("No valid type specified for mix");

		return undef;
	}

	# Not sure if this is correct yet.
	if ($validMixTypes{$for} ne 'song' && $validMixTypes{$for} ne 'album') {

		$id = Slim::Utils::Unicode::utf8encode_locale($id);
	}

	$log->debug("Creating mix for: $validMixTypes{$for} using: $id as seed.");

	my $mixArgs = "$validMixTypes{$for}=$id";

	# url encode the request, but not the argstring
	# Bug: 1938 - Don't encode to UTF-8 before escaping on Mac & Win
	# We might need to do the same on Linux, but I can't get UTF-8 files
	# to show up properly in MMM right now.
	if ($OS eq 'win' || $OS eq 'mac') {

		$mixArgs = URI::Escape::uri_escape($mixArgs);

	} else {

		$mixArgs = Slim::Utils::Misc::escape($mixArgs);
	}
	
	$log->debug("Request http://$MMSHost:$MMSport/api/mix?$mixArgs\&$argString");

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/mix?$mixArgs\&$argString",
		'create' => 0,
	});

	if (!$http) {
		# NYI
		$log->warn("Warning: Couldn't get mix: $mixArgs\&$argString");

		return @mix;
	}

	my @songs = split(/\n/, $http->content);
	my $count = scalar @songs;

	$http->close;

	for (my $j = 0; $j < $count; $j++) {

		# Bug 4281 - need to convert from UTF-8 on Windows.
		if ($OS eq 'win') {

			my $enc = Slim::Utils::Unicode::encodingFromString($songs[$j]);

			$songs[$j] = Slim::Utils::Unicode::utf8decode_guess($songs[$j], $enc);
		}

		my $newPath = Slim::Plugin::MusicMagic::Common::convertPath($songs[$j]);

		$log->debug("Original $songs[$j] : New $newPath");

		push @mix, Slim::Utils::Misc::fileURLFromPath($newPath);
	}

	return \@mix;
}

sub musicmagic_moods {
	my ($client, $params) = @_;

	$params->{'mood_list'} = grabMoods();

	return Slim::Web::HTTP::filltemplatefile("plugins/MusicMagic/musicmagic_moods.html", $params);
}

sub musicmagic_mix {
	my ($client, $params) = @_;

	my $output = "";
	my $mix;

	my $song     = $params->{'song'} || $params->{'track'};
	my $artist   = $params->{'artist'} || $params->{'contributor'};
	my $album    = $params->{'album'};
	my $genre    = $params->{'genre'};
	my $year     = $params->{'year'};
	my $mood     = $params->{'mood'};
	my $player   = $params->{'player'};
	my $playlist = $params->{'playlist'};
	my $p0       = $params->{'p0'};

	my $itemnumber = 0;
	$params->{'browse_items'} = [];
	$params->{'levelName'} = "track";

	if ($mood) {
		$mix = getMix($client, $mood, 'mood');
		$params->{'src_mix'} = $mood;

	} elsif ($playlist) {

		my ($obj) = Slim::Schema->find('Playlist', $playlist);

		if (blessed($obj) && $obj->can('musicmagic_mixable')) {

			if ($obj->musicmagic_mixable) {

				my $playlist = $obj->path;
				if ($obj->url =~ /musicmagicplaylist:(.*?)$/) {
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
		$client->modeParam('musicmagic_mix',$mix);
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

1;

__END__
