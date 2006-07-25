package Slim::Buttons::Common;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Scalar::Util qw(blessed);

use Slim::Player::Client;
use Slim::Utils::Misc;
use Slim::Utils::PluginManager;
use Slim::Display::Display;
use Slim::Buttons::SqueezeNetwork;
use Slim::Buttons::XMLBrowser;
use Slim::Buttons::Volume;

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

# Hashed list for registered Screensavers. Register these using addSaver. 
our %savers = ();

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

# The address of the function hash is set at run time rather than compile time
# so initialize the modeFunctions hash here
sub init {

	# Home must come first!
	Slim::Buttons::Home::init();

	Slim::Buttons::AlarmClock::init();
	Slim::Buttons::BrowseDB::init();
	Slim::Buttons::BrowseTree::init();
	Slim::Buttons::Information::init();
	Slim::Buttons::Playlist::init();
	Slim::Buttons::XMLBrowser::init();
	Slim::Buttons::Power::init();
	Slim::Buttons::ScreenSaver::init();
	Slim::Buttons::Search::init();
	Slim::Buttons::Settings::init();
	Slim::Buttons::SqueezeNetwork::init();
	Slim::Buttons::Synchronize::init();
	Slim::Buttons::TrackInfo::init();
	Slim::Buttons::RemoteTrackInfo::init();
	Slim::Buttons::Volume::init();

	$savers{'playlist'} = Slim::Utils::Strings::string('NOW_PLAYING');
}

sub addSaver {
	my $name = shift;
	my $buttonFunctions = shift;
	my $setModeFunction = shift;
	my $leaveModeFunction = shift;
	my $displayName = shift;

	$savers{$name} = $displayName;

	$::d_plugins && msg("Registering screensaver $displayName\n");

	addMode($name, $buttonFunctions, $setModeFunction, $leaveModeFunction);
	if ($name =~ s/^SCREENSAVER\./OFF\./) {
		addMode($name, $buttonFunctions, $setModeFunction, $leaveModeFunction);
	}
}

sub hash_of_savers {
	return \%savers;
}

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
		# ignore if we aren't playing anything or if we're scanning
		my $playlistlen = Slim::Player::Playlist::count($client);
		my $rate = Slim::Player::Source::rate($client);
		
		if ($playlistlen == 0 || ($rate != 0 && $rate != 1)) {
			return;
		}
		$client->execute(["playlist", "jump", "+1"]);
		$client->showBriefly($client->currentSongLines());
	},
	'rew' => sub  {
		my $client = shift;
		# ignore if we aren't playing anything or if we're scanning
		my $playlistlen = Slim::Player::Playlist::count($client);
		my $rate = Slim::Player::Source::rate($client);
		
		if ($playlistlen == 0 || ($rate != 0 && $rate != 1)) {
			return;
		}

		my $noplay = Slim::Player::Source::playmode($client) eq 'pause';

		#either starts the same song over, or the previous one, depending on whether we jumped back.
		if (Time::HiRes::time() - Slim::Hardware::IR::lastIRTime($client) < 1.0) {  #  less than second, jump back to the previous song
			$client->execute(["playlist", "jump", "-1", $noplay]);
		} else {
			# otherwise, restart this song.
			$client->execute(["playlist", "jump", "+0", $noplay]);
		}

		$client->showBriefly($client->currentSongLines());
	},
	
	'jump' => sub  {
		my $client = shift;
		my $funct = shift;
		my $functarg = shift;
		# ignore if we aren't playing anything or if we're scanning
		my $playlistlen = Slim::Player::Playlist::count($client);
		my $rate = Slim::Player::Source::rate($client);
		
		if (!defined $functarg) { $functarg = ''; }

		if ($playlistlen == 0) {
			return;
		}
		# ignore if we're scanning that way already			
		if ($rate > 1 && $functarg eq 'fwd') {
			return;
		}
		if ($rate < 0 && $functarg eq 'rew') {
			return;
		}
		# if we aren't scanning that way, then use it to stop scanning  and just play.
		if ($rate != 0 && $rate != 1) {
			$client->execute(["play"]);
			return;	
		}
		
		my $noplay = Slim::Player::Source::playmode($client) eq 'pause';
		#either starts the same song over, or the previous one, or the next one depending on whether/how we jumped

		if ($functarg eq 'rew') { 
			my $now = Time::HiRes::time();
			if (Slim::Player::Source::songTime($client) < 5 || Slim::Player::Source::playmode($client) eq "stop") {
				#jump back a song if stopped, invalid songtime, or current song has been playing less
				#than 5 seconds (use modetime instead of now when paused)
				$client->execute(["playlist", "jump", "-1", $noplay]);
			} else { #restart current song
				$client->execute(["playlist", "jump", "+0", $noplay]);
			}
			
		} elsif ($functarg eq 'fwd') { # jump to next song
			$client->execute(["playlist", "jump", "+1", $noplay]);
		} else { #restart current song
			$client->execute(["playlist", "jump", "+0", $noplay]);
		}

		$client->showBriefly($client->currentSongLines());
	},
	'jumpinsong' => sub {
		my ($client,$funct,$functarg) = @_;
		my $dir;
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
	'scan' => sub {
		my ($client,$funct,$functarg) = @_;
		my $rate = Slim::Player::Source::rate($client);
		if (!defined $functarg) {
			return;
		} elsif ($functarg eq 'fwd') {
			Slim::Buttons::Common::pushMode($client, 'playlist');
			if ($rate < 0) { $rate = 1; }
			return if abs($rate) == $SCAN_RATE_MAX_MULTIPLIER;
			$client->execute(['rate', $rate * $SCAN_RATE_MULTIPLIER]);
		} elsif ($functarg eq 'rew') {
			Slim::Buttons::Common::pushMode($client, 'playlist');
			if ($rate > 0) { $rate = 1; }
			return if abs($rate) == $SCAN_RATE_MAX_MULTIPLIER;
			$client->execute(['rate', -abs($rate * $SCAN_RATE_MULTIPLIER)]);
		}
		$client->update();

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
# Fred: done in the command
#		if (Slim::Player::Source::playmode($client) eq 'play' && Slim::Player::Source::rate($client) != 1) {
#			Slim::Player::Source::rate($client,1);
#		}
		$client->showBriefly($client->currentSongLines());
	},
	'stop' => sub  {
		my $client = shift;
		if (Slim::Player::Playlist::count($client) == 0) {
			$client->showBriefly($client->string('PLAYLIST_EMPTY'), "");
		} else {
			$client->execute(["stop"]);
			Slim::Buttons::Common::pushMode($client, 'playlist');
			$client->showBriefly($client->string('STOPPING'), "");
		}
	},
	'menu_pop' => sub  {
		my $client = shift;
		Slim::Buttons::Common::popMode($client);
		$client->update();
	},
	'menu' => sub  {
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;
		
		my $jump = $client->curSelection($client->curDepth());
		
		
		Slim::Buttons::Common::setMode($client, 'home');
		
		if ($button eq 'menu_playlist') {
			Slim::Buttons::Common::pushMode($client, 'playlist');
			$jump = 'NOW_PLAYING';
		} elsif ($button eq 'menu_browse_genre') {
			Slim::Buttons::Common::pushMode($client, 'browsedb',{ 'hierarchy' => 'genre,artist,album,track', 'level' => 0 });
			$jump = 'BROWSE_BY_GENRE';
		} elsif ($button eq 'menu_browse_artist') {
			Slim::Buttons::Common::pushMode($client, 'browsedb',{'hierarchy' => 'artist,album,track', 'level' => 0});
			$jump = 'BROWSE_BY_ARTIST';
		} elsif ($button eq 'menu_browse_album') {
			Slim::Buttons::Common::pushMode($client, 'browsedb', {'hierarchy' => 'album,track', 'level' => 0});
			$jump = 'BROWSE_BY_ALBUM';
		} elsif ($button eq 'menu_browse_song') {
			Slim::Buttons::Common::pushMode($client, 'browsedb', {'hierarchy' => 'track', 'level' => 0});
			$jump = 'BROWSE_BY_SONG';
		} elsif ($button eq 'menu_browse_music') {
			Slim::Buttons::Common::pushMode($client, 'browsetree', {'hierarchy' => ''});
			$jump = 'BROWSE_MUSIC_FOLDER';
		} elsif ($button eq 'menu_synchronize') {
			Slim::Buttons::Common::pushMode($client, 'settings');
			$jump = 'SETTINGS';
			Slim::Buttons::Common::pushModeLeft($client, 'synchronize');
		} elsif ($button eq 'menu_search_artist') {
			my %params = Slim::Buttons::Search::searchFor($client, 'ARTISTS');
			Slim::Buttons::Common::pushModeLeft($client, $params{'useMode'},\%params);
			$jump = 'SEARCH_FOR_ARTISTS';
		} elsif ($button eq 'menu_search_album') {
			my %params = Slim::Buttons::Search::searchFor($client, 'ALBUMS');
			Slim::Buttons::Common::pushModeLeft($client, $params{'useMode'},\%params);
			$jump = 'SEARCH_FOR_ALBUMS';
		} elsif ($button eq 'menu_search_song') {
			my %params = Slim::Buttons::Search::searchFor($client, 'SONGS');
			Slim::Buttons::Common::pushModeLeft($client, $params{'useMode'},\%params);
			$jump = 'SEARCH_FOR_SONGS';
		} elsif ($button eq 'menu_browse_playlists') {
			Slim::Buttons::Common::pushMode($client, 'browsedb', {'hierarchy' => 'playlist,playlistTrack', 'level' => 0});
			$jump = 'SAVED_PLAYLISTS';
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
		
		Slim::Buttons::Home::jump($client,$jump);
		$client->update();
	},
	'brightness' => sub  {
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;
		
		my $brightmode;
		my $mode = Slim::Buttons::Common::mode($client);

		if (!defined $buttonarg || ($mode eq 'block' && $client->modeParam('block.name') eq 'upgrade')) {
			return;
		}
		
		if ($client->power()) {
			$brightmode = 'powerOnBrightness';
			
			if (($mode eq $client->prefGet('screensaver') ||
					$mode eq $client->prefGet('idlesaver') || 
						$client->prefGet('autobrightness')) 
						&&
						(	Slim::Hardware::IR::lastIRTime($client) &&
							Slim::Hardware::IR::lastIRTime($client) < Time::HiRes::time() - $client->prefGet("screensavertimeout")
						)
					) {
						
				$brightmode = 'idleBrightness';
			
			}
		} else {
			$brightmode = 'powerOffBrightness';
		}
		
		$::d_ui && msg("UI: Brightness using $brightmode during mode: $mode\n");
		my $newBrightness;
		if ($buttonarg eq 'toggle') {
			$newBrightness = $client->brightness() - 1;
			if ($newBrightness < 0) {
				$newBrightness = $client->maxBrightness();
			}
		} else {
			$newBrightness = ($buttonarg eq 'down') ? $client->brightness() - 1 : $client->brightness() + 1;
			if ($newBrightness > $client->maxBrightness()) { $newBrightness = $client->maxBrightness();}
			if ($newBrightness < 0) { $newBrightness = 0;}
		}

		$client->prefSet($brightmode, $newBrightness);
		$client->brightness($newBrightness);
	},
	'playdisp' => sub  {
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;
		my $playdisp = undef;
		if (mode($client) eq 'playlist') {
			Slim::Buttons::Playlist::playdisp($client,$button, $buttonarg);
			return;
		}
		unless (defined $buttonarg) { $buttonarg = 'toggle'; };
		if ($buttonarg eq 'toggle') {
			$::d_ui && msg("Switching to playlist view\n");
			if (Slim::Player::Playlist::count($client) == 0) {
				$client->showBriefly($client->string('PLAYLIST_EMPTY'), "");
			} else {
				Slim::Buttons::Common::setMode($client, 'home');
				Slim::Buttons::Home::jump($client, 'playlist');
				Slim::Buttons::Common::pushModeLeft($client, 'playlist');
			}
		} else {
			if ($buttonarg =~ /^[0-5]$/) {
				$client->prefSet("playingDisplayMode", $buttonarg);
			}
		}
	},
	'visual' => sub {
		# toggle display mod for now playing...
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;

		my $vm = $client->prefGet("playingDisplayMode");

		unless (defined $vm) { $vm = 1; };
		unless (defined $buttonarg) { $buttonarg = 'toggle'; };

		if ($button eq 'visual_toggle') {
			$vm = ($vm + 1) % $client->display->visualizerModes();
		} else {
			if ($buttonarg && $buttonarg < $client->display->visualizerModes()) {
				$vm = $buttonarg;
			}
		}
		$client->prefSet("playingDisplayMode", $vm);
		$client->update();
	},

	'search' => sub  {
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;
		my $playdisp = undef;
		if (mode($client) ne 'search') {
			Slim::Buttons::Home::jumpToMenu($client,"SEARCH");
			$client->update();
		}
	},	

	'browse' => sub  {
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;
		my $playdisp = undef;
		Slim::Buttons::Home::jumpToMenu($client,"BROWSE_MUSIC");
		$client->update();
	},

	'favorites' => sub  {
		my $client    = shift;
		my $button    = shift;
		my $buttonarg = shift;
		my $playdisp  = undef;
		
		if (defined $buttonarg && $buttonarg eq "add") {

			my $list = $client->param('listRef');

			if ($list) {
			
				my $obj = $list->[$client->param('listIndex')];
				
				if (blessed($obj) && $obj->can('url')) {

					my $title;

					if ($obj->can('title')) {
						$title = $obj->title;
					} else {
						$title = Slim::Music::Info::standardTitle($client, $obj);
					}
	
					if ($title) {
						Slim::Utils::Favorites->clientAdd($client, $obj, $title);
						$client->showBriefly($client->string('FAVORITES_ADDING'), $title);
					}

				} else {

					$::d_favorites && msg("list item is not an object, not adding favorite\n");
					$::d_favorites && msg(Data::Dumper::Dumper($obj));
				}
			}			

		} elsif (mode($client) ne 'PLUGIN.Favorites') {

			Slim::Buttons::Common::setMode($client, 'home');
			Slim::Buttons::Home::jump($client, 'PLUGIN.Favorites');
			Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.Favorites');
		}
	},	
	'repeat' => sub  {
		# pressing recall toggles the repeat.
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;
		my $repeat = undef;
		if (defined $buttonarg && $buttonarg =~ /^[0-2]$/) {
			$repeat = $buttonarg;
		}
		$client->execute(["playlist", "repeat", $repeat]);
		# display the fact that we are (not) repeating
		if (Slim::Player::Playlist::repeat($client) == 0) {
			$client->showBriefly($client->string('REPEAT_OFF'), "");
		} elsif (Slim::Player::Playlist::repeat($client) == 1) {
			$client->showBriefly($client->string('REPEAT_ONE'), "");
		} elsif (Slim::Player::Playlist::repeat($client) == 2) {
			$client->showBriefly($client->string('REPEAT_ALL'), "");
		}
	},

	'volumemode' => sub {
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;
		
		if ($client->param('parentMode') && $client->param('parentMode') eq 'volume') {
			popModeRight($client);
		} else {
			pushModeLeft($client, 'volume');
		}
	},

	'volume' => sub {
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;
		
		mixer($client,'volume',$buttonarg);
	},


	'pitch' => sub {
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;

		mixer($client,'pitch',$buttonarg);
	},
	'bass' => sub {
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;

		mixer($client,'bass',$buttonarg);
	},
	'treble' => sub {
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;

		mixer($client,'treble',$buttonarg);
	},
	'muting' => sub  {
		my $client = shift;
		
		# try to avoid toggle commands, they make life difficult for listeners
		my $mute = !($client->prefGet("mute"));
		
		$client->execute(["mixer", "muting", $mute]);
	},
	'sleep' => sub  {
		my $client = shift;
		my @sleepChoices = (0,15,30,45,60,90);
		my $i;
		# find the next value for the sleep timer
		for ($i = 0; $i <= $#sleepChoices; $i++) {
			if ( $sleepChoices[$i] > $client->currentSleepTime() ) {
				last;
			}
		}
		if ($i > $#sleepChoices) {
			$i = 0;
		}
		my $sleepTime = $sleepChoices[$i];
		if ($sleepTime == 0) {
			$client->showBriefly($client->string('CANCEL_SLEEP') , '');
		} else {
			$client->showBriefly($client->string('SLEEPING_IN') . ' ' . $sleepTime . ' ' . $client->string('MINUTES'),'');
		}

		$client->execute(["sleep", $sleepTime * 60]);
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
		
		if (Slim::Player::Playlist::shuffle($client) == 2) {
				$client->showBriefly($client->string('SHUFFLE_ON_ALBUMS'), "");
		} elsif (Slim::Player::Playlist::shuffle($client) == 1) {
				$client->showBriefly($client->string('SHUFFLE_ON_SONGS'), "");
		} else {
				$client->showBriefly($client->string('SHUFFLE_OFF'), "");
		}
	},
	'titleFormat' => sub  {
		# rotate the titleFormat
		my $client = shift;
		$client->prefSet("titleFormatCurr"
				, ($client->prefGet("titleFormatCurr") + 1) % ($client->prefGetArrayMax("titleFormat") + 1));
		$client->update();
	},
 	'datetime' => sub  {
 		# briefly display the time/date
 		shift->showBriefly(dateTime(),3);
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
		$client->showBriefly($client->string('CLEARING_PLAYLIST'), '');
		$client->execute(['playlist', 'clear']);
	},
	'modefunction' => sub {
		my ($client,$funct,$functarg) = @_;
		return if !$functarg;
		my ($mode,$modefunct) = split('->',$functarg,2);
		return if !exists($modeFunctions{$mode});
		my $coderef = $modeFunctions{$mode}{$modefunct};
		my $modefunctarg;
 		if (!$coderef && ($modefunct =~ /(.+?)_(.+)/) && ($coderef = $modeFunctions{$mode}{$1})) {
 			$modefunctarg = $2;
 		}
		&$coderef($client,$modefunct,$modefunctarg) if $coderef;
	}
	,'changeMap' => sub {
		my ($client,$funct,$functarg) = @_;
		return if !$functarg;
		my $mapref = Slim::Hardware::IR::mapfiles();
		my %maps = reverse %$mapref;
		return if !exists($maps{$functarg});
		$client->prefSet('irmap',$maps{$functarg});
		$client->showBriefly($client->string('SETUP_IRMAP') . ':', $functarg);
	}

);

sub getFunction {
 	my $client = shift;
 	my $function = shift;
 	my $clientMode = shift;
 	my $coderef;
 	
 	$clientMode = mode($client) unless defined($clientMode);
	if ($coderef = $modeFunctions{$clientMode}{$function}) {
 		return $coderef;
 	} elsif (($function =~ /(.+?)_(.+)/) && ($coderef = $modeFunctions{$clientMode}{$1})) {
 		return $coderef,$2;
 	} elsif ($coderef = $functions{$function}) {
 		return $coderef;
 	} elsif (($function =~ /(.+?)_(.+)/) && ($coderef = $functions{$1})) {
 		return $coderef,$2
 	} else {
 		return;
 	}
}

# setFunction enables a Plugin to affect all common modes.
# (originally added to allow Favorites plugin to make holding a number be a shortcut to playing a users favorite station.)
sub setFunction {
	my $mapping = shift;
	my $function = shift;

	$functions{$mapping} = $function;
}


sub pushButton {
	my $sub = shift;
	my $client = shift;

	no strict 'refs';
	my ($subref,$subarg) = getFunction($client,$sub);
	&$subref($client,$sub,$subarg);
}

# DEPRECATED: Use Slim::Input::Time instead
sub timeDigits {
	Slim::Buttons::Input::Time::timeDigits(shift,shift);
}

sub scroll {
	scroll_dynamic(@_);
}

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

	my $result = undef;
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
	
	my $currVal = $client->prefGet($feature);
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
		($client->lastLetterTime + Slim::Utils::Prefs::get("displaytexttimeout") < $now)) {
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
	return (($digit ne $client->lastLetterDigit) && (($client->lastLetterTime + Slim::Utils::Prefs::get("displaytexttimeout")) > Time::HiRes::time()));
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
			if ($client->lastDigitTime + Slim::Utils::Prefs::get("displaytexttimeout") < $now) {
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

sub mode {
	my $client = shift;

	assert($client);

	return $client->modeStack(-1);
}

sub validMode {
	my $mode = shift;

	return exists $modes{$mode} ? 1 : 0;
}

# standard UI feature enable/disable a setting
sub checkBoxOverlay {
	my $value = shift;
	
	return $value ? "[X]" : "[ ]";
}

sub param {
	my $client = shift;
	return $client->param(@_);
}

sub paramOrPref {
	my $client = shift;
	return $client->paramOrPref(@_);
}

# pushMode takes the following parameters:
#   client - reference to a client structure
#   setmode - name of mode we are pushing into
#   paramHashRef - reference to a hash containing the parameters for that mode
sub pushMode {
	my $client = shift;
	my $setmode = shift;
	my $paramHashRef = shift;

	$::d_ui && msg("pushing button mode: $setmode\n");

	my $oldmode = mode($client);

	if ($oldmode) {

		my $exitFun = $leaveMode{$oldmode};

		if ($exitFun && ref($exitFun) eq 'CODE') {
			&$exitFun($client, 'push');
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

	push @{$client->modeParameterStack}, $paramHashRef;

	my $newModeFunction = $modes{$setmode};

	if (!$newModeFunction || ref($newModeFunction) ne "CODE") {
		bt();
		msg("Crashing because '$setmode' has no mode function or a bogus function.  Perhaps you mis-typed the mode name.\n");
	}

	eval { &$newModeFunction($client, 'push') };

	if ($@) {
		msg("Couldn't push into new mode: [$setmode] !: $@\n");
	}

	# some modes require periodic updates
	startPeriodicUpdates($client);
	
	$client->updateKnob(1);
}

sub popMode {
	my $client = shift;
	if (scalar(@{$client->modeStack}) < 1) {
		$client->updateKnob(1);
		return undef;
	}

	my $oldMode = mode($client);

	if ($oldMode) {

		my $exitFun = $leaveMode{$oldMode};

		if ($exitFun && ref($exitFun) eq 'CODE') {
			&$exitFun($client, 'pop');
		}
	}
	
	pop @{$client->modeStack};
	pop @{$client->modeParameterStack};
	$scrollClientHash->{$client}{scrollParams} = pop @{$scrollClientHash->{$client}{scrollParamsStack}};
	
	my $newmode = mode($client);
	if ($newmode) {
		my $fun = $modes{$newmode};
		&$fun($client,'pop');
	}

	$::d_ui && msg("popped to button mode: " . (mode($client) || 'empty!') . "\n");

	$client->updateKnob(1);
	# some modes require periodic updates
	startPeriodicUpdates($client);
	
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

	my $oldlines = $client->curLines();

	pushMode($client, $setmode, $paramHashRef);

	if (!$client->param('handledTransition')) {
		$client->pushLeft($oldlines, $client->curLines());
		$client->param('handledTransition',0);
	}
}

sub popModeRight {
	my $client = shift;

	my $oldlines = $client->curLines();

	Slim::Buttons::Common::popMode($client);

	$client->pushRight($oldlines, $client->curLines());
}

sub dateTime {
	my $client = shift;

	my @line = (Slim::Utils::Misc::longDateF(), Slim::Utils::Misc::timeF());

	for my $i (0..$#line) {
		# center the strings on the display by space padding them
		$line[$i] = Slim::Display::Display::center($line[$i]);
	}

	return @line;
}

# if and only if the mode has set the modeUpdateInterval parameter,
# call $client->update every modeUpdateInterval seconds.
sub startPeriodicUpdates {
	my $client = shift;
	# unset any previous timers
	Slim::Utils::Timers::killTimers($client, \&_periodicUpdate);
	my $interval = $client->param('modeUpdateInterval');
	return unless $interval;

	my $time = Time::HiRes::time() + $interval;
	Slim::Utils::Timers::setTimer($client, $time, \&_periodicUpdate, $client);
	$client->periodicUpdateTime($time);
}

# resych periodic updates to $time - to synchonise updates with time/elaspsed time
sub syncPeriodicUpdates {
	my $client = shift;
	my $time = shift || Time::HiRes::time();
	# unset any previous timers
	Slim::Utils::Timers::killTimers($client, \&_periodicUpdate);
	my $interval = $client->param('modeUpdateInterval');
	return unless $interval;

	Slim::Utils::Timers::setTimer($client, $time, \&_periodicUpdate, $client);
	$client->periodicUpdateTime($time);
}

sub _periodicUpdate {
	my $client = shift;
	my $interval = $client->param('modeUpdateInterval');
	# if interval is not set, we have left the mode that needed the update
	return unless $interval;
	
	# schedule the next update time, skip if running late
	my $time = $client->periodicUpdateTime();
	my $timenow = Time::HiRes::time();

	do {
		$time += $interval;
	} while ($time < $timenow);

	Slim::Utils::Timers::setTimer($client, $time, \&_periodicUpdate, $client);
	$client->periodicUpdateTime($time);

	# do the update if there's no block on updates
	$client->display->update() unless ($client->display->updateMode());
}



1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
