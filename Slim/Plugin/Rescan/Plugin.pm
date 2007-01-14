package Slim::Plugin::Rescan::Plugin;

# Rescan.pm by Andrew Hedges (andrew@hedges.me.uk) October 2002
# Timer functions added by Kevin Deane-Freeman (kevindf@shaw.ca) June 2004
# $Id: Plugin.pm 11180 2007-01-12 01:04:40Z kdf $

# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Time::HiRes;

use base qw(Slim::Plugin::Base);

use Slim::Plugin::Rescan::Settings;

use Scalar::Util qw(blessed);

use Slim::Control::Request;
use Slim::Utils::Log;

our $interval = 1; # check every x seconds
our @browseMenuChoices;
our %functions;

my @progress = [0];

sub getDisplayName {
	return 'PLUGIN_RESCAN_MUSIC_LIBRARY';
}

sub initPlugin {
	my $class = shift;

	%functions = (
		'play' => sub {
			my $client = shift;

			if ($client->modeParam('listRef')->[$client->modeParam('listIndex')] eq 'PLUGIN_RESCAN_PRESS_PLAY') {

				executeRescan($client);

				$client->showBriefly( {
					'line' => [ $client->string('PLUGIN_RESCAN_MUSIC_LIBRARY'),
							$client->string('PLUGIN_RESCAN_RESCANNING') ]
				});

				Slim::Buttons::Common::pushMode($client, 'scanProgress');
				
			} else {

				$client->bumpRight();
			}
		}
	);
	
	Slim::Buttons::Common::addMode('scanProgress', undef, \&setProgressMode, \&exitProgressMode);

	$class->SUPER::initPlugin();
	Slim::Plugin::Rescan::Settings->new;

	setTimer();
}

sub setMode {
	my $class  = shift;
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	@browseMenuChoices = (
		'PLUGIN_RESCAN_TIMER_SET',
		'PLUGIN_RESCAN_TIMER_OFF',
		'PLUGIN_RESCAN_TIMER_TYPE',
		'PLUGIN_RESCAN_PRESS_PLAY',
	);

	# get previous alarm time or set a default
	if (!defined Slim::Utils::Prefs::get("rescan-time")) {

		Slim::Utils::Prefs::set("rescan-time", 9 * 60 * 60 );
	}
	
	if ( Slim::Music::Import->stillScanning ) {

		Slim::Buttons::Common::pushMode($client, 'scanProgress');
		
	} else {

		if (Slim::Schema->rs('Progress')->search( { 'type' => 'importer' }, { 'order_by' => 'start' } )->all) {
			push @browseMenuChoices, 'PLUGIN_RESCAN_LAST_SCAN'
		}

		my %params = (
			'listRef'        => \@browseMenuChoices,
			'externRefArgs'  => 'CV',
			'header'         => 'PLUGIN_RESCAN_MUSIC_LIBRARY',
			'headerAddCount' => 1,
			'stringHeader'   => 1,
			'callback'       => \&rescanExitHandler,
			'overlayRef'     => sub { 

					if($_[1] =~ /PLUGIN_RESCAN_TIMER_O/) {

						return (undef, Slim::Buttons::Common::checkBoxOverlay( $client, Slim::Utils::Prefs::get("rescan-scheduled")));
					} elsif ($_[1] ne 'PLUGIN_RESCAN_PRESS_PLAY') {

						return (undef, $_[0]->symbols('rightarrow')) 
					}

				},
			'overlayRefArgs' => 'CV',
			'externRef'      => sub {
				my $client = shift;
				my $value  = shift;
				
				if (Slim::Utils::Prefs::get("rescan-scheduled") && $value eq 'PLUGIN_RESCAN_TIMER_OFF') {
	
					return $client->string('PLUGIN_RESCAN_TIMER_ON');
				}
	
				return $client->string($value);
			},
		);
	
		Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);
	}
}

sub setProgressMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	
	my $value = $#progress;

	my %progressParams = (
		'header'             => \&progressHeader,
		'headerArgs'         => 'CI',
		'headerAddCount'     => 1,
		'listRef'            => [0],
		'externRef'          => \&progressBar,
		'externRefArgs'      => 'CI',
		'modeUpdateInterval' => 1,
		'valueref'           => \$value,
	);

	Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%progressParams);
	progressUpdate($client);
}

sub exitProgressMode {
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Utils::Timers::killTimers($client, \&progressUpdate);
	}
}

sub progressHeader {
	my $client = shift;
	my $index  = shift;
	
	my $p = $progress[$index];
	
	if (blessed($p) && $p->name) {
	
		return $client->string($p->name.'_PROGRESS')
			.' '. $client->string( $p->active ? 'RUNNING' : 'COMPLETE')
			.($p->active ? ' ('.  $p->done.'/' . $p->total . ') ' : '' );
	} else {
	
		if (Slim::Music::Import->stillScanning) {
			return $client->string('RESCANNING_SHORT');
		} else {
			return $client->string('RESCANNING_SHORT').$client->string('COMPLETE');
		}
	}
}

sub progressBar {
	my $client = shift;
	my $index  = shift;
	
	my $p = $progress[$index];
	
	if (blessed($p) && $p->name) {
		if ($p->active) {

			return $client->sliderBar($client->displayWidth(), $p->done/$p->total * 100,0,0);
		} else {
			my $runtime = $p->finish - $p->start;
				
			my ($h0, $h1, $m0, $m1) = Slim::Utils::DateTime::timeDigits($runtime);

			return $p->total . ' ' . $client->string('ITEMS') . " $h0$h1:$m0$m1".sprintf(":%02s",($runtime % 60));
		}
	} else {
	
		
		if (Slim::Music::Import->stillScanning) {
			return $client->sliderBar($client->displayWidth(), 0,0,0);
		} else {
			return $client->string('TOTAL_TIME').' '.$p->{'total_time'};
		}
	}
}

sub progressUpdate {
	my $client = shift;

	Slim::Utils::Timers::killTimers($client, \&progressUpdate);
	
	@progress = Slim::Schema->rs('Progress')->search( { 'type' => 'importer' }, { 'order_by' => 'start' } )->all;
	my $size = scalar @{$client->modeParam('listRef')};
	
	if (scalar @progress) {
		$client->modeParam('listRef',[0..$#progress]);
	}

	#adjust the index to the last position if the new item starts while viewing the previous last item
	if ($client->modeParam('listIndex') == $#progress -1 && $size != scalar @progress) {
		$client->modeParam('listIndex',$#progress);
	}
	
	$client->update;
	$client->updateKnob(1);
	
	if ( Slim::Music::Import->stillScanning ) {
		
		# Block screensaver while checking progress and still scanning
		Slim::Hardware::IR::setLastIRTime(
			$client,
			Time::HiRes::time() + ($client->prefGet("screensavertimeout") * 5),
		);
		
		Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 1, \&progressUpdate);
	} else {
		my $totaltime = 0;
		my $count     = 0;
		
		for my $p (@progress) {
			$totaltime += $p->finish - $p->start;
			$count     += $p->total;
		}
		
		my ($h0, $h1, $m0, $m1) = Slim::Utils::DateTime::timeDigits($totaltime);
		
		my $t = {
			'total_time' => "$h0$h1:$m0$m1".sprintf(":%02s",($totaltime % 60)),
			'count'      => $count,
		};
		
		my $size = scalar @{$client->modeParam('listRef')};

		push @progress, $t;
		
		if (scalar @progress) {
			$client->modeParam('listRef',[0..$#progress]);
		}
	
		#adjust the index to the last position if the new item starts while viewing the previous last item
		if ($client->modeParam('listIndex') == $#progress -1 && $size != scalar @progress) {
			$client->modeParam('listIndex',$#progress);
		}
		
		$client->update;
		$client->updateKnob(1);
	}
}

sub rescanExitHandler {
	my ($client,$exittype) = @_;
	
	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {
		my $valueref = $client->modeParam('valueRef');
	
		if ($$valueref eq 'PLUGIN_RESCAN_TIMER_SET') {
			my $value = Slim::Utils::Prefs::get("rescan-time");
			
			my %params = (
				'header' => $client->string('PLUGIN_RESCAN_TIMER_SET'),
				'valueRef' => \$value,
				'cursorPos' => 1,
				'pref' => 'rescan-time',
				'callback' => \&settingsExitHandler
			);
			
			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Time',\%params);
	
		} elsif ($$valueref eq 'PLUGIN_RESCAN_TIMER_OFF') {
	
			Slim::Utils::Prefs::set("rescan-scheduled", 1);
			$$valueref = 'PLUGIN_RESCAN_TIMER_ON';
			setTimer($client);
			$client->update;
	
		} elsif ($$valueref eq 'PLUGIN_RESCAN_TIMER_ON') {
	
			Slim::Utils::Prefs::set("rescan-scheduled", 0);
			$$valueref = 'PLUGIN_RESCAN_TIMER_OFF';
			setTimer($client);
			$client->update;
		
		} elsif ($$valueref eq 'PLUGIN_RESCAN_TIMER_TYPE') {
			my $value = Slim::Utils::Prefs::get("rescan-type");

			my %params = (
				'listRef'  => [
					{
						name   => '{SETUP_STANDARDRESCAN}',
						value  => '1rescan',
					},
					{
						name   => '{SETUP_WIPEDB}',
						value  => '2wipedb',
					},
					{
						name   => '{SETUP_PLAYLISTRESCAN}',
						value  => '3playlist',
					},
				],
				'onPlay'   => sub { Slim::Utils::Prefs::set("rescan-type",$_[1]->{'value'}); },
				'onAdd'    => sub { Slim::Utils::Prefs::set("rescan-type",$_[1]->{'value'}); },
				'onRight'  => sub { Slim::Utils::Prefs::set("rescan-type",$_[1]->{'value'}); },
				'header'   => '{PLUGIN_RESCAN_TIMER_TYPE}{count}',
				'pref'     => sub { return Slim::Utils::Prefs::get("rescan-type"); },
				'valueRef' => \$value,
			);

			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice',\%params);

		} elsif ($$valueref eq 'PLUGIN_RESCAN_LAST_SCAN') {
		
			Slim::Buttons::Common::pushModeLeft($client, 'scanProgress');
		}

	}
}

sub settingsExitHandler {
	my ($client,$exittype) = @_;

	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		Slim::Utils::Prefs::set($client->modeParam('pref'),${$client->modeParam('valueRef')});

		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {

		$client->bumpRight();
	}
}

sub getFunctions {
	my $class = shift;

	\%functions;
}

sub setTimer {
	# timer to check alarms on an interval
	Slim::Utils::Timers::setTimer(0, Time::HiRes::time() + $interval, \&checkScanTimer);
}

sub checkScanTimer {

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

	Slim::Utils::Timers::killTimers(0, \&checkScanTimer);

	my $time = $hour * 60 * 60 + $min * 60;

	if ($sec == 0) { # once we've reached the beginning of a minute, only check every 60s
		$interval = 60;
	}

	if ($sec >= 50) { # if we end up falling behind, go back to checking each second
		$interval = 1;
	}

	if (Slim::Utils::Prefs::get("rescan-scheduled")) {

		my $scantime =  Slim::Utils::Prefs::get("rescan-time");

		if ($scantime && $time == $scantime) {

			# alarm is done, so reset to find the beginning of a minute
			if ($time == $scantime + 60) {
				$interval = 1;
			}

			executeRescan();

		}
	}

	setTimer();
}

sub executeRescan {
	my $client = shift;
	
	my $rescanType = ['rescan'];
	my $rescanPref = Slim::Utils::Prefs::get('rescan-type') || '';

	if ($rescanPref eq '2wipedb') {

		$rescanType = ['wipecache'];

	} elsif ($rescanPref eq '3playlist') {

		$rescanType = [qw(rescan playlists)];
	}

	if (!Slim::Music::Import->stillScanning()) {

		logger('scan.scanner')->info("Initiating scan of type: ", $rescanType->[0]);

		Slim::Control::Request::executeRequest($client, $rescanType);
	}
}

1;
