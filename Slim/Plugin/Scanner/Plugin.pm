#line 2 "Plugin/Scanner/Plugin.pm"
package Slim::Plugin::Scanner::Plugin;

# $Id: Plugin.pm,v 1.2 2007-11-10 04:36:58 fishbone Exp $
# by Kevin Deane-Freeman August 2004

# This code is derived from code with the following copyright message:
#
# SqueezeCenter Copyright (c) 2001-2007 Logitech
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# To use this as a single-button access, add the following to a custom.map file:
# fwd.hold =  menu_Plugins::Scanner::Plugin
#
use strict;

use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Timers;
use Slim::Hardware::IR;
use Slim::Player::Client;
use base qw(Slim::Plugin::Base);

###########################################
### Section 1. Change these as required ###
###########################################

use Slim::Utils::Strings qw (string);
use File::Spec::Functions qw(:ALL);

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.2 $,10);

my $modeName = 'Slim::Plugin::Scanner::Plugin';



sub getDisplayName {return 'PLUGIN_SCANNER'}

##################################################
### Section 2. Your variables and code go here ###
##################################################

my $log          = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.songscanner',
	'defaultLevel' => 'WARN',
	'description'  => getDisplayName(),
});

# Keep track of the state of each client to prevent simultaneous scans clashing with each other
my %clientState = {};

sub _initClientState {
	my $client = shift;
	$clientState{$client->id} = {
		'offset' => 0,
		'jumpToMode' => undef,
		'playingSong' => undef,
		'lastUpdateTime' => 0,
		'activeFfwRew' => 0,
	};
}

my %modeParams = (
	'header' => 'PLUGIN_SCANNER_SET'
	,'stringHeader' => 1
	,'headerValue' => sub {
			my $client = shift;
			my $val = shift;
			if (!$clientState{$client->id}->{'lastUpdateTime'}) {
				$val = $clientState{$client->id}->{'offset'} = Slim::Player::Source::songTime($client);
				$client->modeParam('cursor', undef);
			} else {
				$client->modeParam('cursor', Slim::Player::Source::songTime($client));
			}
			my $pos = int($val);
			my $dur = int(Slim::Player::Source::playingSongDuration($client));
			my $txtPos = sprintf("%02d:%02d", $pos / 60, $pos % 60);
			my $txtDur = sprintf("%02d:%02d", $dur / 60, $dur % 60);
			my $rate = Slim::Player::Source::rate($client);
			my $rateText = '';
			if ($rate < 0 || $rate > 1) {
				$rateText = ($rate < 0 ? ' <<' : ' >>') . abs($rate) . 'X:';
			} elsif (Slim::Player::Source::playmode($client) =~ /pause/) {
				$rateText = ' ' . $client->string('PAUSED') . ':';
			}
			return " ($txtPos/$txtDur)$rateText " . $client->string('PLUGIN_SCANNER_HELP');
		}
	,'headerArgs' => 'CV'
	,'max' => undef
	,'increment' => undef
	,'onChange' => sub { 
			my $client = shift;
			my $val = shift;
			$clientState{$client->id}->{'offset'} = $val;
			$clientState{$client->id}->{'lastUpdateTime'} = time();
		}
	,'onChangeArgs' => 'CV'
	,'callback' => \&_scannerExitHandler
	,'handleLeaveMode' => 1
	,'trackValueChanges' => 1
	,'knobFlags' => Slim::Player::Client::KNOB_NOWRAP()
);

sub _timerHandler {
	my $client = shift;
		
	if ($client->modeStack->[-2] ne $modeName) {
		return;
	}
	
	if ($clientState{$client->id}->{'playingSong'} ne Slim::Player::Playlist::url($client)) {
		Slim::Buttons::Common::popModeRight($client);
		return;
	}

	if ($clientState{$client->id}->{'lastUpdateTime'}
		&& time() - $clientState{$client->id}->{'lastUpdateTime'} >= 2
		&& !(Slim::Player::Source::playmode($client) =~ /pause/))
	{
		Slim::Player::Source::gototime($client, $clientState{$client->id}->{'offset'}, 1);
		$clientState{$client->id}->{'lastUpdateTime'} = 0;
	}

	$client->update;
	
	$clientState{$client->id}->{'activeFfwRew'}++;
	
	Slim::Utils::Timers::setTimer($client, time()+1, \&_timerHandler);
}

sub _scannerExitHandler {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);
	
	if ($exittype eq 'RIGHT') {
		$client->bumpRight();
	} elsif (($exittype ne 'POP' && $clientState{$client->id}->{'jumpToMode'}) || $exittype eq 'PUSH') {
		Slim::Utils::Timers::killOneTimer($client, \&_timerHandler);
		Slim::Buttons::Common::popMode($client);
		$clientState{$client->id}->{'jumpToMode'} = 0;
	} elsif ($exittype eq 'LEFT') {
		Slim::Utils::Timers::killOneTimer($client, \&_timerHandler);
		Slim::Buttons::Common::popModeRight($client);
	}
}


my $SCAN_RATE_MULTIPLIER = 2;
my $SCAN_RATE_MAX_MULTIPLIER = 256; # Seems pretty high

sub _scan {
	my ($client, $direction) = @_;

	my $playmode = Slim::Player::Source::playmode($client);
	my $rate = Slim::Player::Source::rate($client);

	if ($direction > 0) {
		if ($rate < 0) {
			$rate = 1;
		}
		if (abs($rate) == $SCAN_RATE_MAX_MULTIPLIER) {
			return;
		}
		Slim::Player::Source::rate($client, $rate * $SCAN_RATE_MULTIPLIER);
	} else {
		if ($rate > 0) {
			$rate = 1;
		}
		if (abs($rate) == $SCAN_RATE_MAX_MULTIPLIER) {
			return;
		}
		Slim::Player::Source::rate($client, -abs($rate * $SCAN_RATE_MULTIPLIER));
	}
	
	if ($playmode =~ /pause/) {
		# To get the volume to fade in
		Slim::Player::Source::playmode($client, 'resume');
	}
	
	$client->update();
	$clientState{$client->id}->{'lastUpdateTime'} = 0;
}

my %functions = (
	'right' => sub  {
		my ($client,$funct,$functarg) = @_;
		_scannerExitHandler($client,'RIGHT');
	},
	'left' => sub {
		my $client = shift;
		_scannerExitHandler($client,'LEFT');
	},
	'play' => sub {
		my $client = shift;
		my $playmode = Slim::Player::Source::playmode($client);
		Slim::Player::Source::rate($client, 1);
		if ($clientState{$client->id}->{'lastUpdateTime'}) {
			Slim::Player::Source::gototime($client, $clientState{$client->id}->{'offset'}, 1);
			if ($playmode =~ /pause/) {
				# To get the volume to fade in
				Slim::Player::Source::playmode($client, 'resume');
			}
			my $lines = $client->currentSongLines();
			$lines->{'jive'} = undef;
			$client->showBriefly($lines, {block => 1});
		} elsif ($playmode =~ /pause/) {
			Slim::Player::Source::playmode($client, 'play');
		}
		if ($clientState{$client->id}->{'jumpToMode'}) {
			Slim::Buttons::Common::popMode($client);
			$clientState{$client->id}->{'jumpToMode'} = 0;
		}
		$clientState{$client->id}->{'lastUpdateTime'} = 0;
		$client->update;
	},
	'pause' => sub {
		my $client = shift;
		my $playmode = Slim::Player::Source::playmode($client);
		my $rate = Slim::Player::Source::rate($client);
		if ($clientState{$client->id}->{'lastUpdateTime'}) {
			Slim::Player::Source::rate($client, 1);
			Slim::Player::Source::gototime($client, $clientState{$client->id}->{'offset'}, 1);
			if ($playmode =~ /pause/) {
				# To get the volume to fade in
				Slim::Player::Source::playmode($client, 'resume');
			}
		} elsif ($rate != 1 && $rate != 0) {
			Slim::Player::Source::rate($client, 1);
		} elsif ($playmode =~ /pause/) {
			Slim::Player::Source::playmode($client, 'play');
		} else {
			Slim::Player::Source::playmode($client, 'pause');
		}
		$clientState{$client->id}->{'lastUpdateTime'} = 0;
		$client->update;
	},
	'jump_fwd' => sub {
		my $client = shift;
		_scan($client, 1);
	},
	'jump_rew' => sub {
		my $client = shift;
		_scan($client, -1);
	},
	'scanner_fwd' => sub {
		my $client = shift;
		Slim::Buttons::Input::Bar::changePos(shift, 1, 'up') if $clientState{$client->id}->{'activeFfwRew'} > 1;
	},
	'scanner_rew' => sub {
		my $client = shift;
		Slim::Buttons::Input::Bar::changePos(shift, -1, 'down') if $clientState{$client->id}->{'activeFfwRew'} > 1;
	},
	#'scanner' => \&_jumptoscanner,
);

sub _jumptoscanner {
	my $client = shift;
	Slim::Buttons::Common::pushModeLeft($client, $modeName);
	$clientState{$client->id}->{'jumpToMode'} = 1;
	$clientState{$client->id}->{'lastUpdateTime'} = 0;
}

sub getFunctions {
	return \%functions;
}

sub lines {
	my $line1 = string('PLUGIN_SCANNER');
	my $line2 = '';
	
	return {'line'    => [$line1, $line2],}
}

sub setMode {
	my $class  = shift;
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popModeRight($client);
		return;
	}
	
	my $errorStringName;
	my $duration;

	_initClientState($client);
	
	if ($clientState{$client->id}->{'playingSong'} = Slim::Player::Playlist::url($client)) {
		if (Slim::Music::Info::isRemoteURL($clientState{$client->id}->{'playingSong'})) {
			$errorStringName = 'PLUGIN_SCANNER_ERR_REMOTE';
		} elsif (!($duration = Slim::Player::Source::playingSongDuration($client))) {
			$errorStringName = 'PLUGIN_SCANNER_ERR_UNKNOWNSIZE';
		} elsif ($client->masterOrSelf()->audioFilehandleIsSocket()) {
			$errorStringName = 'PLUGIN_SCANNER_ERR_TRANSCODED';
		}
	} else {
		$errorStringName = 'PLUGIN_SCANNER_ERR_NOTRACK';
	}
	
	if (defined $errorStringName) {
		$client->modeParam('handledTransition',1);
		$client->showBriefly(
			{line => [ $client->string($errorStringName), ''], 'jive' => undef},
			{duration => 1.5, scroll => 1,
				callback => sub {Slim::Buttons::Common::popMode($client);}
			}
		);
		return;		
	}
	$client->update;
	my %params = %modeParams;

	$params{'valueRef'} = \$clientState{$client->id}->{'offset'};

	$params{'max'} = $duration;
	
	my $increment = $duration / 100;
	if ($increment < 1) {$increment = 1;} elsif ($increment > 5) {$increment = 5;}
	$params{'increment'} = $increment;

	$clientState{$client->id}->{'offset'} = Slim::Player::Source::songTime($client);
	
	Slim::Buttons::Common::pushMode($client,'INPUT.Bar',\%params);
	$clientState{$client->id}->{'lastUpdateTime'} = 0;
	$clientState{$client->id}->{'activeFfwRew'} = 0;
	
	$client->update();
	
	Slim::Utils::Timers::setTimer($client, time()+1, \&_timerHandler);
}

sub initPlugin {
	my $class = shift;
	Slim::Hardware::IR::addModeDefaultMapping('common', {'fwd.hold' => 'scanner', 'rew.hold' => 'scanner'}, 1);
	Slim::Hardware::IR::addModeDefaultMapping($modeName,
		{'fwd.repeat' => 'scanner_fwd', 'rew.repeat' => 'scanner_rew', 'fwd.hold' => 'dead', 'rew.hold' => 'dead'}, 1);
	Slim::Buttons::Common::setFunction('scanner', \&_jumptoscanner);
	$class->SUPER::initPlugin();
}
