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

package Plugins::DateTime::Plugin;

use Slim::Control::Request;

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.6 $,10);

sub getDisplayName {
	return 'PLUGIN_SCREENSAVER_DATETIME';
}

sub strings { return '
PLUGIN_SCREENSAVER_DATETIME
	CS	Datumový spořič
	DE	Datum/Zeit Bildschirmschoner
	EN	Date and Time Screensaver
	ES	Salvapantallas de Fecha y Hora
	FR	Ecran de veille Date/Heure
	HE	שומר מסך תאריכון
	IT	Data e ora
	NL	Datum en tijd

SETUP_GROUP_DATETIME
	DE	Datum/Zeit Bildschirmschoner Einstellungen
	EN	Date and Time Screensaver Settings
	FR	Paramètres Ecran de veille Date/Heure
	NL	Instellingen datum en tijd schermbeveiliger

SETUP_GROUP_DATETIME_DESC
	DE	Hier können Sie das Format des Datum/Zeit Bildschirmschoners festlegen.
	EN	These settings control the behavior of the Date and Time Screensaver
	FR	Ces réglages ajustent les paramètres de l\'Ecran de veille Date/Heure.
	NL	Deze instellingen stellen het gedrag in van de datum en tijd schermbeveiliger

SETUP_GROUP_DATETIME_DEFAULTTIME
	DE	Slimserver Standard
	EN	Slimserver Default
	FR	Défaut serveur
	NL	SlimServer standaard

SETUP_GROUP_DATETIME_DEFAULTDATE
	DE	Slimserver Standard
	EN	Slimserver Default
	FR	Défaut serveur
	NL	SlimServer standaard
'};

my $timeFormats = {'' => "SETUP_GROUP_DATETIME_DEFAULTTIME", %{Slim::Utils::DateTime::timeFormats()}};
my $dateFormats = {'' => "SETUP_GROUP_DATETIME_DEFAULTDATE", %{Slim::Utils::DateTime::shortDateFormats()}, %{Slim::Utils::DateTime::longDateFormats()}};

sub setupGroup {
	my $client = shift;
	
	my %setupGroup = (
		'PrefOrder' => ['screensaverDateFormat','screensaverTimeFormat']
		,'PrefsInTable' => 1
		,'Suppress_PrefHead' => 1
		,'Suppress_PrefDesc' => 1
		,'Suppress_PrefLine' => 1
		,'Suppress_PrefSub' => 1
		,'GroupHead' => 'SETUP_GROUP_DATETIME'
		,'GroupDesc' => 'SETUP_GROUP_DATETIME_DESC'
		,'GroupLine' => 1
		,'GroupSub' => 1
	);

	my %setupPrefs = (
			"screensaverTimeFormat" => {
						'validate' => \&Slim::Utils::Validate::inHash
						,'validateArgs' => [$timeFormats,1]
						,'options' => $timeFormats
						,'optionSort' => 'K'
					},
			"screensaverDateFormat" => {
						'validate' => \&Slim::Utils::Validate::inHash
						,'validateArgs' => [$dateFormats,1]
						,'options' => $dateFormats
						,'optionSort' => 'K'
					}
	);
	
	return (\%setupGroup, \%setupPrefs);

	
}

##################################################
### Section 2. Your variables and code go here ###
##################################################

sub enabled {
	return ($::VERSION ge '6.1');
}

sub setMode {
	my $client = shift;
	$client->lines(\&lines);

	# setting this param will call client->update() frequently
	$client->param('modeUpdateInterval', 1); # seconds
}

sub initPlugin {
	# Default to screensaverDateFormat, screensaverTimeFormat to '' or update from '0'
	# Having screensaverDateFormat set to '' means that the server wide formats are used

	unless (Slim::Utils::Prefs::get('screensaverDateFormat')) {
		Slim::Utils::Prefs::set('screensaverDateFormat','')
	}

	unless (Slim::Utils::Prefs::get('screensaverTimeFormat')) {
		Slim::Utils::Prefs::set('screensaverTimeFormat','')
	}
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
			$client->prefSet($saver,$Slim::Player::Player::defaultPrefs->{$saver});
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
	return \%functions;
}

###################################################################
### Section 3. Your variables for your screensaver mode go here ###
###################################################################

# First, Register the screensaver mode here.  Must make the call to addStrings in order to have plugin
# localization available at this point.
sub screenSaver {
	Slim::Buttons::Common::addSaver(
		'SCREENSAVER.datetime',
		getScreensaverDatetime(),
		\&setScreensaverDateTimeMode,
		undef,
		'PLUGIN_SCREENSAVER_DATETIME',
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
	$client->param('modeUpdateInterval', 1); # seconds
}


# following is a an optimisation for graphics rendering given the frequency DateTime is displayed
# by always returning the same hash for the font definition render does less work
my $fontDef = {	'graphic-280x16'  => { 'overlay' => [ 'small.1'    ] },
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
		'center' => [ Slim::Utils::DateTime::longDateF(undef,Slim::Utils::Prefs::get('screensaverDateFormat')),
				  Slim::Utils::DateTime::timeF(undef,Slim::Utils::Prefs::get('screensaverTimeFormat')), ],
		'overlay'=> [ ($alarmOn ? $client->symbols('bell') : undef) ],
		'fonts'  => $fontDef,
	};
	
	if ($client->display->hasScreen2 && $client->display->linesPerScreen == 1) {
		$display->{'screen2'}->{'center'} = [undef,Slim::Utils::DateTime::longDateF(undef,Slim::Utils::Prefs::get('screensaverDateFormat'))];
	} else {
		$client->update( { 'screen2' => {} } );
	}

	return $display;
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
