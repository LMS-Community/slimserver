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
use Slim::Utils::Misc;
use Time::HiRes;

my $interval = 1; # check every x seconds

my (@browseMenuChoices, %functions, %menuSelection, %searchCursor, $weekDay, %alarmVolumeSettingsFunctions);

# some initialization code, adding modes for this module
sub init {

	Slim::Buttons::Common::addMode('alarm', getFunctions(), \&Slim::Buttons::AlarmClock::setMode);
	Slim::Buttons::Common::addMode('alarmvolume', getAlarmVolumeFunctions(), \&Slim::Buttons::AlarmClock::setAlarmVolumeMode);
	setTimer();

	%functions = (

		'up' => sub  {
			my $client = shift;
			my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#browseMenuChoices + 1), $menuSelection{$weekDay}{$client});

			if ($newposition != $menuSelection{$weekDay}{$client}) {
				$menuSelection{$weekDay}{$client} = $newposition;
				$client->pushUp();
			}
		},

		'down' => sub  {
			my $client = shift;
			my $newposition = Slim::Buttons::Common::scroll($client, +1, ($#browseMenuChoices + 1), $menuSelection{$weekDay}{$client});

			if ($newposition != $menuSelection{$weekDay}{$client}) {
				$menuSelection{$weekDay}{$client} = $newposition;
				$client->pushDown();
			}
		},

		'left' => sub  {
			my $client = shift;

			Slim::Buttons::Common::popModeRight($client);
		},

		'right' => sub  {
			my $client   = shift;
			my @oldlines = Slim::Display::Display::curLines($client);

			my $menuChoice = $browseMenuChoices[$menuSelection{$weekDay}{$client}];

			if ($menuChoice eq $client->string('ALARM_SET')) {

				my %params = (
					'header'    => $client->string('ALARM_SET'),
					'valueRef'  => $client->prefGet("alarmtime", $weekDay),
					'cursorPos' => 1,
					'callback'  => \&exitSetHandler,
					'onChange'  => sub {
						my $client = shift;

						$client->prefSet(
							'alarmtime',
							Slim::Buttons::Common::param($client, 'valueRef'),
							$weekDay
						);
					},

					'onChangeArgs' => 'C',
				);

				Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Time',\%params);
			}

			if ($menuChoice eq $client->string('ALARM_SELECT_PLAYLIST')) {

				# Make a copy of the playlists, to make sure they
				# aren't removed by the LRU cache. This may fix bug: 1853
				
				my $ds   = Slim::Music::Info::getCurrentDataStore();
				
				my %params = (
					'listRef'        => [ $ds->getPlaylists() ],
					'externRef'      => sub { Slim::Music::Info::standardTitle(@_) },
					'externRefArgs'  => 'CV',
					'header'         => 'ALARM_SELECT_PLAYLIST',
					'headerAddCount' => 1,
					'stringHeader'   => 1,
					'onChange'       => sub {
						my $client = shift;
						my $item   = shift;

						$client->prefSet("alarmplaylist", $item, $weekDay);
					},

					'onChangeArgs'   => 'CV',
					'valueRef'       => \$client->prefGet("alarmplaylist", $weekDay),
				);

				Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List',\%params);

			} elsif ($menuChoice eq $client->string('ALARM_OFF')) {

				$client->prefSet("alarm", 1, $weekDay);

				$browseMenuChoices[$menuSelection{$weekDay}{$client}] = $client->string('ALARM_ON');

				$client->showBriefly($client->string('ALARM_TURNING_ON'),'');

				setTimer($client);

			} elsif ($menuChoice eq $client->string('ALARM_ON')) {

				$client->prefSet("alarm", 0, $weekDay);

				$browseMenuChoices[$menuSelection{$weekDay}{$client}] = $client->string('ALARM_OFF');

				$client->showBriefly($client->string('ALARM_TURNING_OFF'),'');

				setTimer($client);

			} elsif ($menuChoice eq $client->string('ALARM_SET_VOLUME')) {

				Slim::Buttons::Common::pushModeLeft($client, 'alarmvolume');

			} elsif ($menuChoice eq $client->string('ALARM_WEEKDAYS')) {

				# Make a copy of the playlists, to make sure they
				# aren't removed by the LRU cache. This may fix bug: 1853
				my $ds  = Slim::Music::Info::getCurrentDataStore();
				my $day = 0;
				
				my $params = {
					'listRef'        => [ 1..7 ],
					'externRef'      => sub { 
						my $client    = shift;
						my $dayOfWeek = shift;

						my $dowString = $client->string("ALARM_DAY$dayOfWeek");

						if ($client->prefGet('alarm', $dayOfWeek)) {

							$dowString .= sprintf("(%s)",
								Slim::Buttons::Input::Time::timeString(
									$client,
									Slim::Buttons::Input::Time::timeDigits(
										$client,
										$client->prefGet('alarmtime', $day)
									)
								) 
							);
						
						} else {

							$dowString .= sprintf("(%s)", $client->string('OFF'));
						}

						return $dowString;
					},

					'externRefArgs'  => 'CV',
					'header'         => 'ALARM_WEEKDAYS',
					'headerAddCount' => 1,
					'stringHeader'   => 1,
					'valueRef'       => \$day,
					'callback'       => \&weekdayExitHandler,
				};

				Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', $params);
			} 
		},

		'play' => sub {
			my $client = shift;
		},
	);

	#################################################################################
	# Alarm Volume Mode

	%alarmVolumeSettingsFunctions = (
		'left' => sub {
			my $client = shift;

			Slim::Buttons::Common::popModeRight($client);
		},

		'up' => sub {
			my $client = shift;

			my $volume = $client->prefGet("alarmvolume", $weekDay);
			my $inc    = 1;
			my $rate   = 50; #Hz maximum
			my $accel  = 15; #Hz/s

			if (Slim::Hardware::IR::holdTime($client) > 0) {
				$inc *= Slim::Hardware::IR::repeatCount($client,$rate,$accel);
			} else {
				$inc = 2.5;
			}

			if (!defined $volume) {
				$volume = $client->volume;
			}

			$volume += $inc;

			if ($volume > $client->maxVolume) {

				$volume = $client->maxVolume;
			}

			$client->prefSet("alarmvolume", $volume, $weekDay);

			$client->update;
		},

		'down' => sub {
			my $client = shift;

			my $volume = $client->prefGet("alarmvolume", $weekDay);
			my $inc    = 1;
			my $rate   = 50; #Hz maximum
			my $accel  = 15; #Hz/s

			if (Slim::Hardware::IR::holdTime($client) > 0) {
				$inc *= Slim::Hardware::IR::repeatCount($client,$rate,$accel);
			} else {
				$inc = 2.5;
			}

			if (!defined $volume) {
				$volume = $client->volume;
			}

			$volume -= $inc;

			if ($volume < 0) {
				$volume = 0;
			}

			$client->prefSet("alarmvolume", $volume, $weekDay);

			$client->update;
		},

		'right' => sub { shift->bumpRight },
		'add'   => sub { shift->bumpRight },
		'play'  => sub { shift->bumpRight },
	);
}

# the routines
sub setMode {
	my $client = shift;

	$weekDay = ${$client->param('day')} || 0;
	
	@browseMenuChoices = (
		$client->string('ALARM_SET'),
		$client->string('ALARM_SELECT_PLAYLIST'),
		$client->string('ALARM_SET_VOLUME'),
		$client->string('ALARM_OFF'),
	);

	unless ($weekDay) {
		push @browseMenuChoices, $client->string('ALARM_WEEKDAYS');
	}

	unless (defined $menuSelection{$weekDay}{$client}) {
		$menuSelection{$weekDay}{$client} = 0;
	}

	$client->lines(\&lines);

	# get previous alarm time or set a default
	my $time = $client->prefGet("alarmtime", $weekDay);

	unless (defined $time) {
		$client->prefSet("alarmtime", 9 * 60 * 60, $weekDay);
	}
}

sub weekdayExitHandler {
	my ($client, $exittype) = @_;

	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {

		my %params = (
			'day' => $client->param('valueRef'),
		);

		Slim::Buttons::Common::pushModeLeft($client,'alarm', \%params);
	}
}

sub exitSetHandler {
	my ($client, $exittype) = @_;

	$exittype = uc($exittype);

	if ($exittype eq 'LEFT' || $exittype eq 'PLAY') {

		$client->prefSet("alarmtime", $client->param('valueRef'), $weekDay);

		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {

		$client->bumpRight();
	}
}

sub setTimer {
	# timer to check alarms on an interval
	Slim::Utils::Timers::setTimer(0, Time::HiRes::time() + $interval, \&checkAlarms);
}

sub checkAlarms {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday) = localtime(time);

	my $time = $hour * 60 * 60 + $min * 60;

	# once we've reached the beginning of a minute, only check every 60s
	if ($sec == 0) {
		$interval = 60;
	}

	# if we end up falling behind, go back to checking each second
	if ($sec >= 50) {
		$interval = 1;
	}

	foreach my $client (Slim::Player::Client::clients()) {

		for my $day (0, $wday) {

			next unless $client->prefGet("alarm", $day);

			my $alarmtime = $client->prefGet("alarmtime", $day) || next;

			if ($time == ($alarmtime + 60)) {

				# alarm is done, so reset to find the beginning of a minute
				$interval = 1;
			}

			if ($time == $alarmtime) {

				$client->execute(['stop']);

				my $volume = $client->prefGet("alarmvolume", $day);

				if (defined ($volume)) {
					$client->execute(["mixer", "volume", $volume]);
				}

				# fade volume over time
				$client->fade_volume($client->prefGet("alarmfadeseconds", $day));

				if (defined $client->prefGet("alarmplaylist", $day)) {

					$client->execute(["power", 1]);

					Slim::Buttons::Block::block($client, alarmLines($client));

					$client->execute(["playlist", "load", $client->prefGet("alarmplaylist", $day)], \&playDone, [$client]);

				} else {

					$client->execute(['play']);

					Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 2, \&visibleAlarm, $client);	
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
	my $line2 = '';

	# Be sure to pull the correct day, otherwise we'll send an array and standardTitle won't know what to do.
	$weekDay = ${$client->param('day')} || 0;

	if ($client->prefGet("alarmplaylist", $weekDay)) {

		# XXX
		Slim::Music::Info::standardTitle($client, $client->prefGet("alarmplaylist", $weekDay));
	}

	return ($line1, $line2);
}

sub visibleAlarm {
	my $client = shift;

	# show visible alert for 30s
	$client->showBriefly(alarmLines($client), 30);
}

sub lines {
	my $client = shift;

	my $line1 = $client->string('ALARM');

	if ($weekDay) {

		$line1 = sprintf('%s - %', $client->string('ALARM_WEEKDAYS'), $client->string('ALARM_DAY'.$weekDay));
	}

	if ($client->prefGet("alarm", $weekDay) && 
		$browseMenuChoices[$menuSelection{$weekDay}{$client}] eq $client->string('ALARM_OFF')) {

		$browseMenuChoices[$menuSelection{$weekDay}{$client}] = $client->string('ALARM_ON');
	}

	return {
		'line1'   => $line1,
		'line2'   => $browseMenuChoices[$menuSelection{$weekDay}{$client}] || '',
		'overlay' => overlay($client),
	};
}

sub overlay {
	my $client = shift;

	return Slim::Display::Display::symbol('rightarrow');
}

sub getFunctions {
	return \%functions;
}

sub getAlarmVolumeFunctions {
	return \%alarmVolumeSettingsFunctions;
}

sub setAlarmVolumeMode {
	my $client = shift;

	$client->lines(\&alarmVolumeLines);
}

sub alarmVolumeLines {
	my $client = shift;

	my $volume = $client->prefGet("alarmvolume", $weekDay);

	if (!defined $volume) {
		$volume = $client->volume;
	}

	my $level = int($volume / $client->maxVolume * 40);

	my $line1 = ($client->linesPerScreen == 1) ? $client->string('ALARM_SET_VOLUME_SHORT') : $client->string('ALARM_SET_VOLUME');
	my $line2;

	if ($level < 0) {
		$line1 .= sprintf(" (%s)", $client->string('MUTED'));
		$level = 0;
	} else {
		$line1 .= sprintf(" (%s)", $level);
	}

	$line2 = Slim::Display::Display::progressBar($client, $client->displayWidth, $level / 40);

	if ($client->linesPerScreen == 1) {
		$line2 = $line1;
	}

	return {
		'line1' => $line1,
		'line2' => $line2,
	};
}

1;

__END__
