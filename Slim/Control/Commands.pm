package Slim::Control::Commands;

# $Id: Command.pm 5121 2005-11-09 17:07:36Z dsully $
#
# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;

use Slim::Control::Request;
use Slim::Music::Import;
use Slim::Music::Info;
use Slim::Player::Client;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

sub buttonCommand {
	my $request = shift;
	
	$::d_command && msg("buttonCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand(['button'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# use positional parameters as backups
	my $client     = $request->client();
	my $button     = $request->getParam('_buttoncode');
	my $time       = $request->getParam('time')            || $request->getParam('_p2');
	my $orFunction = $request->getParam('orFunction')      || $request->getParam('_p3');
	
	if (!defined $button ) {
		$request->setStatusBadParams();
		return;
	}
	
	Slim::Hardware::IR::executeButton($client, $button, $time, undef, defined($orFunction) ? $orFunction : 1);
	
	$request->setStatusDone();
}

sub debugCommand {
	my $request = shift;
	
	$::d_command && msg("debugCommand()\n");

	# check this is the correct command. Syntax approved by Dean himself!
	if ($request->isNotCommand(['debug'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# use positional parameters as backups
	my $debugFlag = $request->getParam('_debugflag');
	my $newValue = $request->getParam('_newvalue');
	
	if ( !defined $debugFlag || !($debugFlag =~ /^d_/) ) {
		$request->setStatusBadParams();
		return;
	}
	
	$debugFlag = "::" . $debugFlag;
	no strict 'refs';
	
	if (defined($newValue)) {
		$$debugFlag = $newValue;
	} else {
		# toggle if we don't have a new value
		$$debugFlag = ($$debugFlag ? 0 : 1);
	}
	
	$request->setStatusDone();
}

sub displayCommand {
	my $request = shift;
	
	# check this is the correct command.
	if ($request->isNotCommand(['display'])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $client   = $request->client();
	my $line1    = $request->getParam('_line1');
	my $line2    = $request->getParam('_line2');
	my $duration = $request->getParam('_duration');
	my $p4       = $request->getParam('_p4');
	
	if (!defined $line1) {
		$request->setStatusBadParams();
		return;
	}
	
	Slim::Buttons::ScreenSaver::wakeup($client);
	$client->showBriefly($line1, $line2, $duration, $p4);
	
	$request->setStatusDone();
}

sub irCommand {
	my $request = shift;
	
	# check this is the correct command.
	if ($request->isNotCommand(['ir'])) {
		$request->setStatusBadDispatch();
		return;
	}

	# use positional parameters as backups
	my $client      = $request->client();
	my $irCodeBytes = $request->getParam('_ircode');
	my $irTime      = $request->getParam('_time');	
	
	if (!defined $irCodeBytes || !defined $irTime ) {
		$request->setStatusBadParams();
		return;
	}
	
	Slim::Hardware::IR::processIR($client, $irCodeBytes, $irTime);
	
	$request->setStatusDone();
}

sub mixerCommand {
	my $request = shift;
	
	# check this is the correct command.
	if ($request->isNotCommand(['mixer'])) {
		$request->setStatusBadDispatch();
		return;
	}

	# use positional parameters as backups
	my $client   = $request->client();
	my $entity   = $request->getRequest(1);
	my $newvalue = $request->getParam('_newvalue');

	if ($request->paramUndefinedOrNotOneOf($entity, ['volume', 'muting', 'treble', 'bass', 'pitch']) ) {
		$request->setStatusBadParams();
		return;
	}

	my @buddies;

	# if we're sync'd, get our buddies
	if (Slim::Player::Sync::isSynced($client)) {
		@buddies = Slim::Player::Sync::syncedWith($client);
	}
	
	if ($entity eq 'muting') {
		my $vol = $client->volume();
		my $fade;
		
		if ($vol < 0) {
			# need to un-mute volume
			$::d_command && msg("Unmuting, volume is $vol.\n");
			$client->prefSet("mute", 0);
			$fade = 0.3125;
		} else {
			# need to mute volume
			$::d_command && msg("Muting, volume is $vol.\n");
			$client->prefSet("mute", 1);
			$fade = -0.3125;
		}

		$client->fade_volume($fade, \&_mixer_mute, [$client]);

		for my $eachclient (@buddies) {
			if ($eachclient->prefGet('syncVolume')) {
				$eachclient->fade_volume($fade, \&_mixer_mute, [$eachclient]);
			}
		}
	} else {
		my $newval;
		my $oldval = $client->$entity();

		if ($newvalue =~ /^[\+\-]/) {
			$newval = $oldval + $newvalue;
		} else {
			$newval = $newvalue;
		}

		$newval = $client->$entity($newval);

		for my $eachclient (@buddies) {
			if ($eachclient->prefGet('syncVolume')) {
				$eachclient->prefSet($entity, $newval);
				$eachclient->$entity($newval);
				Slim::Display::Display::volumeDisplay($eachclient) if $entity eq 'volume';
			}
		}
	}
		
	$request->setStatusDone();
}

sub playcontrolCommand {
	my $request = shift;
	
	# check this is the correct command.
	if ($request->isNotCommand(['play', 'stop', 'pause', 'mode'])) {
		$request->setStatusBadDispatch();
		return;
	}

	# use positional parameters as backups
	my $client = $request->client();
	my $cmd    = $request->getRequest(0);
	my $param  = $request->getRequest(1);
	
	if ($cmd eq 'mode' && $request->paramUndefinedOrNotOneOf($param, ['play', 'pause', 'stop'])) {
		$request->setStatusBadParams();
		return;
	}

	# which state are we in?
	my $curmode = Slim::Player::Source::playmode($client);
	
	# which state do we want to go to?
	my $wantmode = $cmd;
	
	if ($cmd eq 'mode') {
		
		# we want to go to $param if the command is mode
		$wantmode = $param;
	}
	
	if ($cmd eq 'pause') {
		
		# pause 1, pause 0 and pause (toggle) are all supported, figure out which
		# one we want...
		if (defined $param) {
			$wantmode = $param ? 'pause' : 'play';
		} else {
			$wantmode = ($curmode eq 'pause') ? 'play' : 'pause';
		}
	}

	# Adjust for resume: if we're paused and asked to play, we resume
	$wantmode = 'resume' if ($curmode eq 'pause' && $wantmode eq 'play');

	# Adjust for pause: can only do it from play
	if ($wantmode eq 'pause') {

		# default to doing nothing...
		$wantmode = $curmode;
		
		# pause only from play
		$wantmode = 'pause' if $curmode eq 'play';
	}			
	
	# do we need to do anything?
	if ($curmode ne $wantmode) {
		
		# set new playmode
		Slim::Player::Source::playmode($client, $wantmode);

		# reset rate in all cases
		Slim::Player::Source::rate($client, 1);
		
		# update the display
		$client->update();
	}
		
	$request->setStatusDone();
}

sub playerprefCommand {
	my $request = shift;
	
	$::d_command && msg("playerprefCommand()\n");

	if ($request->isNotCommand(['playerpref'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $client   = $request->client();
	my $prefName = $request->getParam('_prefname');
	my $newValue = $request->getParam('_newvalue');

	if (!defined $prefName || !defined $newValue) {
		$request->setStatusBadParams();
		return;
	}	

	$client->prefSet($prefName, $newValue);
	
	$request->setStatusDone();
}

sub powerCommand {
	my $request = shift;
	
	# check this is the correct command.
	if ($request->isNotCommand(['power'])) {
		$request->setStatusBadDispatch();
		return;
	}

	# use positional parameters as backups
	my $client   = $request->client();
	my $newpower = $request->getParam('_newvalue');
	
	# handle toggle
	if (!defined $newpower) {
		$newpower = $client->power() ? 0 : 1;
	}

	# handle sync'd players
	if (Slim::Player::Sync::isSynced($client)) {

		my @buddies = Slim::Player::Sync::syncedWith($client);
		
		for my $eachclient (@buddies) {
			$eachclient->power($newpower) if $eachclient->prefGet('syncPower');
		}
	}

	$client->power($newpower);

	# Powering off cancels sleep...
	if ($newpower eq "0") {
		Slim::Utils::Timers::killTimers($client, \&_sleepStartFade);
		Slim::Utils::Timers::killTimers($client, \&_sleepPowerOff);
		$client->sleepTime(0);
		$client->currentSleepTime(0);
	}
		
	$request->setStatusDone();
}

sub prefCommand {
	my $request = shift;
	
	$::d_command && msg("prefCommand()\n");

	if ($request->isNotCommand(['pref'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# uses positional things as backups
	my $prefName = $request->getParam('_prefname');
	my $newValue = $request->getParam('_newvalue');

	if (!defined $prefName || !defined $newValue) {
		$request->setStatusBadParams();
		return;
	}	

	Slim::Utils::Prefs::set($prefName, $newValue);
	
	$request->setStatusDone();
}

sub rateCommand {
	my $request = shift;
	
	# check this is the correct command.
	if ($request->isNotCommand(['rate'])) {
		$request->setStatusBadDispatch();
		return;
	}

	# use positional parameters as backups
	my $client  = $request->client();
	my $newrate = $request->getParam('_newvalue');
	
	if (!defined $newrate) {
		$request->setStatusBadParams();
		return;
	}
	
	if ($client->directURL() || $client->audioFilehandleIsSocket) {
		Slim::Player::Source::rate($client, 1);
		# shouldn't we return an error here ???
	} else {
		Slim::Player::Source::rate($client, $newrate);
	}
	
	$request->setStatusDone();
}

sub rescanCommand {
	my $request = shift;
	
	$::d_command && msg("rescanCommand()\n");

	if ($request->isNotCommand(['rescan'])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $playlistsOnly = $request->getParam('_playlists') || 0;
	
	# if we're scanning allready, don't do it twice
	if (!Slim::Music::Import::stillScanning()) {

		if ($playlistsOnly) {

			Slim::Music::Import::scanPlaylistsOnly(1);

		} else {

			Slim::Music::Import::cleanupDatabase(1);
		}

		# rescan should not reset importers. currently iTunes # is the
		# only scanner that defines a reset function, # and that's for
		# the wipedb case only.
		Slim::Music::Info::clearPlaylists();
		Slim::Music::Import::startScan();
	}

	$request->setStatusDone();
}

sub sleepCommand {
	my $request = shift;
	
	# check this is the correct command.
	if ($request->isNotCommand(['sleep'])) {
		$request->setStatusBadDispatch();
		return;
	}

	# use positional parameters as backups
	my $client        = $request->client();
	my $will_sleep_in = $request->getParam('_newvalue');
	
	if (!defined $will_sleep_in) {
		$request->setStatusBadParams();
		return;
	}
	
	# Cancel the timers, we'll set them back if needed
	Slim::Utils::Timers::killTimers($client, \&_sleepStartFade);
	Slim::Utils::Timers::killTimers($client, \&_sleepPowerOff);
		
	# if we have a sleep duration
	if ($will_sleep_in > 0) {
		my $now = Time::HiRes::time();
		my $offTime = $now + $will_sleep_in;
		
		# do a nice fade if time allows. The duration of the fade is 60 seconds
		my $fadeTime = $offTime;
		if ($will_sleep_in > 60) {
			$fadeTime -= 60;
		}
			
		# set our timers
		Slim::Utils::Timers::setTimer($client, $offTime, \&_sleepPowerOff);
		Slim::Utils::Timers::setTimer($client, $fadeTime, \&_sleepStartFade) if $fadeTime != $offTime;

		$client->sleepTime($offTime);
		$client->currentSleepTime($will_sleep_in / 60); # for some reason this is minutes...
	} else {
		# finish canceling any sleep in progress
		$client->sleepTime(0);
		$client->currentSleepTime(0);
	}
	
	$request->setStatusDone();
}

sub syncCommand {
	my $request = shift;
	
	# check this is the correct command.
	if ($request->isNotCommand(['sync'])) {
		$request->setStatusBadDispatch();
		return;
	}

	# use positional parameters as backups
	my $client   = $request->client();
	my $newbuddy = $request->getParam('_indexid-');
	
	if (!defined $newbuddy) {
		$request->setStatusBadParams();
		return;
	}
	
	if ($newbuddy eq '-') {
	
		Slim::Player::Sync::unsync($client);
		
	} else {

		# try an ID
		my $buddy = Slim::Player::Client::getClient($newbuddy);

		# try a player index
		if (!defined $buddy) {
			my @clients = Slim::Player::Client::clients();
			if (defined $clients[$newbuddy]) {
				$buddy = $clients[$newbuddy];
			}
		}
		
		Slim::Player::Sync::sync($buddy, $client) if defined $buddy;
	}
	
	$request->setStatusDone();
}

sub timeCommand {
	my $request = shift;
	
	# check this is the correct command.
	if ($request->isNotCommand(['time', 'gototime'])) {
		$request->setStatusBadDispatch();
		return;
	}

	# use positional parameters as backups
	my $client  = $request->client();
	my $newtime = $request->getParam('_newvalue');
	
	if (!defined $newtime) {
		$request->setStatusBadParams();
		return;
	}
	
	Slim::Player::Source::gototime($client, $newtime);
	
	$request->setStatusDone();
}

sub wipecacheCommand {
	my $request = shift;
	
	$::d_command && msg("wipecacheCommand()\n");

	if ($request->isNotCommand(['wipecache'])) {
		$request->setStatusBadDispatch();
		return;
	}

	# no parameters
	
	# if we're scanning allready, don't do it twice
	if (!Slim::Music::Import::stillScanning()) {

		# Clear all the active clients's playlists
		for my $client (Slim::Player::Client::clients()) {

			$client->execute([qw(playlist clear)]);
		}

		Slim::Music::Info::clearPlaylists();
		Slim::Music::Info::wipeDBCache();
		Slim::Music::Import::resetImporters();
		Slim::Music::Import::startScan();
	}

	$request->setStatusDone();
}

################################################################################
# Helper functions
################################################################################

sub _sleepStartFade {
	my $client = shift;

	$::d_command && msg("_sleepStartFade()\n");
	
	if ($client->isPlayer()) {
		$client->fade_volume(-60);
	}
}

sub _sleepPowerOff {
	my $client = shift;
	
	$::d_command && msg("_sleepPowerOff()\n");

	$client->sleepTime(0);
	$client->currentSleepTime(0);
	
	Slim::Control::Command::execute($client, ['stop', 0]);
	Slim::Control::Command::execute($client, ['power', 0]);
}

sub _mixer_mute {
	my $client = shift;
	$client->mute();
}


1;

__END__
