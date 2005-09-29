# datetime.pm by kdf Dec 2003
#
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

use Slim::Control::Command;

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.5 $,10);

sub getDisplayName {
	return 'PLUGIN_SCREENSAVER_DATETIME';
}

sub strings { return '
PLUGIN_SCREENSAVER_DATETIME
	CZ	Datumový spořič
	DE	Datum/Zeit Bildschirmschoner
	EN	Date and Time
	ES	Salvapantallas de Fecha y Hora
	FR	Ecran de veille Date/Heure
	
PLUGIN_SCREENSAVER_DATETIME_ENABLE
	DE	PLAY drücken zum Aktivieren des Bildschirmschoners
	EN	Press PLAY to enable this screensaver
	ES	Presionar PLAY para activar este salvapantallas
	FR	Appuyer sur PLAY pour activer

PLUGIN_SCREENSAVER_DATETIME_DISABLE
	CZ	Stiskněte PLAY pro zakázání spořiče
	DE	PLAY drücken zum Deaktivieren dieses Bildschirmschoners 
	EN	Press PLAY to disable this screensaver
	ES	Presionar PLAY para desactivar este salvapantallas
	FR	Appuyer sur PLAY pour désactiver
	
PLUGIN_SCREENSAVER_DATETIME_ENABLING
	DE	Datum/Zeit Bildschirmschoner aktivieren
	EN	Enabling DateTime as current screensaver
	ES	Activando Hora y Fecha como salvapantallas actual
	FR	Activation écran de veille Date/Heure

PLUGIN_SCREENSAVER_DATETIME_DISABLING
	CZ	Nastavit výchozí spořič
	DE	Standard-Bildschirmschoner aktivieren
	EN	Resetting to default screensaver
	ES	Restableciendo el salvapantallas por defecto
	FR	Retour à l\'écran de veille par défaut
'};

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
		$client->bumpRight();
	},
	'play' => sub  {
		my $client = shift;
		if ($client->prefGet('screensaver') ne 'SCREENSAVER.datetime') {
			$client->prefSet('screensaver','SCREENSAVER.datetime');
			$client->showBriefly( {
				'line1' => $client->string('PLUGIN_SCREENSAVER_DATETIME'),
				'line2' => $client->string('PLUGIN_SCREENSAVER_DATETIME_ENABLING'),
			});
		} else {
			$client->prefSet('screensaver','screensaver');
			$client->showBriefly( {
				'line1' => $client->string('PLUGIN_SCREENSAVER_DATETIME'),
				'line2' => $client->string('PLUGIN_SCREENSAVER_DATETIME_DISABLING'),
			});
		}
	},
	'stop' => sub {
		my $client = shift;
		Slim::Buttons::Common::pushMode($client, 'SCREENSAVER.datetime');
	}
);

sub lines {
	my $client = shift;
	my $line2;
	if ($client->prefGet('screensaver') ne 'SCREENSAVER.datetime') {
		$line2 = $client->string('PLUGIN_SCREENSAVER_DATETIME_ENABLE');
	} else {
		$line2 = $client->string('PLUGIN_SCREENSAVER_DATETIME_DISABLE');
	};
	return {
		'line1' => $client->string('PLUGIN_SCREENSAVER_DATETIME'),
		'line2' => $line2,
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

sub screensaverDateTimelines {
	my $client = shift;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $alarmOn = $client->prefGet("alarm", 0) || $client->prefGet("alarm", $wday);

	my $nextUpdate = $client->periodicUpdateTime();
	Slim::Buttons::Common::syncPeriodicUpdates($client, int($nextUpdate)) if (($nextUpdate - int($nextUpdate)) > 0.01);

	return {
		'center1' => Slim::Utils::Misc::longDateF(),
		'center2' => Slim::Utils::Misc::timeF(),
		'overlay1'=> ($alarmOn ? $client->symbols('bell') : undef),
		'fonts'   => { 'graphic-280x16'  => { 'overlay1' => \ 'small.1' },
					   'graphic-320x32'  => { 'overlay1' => \ 'standard.1' },
					   'text' =>            { 'displayoverlays' => 1 },
				   },
	};
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
