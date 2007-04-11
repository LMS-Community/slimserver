package Slim::Plugin::DateTime::Plugin;

# SlimServer Copyright (c) 2001-2006 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::Base);
use Slim::Utils::DateTime;
use Slim::Utils::Prefs;

use Slim::Plugin::DateTime::Settings;

my $prefs = preferences('datetime');

sub getDisplayName {
	return 'PLUGIN_SCREENSAVER_DATETIME';
}

sub setMode {
	my $class  = shift;
	my $client = shift;

	$client->lines(\&lines);

	# setting this param will call client->update() frequently
	$client->modeParam('modeUpdateInterval', 1); # seconds
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

our %functions = (
	'up' => sub  {
		my $client = shift;
		my $button = shift;
		$client->bumpUp() if ($button !~ /repeat/);
	},
	'down' => sub  {
	    my $client = shift;
		my $button = shift;
		$client->bumpDown() if ($button !~ /repeat/);;
	},
	'left' => sub  {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
	'right' => sub  {
		my $client = shift;
		
		my $saver = Slim::Player::Source::playmode($client) eq 'play' ? 'screensaver' : 'idlesaver';
		
		if ($client->prefGet($saver) ne 'SCREENSAVER.datetime') {
			$client->prefSet($saver,'SCREENSAVER.datetime');
		} else {
			$client->prefSet($saver, $Slim::Player::Player::defaultPrefs->{$saver});
		}
	},
	'stop' => sub {
		my $client = shift;
		Slim::Buttons::Common::pushMode($client, 'SCREENSAVER.datetime');
	}
);

sub lines {
	my $client = shift;
	
	my $saver = Slim::Player::Source::playmode($client) eq 'play' ? 'screensaver' : 'idlesaver';
	my $line2 = $client->string('SETUP_SCREENSAVER_USE');
	my $overlay2 = Slim::Buttons::Common::checkBoxOverlay($client, $client->prefGet($saver) eq 'SCREENSAVER.datetime');
	
	return {
		'line'    => [ $client->string('PLUGIN_SCREENSAVER_DATETIME'), $line2 ],
		'overlay' => [ undef, $overlay2 ]
	};
}

sub getFunctions {
	my $class = shift;

	return \%functions;
}

###################################################################
### Section 3. Your variables for your screensaver mode go here ###
###################################################################

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
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $alarmOn = $client->prefGet("alarm", 0) || $client->prefGet("alarm", $wday);

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
# 			$display->{'screen2'}->{'center'} = [undef,Slim::Utils::DateTime::longDateF(undef,Slim::Utils::Prefs::get('screensaverDateFormat'))];
# 		} else {
# 			$display->{'screen2'} = {};
# 		}
# 	}

	return $display;
}

1;

__END__
