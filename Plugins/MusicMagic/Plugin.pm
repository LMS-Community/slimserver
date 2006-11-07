package Plugins::MusicMagic::Plugin;

# $Id$

use strict;

use Scalar::Util qw(blessed);

use Slim::Player::ProtocolHandlers;
use Slim::Player::Protocols::HTTP;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings;

use Plugins::MusicMagic::Common;
use Plugins::MusicMagic::Settings;

my $initialized = 0;
my $MMSHost;
my $MMSport;

my $OS  = Slim::Utils::OSDetect::OS();

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.musicmagic',
	'defaultLevel' => 'WARN',
});

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

	$log->info("Using musicmagic: $use");

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
	Slim::Utils::Timers::killTimers(0, \&checker);

	# disable protocol handler?
	Slim::Player::ProtocolHandlers->registerHandler('musicmaglaylist', 0);

	$initialized = 0;

	# delGroups, categories and prefs
	Slim::Web::Setup::delCategory('MUSICMAGIC');
	Slim::Web::Setup::delGroup('BASIC_SERVER_SETTINGS','musicmagic',1);

	# set importer to not use, but only for this session. leave server
	# pref as is to support reenabling the features, without needing a
	# forced rescan
	Slim::Music::Import->useImporter('Plugins::MusicMagic::Plugin', 0);
}

sub initPlugin {
	my $class = shift;

	return 1 if $initialized;
	
	Plugins::MusicMagic::Common::checkDefaults();
	
	if (grep { $_ eq 'MusicMagic::Plugin' } Slim::Utils::Prefs::getArray('disabledplugins')) {

		$log->info("Not initializing: disabled");

		$initialized = 0;

		my ($groupRef, $prefRef) = setupPort();

		Slim::Web::Setup::addGroup('PLUGINS', 'musicmagic_connect', $groupRef, undef, $prefRef);

		return 0;		
	}

	$MMSport = Slim::Utils::Prefs::get('MMSport');
	$MMSHost = Slim::Utils::Prefs::get('MMSHost');

	$log->info("Testing for API on $MMSHost:$MMSport");

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'     => "http://$MMSHost:$MMSport/api/version",
		'create'  => 0,
		'timeout' => 5,
	});

	if (!$http) {

		$initialized = 0;

		$log->warn("Can't connect to port $MMSport - MusicMagic disabled.");

		my ($groupRef, $prefRef) = setupPort();

		Slim::Web::Setup::addGroup('PLUGINS', 'musicmagic_connect', $groupRef, undef, $prefRef);

	} else {

		my $content = $http->content;

		$log->info($content);

		$http->close;

		Plugins::MusicMagic::Settings::init();

		# Note: Check version restrictions if any
		$initialized = $content;

		checker($initialized);

		# addImporter for Plugins, may include mixer function, setup function, mixerlink reference and use on/off.
		Slim::Music::Import->addImporter($class, {
			'mixer'     => \&mixerFunction,
			'setup'     => \&addGroups,
			'mixerlink' => \&mixerlink,
			'use'       => Slim::Utils::Prefs::get($class->prefName),
		});

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

sub addGroups {
	my $category = setupCategory();

	Slim::Web::Setup::addCategory('MUSICMAGIC',$category);

	my ($groupRef, $prefRef) = setupUse();

	Slim::Web::Setup::addGroup('BASIC_SERVER_SETTINGS', 'musicmagic', $groupRef, undef, $prefRef);

	Slim::Web::Setup::addChildren('BASIC_SERVER_SETTINGS', 'MUSICMAGIC');
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

	$log->info("Got status: ", $http->content);

	$http->close;

	# Only say "yes" if it has been more than one minute since we last finished scanning
	# and the file mod time has changed since we last scanned. Note that if we are
	# just starting, $lastMMMChange is undef, so both $fileMTime
	# will be greater than 0 and time()-0 will be greater than 180 :-)
	my $lastScanTime  = Slim::Music::Import->lastScanTime;
	my $lastMMMChange = Slim::Music::Import->lastScanTime('MMMLastLibraryChange');

	if ($fileMTime > $lastMMMChange) {

		my $scanInterval = Slim::Utils::Prefs::get('musicmagicscaninterval');

		$log->debug("MusicMagic: music library has changed!");
		$log->debug("Details:");
		$log->debug("\tCurrCacheID  - $fileMTime");
		$log->debug("\tLastCacheID  - $lastMMMChange");
		$log->debug("\tInterval     - $scanInterval");
		$log->debug("\tLastScanTime - $lastScanTime");

		if (!$scanInterval) {

			# only scan if musicmagicscaninterval is non-zero.
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
	
	if (!Slim::Utils::Prefs::get('musicmagic')) {
		return;
	}

	if (!$firstTime && !Slim::Music::Import->stillScanning && isMusicLibraryFileChanged()) {

		Slim::Control::Request::executeRequest(undef, ['rescan']);
	}

	# make sure we aren't doing this more than once...
	Slim::Utils::Timers::killTimers(0, \&checker);

	# Call ourselves again after 120 seconds
	Slim::Utils::Timers::setTimer(0, (Time::HiRes::time() + 120), \&checker);
}

sub grabFilters {
	my @filters    = ();
	my %filterHash = ();
	
	if (!$initialized) {
		return;
	}
	
	if (grep {$_ eq 'MusicMagic::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins')) {

		$log->debug("Don't get filters list, it's disabled");

		return %filterHash;
	}
	
	$MMSport = Slim::Utils::Prefs::get('MMSport') unless $MMSport;
	$MMSHost = Slim::Utils::Prefs::get('MMSHost') unless $MMSHost;

	$log->debug("Get filters list");

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/filters",
		'create' => 0,
	});

	if ($http) {

		@filters = split(/\n/, $http->content);
		$http->close;

		if ($log->is_debug && scalar @filters) {

			$log->debug("Found filters:");

			for my $filter (@filters) {

				$log->debug("\t$filter");
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

	if (grep {$_ eq 'MusicMagic::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins')) {

		$log->debug("Don't get moods list, it's disabled");

		return %moodHash;
	}
	
	$MMSport = Slim::Utils::Prefs::get('MMSport') unless $MMSport;
	$MMSHost = Slim::Utils::Prefs::get('MMSHost') unless $MMSHost;

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

	# only add link if enabled and usable
	if (canUseMusicMagic() && Slim::Utils::Prefs::get('musicmagic')) {

		# set up a musicmagic link
		$form->{'mixerlinks'}{Plugins::MusicMagic::Plugin->title()} = "plugins/MusicMagic/mixerlink.html";
		
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
			'size'       => $client->prefGet('MMMSize') || Slim::Utils::Prefs::get('MMMSize'),
	
			# (tracks|min|mb) Set the units for size (default tracks)
			'sizetype'   => $type[$client->prefGet('MMMMixType') || Slim::Utils::Prefs::get('MMMMixType')],
	
			# Set the style slider (default 20)
			'style'      => $client->prefGet('MMMStyle') || Slim::Utils::Prefs::get('MMMStyle'),
	
			# Set the variety slider (default 0)
			'variety'    => $client->prefGet('MMMVariety') || Slim::Utils::Prefs::get('MMMVariety'),

			# mix genres or stick with that of the seed. (Default: match seed)
			'mixgenre'   => $client->prefGet('MMMMixGenre') || Slim::Utils::Prefs::get('MMMMixGenre'),
	
			# Set the number of songs before allowing dupes (default 12)
			'rejectsize' => $client->prefGet('MMMRejectSize') || Slim::Utils::Prefs::get('MMMRejectSize'),
		);
	} else {
		%args = (
			# Set the size of the list (default 12)
			'size'       => Slim::Utils::Prefs::get('MMMSize') || 12,
	
			# (tracks|min|mb) Set the units for size (default tracks)
			'sizetype'   => $type[Slim::Utils::Prefs::get('MMMMixType') || 0],
	
			# Set the style slider (default 20)
			'style'      => Slim::Utils::Prefs::get('MMMStyle') || 20,
	
			# Set the variety slider (default 0)
			'variety'    => Slim::Utils::Prefs::get('MMMVariety') || 0,

			# mix genres or stick with that of the seed. (Default: match seed)
			'mixgenre'   => Slim::Utils::Prefs::get('MMMMixGenre') || 0,
	
			# Set the number of songs before allowing dupes (default 12)
			'rejectsize' => Slim::Utils::Prefs::get('MMMRejectSize') || 12,
		);
	}

	# (tracks|min|mb) Set the units for rejecting dupes (default tracks)
	my $rejectType = defined $client ?
		($client->prefGet('MMMRejectType') || Slim::Utils::Prefs::get('MMMRejectType')) : 
		(Slim::Utils::Prefs::get('MMMRejectType') || 0);
	
	# assign only if a rejectType found.  suppresses a warning when trying to access the array with no value.
	if ($rejectType) {
		$args{'rejecttype'} = $type[$rejectType];
	}

	my $filter = defined $client ? $client->prefGet('MMMFilter') || Slim::Utils::Prefs::get('MMMFilter') : Slim::Utils::Prefs::get('MMMFilter');

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

		my $newPath = Plugins::MusicMagic::Common::convertPath($songs[$j]);

		$log->debug("Original $songs[$j] : New $newPath");

		push @mix, Slim::Utils::Misc::fileURLFromPath($newPath);
	}

	return \@mix;
}

sub webPages {

	my %pages = (
		"musicmagic_mix\.(?:htm|xml)"   => \&musicmagic_mix,
		"musicmagic_moods\.(?:htm|xml)" => \&musicmagic_moods,
	);

	return (\%pages);
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
		'PrefsInTable'      => 0,
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

				Slim::Music::Import->useImporter('Plugins::MusicMagic::Plugin', $changeref->{'musicmagic'}{'new'});
			},

			'optionSort' => 'KR',
			'inputTemplate' => 'setup_input_radio.html',
		}
	);

	return (\%setupGroup, \%setupPrefs);
}

sub setupGroup {
	my $category = setupCategory();
	my $group    = playerGroup();

	$category->{'parent'}     = 'BASIC_PLAYER_SETTINGS';
	$category->{'GroupOrder'} = ['Default'];
	$category->{'Groups'}     = $group->{'Groups'};
	
	return ($category->{'Groups'}->{'Default'}, $category->{'Prefs'},1);
}

sub setupPort {
	my $client = shift;

	my $category   = setupCategory();

	my %setupGroup = (
		'PrefOrder' => [qw(MMSport)]
	);

	my %setupPrefs = (
		'MMSport' => $category->{'Prefs'}->{'MMSport'}
	);

	return (\%setupGroup, \%setupPrefs);
}

sub setupCategory {
	
	my %setupCategory = (

		'title' => Slim::Utils::Strings::string('SETUP_MUSICMAGIC'),
		'parent' => 'BASIC_SERVER_SETTINGS',
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

1;

__END__
