package Slim::Buttons::ScreenSaver;

# $Id: ScreenSaver.pm,v 1.17 2004/03/31 02:21:08 kdf Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use POSIX qw(strftime);

use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

# Each button on the remote has a function:
my %functions = (
	'done' => sub  {
		my ($client
		   ,$funct
		   ,$functarg) = @_;
		Slim::Buttons::Common::popMode($client);
		$client->update();
		#pass along ir code to new mode if requested
		if (defined $functarg && $functarg eq 'passback') {
			Slim::Hardware::IR::resendButton($client);
		}
	}
);

sub init {
	Slim::Buttons::Common::addSaver('screensaver',getFunctions(),\&setMode,undef,string('SCREENSAVER_JUMP_BACK_NAME'));
}

sub getFunctions {
	return \%functions;
}

sub screenSaver {
	my $client = shift;
	
	my $now = Time::HiRes::time();
	$::d_time && msg("screenSaver idle display " . ($now - Slim::Hardware::IR::lastIRTime($client) - Slim::Utils::Prefs::clientGet($client,"screensavertimeout")) . "(mode:" . Slim::Buttons::Common::mode($client) . ")\n");
	my $mode = Slim::Buttons::Common::mode($client);
	assert($mode);
	my $saver = Slim::Utils::Prefs::clientGet($client,'screensaver');
		
	# dim the screen if we're not playing...  will restore brightness on next IR input.
	if (Slim::Utils::Prefs::clientGet($client,"screensavertimeout") && 
			 Slim::Utils::Prefs::clientGet($client, 'autobrightness') &&
			 Slim::Hardware::IR::lastIRTime($client) &&
			 Slim::Hardware::IR::lastIRTime($client) < $now - Slim::Utils::Prefs::clientGet($client,"screensavertimeout") && 
			 $mode ne 'block' &&
			 $mode ne $saver &&
			 $mode ne 'off' &&
			 Slim::Hardware::VFD::vfdBrightness($client)) {
		Slim::Hardware::VFD::vfdBrightness($client,1);
	}

	if (Slim::Display::Animation::animating($client)) {
		# if we're animating, let the animation play out
	} elsif ($mode eq 'block') {
		# blocked mode handles its own updating of the screen.
	} elsif (Slim::Utils::Prefs::clientGet($client,"screensavertimeout") && 
			 Slim::Hardware::IR::lastIRTime($client) < $now - Slim::Utils::Prefs::clientGet($client,"screensavertimeout") && 
			 $mode ne Slim::Utils::Prefs::clientGet($client,'screensaver') &&
			 $mode ne 'screensaver' && # just in case it falls into default
			 $mode ne 'block' &&
			 $mode ne 'off') {
		
		# we only go into screensaver mode if we've timed out 
		# and we're not off or blocked
		if ($saver eq 'playlist') {
			if ($mode eq 'playlist') {
				Slim::Buttons::Playlist::jump($client);
				my $linefunc = $client->lines();
				Slim::Display::Animation::scrollBottom($client,&$linefunc($client));
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
	} else {
		# try to scroll the bottom, if necessary
		my $linefunc = $client->lines();
		Slim::Display::Animation::scrollBottom($client,&$linefunc($client));
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
	
	if (Slim::Buttons::Common::mode($client) eq 'off') {
		$curBrightnessPref = Slim::Utils::Prefs::clientGet($client, 'powerOffBrightness');
	} else {
		$curBrightnessPref = Slim::Utils::Prefs::clientGet($client, 'powerOnBrightness');		
	} 
	
	if ($curBrightnessPref != Slim::Hardware::VFD::vfdBrightness($client)) {
		Slim::Hardware::VFD::vfdBrightness($client, $curBrightnessPref);
	}
	# restore preferred scrollpause
	Slim::Buttons::Common::param($client,'scrollPause',Slim::Utils::Prefs::clientGet($client,'scrollPause'));
	# wake up our display if it is off and the player isn't in standby and we're not adjusting the 
	# brightness
	if ($button && 
		$button ne 'brightness_down' &&
		$button ne 'brightness_up' && 
		$button ne 'brightness_toggle' &&
		Slim::Hardware::VFD::vfdBrightness($client) == 0 &&
		Slim::Buttons::Common::mode($client) ne 'off') { 
			Slim::Utils::Prefs::clientSet($client, 'powerOnBrightness', 1);		
	}
} 

sub setMode {
	my $client = shift;
	$::d_time && msg("going into screensaver mode");
	$client->lines(\&lines);
}

sub lines {
	my $client = shift;
	$::d_time && msg("getting screensaver lines");
	return (Slim::Buttons::Playlist::currentSongLines($client));
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
