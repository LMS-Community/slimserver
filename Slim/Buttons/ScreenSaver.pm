package Slim::Buttons::ScreenSaver;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);

use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

our %functions = ();

sub init {

	Slim::Buttons::Common::addSaver('screensaver', getFunctions(), \&setMode, undef, string('SCREENSAVER_JUMP_BACK_NAME'));

	# Each button on the remote has a function:
	%functions = (
		'done' => sub  {
			my ($client ,$funct ,$functarg) = @_;

			Slim::Buttons::Common::popMode($client);
			$client->update();

			# pass along ir code to new mode if requested
			if (defined $functarg && $functarg eq 'passback') {
				Slim::Hardware::IR::resendButton($client);
			}
		}
	);
}

sub getFunctions {
	return \%functions;
}

sub screenSaver {
	my $client = shift;
	
	my $now = Time::HiRes::time();

	$::d_time && msg("screenSaver idle display " . (
		$now - Slim::Hardware::IR::lastIRTime($client) - 
			Slim::Utils::Prefs::clientGet($client,"screensavertimeout")) . 
		"(mode:" . Slim::Buttons::Common::mode($client) . ")\n"
	);

	my $mode = Slim::Buttons::Common::mode($client);

	assert($mode);
	
	# some variables, so save us calling the same functions multiple times.
	my $saver = Slim::Player::Source::playmode($client) eq 'play' ? Slim::Utils::Prefs::clientGet($client,'screensaver') : Slim::Utils::Prefs::clientGet($client,'idlesaver');
	my $dim = Slim::Utils::Prefs::clientGet($client,'idleBrightness');
	my $timeout = Slim::Utils::Prefs::clientGet($client,"screensavertimeout");
	my $irtime = Slim::Hardware::IR::lastIRTime($client);
	
	# if we are already in now playing, jump back screensaver is redundant and confusing
	if ($saver eq 'screensaver' && $mode eq 'playlist') {
		$saver = 'playlist'; 
	}
	
	# dim the screen if we're not playing...  will restore brightness on next IR input.
	# only ned to do this once, but its hard to ensure all cases, so it might be repeated.
	if ( $timeout && $client->brightness() && 
			$client->brightness() != $dim &&
			Slim::Utils::Prefs::clientGet($client, 'autobrightness') &&
			$irtime &&
			$irtime < $now - $timeout && 
			$mode ne 'block' &&
			$client->power()) {
		$client->brightness($dim);
	}

	if ($client->animating() == 1) {
		# don't interrupt client side animations for regular animations 
		# animating() would return 2 if we're just scrolling
	} elsif ($mode eq 'block') {
		# blocked mode handles its own updating of the screen.
	} elsif ($timeout && 
			$irtime < $now - $timeout && 
			$mode ne $saver &&
			$mode ne 'screensaver' && # just in case it falls into default, we dont want recursive pushModes
			$mode ne 'block' &&
			$client->power()) {
		
		# we only go into screensaver mode if we've timed out 
		# and we're not off or blocked
		if ($saver eq 'playlist') {
			if ($mode eq 'playlist') {
				Slim::Buttons::Playlist::jump($client);
				$client->scrollBottom();
			} else {
				Slim::Buttons::Common::pushMode($client,'playlist');
				$client->update();
			}
		} else {
			if (Slim::Buttons::Common::validMode($saver)) {
				Slim::Buttons::Common::pushMode($client, $saver);
			} else {
				$::d_plugins && msg("Mode ".$saver." not found, using default\n");
				Slim::Buttons::Common::pushMode($client,'screensaver');
			}
			$client->update();
		}
	} elsif (!$client->power()) {
		$saver = Slim::Utils::Prefs::clientGet($client,'offsaver');
		$saver =~ s/^SCREENSAVER\./OFF\./;
		if ($mode ne $saver) {
			if (Slim::Buttons::Common::validMode($saver)) {
				Slim::Buttons::Common::pushMode($client, $saver);
			} else {
				$::d_plugins && msg("Mode ".$saver." not found, using default\n");
				Slim::Buttons::Common::setMode($client,'off') unless $mode eq 'off';
			}
			$client->update();
		} else {
			$client->scrollBottom() if ($client->animating() != 2);
		}
	} else {
		# try to scroll the bottom, if necessary
		$client->scrollBottom() if ($client->animating() != 2);
	}
	# Call ourselves again after 1 second
	Slim::Utils::Timers::setTimer($client, ($now + 1.0), \&screenSaver);
}

sub wakeup {
	my $client = shift;
	my $button = shift;
	
	Slim::Hardware::IR::setLastIRTime($client, Time::HiRes::time());

	if (!Slim::Utils::Prefs::clientGet($client, 'autobrightness')) { return; };
	
	my $curBrightnessPref;
	
	if (Slim::Buttons::Common::mode($client) eq 'off' || !$client->power()) {
		$curBrightnessPref = Slim::Utils::Prefs::clientGet($client, 'powerOffBrightness');
	} else {
		$curBrightnessPref = Slim::Utils::Prefs::clientGet($client, 'powerOnBrightness');		
	} 
	
	if ($curBrightnessPref != $client->brightness()) {
		$client->brightness($curBrightnessPref);
	}
	# restore preferred scrollpause
	$client->param('scrollPause',Slim::Utils::Prefs::clientGet($client,'scrollPause'));
	# wake up our display if it is off and the player isn't in standby and we're not adjusting the 
	# brightness
	if ($button && 
		$button ne 'brightness_down' &&
		$button ne 'brightness_up' && 
		$button ne 'brightness_toggle' &&
		$client->brightness() == 0 &&
		$client->power()) { 
			Slim::Utils::Prefs::clientSet($client, 'powerOnBrightness', 1);		
	}
} 

sub setMode {
	my $client = shift;
	$::d_time && msg("going into screensaver mode");
	$client->lines(\&lines);
	# update client every second in this mode
	$client->param('modeUpdateInterval', 1); # seconds
}

sub lines {
	my $client = shift;
	$::d_time && msg("getting screensaver lines");
	return $client->currentSongLines();
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
