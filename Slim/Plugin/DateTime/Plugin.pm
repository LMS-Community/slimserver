package Slim::Plugin::DateTime::Plugin;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::Base);
use Slim::Utils::DateTime;
use Slim::Utils::Prefs;

use Slim::Plugin::DateTime::Settings;

my $prefs = preferences('plugin.datetime');

sub getDisplayName {
	return 'PLUGIN_SCREENSAVER_DATETIME';
}

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin();

	Slim::Plugin::DateTime::Settings->new;

	Slim::Buttons::Common::addSaver(
		'SCREENSAVER.datetime',
		getScreensaverDatetime(),
		\&setScreensaverDateTimeMode,
		undef,
		getDisplayName(),
	);
}

our %screensaverDateTimeFunctions = (
	'done' => sub  {
		my ($client ,$funct ,$functarg) = @_;

		Slim::Buttons::Common::popMode($client);
		$client->update();

		# pass along ir code to new mode if requested
		if (defined $functarg && $functarg eq 'passback') {
			Slim::Hardware::IR::resendButton($client);
		}
	},
);

sub getScreensaverDatetime {
	return \%screensaverDateTimeFunctions;
}

sub setScreensaverDateTimeMode() {
	my $client = shift;
	$client->lines(\&screensaverDateTimelines);
}

# following is a an optimisation for graphics rendering given the frequency DateTime is displayed
# by always returning the same hash for the font definition render does less work
my $fontDef = {
	'graphic-280x16'  => { 'overlay' => [ 'small.1'    ] },
	'graphic-320x32'  => { 'overlay' => [ 'standard.1' ] },
	'graphic-160x32'  => { 'overlay' => [ 'standard.1' ] },
	'text'            => { 'displayoverlays' => 1        },
};

sub screensaverDateTimelines {
	my $client = shift;

	my $alarmOn = 0; # Whether to display the alarm/snooze symbol
	my $nextUpdate = $client->periodicUpdateTime();
	my $updateInterval = $client->modeParam('modeUpdateInterval');

	my $currentAlarm = Slim::Utils::Alarm->getCurrentAlarm($client);
	my $nextAlarm = Slim::Utils::Alarm->getNextAlarm($client);

	if (defined $currentAlarm) {
		# An alarm is currently active - flash the symbol
		my $time = Time::HiRes::time;
		$alarmOn = ($time - int($time)) < 0.5;
	} else {
		# No alarm active, show symbol if alarm scheduled in next 24 hours
		$alarmOn = defined $nextAlarm && ($nextAlarm->nextDue - time < 86400); 
	}

	# Keep update time on the second or 1/2 second
	if ($updateInterval) {
		my $correctUpdate = int($nextUpdate);
		my $delta = $nextUpdate - $correctUpdate;	
		if ($updateInterval == 0.5) {
			if ($delta >= 0.5) {
				$delta -= 0.5;
				$correctUpdate += 0.5;
			}
		}
		if ($delta > 0.01) {
			Slim::Buttons::Common::syncPeriodicUpdates($client, $correctUpdate);
		}
	}

	my $overlay = undef;
	if ($alarmOn) {
		if (defined $currentAlarm && $currentAlarm->snoozeActive) {
			$overlay = $client->symbols('sleep');
		} else {
			$overlay = $client->symbols('bell');
			if (! defined $currentAlarm) {
				# Add next alarm time, removing seconds
				my $timeStr = Slim::Utils::DateTime::timeF($nextAlarm->time % 86400, $prefs->timeformat, 1);
				$timeStr =~ s/(\d?\d:\d\d):\d\d/\1/;
				$overlay .=  " $timeStr";
			}
		}
	}
	my $display = {
		'center2' => Slim::Utils::DateTime::timeF(undef, $prefs->get('timeformat')),
		'overlay1'=> $overlay,
		'fonts'  => $fontDef,
	};
	# If we're displaying next alarm time, use short date format and left-align in order to fit it all on narrow displays
	# This is basically just a hack - there should be a better way!
	if ($alarmOn && ! defined $currentAlarm) {
		$display->{line1} = Slim::Utils::DateTime::shortDateF(),
	} else {
		$display->{center1} = Slim::Utils::DateTime::longDateF(undef, $prefs->get('dateformat'));
	}

	# Arrange for $client->update to be called periodically.
	# Updates are done every second unless the alarm symbol needs to be flashed
	my $newUpdateInterval = defined $currentAlarm ? 0.5 : 1;
	if (! $updateInterval || $newUpdateInterval != $updateInterval) {
		$client->modeParam('modeUpdateInterval', $newUpdateInterval); # seconds
		Slim::Buttons::Common::startPeriodicUpdates($client, int(Time::HiRes::time) + $newUpdateInterval);
	}
	
# BUG 3964: comment out until Dean has a final word on the UI for this.	
# 	if ($client->display->hasScreen2) {
# 		if ($client->display->linesPerScreen == 1) {
# 			$display->{'screen2'}->{'center'} = [undef,Slim::Utils::DateTime::longDateF(undef,$prefs->get('dateformat'))];
# 		} else {
# 			$display->{'screen2'} = {};
# 		}
# 	}

	return $display;
}

1;

__END__
