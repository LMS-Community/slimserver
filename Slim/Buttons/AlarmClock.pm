# AlarmClock.pm V0.8 by Kevin Deane-Freeman (kevindf@shaw.ca) March 2003
# Adapted from code by Lukas Hinsch
# Updated by Dean Blackketter
#
# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

package Slim::Buttons::AlarmClock;

use Slim::Player::Playlist;
use Slim::Utils::Strings qw (string);

my $interval = 1; # check every x seconds
my @browseMenuChoices;
my %menuSelection;
my %searchCursor;


# the routines
sub setMode() {
	my $client = shift;
	@browseMenuChoices = (
		string('ALARM_SET'),
		string('ALARM_SELECT_PLAYLIST'),
		string('ALARM_SET_VOLUME'),
		string('ALARM_OFF'),
		);
	if (!defined($menuSelection{$client})) { $menuSelection{$client} = 0; };
	$client->lines(\&lines);
	#get previous alarm time or set a default
	my $time = Slim::Utils::Prefs::clientGet($client, "alarmtime");
	if (!defined($time)) { Slim::Utils::Prefs::clientSet($client, "alarmtime", 9 * 60 * 60 ); }
   }

my %functions = (
	'up' => sub  {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#browseMenuChoices + 1), $menuSelection{$client});

		$menuSelection{$client} =$newposition;
		Slim::Display::Display::update($client);
	},
	'down' => sub  {
	   my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, +1, ($#browseMenuChoices + 1), $menuSelection{$client});

		$menuSelection{$client} =$newposition;
		Slim::Display::Display::update($client);
	},
	'left' => sub  {
		my $client = shift;

		Slim::Buttons::Common::popModeRight($client);
	},
	'right' => sub  {
		my $client = shift;
		my @oldlines = Slim::Display::Display::curLines($client);

		if ($browseMenuChoices[$menuSelection{$client}] eq string('ALARM_SET')) {
			Slim::Buttons::Common::pushModeLeft($client, 'alarmset');
		}
		if ($browseMenuChoices[$menuSelection{$client}] eq string('ALARM_SELECT_PLAYLIST')) {
			Slim::Buttons::Common::pushModeLeft($client, 'alarmplaylist');
		}
		elsif ($browseMenuChoices[$menuSelection{$client}] eq string('ALARM_OFF')) {
			Slim::Utils::Prefs::clientSet($client, "alarm", 1);
			$browseMenuChoices[$menuSelection{$client}] = string('ALARM_ON');
			Slim::Display::Animation::showBriefly($client,string('ALARM_TURNING_ON'),'');
			setTimer($client);
		}
		elsif ($browseMenuChoices[$menuSelection{$client}] eq string('ALARM_ON')) {
			Slim::Utils::Prefs::clientSet($client, "alarm", 0);
			$browseMenuChoices[$menuSelection{$client}] = string('ALARM_OFF');
			Slim::Display::Animation::showBriefly($client,string('ALARM_TURNING_OFF'),'');
			setTimer($client);
		}
		elsif ($browseMenuChoices[$menuSelection{$client}] eq string('ALARM_SET_VOLUME')) {
			Slim::Buttons::Common::pushModeLeft($client, 'alarmvolume');
		}
	},
	'play' => sub {
		my $client = shift;
	},
);

sub setTimer {
#timer to check alarms on an interval
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
		if (Slim::Utils::Prefs::clientGet($client, "alarm")) {
			my $alarmtime =  Slim::Utils::Prefs::clientGet($client, "alarmtime");
			if ($alarmtime) {
			   if ($time == $alarmtime +60 ) {$interval=1;}; #alarm is done, so reset to find the beginning of a minute
				if ($time == $alarmtime) {
					Slim::Control::Command::execute($client, ['stop']);
					my $volume = Slim::Utils::Prefs::clientGet($client, "alarmvolume");
					if (defined ($volume)) {
						Slim::Control::Command::execute($client, ["mixer", "volume", $volume]);
					}
					if (defined Slim::Utils::Prefs::clientGet($client, "alarmplaylist")) {
						Slim::Control::Command::execute($client, ["power", 1]);
						Slim::Buttons::Block::block($client,alarmLines($client));
						Slim::Control::Command::execute($client, ["playlist", "load", Slim::Utils::Prefs::clientGet($client, "alarmplaylist")], \&playDone, [$client]);
					} else {
						Slim::Control::Command::execute($client, ['play']);
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
	my $line1 = string('ALARM_NOW_PLAYING');
	my $line2 = Slim::Utils::Prefs::clientGet($client, "alarmplaylist") ? Slim::Music::Info::standardTitle($client,Slim::Utils::Prefs::clientGet($client, "alarmplaylist")) : "";
	return ($line1, $line2);
}

sub visibleAlarm {
	my $client = shift;
	my ($line1, $line2) =  alarmLines($client);
#show visible alert for 30s
	Slim::Display::Animation::showBriefly($client,$line1, $line2,30);
}

sub lines {
	my $client = shift;
	my ($line1, $line2, $overlay);
	my $timeFormat = Slim::Utils::Prefs::get("timeFormat");

	$overlay = overlay($client);
	$line1 = string('ALARM');

	if (Slim::Utils::Prefs::clientGet($client, "alarm") && $browseMenuChoices[$menuSelection{$client}] eq string('ALARM_OFF')) {
		$browseMenuChoices[$menuSelection{$client}] = string('ALARM_ON');
	}
	$line2 = "";

	$line2 = $browseMenuChoices[$menuSelection{$client}];
	return ($line1, $line2, undef, $overlay);
}

sub overlay {
	my $client = shift;

	return Slim::Hardware::VFD::symbol('rightarrow');
	
	return undef;
}

sub getFunctions() {
	return \%functions;
}

#################################################################################
# Alarm Volume Mode
my %alarmVolumeSettingsFunctions = (
	'left' => sub { Slim::Buttons::Common::popModeRight(shift); },
	'up' => sub {
		my $client = shift;
		my $volume = Slim::Utils::Prefs::clientGet($client, "alarmvolume");
		my $inc = 1;
		my $rate = 50; #Hz maximum
		my $accel = 15; #Hz/s

		if (Slim::Hardware::IR::holdTime($client) > 0) {
			$inc *= Slim::Hardware::IR::repeatCount($client,$rate,$accel);
		} else {
			$inc = 2.5;
		}

		if (!defined($volume)) { $volume = Slim::Utils::Prefs::clientGet($client, "volume"); }
		$volume += $inc;
		if ($volume > $Slim::Player::Control::maxVolume) { $volume = $Slim::Player::Control::maxVolume; };
		Slim::Utils::Prefs::clientSet($client, "alarmvolume", $volume);
		Slim::Display::Display::update($client);
	},

	'down' => sub {
		my $client = shift;
		my $volume = Slim::Utils::Prefs::clientGet($client, "alarmvolume");
		my $inc = 1;
		my $rate = 50; #Hz maximum
		my $accel = 15; #Hz/s

		if (Slim::Hardware::IR::holdTime($client) > 0) {
			$inc *= Slim::Hardware::IR::repeatCount($client,$rate,$accel);
		} else {
			$inc = 2.5;
		}

		if (!defined($volume)) { $volume = Slim::Utils::Prefs::clientGet($client, "volume"); }
		$volume -= $inc;
		if ($volume < 0) { $volume = 0; };
		Slim::Utils::Prefs::clientSet($client, "alarmvolume", $volume);
		Slim::Display::Display::update($client);
	},

	'right' => sub { Slim::Display::Animation::bumpRight(shift); },
	'add' => sub { Slim::Display::Animation::bumpRight(shift); },
	'play' => sub { Slim::Display::Animation::bumpRight(shift); },

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
	my $volume = Slim::Utils::Prefs::clientGet($client, "alarmvolume");

	if (!defined($volume)) { $volume = Slim::Utils::Prefs::clientGet($client, "volume"); }

	my $level = int($volume / $Slim::Player::Control::maxVolume * 40);

	my $line1 = Slim::Utils::Prefs::clientGet($client,'doublesize') ? string('ALARM_SET_VOLUME_SHORT') : string('ALARM_SET_VOLUME');
	my $line2;

	if ($level < 0) {
		$line1 .= " (". string('MUTED') . ")";
		$level = 0;
	} else {
		$line1 .= " (".$level.")";
	}

	$line2 = Slim::Display::Display::progressBar($client, 40, $level / 40);

	if (Slim::Utils::Prefs::clientGet($client,'doublesize')) { $line2 = $line1; }
	return ($line1, $line2);
}


#################################################################################

my %alarmSetFunctions = (
	'up' => sub {
		my $client = shift;
		scrollDigit($client, +1);
	},
	'down' => sub {
		my $client = shift;
		scrollDigit($client, -1);
	},

	'left' => sub {
		my $client = shift;
		$searchCursor{$client}--;
		if ($searchCursor{$client} < 0) {
			Slim::Buttons::Common::popModeRight($client);
		} else {
			Slim::Display::Display::update($client);
		}
	 },
	'right' => sub {
		my $client = shift;

		my ($h0, $h1, $m0, $m1, $p) = timeDigits($client);

		$searchCursor{$client}++;

		my $max = defined($p) ? 4 : 3;
		if ($searchCursor{$client} > $max) {
			$searchCursor{$client} = $max;
			#Slim::Buttons::Common::popModeRight($client);
		}
		Slim::Display::Display::update($client);
	},

	'add' => sub { Slim::Display::Animation::bumpRight(shift); },
	'play' => sub { Slim::Display::Animation::bumpRight(shift); },
	'numberScroll' => sub  {
		my $client = shift;
		my $button = shift;
		my $digit = shift;

		my ($h0, $h1, $m0, $m1, $p) = timeDigits($client);

		my $h = $h0 * 10 + $h1;
		if ($p && $h == 12) { $h = 0 };

		my $c = $searchCursor{$client};
		if ($c == 0 && $digit < ($p ? 2:3)) { $h0 = $digit; $searchCursor{$client}++; };
		if ($c == 1 && (($h0 * 10 + $digit) < 24)) { $h1 = $digit; $searchCursor{$client}++; };
		if ($c == 2) { $m0 = $digit; $searchCursor{$client}++; };
		if ($c == 3) { $m1 = $digit };

		$p = (defined $p && $p eq 'PM') ? 1 : 0;
		if ($c == 4) { $p = $digit % 2; }

		my $time = ($h0 * 10 + $h1) * 60 * 60 + $m0 * 10 * 60 + $m1 * 60 + $p * 12 * 60 * 60;
		Slim::Utils::Prefs::clientSet($client, "alarmtime", $time);
		Slim::Display::Display::update($client);

		#update the display
		Slim::Display::Display::update($client);
	}
);

sub getAlarmSetFunctions {
	return \%alarmSetFunctions;
}

sub setAlarmSetMode {
	my $client = shift;
	$searchCursor{$client} = 0;
	$client->lines(\&alarmSetSettingsLines);
}

 sub alarmSetSettingsLines {
	my $client = shift;

	my ($h0, $h1, $m0, $m1, $p) = timeDigits($client);

	my $cs = Slim::Hardware::VFD::symbol('cursorpos');
	my $c = $searchCursor{$client};

	my $timestring = ($c == 0 ? $cs : '') . ((defined($p) && $h0 == 0) ? ' ' : $h0) . ($c == 1 ? $cs : '') . $h1 . ":" . ($c == 2 ? $cs : '') .  $m0 . ($c == 3 ? $cs : '') . $m1 . " " . ($c == 4 ? $cs : '') . (defined($p) ? $p : '');

	return (string('ALARM_SET'), $timestring);
}

sub scrollDigit {
		my $client = shift;
		my $dir = shift;
		my ($h0, $h1, $m0, $m1, $p) = timeDigits($client);
		my $h = $h0 * 10 + $h1;
		
		if ($p && $h == 12) { $h = 0 };
		
		if ($searchCursor{$client} == 0) {$searchCursor{$client}++;};
		my $c = $searchCursor{$client};
		
		$p = ($p && $p eq 'PM') ? 1 : 0;
		
		if ($c == 1) {
		   $h = Slim::Buttons::Common::scroll($client, $dir, ($p == 1) ? 12 : 24, $h);
		   #change AM and PM if we scroll past midnight or noon boundary
		   if (Slim::Utils::Prefs::get('timeFormat') =~ /%p/) {
		   	if (($h == 0 && $dir == 1)||($h == 11 && $dir == -1)) { $p = Slim::Buttons::Common::scroll($client, +1, 2, $p); };
			};
		};
		if ($c == 2) { $m0 = Slim::Buttons::Common::scroll($client, $dir, 6, $m0) };
		if ($c == 3) { $m1 = Slim::Buttons::Common::scroll($client, $dir, 10, $m1)};
		if ($c == 4) { $p = Slim::Buttons::Common::scroll($client, +1, 2, $p); }

		my $time = $h * 60 * 60 + $m0 * 10 * 60 + $m1 * 60 + $p * 12 * 60 * 60;

		Slim::Utils::Prefs::clientSet($client, "alarmtime", $time);
		Slim::Display::Display::update($client);
}

sub timeDigits {
	my $client = shift;
	my $time = Slim::Utils::Prefs::clientGet($client, "alarmtime");

	my $h = int($time / (60*60));
	my $m = int(($time - $h * 60 * 60) / 60);
	my $p = undef;

	my $timestring;

	if (Slim::Utils::Prefs::get('timeFormat') =~ /%p/) {
		$p = 'AM';
		if ($h > 11) { $h -= 12; $p = 'PM'; }
		if ($h == 0) { $h = 12; }
	} #else { $p = " "; };

	if ($h < 10) { $h = '0' . $h; }

	if ($m < 10) { $m = '0' . $m; }

	my $h0 = substr($h, 0, 1);
	my $h1 = substr($h, 1, 1);
	my $m0 = substr($m, 0, 1);
	my $m1 = substr($m, 1, 1);

	return ($h0, $h1, $m0, $m1, $p);
}


#################################################################################
# Alarm Playlist Mode
my %alarmPlaylistSettingsFunctions = (
	'left' => sub {
		my $client = shift;

		@{$client->dirItems}=(); #Clear list and get outta here
		Slim::Buttons::Common::popModeRight($client);
	},

	'up' => sub {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, -1, $client->numberOfDirItems(), $client->currentDirItem());

		$client->currentDirItem($newposition);
		Slim::Utils::Prefs::clientSet($client, "alarmplaylist", $client->dirItems($client->currentDirItem));

		Slim::Display::Display::update($client);
	},

	'down' => sub {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, +1, $client->numberOfDirItems(), $client->currentDirItem());

		$client->currentDirItem($newposition);
		Slim::Utils::Prefs::clientSet($client, "alarmplaylist", $client->dirItems($client->currentDirItem) );

		Slim::Display::Display::update($client);
	},

	'right' => sub { Slim::Display::Animation::bumpRight(shift); },
	'add' => sub { Slim::Display::Animation::bumpRight(shift); },
	'play' => sub { Slim::Display::Animation::bumpRight(shift); },

	'numberScroll' => sub  {
		my $client = shift;
		my $button = shift;
		my $digit = shift;
		my $i = Slim::Buttons::Common::numberScroll($client, $digit, $client->dirItems);

		$client->currentDirItem($i);
		Slim::Display::Display::update($client);
	},

);

sub getAlarmPlaylistFunctions {
	return \%alarmPlaylistSettingsFunctions;
}

sub setAlarmPlaylistMode {
	my $client = shift;
	$client->lines(\&alarmPlaylistLines);

	@{$client->dirItems}=();	
	
	Slim::Utils::Scan::addToList($client->dirItems, Slim::Utils::Prefs::get('playlistdir'), 0);
	if (Slim::Music::iTunes::useiTunesLibrary()) {
		push @{$client->dirItems}, @{Slim::Music::iTunes::playlists()};
	} 

	$client->numberOfDirItems(scalar @{$client->dirItems});
	$client->currentDirItem(0);
	my $list = Slim::Utils::Prefs::clientGet($client, "alarmplaylist");
	if ($list) {
		my $i = 0;
		my $items = $client->dirItems;
		foreach my $cur (@$items) {
			if ($list eq $cur) {
				$client->currentDirItem($i);
				last;
			}
			$i++;
		}
	}
	Slim::Utils::Prefs::clientSet($client, "alarmplaylist", $client->dirItems($client->currentDirItem) );
}

sub alarmPlaylistLines {
	my $client = shift;
	my $line1;
	my $line2;

	$line1 = string('ALARM_PLAYLIST_ENTRY');

	if (defined $client->dirItems($client->currentDirItem)) {
		$line2 = Slim::Music::Info::standardTitle($client,$client->dirItems($client->currentDirItem));
	} else {
		$line2 = string('EMPTY');
	}

	if ($client->numberOfDirItems()) {
		$line1 .= sprintf(" (%d ".string('OUT_OF')." %s)", $client->currentDirItem + 1, $client->numberOfDirItems());
	}
	
	return ($line1, $line2);
}

# some initialization code, adding modes for this module
Slim::Buttons::Common::addMode('alarm', getFunctions(), \&Slim::Buttons::AlarmClock::setMode);
Slim::Buttons::Common::addMode('alarmvolume', getAlarmVolumeFunctions(), \&Slim::Buttons::AlarmClock::setAlarmVolumeMode);
Slim::Buttons::Common::addMode('alarmset', getAlarmSetFunctions(), \&Slim::Buttons::AlarmClock::setAlarmSetMode);
Slim::Buttons::Common::addMode('alarmplaylist', getAlarmPlaylistFunctions(), \&Slim::Buttons::AlarmClock::setAlarmPlaylistMode);
setTimer();


1;

__END__

