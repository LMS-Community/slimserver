package Slim::Plugin::DateTime::Plugin;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::Base);
use Slim::Utils::DateTime;
use Slim::Utils::Prefs;

if ( !main::SLIM_SERVICE && !$::noweb ) {
 	require Slim::Plugin::DateTime::Settings;
}

if ( main::SLIM_SERVICE ) {
	require DateTime;
}

my $prefs = preferences(main::SLIM_SERVICE ? 'server' : 'plugin.datetime');

sub getDisplayName {
	return 'PLUGIN_SCREENSAVER_DATETIME';
}

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin();

	if ( !main::SLIM_SERVICE && !$::noweb ) {
		Slim::Plugin::DateTime::Settings->new;
	}

	Slim::Buttons::Common::addSaver(
		'SCREENSAVER.datetime',
		getScreensaverDatetime(),
		\&setScreensaverDateTimeMode,
		\&exitScreensaverDateTimeMode,
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

	'snooze' => sub {
		my $client = shift;

		my $currentAlarm = Slim::Utils::Alarm->getCurrentAlarm($client);

		# snooze if alarm is currently playing
		if (defined $currentAlarm) {
			$currentAlarm->snooze;

		# display info about next alarm and/or current time
		} else {
			showTimeOrAlarm($client);
		}
	},
);

sub getScreensaverDatetime {
	return \%screensaverDateTimeFunctions;
}

sub setScreensaverDateTimeMode() {
	my $client = shift;

	$client->lines(\&screensaverDateTimelines);

	$client->modeParam('modeUpdateInterval', 1);
}

sub exitScreensaverDateTimeMode {
	my $client = shift;

	Slim::Utils::Timers::killTimers($client, \&_flashAlarm);
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
	my $args   = shift;

	my $flash  = $args->{'flash'}; # set when called from animation callback
	
	my ($timezone, $dt);
	
	if ( main::SLIM_SERVICE ) {
		$timezone = preferences('server')->client($client)->get('timezone') 
			|| $client->playerData->userid->timezone 
			|| 'America/Los_Angeles';
	
	 	$dt = DateTime->now( 
			time_zone => $timezone
		);
		
		# Align updates at each minute change so we only have to run once a minute instead
		# of every few seconds
		my $sec = (localtime(time))[0];
		my $snInterval = 60 - $sec;
		
		$client->modeParam( modeUpdateInterval => $snInterval );
		Slim::Buttons::Common::startPeriodicUpdates( $client, time() + $snInterval );
	}

	if (Slim::Utils::Alarm->getCurrentAlarm($client) && !$flash) {
		# schedule another update to remove the alarm symbol during alarm
		Slim::Utils::Timers::setTimer($client, Time::HiRes::time + 0.5, \&_flashAlarm);
	}
	
# BUG 3964: comment out until Dean has a final word on the UI for this.	
# 	if ($client->display->hasScreen2) {
# 		if ($client->display->linesPerScreen == 1) {
# 			$display->{'screen2'}->{'center'} = [undef,Slim::Utils::DateTime::longDateF(undef,$prefs->get('dateFormat'))];
# 		} else {
# 			$display->{'screen2'} = {};
# 		}
# 	}

	return dateTimeLines($client, $flash);
}

# Return the lines to display the date and time on a display, along with alarm information
sub dateTimeLines {
	my $client = shift;
	# Boolean.  If false, the whole display is rendered.  Otherwise, the bits which flash aren't included.
	my $flash = shift;

	my $currentAlarm = Slim::Utils::Alarm->getCurrentAlarm($client);

	my $nextAlarm = Slim::Utils::Alarm->getNextAlarm($client);

	# show alarm symbol if active or set for next 24 hours
	my $alarmOn = defined $currentAlarm || ( defined $nextAlarm && ($nextAlarm->nextDue - time < 86400) );

	my $twoLines = $client->linesPerScreen == 2;
	my $narrow = $client->display->isa('Slim::Display::Boom');

	my $overlay = undef;

	if ($alarmOn && !$flash) {
		if (defined $currentAlarm && $currentAlarm->snoozeActive) {
			$overlay = $client->symbols('sleep');
		} else {
			$overlay = $client->symbols('bell');
			# Include the next alarm time in the overlay if there's room
			if (!$narrow && !defined $currentAlarm) {
				# Remove seconds from alarm time
				my $timeStr = Slim::Utils::DateTime::timeF($nextAlarm->time % 86400, $prefs->client($client)->get('timeFormat'), 1);
				$timeStr =~ s/(\d?\d\D\d\d)\D\d\d/$1/;
				$overlay .=  " $timeStr";
			}
		}
	}
	
	my $display;
	
	$display = {
		center  => [ $client->longDateF(), $client->timeF() ],
		overlay => [ $overlay ],
		fonts   => $fontDef,
	};

	return $display;
}

sub showTimeOrAlarm {
	my $client = shift;

	my $sbName = getDisplayName() . '::showTimeOrAlarm';

	my $currentMode = Slim::Buttons::Common::mode($client);
	my $currentSbName = $client->display->sbName;
	$currentSbName = '' unless defined $currentSbName;

	my $nextAlarm = Slim::Utils::Alarm->getNextAlarm($client);
	my $showAlarm = defined $nextAlarm && ($nextAlarm->nextDue - time < 86400);

	# Show time if it isn't already being displayed or it is but there's no next alarm
	if (($currentMode !~ '\.datetime$' || $client->display->currBrightness() == 0)
		&& ($currentSbName ne $sbName || ! $showAlarm)) {

		$client->showBriefly( dateTimeLines($client), {
			'brightness' => 'powerOn',
			'duration' => 3,
			'name' => $sbName,
		});
		
	# display next alarm time if alarm is within the next 24h		
	} elsif ($showAlarm) {

		my $line = $client->symbols('bell');

		# Remove seconds from alarm time
		my $timeStr = Slim::Utils::DateTime::timeF($nextAlarm->time % 86400, $prefs->client($client)->get('timeFormat'), 1);
		$timeStr =~ s/(\d?\d\D\d\d)\D\d\d/$1/;
		$line .=  " $timeStr";

		# briefly display the next alarm
		$client->showBriefly(
			{
				'center' => [ 
					$client->string('ALARM_NEXT_ALARM'),
					$line,
				]
			},
			{ 'duration' => 3, 'brightness' => 'powerOn'},
		);
	}
}

sub _flashAlarm {
	my $client = shift;
	
	$client->update( screensaverDateTimelines($client, { flash => 1 }) );
}

1;

__END__
