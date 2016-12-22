package Slim::Plugin::Rescan::Plugin;

# Rescan.pm by Andrew Hedges (andrew@hedges.me.uk) October 2002
# Timer functions added by Kevin Deane-Freeman (kevindf@shaw.ca) June 2004
# $Id: Plugin.pm 11180 2007-01-12 01:04:40Z kdf $

# This code is derived from code with the following copyright message:
#
# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Time::HiRes;

use base qw(Slim::Plugin::Base);

if ( main::WEBUI ) {
	require Slim::Plugin::Rescan::Settings;
}

use Scalar::Util qw(blessed);

use Slim::Control::Request;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);

use constant RESCAN_TYPES => [
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
];

my $prefs = preferences('plugin.rescan');

$prefs->migrate(1, sub {
	require Slim::Utils::Prefs::OldPrefs;
	$prefs->set('time',      Slim::Utils::Prefs::OldPrefs->get('rescan-time')      || 9 * 60 * 60 );
	$prefs->set('scheduled', Slim::Utils::Prefs::OldPrefs->get('rescan-scheduled') || 0           );
	$prefs->set('type',      Slim::Utils::Prefs::OldPrefs->get('rescan-type')      || '1rescan'   );
	1;
});

my $interval = 1; # check every x seconds

my @progress = [0];

sub getDisplayName {
	return 'PLUGIN_RESCAN_MUSIC_LIBRARY';
}

sub initPlugin {
	my $class = shift;
	
	Slim::Buttons::Common::addMode('scanProgress', undef, \&setProgressMode, \&exitProgressMode);

	$class->SUPER::initPlugin();
	
	if ( main::WEBUI ) {
		Slim::Plugin::Rescan::Settings->new;
	}

	
	Slim::Control::Request::addDispatch(['rescanplugin', 'rescan'],   [0, 0, 0, \&executeRescan]);
	Slim::Control::Request::addDispatch(['rescanplugin', 'menu'],     [0, 1, 0, \&jiveRescanMenu]);
	Slim::Control::Request::addDispatch(['rescanplugin', 'typemenu'], [0, 1, 0, \&jiveRescanTypeMenu]);

	Slim::Control::Jive::registerPluginMenu([{
		text    => $class->getDisplayName,
		id      => 'settingsRescan',
		node    => 'advancedSettings',
		actions => {
			go => {
				cmd => ['rescanplugin', 'menu'],
				player => 0
			},
		},
	}]);

	setTimer();
}

sub jiveRescanMenu {
	my $request = shift;
	my $client  = $request->client();

	$request->addResult('offset', 0);

	$request->setResultLoopHash('item_loop', 0, {
		text => cstring($client, 'PLUGIN_RESCAN_TIMER_SET'),
		input => {
			initialText  => $prefs->get('time'),
			title => $client->string('PLUGIN_RESCAN_TIMER_SET'),
			_inputStyle  => 'time',
			len          => 1,
			help         => {
				text => $client->string('PLUGIN_RESCAN_TIMER_DESC')
			},
		},
		actions => {
			do => {
				player => 0,
				cmd    => [ 'pref', 'plugin.rescan:time' ],
				params => {
					value => '__TAGGEDINPUT__',	
					enabled => 1,
				},
			},
		},
		nextWindow => 'refresh',
	});

	$request->setResultLoopHash('item_loop', 1, {
		text    => cstring($client, 'PLUGIN_RESCAN_TIMER_NAME'),
		checkbox=> $prefs->get('scheduled') ? 1 : 0,
		actions => {
			on => {
				player => 0,
				cmd    => [ 'pref' , 'plugin.rescan:scheduled', 1 ],
			},
			off => {
				player => 0,
				cmd    => [ 'pref' , 'plugin.rescan:scheduled', 0 ],
			},
		},
		nextWindow => 'refresh',
	});

	$request->setResultLoopHash('item_loop', 2, {
		text    => cstring($client, 'PLUGIN_RESCAN_TIMER_TYPE'),
		actions => {
			go => {
				player => 0,
				cmd    => [ 'rescanplugin' , 'typemenu' ],
			},
		},
	});

	if ( Slim::Music::Import->stillScanning ) {
		$request->setResultLoopHash('item_loop', 3, {
			text => cstring($client, 'PLUGIN_RESCAN_RESCANNING'),
			nextWindow => 'refresh',
		});
	}
	else {
		$request->setResultLoopHash('item_loop', 3, {
			text    => cstring($client, 'PLUGIN_RESCAN_MUSIC_LIBRARY'),
			actions => {
				do => {
					cmd => [ 'rescanplugin' , 'rescan' ],
				},
			},
			nextWindow => 'refresh',
		});
	}
	
	$request->addResult('count', 4);
	$request->setStatusDone()
}

sub jiveRescanTypeMenu {
	my $request = shift;
	my $client  = $request->client();

	$request->addResult('offset', 0);

	my $i = 0;
	my $currentType = $prefs->get('type');
	
	foreach ( map {
		$_->{name} =~ /\{(.*)\}/;
		{
			name => $1 || $_->{name},
			value => $_->{value}
		}
	} @{RESCAN_TYPES()} ) {
		$request->setResultLoopHash('item_loop', $i++, {
			text    => cstring($client, $_->{name}),
			radio   => $currentType eq $_->{value} ? 1 : 0,
			actions => {
				do => {
					player => 0,
					cmd    => [ 'pref' , 'plugin.rescan:type' ],
					params => {
						value => $_->{value}
					}
				},
			},
		});
	}

	$request->addResult('count', $i);
	$request->setStatusDone();
}

sub setMode {
	my $class  = shift;
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my $browseMenuChoices = [
		'PLUGIN_RESCAN_TIMER_SET',
		'PLUGIN_RESCAN_TIMER_OFF',
		'PLUGIN_RESCAN_TIMER_TYPE',
		'PLUGIN_RESCAN_PRESS_PLAY',
	];

	if ( Slim::Music::Import->stillScanning ) {

		Slim::Buttons::Common::pushMode($client, 'scanProgress');
		
	} else {

		if (Slim::Schema::hasLibrary() && Slim::Schema->rs('Progress')->search( { 'type' => 'importer' }, { 'order_by' => 'start' } )->all) {
			push @$browseMenuChoices, 'SETUP_VIEW_NOT_SCANNING'
		}

		my %params = (
			'listRef'        => $browseMenuChoices,
			'externRefArgs'  => 'CV',
			'header'         => 'PLUGIN_RESCAN_MUSIC_LIBRARY',
			'headerAddCount' => 1,
			'stringHeader'   => 1,
			'callback'       => \&rescanExitHandler,
			'overlayRef'     => sub { 

					if($_[1] =~ /PLUGIN_RESCAN_TIMER_O/) {

						return (undef, Slim::Buttons::Common::checkBoxOverlay( $client, $prefs->get('scheduled')));

					} elsif ($_[1] ne 'PLUGIN_RESCAN_PRESS_PLAY') {

						return (undef, $_[0]->symbols('rightarrow'))
					}

				},
			'overlayRefArgs' => 'CV',
			'externRef'      => sub {
				my $client = shift;
				my $value  = shift;
				
				if ($prefs->get('scheduled') && $value eq 'PLUGIN_RESCAN_TIMER_OFF') {
	
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
		'listRef'            => [0],
		'externRef'          => \&progressBar,
		'externRefArgs'      => 'CI',
		'overlayRef'         => \&progressOverlay,
		'overlayRefArgs'     => 'CI',
		'modeUpdateInterval' => 1,
		'valueref'           => \$value,
		'listEnd'            => 1,
	);

	Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%progressParams);

	$client->block();
		
	progressUpdate($client);
}

sub progressOverlay {
	my $client = shift;
	my $index  = shift;
	
	my $overlay = ' (' . ($index + 1) . ' ' . $client->string('OF') .' ' . scalar(@{$client->modeParam('listRef')}) . ')';
	
	return ($overlay,undef);
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

		my $line = $p->name =~ /(.*)\|(.*)/ 
					? ($client->string($2 . '_PROGRESS') . $client->string('COLON') . ' ' . $1)
					: $client->string($p->name . '_PROGRESS');
	
		if ($p->active) {

			if ($p->total) {

				$line .= " ".$client->string('RUNNING');
				$line .= " ".($p->done.'/' . $p->total);
			
			} else {
				$line .= " ".$client->string('PLUGIN_RESCAN_PLEASE_WAIT');
			
			} 
		
		} else {
			$line .= " ".$client->string('COMPLETE');
		}
			
		return $line;
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

			my $complete = $p->total ? $p->done/$p->total : 0;

			return $client->sliderBar($client->displayWidth(), $complete * 100,0,0);
		} else {
			my $runtime = $p->finish - $p->start;
				
			my ($h0, $h1, $m0, $m1) = Slim::Utils::DateTime::timeDigits($runtime);

			return ($p->total || '0') . ' ' . $client->string('ITEMS') . " $h0$h1:$m0$m1".sprintf(":%02s",($runtime % 60));
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

	if (Slim::Schema::hasLibrary()) {
		@progress = Slim::Schema->rs('Progress')->search( { 'type' => 'importer' }, { 'order_by' => 'start' } )->all;
	}
	
	my $size;
	
	if (scalar @progress) {

		$client->unblock;

		$size = scalar @{$client->modeParam('listRef')};
		$client->modeParam('listRef',[0..$#progress]);

		# adjust the index to the last position if we were previously viewing the last entry
		# nb more than one entry may be added before we get called again
		if ($client->modeParam('listEnd') && $size != scalar @progress) {
			$client->modeParam('listIndex',$#progress);
		}
		$client->modeParam('listEnd', $client->modeParam('listIndex') == $#progress);

		$client->update;
		$client->updateKnob(1);
	}
	
	if ( Slim::Music::Import->stillScanning ) {
		
		# Block screensaver while checking progress and still scanning
		Slim::Hardware::IR::setLastIRTime(
			$client,
			Time::HiRes::time() + (preferences('server')->client($client)->get('screensavertimeout') * 5),
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

		$client->unblock();
		
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
			my $value = $prefs->get('time');
			
			my %params = (
				'header' => $client->string('PLUGIN_RESCAN_TIMER_SET'),
				'valueRef' => \$value,
				'callback' => \&settingsExitHandler
			);
			
			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Time',\%params);
	
		} elsif ($$valueref eq 'PLUGIN_RESCAN_TIMER_OFF') {
	
			$prefs->set('scheduled', 1);
			$$valueref = 'PLUGIN_RESCAN_TIMER_ON';
			setTimer($client);
			$client->update;
	
		} elsif ($$valueref eq 'PLUGIN_RESCAN_TIMER_ON') {
	
			$prefs->set('scheduled', 0);
			$$valueref = 'PLUGIN_RESCAN_TIMER_OFF';
			setTimer($client);
			$client->update;
		
		} elsif ($$valueref eq 'PLUGIN_RESCAN_TIMER_TYPE') {

			my $value = $prefs->get('type');

			my %params = (
				'listRef'      => RESCAN_TYPES,
				'onPlay'       => sub { $prefs->set('type', $_[1]->{'value'}); },
				'onAdd'        => sub { $prefs->set('type', $_[1]->{'value'}); },
				'onRight'      => sub { $prefs->set('type', $_[1]->{'value'}); },
				'header'       => '{PLUGIN_RESCAN_TIMER_TYPE}',
				'headerAddCount' => 1,
				'pref'         => sub { return $prefs->get('type'); },
				'initialValue' => sub { return $prefs->get('type'); },
				'valueRef'     => \$value,
			);

			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice',\%params);

		} elsif ($$valueref eq 'SETUP_VIEW_NOT_SCANNING') {
		
			Slim::Buttons::Common::pushModeLeft($client, 'scanProgress');
		}

	}
}

sub settingsExitHandler {
	my ($client,$exittype) = @_;

	$exittype = uc($exittype);

	if ($exittype eq 'LEFT' || $exittype eq 'RIGHT') {

		$prefs->set('time', ${$client->modeParam('valueRef')});

		$client->showBriefly({line=>[$client->string('PLUGIN_RESCAN_TIMER_SAVED')]});

		Slim::Buttons::Common::popMode($client);
	}
}

sub getFunctions {
	my $class = shift;

	return {
		'play' => sub {
			my $client = shift;

			if ($client->modeParam('listRef')->[$client->modeParam('listIndex')] eq 'PLUGIN_RESCAN_PRESS_PLAY') {

				executeRescan();

				$client->showBriefly( {
					'line' => [ $client->string('PLUGIN_RESCAN_MUSIC_LIBRARY'),
							$client->string('PLUGIN_RESCAN_RESCANNING') ]
				});

				Slim::Buttons::Common::pushMode($client, 'scanProgress');
				
			} else {

				$client->bumpRight();
			}
		}
	};
}

sub setTimer {
	# timer to check alarms on an interval
	Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + $interval, \&checkScanTimer);
}

sub checkScanTimer {

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

	Slim::Utils::Timers::killTimers(undef, \&checkScanTimer);

	my $time = $hour * 60 * 60 + $min * 60;

	if ($sec == 0) { # once we've reached the beginning of a minute, only check every 60s
		$interval = 60;
	}

	if ($sec >= 50) { # if we end up falling behind, go back to checking each second
		$interval = 1;
	}

	if ($prefs->get('scheduled')) {

		my $scantime = $prefs->get('time');

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
	my $rescanType = ['rescan'];
	my $rescanPref = $prefs->get('type') || '';

	if ($rescanPref eq '2wipedb') {

		$rescanType = ['wipecache'];

	} elsif ($rescanPref eq '3playlist') {

		$rescanType = [qw(rescan playlists)];
	}

	if (!Slim::Music::Import->stillScanning()) {

		main::INFOLOG && logger('scan.scanner')->info("Initiating scan of type: ", $rescanType->[0]);

		Slim::Control::Request::executeRequest(undef, $rescanType);
	}
}

1;
