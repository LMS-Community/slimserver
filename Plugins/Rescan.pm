# Rescan.pm by Andrew Hedges (andrew@hedges.me.uk) October 2002
# Timer functions added by Kevin Deane-Freeman (kevindf@shaw.ca) June 2004
# $Id: Rescan.pm,v 1.6 2004/08/03 17:29:07 vidur Exp $

# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
use strict;

###########################################
### Section 1. Change these as required ###
###########################################

package Plugins::Rescan;

use Slim::Control::Command;
use Slim::Utils::Strings qw (string);
use Time::HiRes;

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.6 $,10);

my $interval = 1; # check every x seconds
my @browseMenuChoices;
my %menuSelection;
my %searchCursor;

sub getDisplayName() {return string('PLUGIN_RESCAN_MUSIC_LIBRARY')}

##################################################
### Section 2. Your variables and code go here ###
##################################################


sub setMode {
	my $client = shift;
	@browseMenuChoices = (
		string('PLUGIN_RESCAN_TIMER_SET'),
		string('PLUGIN_RESCAN_TIMER_OFF'),
		string('PLUGIN_RESCAN_PRESS_PLAY'),
		);
	if (!defined($menuSelection{$client})) { $menuSelection{$client} = 0; };
	$client->lines(\&lines);
	#get previous alarm time or set a default
	my $time = Slim::Utils::Prefs::get($client, "rescan-time");
	if (!defined($time)) { Slim::Utils::Prefs::get($client, "rescan-time", 9 * 60 * 60 ); }

}

my %functions = (
	'up' => sub  {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#browseMenuChoices + 1), $menuSelection{$client});

		$menuSelection{$client} =$newposition;
		$client->update();
	},
	'down' => sub  {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, +1, ($#browseMenuChoices + 1), $menuSelection{$client});

		$menuSelection{$client} =$newposition;
		$client->update();
	},
	'left' => sub  {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
	'right' => sub  {
		my $client = shift;
		my @oldlines = Slim::Display::Display::curLines($client);

		if ($browseMenuChoices[$menuSelection{$client}] eq string('PLUGIN_RESCAN_TIMER_SET')) {
			
			my %params = (
				'header' => string('PLUGIN_RESCAN_TIMER_SET')
				,'valueRef' => Slim::Utils::Prefs::get("rescan-time")
				,'cursorPos' => 1
				,'callback' => \&settingsExitHandler
			);
			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Time',\%params);
		}
		elsif ($browseMenuChoices[$menuSelection{$client}] eq string('PLUGIN_RESCAN_TIMER_OFF')) {
			Slim::Utils::Prefs::set("rescan-scheduled", 1);
			$browseMenuChoices[$menuSelection{$client}] = string('PLUGIN_RESCAN_TIMER_ON');
			$client->showBriefly(string('PLUGIN_RESCAN_TIMER_TURNING_ON'),'');
			setTimer($client);
		}
		elsif ($browseMenuChoices[$menuSelection{$client}] eq string('PLUGIN_RESCAN_TIMER_ON')) {
			Slim::Utils::Prefs::set("rescan-scheduled", 0);
			$browseMenuChoices[$menuSelection{$client}] = string('PLUGIN_RESCAN_TIMER_OFF');
			$client->showBriefly(string('PLUGIN_RESCAN_TIMER_TURNING_OFF'),'');
			setTimer($client);
		}
	},
	'play' => sub {
		my $client = shift;
		if ($browseMenuChoices[$menuSelection{$client}] eq string('PLUGIN_RESCAN_PRESS_PLAY')) {
			my @pargs=('rescan');
			my ($line1, $line2) = (string('PLUGIN_RESCAN_MUSIC_LIBRARY'), string('PLUGIN_RESCAN_RESCANNING'));
			Slim::Control::Command::execute($client, \@pargs, undef, undef);
			$client->showBriefly( $line1, $line2);
		} else {
			$client->bumpRight();
		}
	}
);

sub lines {
	my $client = shift;
	my ($line1, $line2, $overlay);
	my $timeFormat = Slim::Utils::Prefs::get("timeFormat");

	$line1 = string('PLUGIN_RESCAN_MUSIC_LIBRARY');

	if (Slim::Utils::Prefs::get("rescan-scheduled") && $browseMenuChoices[$menuSelection{$client}] eq string('PLUGIN_RESCAN_TIMER_OFF')) {
		$browseMenuChoices[$menuSelection{$client}] = string('PLUGIN_RESCAN_TIMER_ON');
	}
	$line2 = "";

	$line2 = $browseMenuChoices[$menuSelection{$client}];
	return ($line1, $line2, undef, Slim::Display::Display::symbol('rightarrow'));
}

sub settingsExitHandler {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);
	if ($exittype eq 'LEFT') {
		Slim::Utils::Prefs::set("rescan-time",Slim::Buttons::Common::param($client,'valueRef'));
		Slim::Buttons::Common::popModeRight($client);
	} elsif ($exittype eq 'RIGHT') {
			$client->bumpRight();
	} else {
		return;
	}
}

sub getFunctions() {
	return \%functions;
}

sub setTimer {
#timer to check alarms on an interval
	Slim::Utils::Timers::setTimer(0, Time::HiRes::time() + $interval, \&checkScanTimer);
}

sub checkScanTimer
{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

	my $time = $hour * 60 * 60 + $min * 60;

	if ($sec == 0) { # once we've reached the beginning of a minute, only check every 60s
		$interval = 60;
	}
	if ($sec >= 50) { # if we end up falling behind, go back to checking each second
		$interval = 1;
	}

		if (Slim::Utils::Prefs::get("rescan-scheduled")) {
			my $scantime =  Slim::Utils::Prefs::get("rescan-time");
			if ($scantime) {
			   if ($time == $scantime +60 ) {$interval=1;}; #alarm is done, so reset to find the beginning of a minute
				if ($time == $scantime && !Slim::Music::MusicFolderScan::stillScanning()) {
					Slim::Music::MusicFolderScan::startScan();
				}
			}
		}
	setTimer();
}


sub setupGroup
{
	my %group =
	(
		PrefOrder => ['rescan-scheduled','rescan-time'],
		PrefsInTable => 1,
		GroupHead => string('PLUGIN_RESCAN_MUSIC_LIBRARY'),
		GroupDesc => string('PLUGIN_RESCAN_TIMER_DESC'),,
		GroupLine => 1,
		GroupSub => 1,
		Suppress_PrefSub => 1,
		Suppress_PrefLine => 1,
		Suppress_PrefHead => 1
	);
	
	my %prefs = 
	(
		'rescan-scheduled' => {
			'validate' => \&Slim::Web::Setup::validateTrueFalse
			,'PrefChoose' => string('PLUGIN_RESCAN_TIMER_NAME')
			,'changeIntro' => string('PLUGIN_RESCAN_TIMER_NAME')
			,'options' => {
					'1' => string('ON')
					,'0' => string('OFF')
				}
		},
		'rescan-time' => {
		'validate' => \&Slim::Web::Setup::validateAcceptAll
		,'validateArgs' => [0,undef]
		,'PrefChoose' => string('PLUGIN_RESCAN_TIMER_SET')
		,'changeIntro' => string('PLUGIN_RESCAN_TIMER_SET')
		,'currentValue' => sub {
				my $client = shift;
				my $time = Slim::Utils::Prefs::get("rescan-time");
				my ($h0, $h1, $m0, $m1, $p) = Slim::Buttons::Input::Time::timeDigits($client,$time);
				my $timestring = ((defined($p) && $h0 == 0) ? ' ' : $h0) . $h1 . ":" . $m0 . $m1 . " " . (defined($p) ? $p : '');
				return $timestring;
			}
			,'onChange' => sub {
					my ($client,$changeref,$paramref,$pageref) = @_;
					my $time = $changeref->{'rescan-time'}{'new'};
					my $newtime = 0;
					$time =~ s{
						^(0?[0-9]|1[0-9]|2[0-4]):([0-5][0-9])\s*(P|PM|A|AM)?$
					}{
						if (defined $3) {
							$newtime = ($1 == 12?0:$1 * 60 * 60) + ($2 * 60) + ($3 =~ /P/?12 * 60 * 60:0);
						} else {
							$newtime = ($1 * 60 * 60) + ($2 * 60);
						}
					}iegsx;
					Slim::Utils::Prefs::set('rescan-time',$newtime);
				}
		},
	);
	return (\%group,\%prefs);
};

Slim::Buttons::Common::addMode('scantimer', getFunctions(), \&Plugins::Rescan::setMode);
setTimer();

sub strings
{
    local $/ = undef;
    <DATA>;
}

1;

__DATA__

PLUGIN_RESCAN_MUSIC_LIBRARY
	DE	Musikverzeichnis erneut durchsuchen
	EN	Rescan Music Library
	FR	Répertorier musique
	
PLUGIN_RESCAN_RESCANNING
	DE	Server durchsucht Verzeichnisse...
	EN	Server now rescanning...
	FR	En cours...

PLUGIN_RESCAN_PRESS_PLAY
	EN	Press PLAY to rescan now.

PLUGIN_RESCAN_TIMER_NAME
	EN	Rescan Timer

PLUGIN_RESCAN_TIMER_SET
	EN	Set Rescan Time

PLUGIN_RESCAN_TIMER_TURNING_OFF
	EN	Turning rescan timer off...

PLUGIN_RESCAN_TIMER_TURNING_ON
	EN	Turning rescan timer on...

PLUGIN_RESCAN_TIMER_ON
	EN	Rescan Timer ON

PLUGIN_RESCAN_TIMER_DESC
	EN	You can choose to allow a scheduled rescan of your music library every 24 hours.  Set the time, and set the Rescan Timer to ON to use this feature.

PLUGIN_RESCAN_TIMER_OFF
	EN	Rescan Timer OFF

