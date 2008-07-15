package Slim::Plugin::DateTime::Plugin;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::Base);
use Slim::Utils::DateTime;
use Slim::Utils::Prefs;

if ( !main::SLIM_SERVICE ) {
 	require Slim::Plugin::DateTime::Settings;
}

my $prefs = preferences('plugin.datetime');

sub getDisplayName {
	return 'PLUGIN_SCREENSAVER_DATETIME';
}

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin();

	if ( !main::SLIM_SERVICE ) {
		Slim::Plugin::DateTime::Settings->new;
	}

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

	# setting this param will call client->update() frequently
	$client->modeParam('modeUpdateInterval', 1); # seconds
}

# following is a an optimisation for graphics rendering given the frequency DateTime is displayed
# by always returning the same hash for the font definition render does less work
my $fontDef = {
	'graphic-280x16'  => { 'overlay' => [ 'small.1'    ] },
	'graphic-320x32'  => { 'overlay' => [ 'standard.1' ] },
	'text'            => { 'displayoverlays' => 1        },
};

sub screensaverDateTimelines {
	my $client = shift;
	
	if ( main::SLIM_SERVICE ) {
		# We use the same method as alarm clock, to align updates at each minute change
		# so we only have to run once a minute instead of every few seconds
		my $sec = (localtime(time))[0];
		if ( $sec == 59 ) {
			# This method is called 1 extra time after we change modeUpdateInterval,
			# so use sec=59 to get it to actually update exactly on the minute
			$client->modeParam('modeUpdateInterval', 60);
		}
		# if we end up falling behind, go back to checking each second
		elsif ( $sec >= 50 ) {
			$client->modeParam('modeUpdateInterval', 1);
		}
		
		my $timezone 
			=  preferences('server')->client($client)->get('timezone') 
			|| $client->playerData->userid->timezone 
			|| 'America/Los_Angeles';
		
		my $dt = DateTime->now( 
			time_zone => $timezone
		);
		
		my $alarmOn 
			 = preferences('server')->client($client)->get('alarm')->[0]
			|| preferences('server')->client($client)->get('alarm')->[ $dt->day_of_week ];
		
		my $nextUpdate = $client->periodicUpdateTime();
		Slim::Buttons::Common::syncPeriodicUpdates($client, int($nextUpdate)) if (($nextUpdate - int($nextUpdate)) > 0.01);
		
		return {
			center  => [ $client->longDateF(), $client->timeF() ],
			overlay => [ ($alarmOn ? $client->symbols('bell') : undef) ],
			fonts   => $fontDef,
		};
	}
	
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

	# the alarm's days are sunday=7 based - 0 is daily
	$wday = 7 if !$wday;

	my $alarm = preferences('server')->client($client)->get('alarm');

	my $alarmtime = preferences('server')->client($client)->get('alarmtime');
	my $currtime = $sec + 60*$min + 60*60*$hour;
	my $tomorrow = ($wday+1) % 7 || 7;

	my $alarmOn = $alarm->[ 0 ] 
			|| ($alarm->[ $wday ] && $alarmtime->[ $wday ] > $currtime)
			|| ($alarm->[ $tomorrow ] && $alarmtime->[ $tomorrow ] < $currtime);

	my $nextUpdate = $client->periodicUpdateTime();
	Slim::Buttons::Common::syncPeriodicUpdates($client, int($nextUpdate)) if (($nextUpdate - int($nextUpdate)) > 0.01);

	my $display = {
		'center' => [ Slim::Utils::DateTime::longDateF(undef, $prefs->get('dateformat')),
					  Slim::Utils::DateTime::timeF(undef, $prefs->get('timeformat')) ],
		'overlay'=> [ ($alarmOn ? $client->symbols('bell') : undef) ],
		'fonts'  => $fontDef,
	};
	
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
