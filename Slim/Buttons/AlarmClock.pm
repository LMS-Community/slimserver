# AlarmClock.pm by Kevin Deane-Freeman (kevindf@shaw.ca) March 2003
# Adapted from code by Lukas Hinsch
# Updated by Dean Blackketter
#
# This code is derived from code with the following copyright message:
#
# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

package Slim::Buttons::AlarmClock;

use Slim::Player::Playlist;
use Slim::Buttons::Common;
use Time::HiRes;

my $interval = 1; # check every x seconds
our @browseMenuChoices;
our %menuSelection;
our %searchCursor;
our $weekday;

# some initialization code, adding modes for this module
sub init {
	Slim::Buttons::Common::addMode('alarm', getFunctions(), \&Slim::Buttons::AlarmClock::setMode);
	Slim::Buttons::Common::addMode('alarmvolume', getAlarmVolumeFunctions(), \&Slim::Buttons::AlarmClock::setAlarmVolumeMode);
	setTimer();
}

# the routines
sub setMode {

	my $client = shift;

	$weekday = ${$client->param('day')} || 0;
	
	@browseMenuChoices = (
		$client->string('ALARM_SET'),
		$client->string('ALARM_SELECT_PLAYLIST'),
		$client->string('ALARM_SET_VOLUME'),
		$client->string('ALARM_OFF'),
	);

	unless ($weekday) {
		push @browseMenuChoices, $client->string('ALARM_WEEKDAYS');
	}

	unless (defined $menuSelection{$weekday}{$client}) {
		$menuSelection{$weekday}{$client} = 0;
	}

	$client->lines(\&lines);

	# get previous alarm time or set a default
	my $time = Slim::Utils::Prefs::clientGet($client, "alarmtime", $weekday);

	unless (defined $time) {
		Slim::Utils::Prefs::clientSet($client, "alarmtime", 9 * 60 * 60, $weekday);
	}
}

our %functions = (
	'up' => sub  {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#browseMenuChoices + 1), $menuSelection{$weekday}{$client});

		if ($newposition != $menuSelection{$weekday}{$client}) {
			$menuSelection{$weekday}{$client} = $newposition;
			$client->pushUp();
		}
	},
	'down' => sub  {
	   my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, +1, ($#browseMenuChoices + 1), $menuSelection{$weekday}{$client});

		if ($newposition != $menuSelection{$weekday}{$client}) {
			$menuSelection{$weekday}{$client} = $newposition;
			$client->pushDown();
		}
	},
	'left' => sub  {
		my $client = shift;

		Slim::Buttons::Common::popModeRight($client);
	},
	'right' => sub  {
		my $client = shift;
		my @oldlines = Slim::Display::Display::curLines($client);

		if ($browseMenuChoices[$menuSelection{$weekday}{$client}] eq $client->string('ALARM_SET')) {
			my %params = (
				'header' => $client->string('ALARM_SET')
				,'valueRef' => Slim::Utils::Prefs::clientGet($client,"alarmtime", $weekday)
				,'cursorPos' => 1
				,'callback' => \&exitSetHandler
				,'onChange' => sub { Slim::Utils::Prefs::clientSet($_[0],"alarmtime",Slim::Buttons::Common::param($_[0],'valueRef'), $weekday); }
				,'onChangeArgs' => 'C'
			);
			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Time',\%params);
		}
		if ($browseMenuChoices[$menuSelection{$weekday}{$client}] eq $client->string('ALARM_SELECT_PLAYLIST')) {

			# Make a copy of the playlists, to make sure they
			# aren't removed by the LRU cache. This may fix bug: 1853
			
			my $ds   = Slim::Music::Info::getCurrentDataStore();
			
			my %params = (
				'listRef' => [ $ds->getPlaylists() ]
				,'externRef' => sub {Slim::Music::Info::standardTitle($_[0],$_[1]);}
				,'externRefArgs' => 'CV'
				,'header' => 'ALARM_SELECT_PLAYLIST'
				,'headerAddCount' => 1
				,'stringHeader' => 1
				,'onChange' => sub { 	Slim::Utils::Prefs::clientSet($_[0], "alarmplaylist", $_[1], $weekday); }
				,'onChangeArgs' => 'CV'
				,'valueRef' => \&Slim::Utils::Prefs::clientGet($client,"alarmplaylist", $weekday)
			);
			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List',\%params);
		}
		elsif ($browseMenuChoices[$menuSelection{$weekday}{$client}] eq $client->string('ALARM_OFF')) {
			Slim::Utils::Prefs::clientSet($client, "alarm", 1, $weekday);
			$browseMenuChoices[$menuSelection{$weekday}{$client}] = $client->string('ALARM_ON');
			$client->showBriefly($client->string('ALARM_TURNING_ON'),'');
			setTimer($client);
		}
		elsif ($browseMenuChoices[$menuSelection{$weekday}{$client}] eq $client->string('ALARM_ON')) {
			Slim::Utils::Prefs::clientSet($client, "alarm", 0, $weekday);
			$browseMenuChoices[$menuSelection{$weekday}{$client}] = $client->string('ALARM_OFF');
			$client->showBriefly($client->string('ALARM_TURNING_OFF'),'');
			setTimer($client);
		}
		elsif ($browseMenuChoices[$menuSelection{$weekday}{$client}] eq $client->string('ALARM_SET_VOLUME')) {
			Slim::Buttons::Common::pushModeLeft($client, 'alarmvolume');
		}
		elsif ($browseMenuChoices[$menuSelection{$weekday}{$client}] eq $client->string('ALARM_WEEKDAYS')) {
			# Make a copy of the playlists, to make sure they
			# aren't removed by the LRU cache. This may fix bug: 1853
			
			my $ds   = Slim::Music::Info::getCurrentDataStore();
			my $day;
			
			my %params = (
				'listRef' => [1..7]
				,'externRef' => sub {$_[0]->string(ALARM_DAY.$_[1]);}
				,'externRefArgs' => 'CV'
				,'header' => 'ALARM_WEEKDAYS'
				,'headerAddCount' => 1
				,'stringHeader' => 1
				,'valueRef' => \$day
				,'callback' => \&weekdayExitHandler
			);
			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List',\%params);
		} 
	},
	'play' => sub {
		my $client = shift;
	},
);

sub weekdayExitHandler {
	my ($client, $exittype) = @_;

	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {

		my %params = (
			'day' => $client->param('valueRef'),
		);
		Slim::Buttons::Common::pushModeLeft($client,'alarm',\%params);

	} else {
		return;
	}
}

sub exitSetHandler {
	my ($client, $exittype) = @_;

	$exittype = uc($exittype);

	if ($exittype eq 'LEFT' || $exittype eq 'PLAY') {

		Slim::Utils::Prefs::clientSet($client,"alarmtime",$client->param('valueRef'), $weekday);
		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {

		$client->bumpRight();

	} else {
		return;
	}
}

sub setTimer {
	# timer to check alarms on an interval
	Slim::Utils::Timers::setTimer(0, Time::HiRes::time() + $interval, \&checkAlarms);
}

sub checkAlarms
{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

	my $time = $hour * 60 * 60 + $min * 60;

	if ($sec == 0) { # once we've reached the beginning of a minute, only check every 60s
		$interval = 60;
	}

	if ($sec >= 50) { # if we end up falling behind, go back to checking each second
		$interval = 1;
	}

	foreach my $client (Slim::Player::Client::clients()) {
		if (Slim::Utils::Prefs::clientGet($client, "alarm", 0)) {
			my $alarmtime =  Slim::Utils::Prefs::clientGet($client, "alarmtime", 0);
			if ($alarmtime) {
			   if ($time == $alarmtime +60 ) {$interval=1;}; #alarm is done, so reset to find the beginning of a minute
				if ($time == $alarmtime) {
					$client->execute(['stop']);
					my $volume = Slim::Utils::Prefs::clientGet($client, "alarmvolume", 0);
					if (defined ($volume)) {
						$client->execute(["mixer", "volume", $volume]);
					}

					# fade volume over time
					$client->fade_volume(Slim::Utils::Prefs::clientGet($client, "alarmfadeseconds", 0));

					if (defined Slim::Utils::Prefs::clientGet($client, "alarmplaylist", 0)) {
						$client->execute(["power", 1]);
						Slim::Buttons::Block::block($client,alarmLines($client));
						$client->execute(["playlist", "load", Slim::Utils::Prefs::clientGet($client, "alarmplaylist", 0)], \&playDone, [$client]);
					} else {
						$client->execute(['play']);
						Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 2, \&visibleAlarm, $client);	
					}
				}
			}
		}
		if (Slim::Utils::Prefs::clientGet($client, "alarm", $wday)) {
			my $alarmtime =  Slim::Utils::Prefs::clientGet($client, "alarmtime", $wday);
			if ($alarmtime) {
			   if ($time == $alarmtime +60 ) {$interval=1;}; #alarm is done, so reset to find the beginning of a minute
				if ($time == $alarmtime) {
					$client->execute(['stop']);
					my $volume = Slim::Utils::Prefs::clientGet($client, "alarmvolume", $wday);
					if (defined ($volume)) {
						$client->execute(["mixer", "volume", $volume]);
					}

					# fade volume over time
					$client->fade_volume(Slim::Utils::Prefs::clientGet($client, "alarmfadeseconds", $wday));

					if (defined Slim::Utils::Prefs::clientGet($client, "alarmplaylist", $wday)) {
						$client->execute(["power", 1]);
						Slim::Buttons::Block::block($client,alarmLines($client));
						$client->execute(["playlist", "load", Slim::Utils::Prefs::clientGet($client, "alarmplaylist", $wday)], \&playDone, [$client]);
					} else {
						$client->execute(['play']);
						Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 2, \&visibleAlarm, $client);	
					}
				}
			}
		}
	}
	setTimer();
}

sub playDone {
	my $client = shift;
	Slim::Buttons::Block::unblock($client);
	# show the alarm screen after a couple of seconds when the song has started playing and the display is updated
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 2, \&visibleAlarm, $client);	
}

sub alarmLines {
	my $client = shift;
	my $line1 = $client->string('ALARM_NOW_PLAYING');
	my $line2 = Slim::Utils::Prefs::clientGet($client, "alarmplaylist", $weekday) ? Slim::Music::Info::standardTitle($client,Slim::Utils::Prefs::clientGet($client, "alarmplaylist", $weekday)) : "";
	return ($line1, $line2);
}

sub visibleAlarm {
	my $client = shift;
	my ($line1, $line2) =  alarmLines($client);
	#show visible alert for 30s
	$client->showBriefly($line1, $line2,30);
}

sub lines {
	my $client = shift;
	my ($line1, $line2, $overlay);

	$overlay = overlay($client);
	$line1 = $weekday ? 
		$client->string('ALARM_WEEKDAYS')." - ".$client->string('ALARM_DAY'.$weekday) : 
		$client->string('ALARM');

	if (Slim::Utils::Prefs::clientGet($client, "alarm", $weekday) && $browseMenuChoices[$menuSelection{$weekday}{$client}] eq $client->string('ALARM_OFF')) {
		$browseMenuChoices[$menuSelection{$weekday}{$client}] = $client->string('ALARM_ON');
	}
	$line2 = "";

	$line2 = $browseMenuChoices[$menuSelection{$weekday}{$client}];
	return ($line1, $line2, undef, $overlay);
}

sub overlay {
	my $client = shift;

	return Slim::Display::Display::symbol('rightarrow');
	
	return undef;
}

sub getFunctions {
	return \%functions;
}

#################################################################################
# Alarm Volume Mode
our %alarmVolumeSettingsFunctions = (
	'left' => sub { Slim::Buttons::Common::popModeRight(shift); },
	'up' => sub {
		my $client = shift;
		my $volume = Slim::Utils::Prefs::clientGet($client, "alarmvolume", $weekday);
		my $inc = 1;
		my $rate = 50; #Hz maximum
		my $accel = 15; #Hz/s

		if (Slim::Hardware::IR::holdTime($client) > 0) {
			$inc *= Slim::Hardware::IR::repeatCount($client,$rate,$accel);
		} else {
			$inc = 2.5;
		}

		if (!defined($volume)) { $volume = $client->volume(); }
		$volume += $inc;
		if ($volume > $client->maxVolume()) { $volume = $client->maxVolume(); };
		Slim::Utils::Prefs::clientSet($client, "alarmvolume", $volume, $weekday);
		$client->update();
	},

	'down' => sub {
		my $client = shift;
		my $volume = Slim::Utils::Prefs::clientGet($client, "alarmvolume", $weekday);
		my $inc = 1;
		my $rate = 50; #Hz maximum
		my $accel = 15; #Hz/s

		if (Slim::Hardware::IR::holdTime($client) > 0) {
			$inc *= Slim::Hardware::IR::repeatCount($client,$rate,$accel);
		} else {
			$inc = 2.5;
		}

		if (!defined($volume)) { $volume = $client->volume(); }
		$volume -= $inc;
		if ($volume < 0) { $volume = 0; };
		Slim::Utils::Prefs::clientSet($client, "alarmvolume", $volume, $weekday);
		$client->update();
	},

	'right' => sub { shift->bumpRight(); },
	'add' => sub { shift->bumpRight(); },
	'play' => sub { shift->bumpRight(); },

);

sub getAlarmVolumeFunctions {
	return \%alarmVolumeSettingsFunctions;
}

sub setAlarmVolumeMode {
	my $client = shift;
	$client->lines(\&alarmVolumeLines);
}

sub alarmVolumeLines {
	my $client = shift;
	my $volume = Slim::Utils::Prefs::clientGet($client, "alarmvolume", $weekday);

	if (!defined($volume)) { $volume = $client->volume(); }

	my $level = int($volume / $client->maxVolume() * 40);

	my $line1 = ($client->linesPerScreen() == 1) ? $client->string('ALARM_SET_VOLUME_SHORT') : $client->string('ALARM_SET_VOLUME');
	my $line2;

	if ($level < 0) {
		$line1 .= " (". $client->string('MUTED') . ")";
		$level = 0;
	} else {
		$line1 .= " (".$level.")";
	}

	$line2 = Slim::Display::Display::progressBar($client, $client->displayWidth(), $level / 40);

	if ($client->linesPerScreen() == 1) { $line2 = $line1; }
	return ($line1, $line2);
}

1;

__END__
