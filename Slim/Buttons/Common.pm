package Slim::Buttons::Common;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Buttons::Common

=head1 SYNOPSIS

Slim::Buttons::Common::addMode('mymodename', getFunctions(), \&setMode);

Slim::Buttons::Common::addSaver('screensaver', getFunctions(), \&setMode, undef, 'SCREENSAVER_JUMP_BACK_NAME');

Slim::Buttons::Common::pushModeLeft($client,'mymodename');

Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);

Slim::Buttons::Common::popModeRight($client);

Slim::Buttons::Common::popMode($client);

Slim::Buttons::Common::scroll($client, $dir, 6, $m0);

=head1 DESCRIPTION

L<Slim::Buttons::Common> is the central collection of functions for accessing and manipulating the Player UI state machine.  
This includes navigating menus, registering and managing player modes, and accessing core UI widgets.

=cut

use strict;

use Scalar::Util qw(blessed);

use Slim::Buttons::Alarm;
use Slim::Buttons::Volume;
use Slim::Buttons::GlobalSearch;
use Slim::Buttons::XMLBrowser;
use Slim::Player::Client;
use Slim::Utils::DateTime;
use Slim::Utils::Favorites;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Buttons::Block;
use Slim::Utils::Prefs;

# hash of references to functions to call when we leave a mode
our %leaveMode = ();

#references to mode specific function hashes
our %modeFunctions = ();

my $SCAN_RATE_MULTIPLIER = 2;
my $SCAN_RATE_MAX_MULTIPLIER = 256;

# hash of references to functions to call when we enter a mode
# Note:  don't add to this list, rather use the addMode() function 
# below to have the module add its mode itself
our %modes = ();

# Store of registered Screensavers. Register these using addSaver.
our $savers = {};

# Map the numbers on the remote to their corresponding letter sequences.
our @numberLetters = (
	[' ','0'], # 0
	['.',',',"'",'?','!','@','-','1'], # 1
	['A','B','C','2'], 	# 2
	['D','E','F','3'], 	# 3
	['G','H','I','4'], 	# 4
	['J','K','L','5'], 	# 5
	['M','N','O','6'], 	# 6
	['P','Q','R','S','7'], 	# 7
	['T','U','V','8'], 	# 8
	['W','X','Y','Z','9']   # 9
);

# Minimum Velocity for scrolling, in items/second
my $minimumVelocity = 2;

# Time that you must hold the scroll button before the automatic
# scrolling and acceleration starts. 
# in seconds.
my $holdTimeBeforeScroll = 0.300;  

our $scrollClientHash = {};

my $log = logger('player.ui');

my $prefs = preferences('server');

=head1 METHODS

=head2 init( )

This method must be called before all other Slim::Buttons::* modules.  It
initialises all other Logitech Media Server core button modules and registers the "Now
Playing" screensaver.

=cut

# The address of the function hash is set at run time rather than compile time
# so initialize the modeFunctions hash here
sub init {

	# Home must come first!
	Slim::Buttons::Home::init();
	
	# Initialise main settings menu next
	Slim::Buttons::Settings::init();
	
	Slim::Buttons::Alarm::init();
	Slim::Buttons::Block::init();
	Slim::Buttons::Information::init();
	Slim::Buttons::Playlist::init();
	Slim::Buttons::XMLBrowser::init();
	Slim::Buttons::Power::init();
	Slim::Buttons::ScreenSaver::init();
	Slim::Buttons::GlobalSearch::init();
	
	if (!main::NOMYSB) {
		require Slim::Buttons::SqueezeNetwork;
		Slim::Buttons::SqueezeNetwork::init();
	}
	
	Slim::Buttons::Synchronize::init();
	Slim::Buttons::TrackInfo::init();
	Slim::Buttons::RemoteTrackInfo::init();
	Slim::Buttons::Volume::init();

	addSaver('playlist', undef, undef, undef, 'SCREENSAVER_JUMP_TO_NOW_PLAYING', 'PLAY');
}

=head2 forgetClient ( $client )

Clean up global hash when a client is gone

=cut

sub forgetClient {
	my $client = shift;
	
	delete $scrollClientHash->{ $client };
}

=head2 addSaver ( $name, [ $buttonFunctions ], [ $setModeFunction ], [ $leaveModeFunction ], $displayName, [ $type ], [ $valid ] )

This function registers a screensaver mode.  The required $name argument should be a unique string,
identifying the mode, $displayName is also required and must be a valid string token (all caps, with
localised translations) for identifying the friendly name of the screensaver.

Optional $buttonFunctions is a reference the routine to call for accessing the reference to the button
functions used while operating in the screensaver.  This is only required if the screensaver makes use
 of any custom functions not found in this module.

$setModeFunction is an optional reference to the modes setMode function call, which sets up the required
state for the screensaver mode. This is not required if the screensaver is only for display or makes use
of existing INPUT.* modes.

$leaveModeFunction is an optional reference to a routine to run when exiting the screensaver mode.

$displayName is a string token for the screensaver (non optional)

$type is a string containing one or more tokens: PLAY IDLE OFF to indicate the type of saver, e.g. "PLAY-IDLE"
If omitted it defaults to "PLAY-IDLE-OFF", i.e. the saver is valid for all screensaver types.

$valid is an optional callback to verify if the saver is valid for a specific player.  It is passed $client when called.

=cut

sub addSaver {
	my $name = shift;
	my $buttonFunctions = shift;
	my $setModeFunction = shift;
	my $leaveModeFunction = shift;
	my $displayName = shift;
	my $type = shift || 'PLAY-IDLE-OFF-ALARM';
	my $valid = shift;

	main::INFOLOG && logger('player.ui')->info("Registering screensaver $displayName $type");

	$savers->{$name} = {
		'name'  => $displayName,
		'type'  => $type,
		'valid' => ($valid && ref $valid eq 'CODE' ? $valid : undef),
	};

	# playlist is a special case as it is shared with a non screensaver mode
	# bypass addMode for the screensaver version
	if ($name eq 'playlist') { return };

	addMode($name, $buttonFunctions, $setModeFunction, $leaveModeFunction);

	# add an extra mode entry to use as an idle saver
	my $saver = $name;
	if ($type =~ /IDLE/ && $saver =~ s/^SCREENSAVER\./IDLESAVER\./) {

		addMode($saver, $buttonFunctions, $setModeFunction, $leaveModeFunction);
	}

	# add an extra mode entry to use as an off saver
	$saver = $name;
	if ($type =~ /OFF/ && $saver =~ s/^SCREENSAVER\./OFF\./) {

		addMode($saver, $buttonFunctions, $setModeFunction, $leaveModeFunction);
	}
}

=head2 validSavers ( $client )

Returns hash of valid savers for this client. Pass no $client ref for a full list of savers.
Called from settings routines in Slim::Web::Setup and Slim::Buttons::Settings

=cut

sub validSavers {
	my $client = shift;

	my $ret = { 'screensaver' => {}, 'idlesaver' => {}, 'offsaver' => {}, 'alarmsaver' => {} };

	for my $name (keys %$savers) {

		my $saver = $savers->{$name};

		if ( (!defined($client)) || !$saver->{'valid'} || $saver->{'valid'}->($client) ) {

			$ret->{'screensaver'}->{$name} = $saver->{'name'} if $saver->{'type'} =~ /PLAY/;
			$ret->{'alarmsaver'}->{$name}  = $saver->{'name'} if $saver->{'type'} =~ /ALARM/;
			$ret->{'idlesaver'}->{$name}   = $saver->{'name'} if $saver->{'type'} =~ /IDLE/;
			$ret->{'offsaver'}->{$name}    = $saver->{'name'} if $saver->{'type'} =~ /OFF/;
		}
	}
	
	return $ret;
}

=head2 addMode ( )

Register new player modes with the server. $name must be a uniqe string to identify the player mode. 

Optional $buttonFunctions is a reference the routine to call for accessing the reference to the button
functions used while operating in the new button mode.  This is only required if the new mode makes use
 of any custom functions not found in this module.

$setModeFunction is an optional reference to the modes setMode function call, which sets up the required
state for the new button mode. This is not required if the new mode is only for display or makes use
of existing INPUT.* modes.

$leaveModeFunction is an optional reference to a routine to run when exiting the player button mode.

=cut

sub addMode {
	my $name = shift;
	my $buttonFunctions = shift;
	my $setModeFunction = shift;
	my $leaveModeFunction = shift;

	$modeFunctions{$name} = $buttonFunctions;
	$modes{$name} = $setModeFunction;
	$leaveMode{$name} = $leaveModeFunction;
}
	
# Common functions for more than one mode:
our %functions = (
	'dead' => sub  {},

	'fwd' => sub  {
		my $client = shift;

		# ignore if we aren't playing anything 
		return unless Slim::Player::Playlist::count($client);

		$client->execute(["playlist", "jump", "+1"]);
	},

	'rew' => sub  {
		my $client = shift;

		# ignore if we aren't playing anything
		return unless Slim::Player::Playlist::count($client);

		# either starts the same song over, or the previous one, depending on whether we jumped back.
		if (Time::HiRes::time() - Slim::Hardware::IR::lastIRTime($client) < 1.0) {

			# less than second, jump back to the previous song
			$client->execute(["playlist", "jump", "-1"]);

		} else {

			# otherwise, restart this song.
			$client->execute(["playlist", "jump", "+0"]);
		}
	},

	'jump' => sub  {
		my $client   = shift;
		my $funct    = shift;
		my $functarg = shift;

		# ignore if we aren't playing anything
		return unless Slim::Player::Playlist::count($client);

		if (!defined $functarg) {
			$functarg = '';
		}

		# either starts the same song over, or the previous one, or
		# the next one depending on whether/how we jumped
		if ($functarg eq 'rew') { 

			my $now = Time::HiRes::time();

			if (Slim::Player::Source::songTime($client) < 5 || Slim::Player::Source::playmode($client) eq "stop") {

				# jump back a song if stopped, invalid
				# songtime, or current song has been playing
				# less than 5 seconds (use modetime instead of now when paused)
				$client->execute(["playlist", "jump", "-1"]);

			} else {

				#restart current song
				$client->execute(["playlist", "jump", "+0"]);
			}

		} elsif ($functarg eq 'fwd') {

			# jump to next song
			$client->execute(["playlist", "jump", "+1"]);

		} else {

			#restart current song
			$client->execute(["playlist", "jump", "+0"]);
		}
	},

	'jumpinsong' => sub {
		my ($client, $funct, $functarg) = @_;

		my $dir     = 0;
		my $timeinc = 1;

		if (!defined $functarg) {

			return;

		} elsif ($functarg =~ /(.+?)_(\d+)_(\d+)/) {

			$dir = ($1 eq 'fwd' ? '+' : '-') . "$2";

		} elsif ($functarg eq 'fwd') {

			$dir = "+$timeinc";

		} elsif ($functarg eq 'rew') {

			$dir = "-$timeinc";

		} else {

			return;
		}

		$client->execute(['gototime', $dir]);
	},

	'pause' => sub  {
		my $client = shift;

		# ignore if we aren't playing anything
		my $playlistlen = Slim::Player::Playlist::count($client);

		if ($playlistlen == 0) {
			return;
		}

		# try to avoid toggle commands, they make life difficult for listeners
		my $wantmode = (Slim::Player::Source::playmode($client) eq 'pause') ? '0' : '1';

		$client->execute(["pause", $wantmode]);
	},

	'stop' => sub  {
		my $client = shift;

		if (Slim::Player::Playlist::count($client) == 0) {

			$client->showBriefly( {
				'line' => [ "", $client->string('PLAYLIST_EMPTY') ]
			});

		} else {

			$client->execute(["stop"]);

			# Push into playlist, unless already there 
			if (Slim::Buttons::Common::mode($client) ne 'playlist') {
				Slim::Buttons::Common::pushMode($client, 'playlist');
			}

			$client->showBriefly( {
				'line' => [ "", $client->string('STOPPING') ],
				'jive' => undef,	
			}) unless suppressStatus($client);
		}
	},

	'menu_pop' => sub  {
		my $client = shift;

		Slim::Buttons::Common::popMode($client);

		$client->update();
	},

	'menu' => sub  {
		my $client = shift;
		my $button = shift || '';
		my $buttonarg = shift;

		my $jump = $client->curSelection($client->curDepth());

		Slim::Buttons::Common::setMode($client, 'home');

		if ($button eq 'menu_playlist') {

			Slim::Buttons::Common::pushMode($client, 'playlist');
			$jump = 'NOW_PLAYING';

		} elsif ($button eq 'menu_browse_genre') {

			Slim::Menu::BrowseLibrary->setMode($client, 'push', 'genres', 'BROWSE_BY_GENRE');

			$jump = undef;

		} elsif ($button eq 'menu_browse_artist') {

			Slim::Menu::BrowseLibrary->setMode($client, 'push', 'artists', 'BROWSE_BY_ARTIST');

			$jump = undef;

		} elsif ($button eq 'menu_browse_album') {

			Slim::Menu::BrowseLibrary->setMode($client, 'push', 'albums', 'BROWSE_BY_ALBUM');

			$jump = undef;

		} elsif ($button eq 'menu_browse_song') {

			Slim::Menu::BrowseLibrary->setMode($client, 'push', 'tracks', 'BROWSE_BY_SONG');

			$jump = undef;

		} elsif ($button eq 'menu_browse_music') {

			Slim::Menu::BrowseLibrary->setMode($client, 'push', 'bmf', 'BROWSE_MUSIC_FOLDER');

			$jump = undef;

		} elsif ($button eq 'menu_browse_playlists') {

			Slim::Menu::BrowseLibrary->setMode($client, 'push', 'playlists', 'SAVED_PLAYLISTS');

			$jump = undef;

		} elsif ($button eq 'menu_synchronize') {

			Slim::Buttons::Common::pushMode($client, 'settings');

			$jump = 'SETTINGS';

			Slim::Buttons::Common::pushModeLeft($client, 'synchronize');

		} elsif ($buttonarg =~ /^plugin/i) {

			if (exists($modes{$buttonarg})) {
				Slim::Buttons::Common::pushMode($client, $buttonarg);
			} else {
				Slim::Buttons::Common::pushMode($client, 'plugins');
			}

			$jump = 'PLUGINS';

		} elsif ($button eq 'menu_settings') {

			Slim::Buttons::Common::pushMode($client, 'settings');
			$jump = 'SETTINGS';
		}

		Slim::Buttons::Home::jump($client,$jump) if defined $jump;

		$client->update();
	},

	'brightness' => sub  {
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;
		
		my $mode = Slim::Buttons::Common::mode($client);

		if (!defined $buttonarg || ($mode eq 'block' && $client->modeParam('block.name') eq 'upgrade')) {
			return;
		}

		my $brightmode = 'powerOffBrightness';

		if ($client->power) {

			$brightmode = 'powerOnBrightness';

			my $lastIR  = Slim::Hardware::IR::lastIRTime($client);
			my $timeout = Time::HiRes::time() - $prefs->client($client)->get('screensavertimeout');
			my $mode    = Slim::Buttons::Common::mode($client);

			if (($mode ne 'block') && ($lastIR && $lastIR < $timeout)) {

				$brightmode = 'idleBrightness';
			}
		}

		main::INFOLOG && $log->info("Brightness using $brightmode during mode: $mode");

		my $newBrightness;

		if ($buttonarg eq 'toggle') {

			$newBrightness = $client->brightness() - 1;

			if ($newBrightness < 0) {

				$newBrightness = $client->maxBrightness();
			}

		} else {

			if ($buttonarg eq 'down') {

				$newBrightness = $client->brightness() - 1;

			} else {
	
				$newBrightness = $client->brightness() + 1;
			}

			if ($newBrightness > $client->maxBrightness()) {

				$newBrightness = $client->maxBrightness();
			}

			if ($newBrightness < 0) {
				$newBrightness = 0;
			}
		}

		$prefs->client($client)->set($brightmode, $newBrightness);

		$client->brightness($newBrightness);
	},

	'playdisp' => sub  {
		my $client    = shift;
		my $button    = shift;
		my $buttonarg = shift;
		my $playdisp  = undef;

		if (mode($client) eq 'playlist') {

			Slim::Buttons::Playlist::jump($client);
			return;
		}

		if (!defined $buttonarg) {
			$buttonarg = 'toggle';
		}

		if ($buttonarg eq 'toggle') {

			main::INFOLOG && $log->info("Switching to playlist view.");

			Slim::Buttons::Common::setMode($client, 'home');
			Slim::Buttons::Home::jump($client, 'playlist');
			Slim::Buttons::Common::pushModeLeft($client, 'playlist');

		} elsif ($buttonarg =~ /^[0-5]$/) {

			$prefs->client($client)->set('playingDisplayMode', $buttonarg);
		}
	},

	'visual' => sub {
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;
		
		my $visModes = scalar @{ $prefs->client($client)->get('visualModes') };
		my $vm       = $prefs->client($client)->get('visualMode');

		if (!defined $vm || $vm > $visModes) {
			$vm = 0;
		}
		
		if (!defined $buttonarg) {
			$buttonarg = 'toggle';
		}

		if ($button eq 'visual_toggle') {

			$vm = ($vm + 1) % $visModes;

		} elsif (defined $buttonarg && $buttonarg < $visModes) {

			$vm = $buttonarg;
		}

		$prefs->client($client)->set('visualMode', $vm);

		updateScreen2Mode($client);

		$client->update();
	},

	'search' => sub  {
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;
		my $playdisp = undef;

		if (!Slim::Schema::hasLibrary()) {
			$client->bumpRight();
			return;
		}

		# Repeat presses of 'search' will step through search menu while in the top level search menu
		if (($client->modeParam('header') eq 'SEARCH' || 
				$client->curSelection($client->curDepth) eq 'SEARCH') && mode($client) eq 'INPUT.List') {

			(Slim::Buttons::Input::List::getFunctions())->{'down'}($client);

		} elsif (mode($client) ne 'search') {

			Slim::Buttons::Common::pushModeLeft($client, 'search');

			$client->update();
		}
	},

	'globalsearch' => sub  {
		my $client = shift;

		if ($client->modeParam('header') ne 'GLOBAL_SEARCH') {

			setMode($client, 'home');
			Slim::Buttons::Home::jump($client, 'globalsearch');
			Slim::Buttons::Common::pushModeLeft($client, 'globalsearch');

		}
	},

	'browse' => sub  {
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;
		my $playdisp = undef;
		
		if (!Slim::Schema::hasLibrary()) {
			$client->bumpRight();
			return;
		}

		# Repeat presses of 'browse' will step through browse menu
		if ($client->curDepth eq '-BROWSE_MUSIC' && mode($client) eq 'INPUT.List') {

			(Slim::Buttons::Input::List::getFunctions())->{'down'}($client);

		} else {

			setMode($client, 'home');

			Slim::Buttons::Home::jumpToMenu($client,"BROWSE_MUSIC");

			$client->update();
		}
	},

	'favorites' => sub  {
		my $client    = shift;
		my $button    = shift;
		my $buttonarg = shift;
		my $playdisp  = undef;

		if (defined $buttonarg && $buttonarg =~ /^add$|^add(\d+)/) {

			my $preset = $1;

			# First lets try for a listRef from INPUT.*
			my $list = $client->modeParam('listRef');
			my $obj;
			my $title;
			my $url;
			my $type;
			my $parser;
			my $icon;

			# If there is a list, try grabbing the current index.
			if ($list) {

				$obj = $list->[$client->modeParam('listIndex')];

			# hack to grab currently browsed item from current playlist (needs to use INPUT.List at some point)
			} elsif (Slim::Buttons::Common::mode($client) eq 'playlist') {

				$obj = Slim::Player::Playlist::song($client, Slim::Buttons::Playlist::browseplaylistindex($client));
			}

			# xmlbrowser mode - save type and parser params to favorites too
			if ($client->modeParam('modeName') && $client->modeParam('modeName') =~ /XMLBrowser/) {
				$url   = $obj->{'favorites_url'};
				$url ||= $obj->{'play'} if $obj->{'play'} && !ref $obj->{'play'};
				$url ||= $obj->{'url'}  if $obj->{'url'}  && !ref $obj->{'url'};
				$type  = $obj->{'type'} || 'link';
				$title = $obj->{'name'};
				$icon  = $obj->{'image'};
				
				if ( $obj->{'play'} ) {
					$type = 'audio';
				}
				
				# There may be an alternate URL for playlist
				if ( $type eq 'playlist' && $obj->{playlist} && !ref $obj->{playlist}) {
					$url = $obj->{playlist};
				}
				
				$parser = $obj->{'parser'};
			}

			# if that doesn't work, perhaps we have a track param from something like trackinfo
			if (!blessed($obj) && !$url) {

				if ($client->modeParam('track')) {

					$obj = $client->modeParam('track');
				}
			}

			# convert object to url and title
			if ($obj && !$url) {

				if (blessed($obj) && $obj->can('url')) {

					$url = $obj->url;
				}

				if (blessed($obj) && $obj->can('name')) {

					$title = $obj->name;
				}

				if (!$title) {

					# failing specified name values, try the db title
					$title = Slim::Music::Info::standardTitle($client, $obj) || $url;
				}
			}

			# remoteTrackInfo uses url and title params for lists.
			if ($client->modeParam('url') && !$url) {

				$url   = $client->modeParam('url');
				$title = $client->modeParam('title');
			}

			my $favs = Slim::Utils::Favorites->new($client);

			if ($url && $title && $favs) {

				if (defined $preset) {
					# Add/overwrite preset for this slot
					$client->setPreset( {
						slot   => $preset,
						URL    => $url,
						text   => $title,
						type   => $type || 'audio',
						parser => $parser,
					} );
					
					$client->showBriefly( {
						'line' => [ $client->string('PRESET_ADDING', $preset), $title ]
					} );
				}
				else {
					$favs->add($url, $title, $type || 'audio', $parser, undef, $icon);
					
					$client->showBriefly( {
						'line' => [ $client->string('FAVORITES_ADDING'), $title ]
					} );
				}

			# if all of that fails, send the debug with a best guess helper for tracing back
			} else {

				if ($log->is_error) { 

					$log->error("Error: No valid url found, not adding favorite!");

					if (main::DEBUGLOG && $log->is_debug && $obj) {
						$log->error(Data::Dump::dump($obj));
					} else {
						$log->logBacktrace;
					}
				}
			}

		} elsif (mode($client) ne 'FAVORITES') {

			setMode($client, 'home');
			Slim::Buttons::Home::jump($client, 'FAVORITES');
			Slim::Buttons::Common::pushModeLeft($client, 'FAVORITES');
		}
	},
	
	# Play preset
	'playPreset' => sub {
		my ( $client, $button, $digit ) = @_;
		
		if ( $digit == 0 ) {
			$digit = 10;
		}
		
		my $preset = $prefs->client($client)->get('presets')->[ $digit - 1 ];
		
		if ( $preset && $preset->{type} =~ /audio|playlist/ ) {
			my $url   = $preset->{URL};
			my $title = $preset->{text};

			if ( $preset->{parser} || ($preset->{type} eq 'playlist' && Slim::Music::Info::isRemoteURL($url)) ) {

				main::INFOLOG && $log->info("Playing preset number $digit $title $url via xmlbrowser");

				my $item = {
					url    => $url,
					title  => $title,
					type   => $preset->{type},
					parser => $preset->{parser},
				};

				Slim::Buttons::XMLBrowser::playItem($client, $item);
			}
			else {
				main::INFOLOG && $log->info("Playing preset number $digit $title $url");

				Slim::Music::Info::setTitle($url, $title);

				$client->showBriefly($client->currentSongLines({ suppressDisplay => Slim::Buttons::Common::suppressStatus($client) }));

				$client->execute(['playlist', 'play', $url]);
			}
			$client->showBriefly( 
	                        {
              				         'jive' =>
	                                {
              			                         'type'    => 'popupplay',
                              			         'text'    => [ $client->string('PRESET', $digit), $title ],
	                                },
				}
			);
		}
		else {
			main::INFOLOG && $log->info("Can't play preset number $digit - not an audio entry");

			$client->showBriefly( {
				 line => [ sprintf($client->string('PRESETS_NOT_DEFINED'), $digit) ],
			} );
		}
	},

	# preset - IR remote (play or store depending on how long the button is held for)
	'preset' => sub {
		my ( $client, $button, $digit ) = @_;

		my $release = $digit =~ /release/;
		$digit =~ s/release//;
		my $num = $digit ? $digit : 10;

		if (!$release) {

			my $display = $client->curLines;

			if ($client->linesPerScreen == 1) {
				$display->{'line'}[1] = sprintf($client->string('PRESET'), $num);
			} else {
				$display->{'line'}[0] = sprintf($client->string('PRESET_HOLD_TO_SAVE'), $num);
			}
			$display->{'jive'} = undef;

			$client->showBriefly($display, { duration => 5, callback => sub {
				if (Slim::Hardware::IR::holdTime($client) > 5 ) {
					# do this on a timer so it happens after showBriefly ends and we can see any screen updates which result
					Slim::Utils::Timers::setTimer($client, Time::HiRes::time(), \&Slim::Hardware::IR::executeButton, "favorites_add$num", $client->lastirtime, undef, 1);
				}
			} });

		} else {

			if (Slim::Hardware::IR::holdTime($client) < 5 ) {
				Slim::Hardware::IR::executeButton($client, "playPreset_$num", $client->lastirtime, undef, 1);
			}
		}

	},

	# pressing recall toggles the repeat.
	'repeat' => sub  {
		my $client    = shift;
		my $button    = shift;
		my $buttonarg = shift;
		my $repeat    = undef;

		if (defined $buttonarg && $buttonarg =~ /^[0-2]$/) {
			$repeat = $buttonarg;
		}

		$client->execute(["playlist", "repeat", $repeat]);

		# display the fact that we are (not) repeating
		my $line;
		if (Slim::Player::Playlist::repeat($client) == 0) {
			$line = $client->string('REPEAT_OFF');

		} elsif (Slim::Player::Playlist::repeat($client) == 1) {
			$line = $client->string('REPEAT_ONE');

		} elsif (Slim::Player::Playlist::repeat($client) == 2) {
			$line = $client->string('REPEAT_ALL');
		}

		$client->showBriefly( {
			'line' => [ "", $line ],
			jive => {
				text => [ "", $line ],
				type => 'icon',
				style => 'repeat' . Slim::Player::Playlist::repeat($client),
			}
		});
		
	},

	# Volume always pushes into Slim::Buttons::Volume to allow Transporter and Boom knobs to be used
	# - from the volumemode front panel button use a push transition with 3 sec timeout
	# - for a remote volume up/down button just push the mode with 1 sec timeout
	# - for the front panel volume up/down push the mode with 3 sec timeout

	'volumemode' => sub {
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;

		return if (!$client->hasVolumeControl());
		
		if ($client->modeParam('parentMode') && $client->modeParam('parentMode') eq 'volume') {
			popModeRight($client);
		} else {
			pushModeLeft($client, 'volume', { 'timeout' => 3, 'transition' => 1, 'passthrough' => 0 });
		}
	},

	'volume' => sub {
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;

		return if (!$client->hasVolumeControl());

		my $timeout = $buttonarg && $buttonarg eq 'front' ? 3 : 1;

		if (!$client->modeParam('parentMode') || $client->modeParam('parentMode') ne 'volume') {
			pushMode($client, 'volume', {'timeout' => $timeout, 'transition' => 0, 'passthrough' => 1});
			$client->update;
		}
	},

	'pitch' => sub {
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;

		mixer($client, 'pitch', $buttonarg);
	},

	'bass' => sub {
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;

		mixer($client, 'bass', $buttonarg);
	},

	'treble' => sub {
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;

		mixer($client, 'treble', $buttonarg);
	},

	'muting' => sub  {
		my $client = shift;

		# try to avoid toggle commands, they make life difficult for listeners
		my $mute = !($prefs->client($client)->get('mute'));

		$client->execute(["mixer", "muting", $mute]);
	},

	'snooze' => sub  {
		my $client = shift;
		
		# Bug 8860, if setting the sleep timer, a single snooze press will
		# also adjust the timer
		if ( $client->modeParam('sleepMode') ) {
			Slim::Hardware::IR::executeButton( $client, 'sleep', undef, undef, 1 );
			return;
		}

		my $currentAlarm = Slim::Utils::Alarm->getCurrentAlarm($client);
		if (defined $currentAlarm) {
			$currentAlarm->snooze;
		} else {
			pushButton('datetime', $client);
		}
	},
	
	'sleep' => sub  {
		my $client = shift;
		
		# sleep function is overridden when alarm activates
		my $currentAlarm = Slim::Utils::Alarm->getCurrentAlarm($client);
		if (defined $currentAlarm) {
			
			main::INFOLOG && $log->info("Alarm Active: sleep function override for snooze");
			$currentAlarm->snooze;
			return;
		}
		
		# Bug: 2151 some extra stuff to add the option to sleep after the current song.
		# first make sure we're playing, and its a valid song.
		my $remaining = 0;

		if ($client->isPlaying()) { 

			my $dur = $client->controller()->playingSongDuration();

			# calculate the time based remaining, in seconds then into fractional minutes.
			$remaining = $dur - Slim::Player::Source::songTime($client);
			$remaining = $remaining / 60;
		}

		my @sleepChoices = (0,15,30,45,60,90);
		my $i = 0;

		# find the next value for the sleep timer
		for ($i = 0; $i <= $#sleepChoices; $i++) {
			
			# if remaining time is close to a default value, replace the default.
			if ( int($remaining + 0.5) == $sleepChoices[$i]) {
				
				$sleepChoices[$i] = $remaining;
			}
			
			if ( $sleepChoices[$i] > $client->currentSleepTime() ) {
				last;
			}
		}

		my $sleepTime = 0;
		if ($i > $#sleepChoices) {
		
			# set to remaining time if it's longer than the highest sleep option, 
			# and not already set at a time longer than the highest sleep option.
			$sleepTime = $remaining > $sleepChoices[-1] && 
							$client->currentSleepTime <= $sleepChoices[-1] ? $remaining : 0;
			
		# case of remaining time being in between the current sleep time and the next default option.
		} elsif ($remaining > $client->currentSleepTime && $remaining < $sleepChoices[$i]) {
			
			$sleepTime = $remaining;
		} else {

			# all else fails, go with the default next option
			$sleepTime = $sleepChoices[$i];
		}

		$client->execute(["sleep", $sleepTime * 60]);
		
		# This is used to enable the ability to press the snooze bar
		# again to quickly adjust the sleep time
		$client->modeParam( sleepMode => 1 );

		my $line = $sleepTime == 0 ? $client->string('CANCEL_SLEEP') : $client->prettySleepTime;

		$client->showBriefly( {
			jive => undef,
			line => [ "", $line ],
		},
		{
			scroll   => 1,
			callback => sub {
				$client->modeParam( sleepMode => 0 );
			}
		} );
	},

	'power' => sub  {
		my $client = shift;
		my $button = shift;
		my $power= undef;
		
		# try to avoid toggle commands, they make life difficult for listeners
		if ($button eq 'power_on') {
			$power = 1;
		} elsif ($button eq 'power_off') {
			$power = 0;
		} else {
			$power = $client->power() ? 0 : 1;
		}

		$client->execute(["power", $power]);
	},

	'shuffle' => sub  {
		my $client = shift;
		my $button = shift;
		my $shuffle = undef;

		if ($button eq 'shuffle_on') {
			$shuffle = 1;
		} elsif ($button eq 'shuffle_off') {
			$shuffle = 0;
		}

		$client->execute(["playlist", "shuffle" , $shuffle]);
		
		my $line;
		if (Slim::Player::Playlist::shuffle($client) == 2) {
			$line = $client->string('SHUFFLE_ON_ALBUMS');

		} elsif (Slim::Player::Playlist::shuffle($client) == 1) {
			$line = $client->string('SHUFFLE_ON_SONGS');

		} else {
			$line = $client->string('SHUFFLE_OFF');

		}

		$client->showBriefly( {
			'line' => [ '', $line ],
			jive => {
				text  => [ '', $line ],
				type  => 'icon',
				style => 'shuffle' . Slim::Player::Playlist::shuffle($client),
			}
		});

	},

	'titleFormat' => sub  {
		my $client = shift;

		# rotate the titleFormat
		$prefs->client($client)->set('titleFormatCurr' ,
			($prefs->client($client)->get('titleFormatCurr') + 1) %
			(scalar @{ $prefs->client($client)->get('titleFormat') })
		);

		$client->update();
	},

 	'datetime' => sub  {
		my $client = shift;

		# Use the DateTime plugin to display time/alarm info if it's available
		if (exists $INC{'Slim/Plugin/DateTime/Plugin.pm'}) {
			Slim::Plugin::DateTime::Plugin::showTimeOrAlarm($client);

		# otherwise just show the time and date
		} else {
			$client->showBriefly( dateTime($client), {
				'brightness' => 'powerOn',
				'duration' => 3
			});
		}
 	},

	'textsize' => sub  {
		my $client = shift;
		my $button = shift;

		my $doublesize = $client->textSize;

		if ($button eq 'textsize_large') {

			$doublesize = $client->maxTextSize;

		} elsif ($button eq 'textsize_medium') {

			$doublesize = 1;

		} elsif ($button eq 'textsize_small') {

			$doublesize = 0;

		} elsif ($button eq 'textsize_toggle') {

			$doublesize++;
		}

		if ($doublesize && $doublesize > $client->maxTextSize) {
			$doublesize = 0;
		}

		$client->textSize($doublesize);
		$client->update();
	},

	'clearPlaylist' => sub {
		my $client = shift;

		$client->showBriefly( {
			'line' => [ "", $client->string('CLEARING_PLAYLIST') ]
		});

		$client->execute(['playlist', 'clear']);
	},

	'modefunction' => sub {
		my ($client, $funct, $functarg) = @_;

		return if !$functarg;

		# XXXX - WTF?
		my ($mode,$modefunct) = split('->', $functarg, 2);

		return if !exists($modeFunctions{$mode});

		my $coderef = $modeFunctions{$mode}{$modefunct};
		my $modefunctarg;

 		if (!$coderef && ($modefunct =~ /(.+?)_(.+)/) && ($coderef = $modeFunctions{$mode}{$1})) {
 			$modefunctarg = $2;
 		}

		&$coderef($client,$modefunct,$modefunctarg) if $coderef;
	},

	'changeMap' => sub {
		my ($client, $funct, $functarg) = @_;

		return if !$functarg;

		my $mapref = Slim::Hardware::IR::mapfiles();
		my %maps   = reverse %$mapref;

		if (!exists($maps{$functarg})) {
			return;
		}

		$prefs->client($client)->set('irmap',$maps{$functarg});

		$client->showBriefly( {
			'line' => [ $client->string('SETUP_IRMAP') . ':', $functarg ]
		});
	},

	'home' => sub {
		my ($client, $funct, $functarg) = @_;

		my $display    = $client->display;
		my $oldscreen2 = $client->modeParam('screen2active');
		my $oldlines   = $client->curLines;

		if ($client->modeParam('HOME-MENU')) {

			main::INFOLOG && $log->info("Switching to playlist view.");

			Slim::Buttons::Common::setMode($client, 'home');
			Slim::Buttons::Home::jump($client, 'NOW_PLAYING');

			pushMode($client, 'playlist');

			unless ($display->hasScreen2) {

				$display->pushLeft($oldlines, $display->curLines({ trans => 'pushModeLeft' }));

			} else {

				$client->pushLeft($oldlines, pushpopScreen2($client, $oldscreen2, $display->curLines({ trans => 'pushModeLeft' })));
			}

		} else {

			main::INFOLOG && $log->info("Switching to home menu.");

			Slim::Buttons::Common::setMode($client, 'home');

			unless ($display->hasScreen2) {

				$display->pushRight($oldlines, $display->curLines({ trans => 'pushModeRight'}));

			} else {

				$display->pushRight($oldlines, pushpopScreen2($client, $oldscreen2, $display->curLines({ trans => 'pushModeRight' })));
			}
		}
	},

	'zap' => sub {
		my $client = shift;
		
		if (Slim::Player::Playlist::count($client) > 0) {

			# we zap the displayed song in playlist mode and playing song in all others
			my $index = mode($client) eq 'playlist' ? Slim::Buttons::Playlist::browseplaylistindex($client) : 
				Slim::Player::Source::playingSongIndex($client);
			
			$client->showBriefly( {
				'line' => [ $client->string('ZAPPING_FROM_PLAYLIST'), 
							Slim::Music::Info::standardTitle($client, Slim::Player::Playlist::song($client, $index)) ]
			   }, {'firstline' => 1, block => 1 }
			); 
			
			$client->execute(["playlist", "zap", $index]);
		}
	},
);

sub getFunction {
	my $client     = shift || return;
	my $function   = shift || return;
	my $clientMode = shift || mode($client);

 	my $coderef;
	if ($coderef = $modeFunctions{$clientMode}{$function}) {

 		return $coderef;

 	} elsif (($function =~ /(.+?)_(.+)/) && ($coderef = $modeFunctions{$clientMode}{$1})) {

 		return ($coderef, $2);
 
 	} elsif ($coderef = $functions{$function}) {

 		return $coderef;

 	} elsif (($function =~ /(.+?)_(.+)/) && ($coderef = $functions{$1})) {

 		return ($coderef, $2)
	}
}

=head2 setFunction( $mapping, $function )

setFunction enables a Plugin to affect all common modes. 

Originally added to allow Favorites plugin to make holding a number be a
shortcut to playing a users favorite station.

=cut

sub setFunction {
	my $mapping = shift;
	my $function = shift;

	$functions{$mapping} = $function;
}

sub pushButton {
	my $sub = shift;
	my $client = shift;

	no strict 'refs';

	my ($subref, $subarg) = getFunction($client,$sub);

	&$subref($client, $sub, $subarg);
}

# Return the sign of the argument as -1 or 1.  If arg is 0, then return 1.
sub sign {
	my $arg = shift;
	if ($arg < 0) {
		return -1;
	} else {
		return 1;
	}
}


sub scroll {
	scroll_dynamic(@_);
}

=head2 scrollDynamic ( $client, $direction, $listlength, $currentPosition )

This is a common UI function for moving up or down through a list,
accelerating as the scrolling continues.

Four arguments are required:

The $client object

$direction is typically either 1 or -1, but any positive or negative number
will properly decide direction

$listlength is the total number of items in the current list

$currentPosition is the zero-indexed position of the current item shown on the
player screen, from which the scroll is required to move.

The IR holdtime triggers acceleration of the scrolling effect.

=cut

sub scroll_dynamic {
	my $client = shift;
	my $direction = shift;
	my $listlength = shift;
	my $currentPosition = shift;
	my $newposition;
	my $holdTime = Slim::Hardware::IR::holdTime($client);
	# Set up initial conditions
	if (!defined $scrollClientHash->{$client}) {
		#$client->{scroll_params} =
		$scrollClientHash->{$client}{scrollParams} = scroll_getInitialScrollParams($minimumVelocity, $listlength, $direction);
	}

	my $scrollParams = $scrollClientHash->{$client}{scrollParams};
	
	my $knobData = $client->knobData;

	my $result = undef;
	if ($knobData->{'_knobEvent'}) {
		# This is a boom knob event.  Calculate acceleration for this case.
		$result=$currentPosition;
		my $velocity      = $knobData->{'_velocity'};
		my $acceleration  = $knobData->{'_acceleration'};
		my $deltatime     = $knobData->{'_deltatime'};
		if ($velocity == 0) {
			$result = $currentPosition + (($direction > 0) ? 1 : -1);
			if ($deltatime < 2) {
				# We just changed directions, or stopped for a bit and restarted the same direction
				# So, just update the start and end estimates.
				if ($direction > 0) {
					# Moving up in list, stopped, and kept moving up
					$scrollParams->{estimateStart} = $currentPosition;
					$scrollParams->{estimateEnd}   = $scrollParams->{estimateEnd} - ($scrollParams->{estimateEnd} - $currentPosition)/2;
				} elsif ($direction < 0) {
					$scrollParams->{estimateStart} = $scrollParams->{estimateStart} + ($currentPosition - $scrollParams->{estimateStart})/2;
					$scrollParams->{estimateEnd}   = $currentPosition;
				}
				if ($scrollParams->{estimateEnd} > $listlength) {
					$scrollParams->{estimateEnd} = $listlength;
				}
				if ($scrollParams->{estimateStart} < 0) {
					$scrollParams->{estimateStart} = 0;
				}
			} else {
				# We just starting moving
				$scrollParams->{estimateStart} = 0;
				$scrollParams->{estimateEnd}   = $listlength;
			}
			$scrollParams->{A}             = 0;
			$scrollParams->{V}             = 0;
			$scrollParams->{t0}            = $knobData->{'_time'};
			$scrollParams->{hitEndTime}    = undef;
			$scrollParams->{time}          = 0;
			$scrollParams->{lasttime}      = 0;
			if ($result < 0) {
				$result = $listlength;
			} elsif ($result >= $listlength) {
				$result = 0;
			}
		} else {
			# We should start accelerating now...
			my $timeToCompleteList = $scrollParams->{Kc} / $velocity; # seconds/full_list
			my $estimatedLength = $scrollParams->{estimateEnd} - $scrollParams->{estimateStart};
			# We can calculate the needed acceleration by the formula
			$scrollParams->{time} += $deltatime;
			my $time     = $scrollParams->{time};
			my $lasttime = $scrollParams->{lasttime};
			$scrollParams->{A} = 2* $estimatedLength/($timeToCompleteList*$timeToCompleteList) ;
			$scrollParams->{V} = $scrollParams->{V} + $scrollParams->{A} * $deltatime;
			my $deltaX = .5 * $scrollParams->{A} * ($time*$time - $lasttime*$lasttime);
			my $maxDeltaXPercent = $scrollParams->{KmaxScrollPct} / 100;
			my $maxDeltaX = ($maxDeltaXPercent * $listlength);
			if (abs($deltaX) > $maxDeltaX) {
				$deltaX = $maxDeltaX * sign($deltaX);
			}
			if ($deltaX < 1) {
				$deltaX = 1;
			}
			$deltaX = int($deltaX);
			if ($velocity < 0) {
				$deltaX = - $deltaX;
			}
			$result = $currentPosition + $deltaX;
			if ($result < 0 || $result > $listlength-1) {
				my $rollover = 0;
				if (!defined $scrollParams->{hitEndTime}) {
					$scrollParams->{hitEndTime} = $knobData->{'_time'};
				} else {
					# We hit the end previously.  Calculate the difference in time between then and now.
					my $deltaT = $knobData->{'_time'} - $scrollParams->{hitEndTime};
					my $rolloverTime = $scrollParams->{KrolloverTime};
					if ($deltaT > $rolloverTime) {
						$rollover = 1;
						$scrollParams->{hitEndTime} = undef;
					}
				}
				if ($rollover) {
					if ($result < 0) {
						$result = $listlength-1;
					} else {
						$result = 0;
					}
				}
			}
				
			$scrollParams->{lasttime} = $time;
			if ($result > $scrollParams->{estimateEnd}) {
				$scrollParams->{estimateEnd} = $scrollParams->{estimateEnd} + ($scrollParams->{estimateEnd} - $scrollParams->{estimateStart});
			}
			if ($result < $scrollParams->{estimateStart}) {
				$scrollParams->{estimateStart} = $scrollParams->{estimateStart} - ($scrollParams->{estimateEnd} - $scrollParams->{estimateStart});
			}
			if ($scrollParams->{estimateStart} < 0) {
				$scrollParams->{estimateStart} = 0;
			}
			if ($scrollParams->{estimateEnd} > $listlength) {
				$scrollParams->{estimateEnd} = $listlength;
			}
			
		}
		
	} else {
	
		if ($holdTime == 0) {
			# define behavior for button press, before any acceleration
			# kicks in.
			
			# if at the end of the list, and down is pushed, go to the beginning.
			if ($currentPosition == $listlength-1  && $direction > 0) {
				# if at the end of the list, and down is pushed, go to the beginning.
				$currentPosition = -1; # Will be added to later...
				$scrollParams->{estimateStart} = 0;
				$scrollParams->{estimateEnd}   = $listlength - 1;
			} elsif ($currentPosition == 0 && $direction < 0) {
				# if at the beginning of the list, and up is pushed, go to the end.
				$currentPosition = $listlength;  # Will be subtracted from later.
				$scrollParams->{estimateStart} = 0;
				$scrollParams->{estimateEnd}   = $listlength - 1;
			}
			# Do the standard operation...
			$scrollParams->{lastHoldTime} = 0;
			$scrollParams->{V} = $scrollParams->{minimumVelocity} *
				$direction;
			$scrollParams->{A} = 0;
			$result = $currentPosition + $direction;
			if ($direction > 0) {
				$scrollParams->{estimateStart} = $result;
				if ($scrollParams->{estimateEnd} <
					$scrollParams->{estimateStart}) {
					$scrollParams->{estimateEnd} =
						$scrollParams->{estimateStart} + 1; 
				}
			} else {
				$scrollParams->{estimateEnd} = $result;
				if ($scrollParams->{estimateStart} >
					$scrollParams->{estimateEnd}) {
					$scrollParams->{estimateStart} =
						$scrollParams->{estimateEnd} - 1;
				}
			}
			scroll_resetScrollRange($result, $scrollParams, $listlength);
			$scrollParams->{lastPosition} = $result;
		} elsif ($holdTime < $holdTimeBeforeScroll) {
			# Waiting until holdTimeBeforeScroll is exceeded
			$result = $currentPosition;
		} else {
			# define behavior for scrolling, i.e. after the initial
			# timeout.
			$scrollParams->{A} = scroll_calculateAcceleration
				(
				 $direction, 
				 $scrollParams->{estimateStart},
				 $scrollParams->{estimateEnd},
				 $scrollParams->{Tc}
				 );
			my $accel = $scrollParams->{A};
			my $time = $holdTime - $scrollParams->{lastHoldTime};
			my $velocity = $scrollParams->{A} * $time + $scrollParams->{V};
			my $pos = ($scrollParams->{lastPositionReturned} == $currentPosition) ? 
				$scrollParams->{lastPosition} : 
				$currentPosition;
			my $X = 
				(0.5 * $scrollParams->{A} * $time * $time) +
				($scrollParams->{V} * $time) + 
				$pos;
			$scrollParams->{lastPosition} = $X; # Retain the last floating
			                                    # point value of $X
			                                    # because it's needed to
			                                    # maintain the proper
			                                    # acceleration when
			                                    # $minimumVelocity is
			                                    # small and not much
			                                    # motion happens between
			                                    # successive calls.
			$result = int(0.5 + $X);
			scroll_resetScrollRange($result, $scrollParams, $listlength);
			$scrollParams->{V} = $velocity;
			$scrollParams->{lastHoldTime} = $holdTime;
		}
	}
	if ($result >= $listlength) {
		$result = $listlength - 1;
	}
	if ($result < 0) {
		$result = 0;
	}
	$scrollParams->{lastPositionReturned} = $result;
	$scrollParams->{lastDirection}        = $direction;
	return $result;
}

sub scroll_resetScrollRange
{
	my $currentPosition = shift;
	my $scrollParams    = shift;
	my $listlength      = shift;

	my $delta = ($scrollParams->{estimateEnd} - $scrollParams->{estimateStart})+1;
	if ($currentPosition > $scrollParams->{estimateEnd}) {
	    $scrollParams->{estimateEnd} = $scrollParams->{estimateEnd} + $delta;
	    if ($scrollParams->{estimateEnd} >= $listlength) {
			$scrollParams->{estimateEnd} = $listlength-1;
	    }
	} elsif ($currentPosition < $scrollParams->{estimateStart}) {
	    $scrollParams->{estimateStart} = $scrollParams->{estimateStart} - $delta;
	    if ($scrollParams->{estimateStart} < 0) {
			$scrollParams->{estimateStart} = 0;
		}
	}
}

sub scroll_calculateAcceleration {
	my ($direction, $estimatedStart, $estimatedEnd, $Tc)  = @_;
	my $deltaX = $estimatedEnd - $estimatedStart;

	return 2.0 * $deltaX / ($Tc * $Tc) * $direction;
}

sub scroll_getInitialScrollParams {
	my $minimumVelocity = shift; 
	my $listLength      = shift;
	my $direction       = shift;

	my $result = {
		# Constants.
		# Items/second.  Don't go any slower than this under any circumstances. 
		minimumVelocity => $minimumVelocity,  
					
		# Knob -> acceleration constant.  
		# This constant converts wheel speed (ticks/second) into 'time to complete full list' (seconds for list_items)
		# For example, if you're spinning the knob .5 revolution (10 ticks) per second, and Kc is 2,
		# We should traverse the entire list in 2 / 0.5 = 4 seconds.   
		Kc              => 100,
		
		KmaxScrollPct   => 1, # Maximum step, in percentage of list length
		
		KrolloverTime   => 0.8, # Time that it takes while spinning knob to roll over.

		# seconds.  Finishs a list in this many seconds. 
		Tc              => 5,   

		# Variables
		# Starting estimate of target space.
		estimateStart   => 0,   
		
		# Ending estimate of target space
		estimateEnd     => $listLength, 
					
		# The current velocity.  account for direction
		V               => $minimumVelocity * $direction,
		
		# The current acceleration.
		A               => 0,

		# The 'hold Time' value the last time we were called.
		# a negative number means it hasn't been called before, or
		# the button has been released.
		lastHoldTime    => -1,

		# To make the 
		lastPosition    => 0,      # Last calculated position (floating point)
		lastPositionReturned => 0, # Last returned position   (integer), used to detect when $currentPosition 
					   # has been modified outside the scroll routines.
		
		# Maintain the last direction, so that we can implement a
		# slowdown when the user hits  the same direciton twice.
		# i.e. he's almost to where he wants to go, but not quite
		# there yet.  Slow velocity by half, and don't wait for
		# pause. 
		#lastDirection   => 0,      
	};

	return $result;
}

=head2 mixer ( $client, $feature, $setting)

Update audio mixer settings

$client object is required.
$feature argument is a string to determine which of teh mixer settings is to be changed: bass/treble/pitch where applicable
$setting is a scalar value for the new mixer setting.  Optionally it may be the string 'up' or 'down to adjust the current
value either up or down.  

Holding the IR button causes the up or down adjustment to accelerate the longer the button is held.

=cut

sub mixer {
	my $client = shift;
	my $feature = shift; # bass/treble/pitch
	my $setting = shift; # up/down/value
	
	my $accel = 8; # Hz/sec
	my $rate = 50; # Hz
	my $inc = 1;
	my $midpoint = $client->mixerConstant($feature,'mid');

	my $cmd;
	if (Slim::Hardware::IR::holdTime($client) > 0) {
		$inc *= Slim::Hardware::IR::repeatCount($client,$rate,$accel);
	} else {
		$inc = $client->mixerConstant($feature,'increment');
	}
	
	if ((!$inc && $setting =~ /up|down/) || $feature !~ /volume|bass|treble|pitch/) {
		return;
	}
	
	my $currVal = $prefs->client($client)->get($feature);
	if ($setting  eq 'up') {
		$cmd = "+$inc";
		if ($currVal < ($midpoint - 1.5) && ($currVal + $inc) >= ($midpoint - 1.5)) {
			# make the midpoint sticky by resetting the start of the hold
			$cmd = $midpoint;
			Slim::Hardware::IR::resetHoldStart($client);
		}
	} elsif ($setting eq 'down') {
		$cmd = "-$inc";
		if ($currVal > ($midpoint + 1.5) && ($currVal - $inc) <= ($midpoint + 1.5)) {
			# make the midpoint sticky by resetting the start of the hold
			$cmd = $midpoint;
			Slim::Hardware::IR::resetHoldStart($client);
		}
	} elsif ($setting =~ /(\d+)/) {
		$cmd = $1;
	} else {
		# just display current value
		$client->mixerDisplay($feature);
		return;
	}
		
	$client->execute(["mixer", $feature, $cmd]);
	
	$client->mixerDisplay($feature);
}

sub numberLetter {
	my $client = shift;
	my $digit = shift;
	my $table = shift || \@numberLetters;
	my $letter;
	my $index;

	my $now = Time::HiRes::time();
	# if the user has hit new button or hasn't hit anything for 1.0 seconds, use the first letter
	if (($digit ne $client->lastLetterDigit) ||
		($client->lastLetterTime + $prefs->get('displaytexttimeout') < $now)) {
		$index = 0;
	} else {
		$index = $client->lastLetterIndex + 1;
		$index = $index % (scalar(@{$table->[$digit]}));
	}

	$client->lastLetterDigit($digit);
	$client->lastLetterIndex($index);
	$client->lastLetterTime($now);

	return $table->[$digit][$index];
}

sub testSkipNextNumberLetter {
	my $client = shift;
	my $digit = shift;
	return (($digit ne $client->lastLetterDigit) && (($client->lastLetterTime + $prefs->get('displaytexttimeout')) > Time::HiRes::time()));
}

sub numberScroll {
	my $client = shift;
	my $digit = shift;
	my $listref = shift;
	my $sorted = shift; # is the list sorted?

	# optional reference to subroutine that takes a single parameter
	# of an index and returns the value for the item in the array we're searching.
	my $lookupsubref = shift;

	my $listsize = scalar @{$listref};

	if ($listsize <= 1) {
		return 0;
	}

	my $i;
	if (!$sorted) {
		# If there are 10 items or less then jump straight to the requested item
		if ($listsize <= 10) {
			$i = ($digit - 1) % 10;
			if ($i > $listsize - 1) { $i = $listsize - 1; }
		}else{
			my $now = Time::HiRes::time();
			# If the user hasn't pressed a button for the last 1.0 seconds then jump straight to the requested item
			if ($client->lastDigitTime + $prefs->get('displaytexttimeout') < $now) {
				$i = ($digit - 1) % 10;
			}else{
				$i = $client->lastDigitIndex * 10 + $digit - 1;
			}
			if ($i > $listsize - 1) { $i = $listsize - 1; }

			$client->lastDigitIndex($i + 1);
			$client->lastDigitTime($now);
		}
	} else {

		if (!defined($lookupsubref)) {
			$lookupsubref = sub { return $listref->[shift]; }
		}

		my $letter = numberLetter($client, $digit);
		# binary search	through the diritems, assuming that they are sorted...
		$i = firstIndexOf($letter, $lookupsubref, $listsize);


		# reset the scroll parameters so that the estimated start and end are at the previous letter and next letter respectively.
		$scrollClientHash->{$client}{scrollParams}{estimateStart} =
			firstIndexOf(chr(ord($letter)-1), $lookupsubref, $listsize);
		$scrollClientHash->{$client}{scrollParams}{estimateEnd} = 
			firstIndexOf(chr(ord($letter)+1), $lookupsubref, $listsize);
	}
	return $i;
}
# 
# utility function for numberScroll.  Does binary search for $letter,
# using $lookupsubref to lookup where we are.
# 
sub firstIndexOf
{
	my ($letter, $lookupsubref, $listsize)  = @_;

	my $high = $listsize;
	my $low = -1;
	my $i = -1;
	for ( $low = -1; $high - $low > 1; ) {
		$i = int(($high + $low) / 2);
		my $j = uc(substr($lookupsubref->($i), 0, 1));
		if ($letter eq $j) {
			last;
		} elsif ($letter lt $j) {
			$high = $i;
		} else {
			$low = $i;
		}
	}
	
	# skip back to the first matching item.
	while ($i > 0 && $letter eq uc(substr($lookupsubref->($i-1), 0, 1))) {
		$i--;
	}
	return $i;

}

=head2 mode ( $client)

Return the unique string name for the current player mode.

Required argument is the $client object for which the current mode information is desired.

=cut

# called very frequently so optimised for speed
sub mode {
	$_[0] ? $_[0]->modeStack->[-1] : undef;
}

=head2 validMode ( $client)

Given a string, returns true or false if the given string is a match for a valid, registered player mode.

=cut

sub validMode {
	my $mode = shift;

	return exists $modes{$mode} ? 1 : 0;
}

=head2 checkBoxOverlay ( $client, $value)

This is a standard UI widget for showing a multi-selected item in a list, or a true/false state of a setting

If the $client argument is a valid client object, graphics capable players will show a 'check box'-style ui.
Otherwise, an text-based check box will be marked wtih an X for true and empty for false.

The $value argument is a boolean result provided by the caller to determine if the box is checked or not.

=cut

# standard UI feature multi-select list
sub checkBoxOverlay {
	my $client = shift;
	my $value = shift;

	unless (blessed($client) && $client->isa('Slim::Player::Client')) {

		logBacktrace("Plugins must provide client when calling checkBoxOverlay!");

		$value = $client;

	} elsif ($client->display->isa('Slim::Display::Graphics')) {

		return $client->symbols( $value ? 'filledsquare' : 'square' );
	}

	return $value ? "[X]" : "[ ]";
}

=head2 radioButtonOverlay ( $client, $value)

This is a standard UI widget for showing a single-selected item in a list

If the $client argument is a valid client object, graphics capable players will show a 'radio button'-style ui.
Otherwise, an text-based radio button will be marked wtih an O for true and empty for false.

The $value argument is a boolean result provided by the caller to determine if the box is checked or not.

=cut

# standard UI feature enable/disable a setting
sub radioButtonOverlay {
	my $client = shift;
	my $value = shift;

	unless (blessed($client) && $client->isa('Slim::Player::Client')) {

		logBacktrace("Plugins must now provide client when calling radioButtonOverlay!");

		$value = $client;

	} elsif ($client->display->isa('Slim::Display::Graphics')) {

		return $client->symbols( $value ? 'filledcircle' : 'circle' );
	}

	return $value ? "(O)" : "( )";
}



sub param {
	my $client = shift;
	return $client->modeParam(@_);
}

=head2 pushMode ( $client, $setmode, [ $paramHashRef ])

Push the next mode onto the client's mode stack.

pushMode takes the following parameters:
   client - reference to a client structure
   setmode - name of mode we are pushing into
   paramHashRef - optional reference to a hash containing the parameters for that mode. 
      If no preset params are required, this arg is not required.

=cut
sub pushMode {
	my $client = shift;
	my $setmode = shift;
	my $paramHashRef = shift;

	main::INFOLOG && $log->info("Pushing button mode: $setmode");

	my $oldscreen2 = $client->modeParam('screen2active');

	my $oldmode = mode($client);

	if ($oldmode) {

		my $exitFun = $leaveMode{$oldmode};

		if ($exitFun && ref($exitFun) eq 'CODE') {

			eval { &$exitFun($client, 'push') };

			if ($@) {
				logError("Couldn't execute mode exit function: $@");
			}
		}
	}

	# reset the scroll parameters
	push (@{$scrollClientHash->{$client}{scrollParamsStack}}, 
		$scrollClientHash->{$client}{scrollParams});
	
	$scrollClientHash->{$client}{scrollParams} = scroll_getInitialScrollParams($minimumVelocity, 1, 1);

	push @{$client->modeStack}, $setmode;

	if (!defined($paramHashRef)) {
		$paramHashRef = {};
	}

	# Bug 8864: copy state of screen2 into new mode so case of recursively pushing modes can see existing state
	if ($client->display->hasScreen2) {
		$paramHashRef->{'screen2active'} = $client->modeParam('screen2active');
	}

	push @{$client->modeParameterStack}, $paramHashRef;

	my $newModeFunction = $modes{$setmode};

	if (!$newModeFunction || ref($newModeFunction) ne "CODE") {

		logError("Crashing because '$setmode' has no mode function or a bogus function. Perhaps you mis-typed the mode name.");
	}

	eval { &$newModeFunction($client, 'push') };

	if ($@) {
		logError("Couldn't push into new mode: [$setmode] !: $@");

		pop @{$scrollClientHash->{$client}{scrollParamsStack}};
		pop @{$client->modeStack};
		pop @{$client->modeParameterStack};

		return;
	}

	if ($client->display->hasScreen2) {
		my $screen2 = $client->modeParam('screen2');

		if ($client->display->showExtendedText() && $client->power() && !$screen2) {
			$screen2 = 'periodic';
		} elsif ($screen2 && $screen2 eq 'inherit') {
			$screen2 = $oldscreen2;
		}

		# set active param so we can modify it later
		$client->modeParam('screen2active', $screen2);
	}

	# some modes require periodic updates
	startPeriodicUpdates($client);
	
	$client->updateKnob(1);
}

=head2 popMode ( $client, $setmode, [ $paramHashRef ])

Pop's the current mode from the mode stack, and returns the player to the previous mode on the stack.

Only the $client object or structure is a required argument for popMode.

If the mode stack is empty, this function only updates the knob parameters and exits.

=cut
sub popMode {
	my $client = shift;

	if (scalar(@{$client->modeStack}) < 1) {

		$client->updateKnob(1);

		main::INFOLOG && $log->info("Nothing on the modeStack - updatingKnob & returning.");

		return undef;
	}

	my $oldscreen2 = $client->modeParam('screen2active');

	my $oldMode = mode($client);

	if ($oldMode) {

		my $exitFun = $leaveMode{$oldMode};

		if ($exitFun && ref($exitFun) eq 'CODE') {

			eval { &$exitFun($client, 'pop') };

			if ($@) {
				logError("Couldn't execute mode exit function: $@");
			}
		}
	}
	
	pop @{$client->modeStack};
	pop @{$client->modeParameterStack};
	$scrollClientHash->{$client}{scrollParams} = pop @{$scrollClientHash->{$client}{scrollParamsStack}};
	
	my $newMode = mode($client);

	# Block mode is special.  Avoid running setmode again when leaving block mode as this 
	# can cause confusion (eq. broken play in BMF)
	if ($newMode && $oldMode ne 'block') {

		my $fun = $modes{$newMode};

		eval { &$fun($client,'pop') };

		if ($@) {
			logError("Couldn't execute setMode on pop: $@");
		}
	}

	if ( main::INFOLOG && $log->is_info ) {
		$log->info("Popped to button mode: " . (mode($client) || 'empty!'));
	}

	if ($client->display->hasScreen2) {

		my $suppressScreen2Update = shift;

		my $screen2 = $client->modeParam('screen2active');

		if ($client->display->showExtendedText() && $client->power()) {

			$client->modeParam('screen2active', 'periodic') unless $screen2;

		} elsif ($screen2 && $screen2 eq 'periodic') {

			$client->modeParam('screen2active', undef);
		}

		if (!$suppressScreen2Update && $oldscreen2 && !$client->modeParam('screen2active')) {

			$client->update( { 'screen2' => {} } );
		}
	}

	# some modes require periodic updates
	startPeriodicUpdates($client);

	$client->updateKnob(1);
	
	return $oldMode
}

sub setMode {
	my $client = shift;
	my $setmode = shift;
	my $paramHashRef = shift;

	while (popMode($client)) {};

	pushMode($client, $setmode, $paramHashRef);
}

sub pushModeLeft {
	my $client = shift;
	my $setmode = shift;
	my $paramHashRef = shift;
	my $display = $client->display();

	my $oldlines = $display->curLines();

	unless ($display->hasScreen2) {
		
		pushMode($client, $setmode, $paramHashRef);

		if (!$client->modeParam('handledTransition')) {
			$display->pushLeft($oldlines, $display->curLines({ trans => 'pushModeLeft' }));
			$client->modeParam('handledTransition',0);
		}

	} else {

		my $oldscreen2 = $client->modeParam('screen2active');

		pushMode($client, $setmode, $paramHashRef);

		if (!$client->modeParam('handledTransition')) {
			$client->pushLeft($oldlines, pushpopScreen2($client, $oldscreen2, $display->curLines({ trans => 'pushModeLeft' })));
			$client->modeParam('handledTransition',0);
		}
	}
}

sub popModeRight {
	my $client = shift;
	my $display = $client->display();

	my $oldlines = $display->curLines();

	unless ($display->hasScreen2) {

		Slim::Buttons::Common::popMode($client);

		$display->pushRight($oldlines, $display->curLines({ trans => 'pushModeRight'}));

	} else {

		my $oldscreen2 = $client->modeParam('screen2active');

		Slim::Buttons::Common::popMode($client, 1);

		$display->pushRight($oldlines, pushpopScreen2($client, $oldscreen2, $display->curLines({ trans => 'pushModeRight' })));
	}
}

sub pushpopScreen2 {
	my $client = shift;
	my $oldscreen2 = shift;
	my $newlines = shift;

	my $display = $client->display;

	my $newscreen2 = $client->modeParam('screen2active');

	if ($newscreen2 && $newscreen2 eq 'periodic' && (!$oldscreen2 || $oldscreen2 ne 'periodic')) {
		my $linesfunc = $client->lines2periodic();
		$newlines->{'screen2'} = $linesfunc->($client, { screen2 => 1 })->{'screen2'};

	} elsif ($oldscreen2 && !$newscreen2) {
		$newlines->{'screen2'} = {};
	}

	return $newlines;
}

sub updateScreen2Mode {
	my $client = shift || return;

	my $screen2 = $client->modeParam('screen2active');

	if ($client->display->showExtendedText() && $client->power()) {
		if (!$screen2) {
			$client->modeParam('screen2active', 'periodic');
			startPeriodicUpdates($client);
		}
	} else {
		if ($screen2) {
			if ($screen2 eq 'periodic') {
				$client->modeParam('screen2active', undef);
			}
			$client->update( { 'screen2' => {} } );
		}
	}
}

sub suppressStatus {
	my $client = shift;

	my $suppress = $client->suppressStatus();

	return $suppress if (defined ($suppress));

	return undef unless $client->display->hasScreen2();

	my $screen2 = $client->modeParam('screen2active');

	if ($screen2 && $screen2 eq 'periodic') {
		return 1;
	}

	return undef;
}

sub msgOnScreen2 {
	my $client = shift;

	if ($client->display->hasScreen2) {

		my $screen2 = $client->modeParam('screen2active');
		
		if ($screen2 && $screen2 eq 'periodic') {
			return 1;
		}
	}

	return undef;
}

sub dateTime {
	my $client = shift;
	
	my $line;

	# Use the DateTime plugin to get the lines if it's available
	if (exists $INC{'Slim/Plugin/DateTime/Plugin.pm'}) {
		$line = Slim::Plugin::DateTime::Plugin::dateTimeLines($client);
	} else {
		# Fall back to a more basic date/time display
		# client-specific date/time on SN
		$line = {
			'center' => [ $client->longDateF(), $client->timeF() ],
		};
	}
	
	return $line;
}

sub startPeriodicUpdates {
	my $client = shift;
	# Optional time for first update
	my $startTime = shift;

	# unset any previous timers
	Slim::Utils::Timers::killTimers($client, \&_periodicUpdate);

	return if $client->display->isa('Slim::Display::NoDisplay');

	my $interval  = $client->modeParam('modeUpdateInterval');
	my $interval2 = undef;

	if ($client->modeParam('screen2active') && $client->modeParam('screen2active') eq 'periodic') {

		$interval2 = 1;
	}

	return unless ($interval || $interval2);

	my $time = $startTime || (Time::HiRes::time() + ($interval || 0.05));

	Slim::Utils::Timers::setTimer($client, $time, \&_periodicUpdate, $client);

	$client->periodicUpdateTime($time);
}

# resync periodic updates to $time - to synchronise updates with time/elapsed time
sub syncPeriodicUpdates {
	my $client = shift;
	my $time = shift || Time::HiRes::time();

	if (Slim::Utils::Timers::killTimers($client, \&_periodicUpdate)) {
		Slim::Utils::Timers::setTimer($client, $time, \&_periodicUpdate, $client);
		$client->periodicUpdateTime($time);
	}
}

sub _periodicUpdate {
	my $client = shift;

	my $update  = $client->modeParam('modeUpdateInterval');
	my $update2 = undef;

	if ($client->modeParam('screen2active') && $client->modeParam('screen2active') eq 'periodic') {

		$update2 = 1;
	}

	# if params not set then no longer required
	return unless ($update || $update2);

	# schedule the next update time, skip if running late
	my $time     = $client->periodicUpdateTime();
	my $timenow  = Time::HiRes::time();
	my $interval = $update || 1;

	do {
		$time += $interval;
	} while ($time < $timenow);

	Slim::Utils::Timers::setTimer($client, $time, \&_periodicUpdate, $client);

	$client->periodicUpdateTime($time);

	my $display = $client->display;

	if ($update && !$display->updateMode) {

		if (my $screen = $client->curLines({ periodic => 1 })) {

			$display->update( $screen );
		}
	}

	if ($update2 && (!$display->updateMode || $display->screen2updateOK) && (my $linefunc = $client->lines2periodic()) ) {

		my $screen2 = eval { &$linefunc($client, { screen2 => 1, periodic => 1 }) };

		if ($@) {
			logError("bad screen2 lines: $@");
		}

		$display->update($screen2, undef, 1);
	}
}

=head1 SEE ALSO

L<Scalar::Util>

L<Slim::Display::Display>

L<Slim::Buttons::*>

=cut

1;

__END__
