package Slim::Buttons::ScreenSaver;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Buttons::ScreenSaver

=head1 DESCRIPTION

Module to register basic core screensavers and to handle moving the player in
and out of screensaver modes.

=cut

use strict;

use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

my $prefs = preferences('server');

my $log       = logger('player.ui.screensaver');
my $timerslog = logger('server.timers');

our %functions = ();

sub init {

	Slim::Buttons::Common::addSaver('screensaver', getFunctions(), \&setMode, undef, 'SCREENSAVER_JUMP_BACK_NAME', 'PLAY');
	Slim::Buttons::Common::addSaver('nosaver', undef, undef, undef, 'SCREENSAVER_NONE', 'PLAY-IDLE-OFF');

	# Each button on the remote has a function:
	%functions = (

		'playdisp' => \&Slim::Buttons::Playlist::playdisp,

		'done' => sub  {
			my ($client ,$funct ,$functarg) = @_;

			Slim::Buttons::Common::popMode($client);
			$client->update();

			# pass along ir code to new mode if requested
			if (defined $functarg && $functarg eq 'passback') {
				Slim::Hardware::IR::resendButton($client);
			}

			# passback only if exposed mode is playlist
			if (defined $functarg && $functarg eq 'passbackplaylist' && Slim::Buttons::Common::mode($client) eq 'playlist') {
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

	return if $client->display->isa('Slim::Display::NoDisplay');

	my $display = $client->display;

	my $now  = Time::HiRes::time();
	my $mode = Slim::Buttons::Common::mode($client);
	
	my $cprefs = $prefs->client($client);

	assert($mode);

	if ( main::INFOLOG && $timerslog->is_info ) {

		my $diff = $now - Slim::Hardware::IR::lastIRTime($client) - $cprefs->get('screensavertimeout');

		$timerslog->info("screenSaver idle display [$diff] (mode: [$mode])");
	}

	# some variables, to save us calling the same functions multiple times.
	my $type    = Slim::Player::Source::playmode($client) eq 'play' ? 'screensaver' : 'idlesaver';
	my $saver   = $cprefs->get($type);
	my $dim     = $cprefs->get('idleBrightness');
	my $timeout = $cprefs->get('screensavertimeout');
	my $irtime  = Slim::Hardware::IR::lastIRTime($client);

	my $savermode = $saver eq 'playlist' ? 'screensaver' : $saver;  # mode when in screensaver, not always same as $saver 

	if ($type eq 'idlesaver') {
		$savermode =~ s/^SCREENSAVER\./IDLESAVER\./;
	}
	
	# automatically control brightness unless in the middle of showBriefly
	if (defined $display->brightness() && $display->animateState() != 5) {

		if ($client->power) {
		
			# dim the screen...  will restore brightness on next IR input.
			# only need to do this once, but its hard to ensure all cases, so it might be repeated.
			if ( $timeout && 
				 $irtime && $irtime < $now - $timeout && 
				 $mode ne 'block' ) {

				$display->brightness($dim) if $display->brightness() != $dim;
		
			} elsif ($display->brightness() != $cprefs->get('powerOnBrightness')) {

				$display->brightness($cprefs->get('powerOnBrightness'));
			}
		
		} elsif ($display->brightness() != $cprefs->get('powerOffBrightness')) {

			$display->brightness($cprefs->get('powerOffBrightness'));
		}
	}

	my $alarmSaverActive = Slim::Utils::Alarm->getCurrentAlarm($client) && $mode eq Slim::Utils::Alarm->alarmScreensaver($client);

	if (!$alarmSaverActive && $mode =~ /^screensaver|^SCREENSAVER|^IDLESAVER/ && $mode ne $savermode &&
			Slim::Buttons::Common::validMode($savermode)) {

		# the screensaver has changed - pop the old one
		Slim::Buttons::Common::popMode($client);
	} 

	if ($alarmSaverActive || $display->inhibitSaver || $mode eq 'block' || $saver eq 'nosaver' && $client->power()) {

		# do nothing - stay in current mode

	} elsif ($client->power() && $timeout && 
			
			# no ir for at least the screensaver timeout
			$irtime < $now - $timeout && 
			
			# make sure it's not already in a valid saver mode.
			( ($mode ne $savermode && Slim::Buttons::Common::validMode($savermode)) || 
				# in case the saver is 'now playing' and we're browsing another song
				($mode eq 'playlist' && !Slim::Buttons::Playlist::showingNowPlaying($client)) ||
				# just in case it falls into default, we dont want recursive pushModes
				($mode ne 'screensaver' && !Slim::Buttons::Common::validMode($savermode)) ) ) {
		
		# we only go into screensaver mode if we've timed out 
		# and we're not off or blocked
		if ($saver eq 'playlist') {

			if ($mode eq 'playlist') {

				# set playlist to playing song
				Slim::Buttons::Playlist::browseplaylistindex($client, Slim::Player::Source::playingSongIndex($client));

			} else {

				# clear mode stack and set mode to playlist
				Slim::Buttons::Common::setMode($client, 'home');
				Slim::Buttons::Home::jump($client, 'playlist');
				Slim::Buttons::Common::pushMode($client,'playlist');
			}

			# cover playlist mode with screensaver mode so we get screensaver button functions
			Slim::Buttons::Common::pushMode($client, 'screensaver');

		} else {

			if (Slim::Buttons::Common::validMode($savermode)) {

				Slim::Buttons::Common::pushMode($client, $savermode);

			} else {

				$log->warn("Mode [$savermode] not found, using default");

				Slim::Buttons::Common::pushMode($client, 'screensaver');
			}
		}

		$display->update();

	} elsif (!$client->power()) {

		$savermode = $cprefs->get('offsaver');
		$savermode =~ s/^SCREENSAVER\./OFF\./;

		if ($savermode eq 'nosaver') {

			# do nothing

		} elsif ($mode ne $savermode) {

			if (Slim::Buttons::Common::validMode($savermode)) {

				Slim::Buttons::Common::pushMode($client, $savermode);

			} else {

				$log->warn("Mode [$savermode] not found, using default");

				if ($mode ne 'off') {
					Slim::Buttons::Common::setMode($client, 'off');
				}
			}

			$display->update();
		}

	}

	# Call ourselves again after 1 second
	Slim::Utils::Timers::setTimer($client, ($now + 1), \&screenSaver);
}

sub wakeup {
	my $client = shift;
	my $button = shift;
	
	my $display = $client->display;
	
	return if ($button && ($button =~ "brightness" || $button eq "dead"));
	
	Slim::Hardware::IR::setLastIRTime($client, Time::HiRes::time());

	return if !defined $display->maxBrightness();
	
	my $curBrightnessPref;
	
	my $cprefs = $prefs->client($client);
	
	if (Slim::Buttons::Common::mode($client) eq 'off' || !$client->power()) {
		$curBrightnessPref = $cprefs->get('powerOffBrightness');
	} else {
		$curBrightnessPref = $cprefs->get('powerOnBrightness');
	} 
	
	if ($curBrightnessPref != $display->brightness()) {
		$display->brightness($curBrightnessPref);
	}
	
	# Bug 2293: jump to now playing index if we were showing the current song before the screensaver kicked in
	if (Slim::Buttons::Playlist::showingNowPlaying($client) || (Slim::Player::Playlist::count($client) < 1)) {
		Slim::Buttons::Playlist::jump($client);
	}

	# wake up our display if it is off and the player isn't in standby and we're not adjusting the 
	# brightness
	if ($button && 
		$button ne 'brightness_down' &&
		$button ne 'brightness_up' && 
		$button ne 'brightness_toggle' &&
		$display->brightness() == 0 &&
		$client->power()) { 
			$cprefs->set('powerOnBrightness', 1);
			$display->brightness(1);
	}
} 

sub setMode {
	my $client = shift;

	main::DEBUGLOG && $log->is_debug && $log->debug("Going into screensaver mode.");

	$client->lines( $client->customPlaylistLines() || \&Slim::Buttons::Playlist::lines );

	# update client every second in this mode
	$client->modeParam('modeUpdateInterval', 1); # seconds
	$client->modeParam('screen2', 'screensaver');
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

L<Slim::Hardware::IR>

=cut

1;

__END__
