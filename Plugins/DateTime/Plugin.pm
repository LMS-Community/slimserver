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
use Slim::Utils::Strings qw (string);

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.2 $,10);

sub getDisplayName() {return string('PLUGIN_SCREENSAVER_DATETIME');}

sub strings() { return '
PLUGIN_SCREENSAVER_DATETIME
	DE	Datum/Zeit Bildschirmschoner
	EN	Datetime Screensaver
	FR	Ecran de veille Date/Heure
	
PLUGIN_SCREENSAVER_DATETIME_ENABLE
	DE	PLAY drücken zum Aktivieren des Bildschirmschoners
	EN	Press PLAY to enable this screensaver
	FR	Appuyer sur PLAY pour activer

PLUGIN_SCREENSAVER_DATETIME_DISABLE
	DE	PLAY drücken zum Deaktivieren dieses Bildschirmschoners 
	EN	Press PLAY to disable this screensaver
	FR	Appuyer sur PLAY pour désactiver
	
PLUGIN_SCREENSAVER_DATETIME_ENABLING
	DE	Datum/Zeit Bildschirmschoner aktivieren
	EN	Enabling DateTime as current screensaver
	FR	Activation écran de veille Date/Heure

PLUGIN_SCREENSAVER_DATETIME_DISABLING
	DE	Standard-Bildschirmschoner aktivieren
	EN	Resetting to default screensaver
	FR	Retour à écran de veille par défaut
'};

##################################################
### Section 2. Your variables and code go here ###
##################################################


sub setMode() {
	my $client = shift;
	$client->lines(\&lines);
}

my %functions = (
	'up' => sub  {
		my $client = shift;
		Slim::Display::Animation::bumpUp($client);
	},
	'down' => sub  {
	    my $client = shift;
		Slim::Display::Animation::bumpDown($client);
	},
	'left' => sub  {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
	'right' => sub  {
		my $client = shift;
		Slim::Display::Animation::bumpRight($client);
	},
	'play' => sub  {
		my $client = shift;
		if (Slim::Utils::Prefs::clientGet($client,'screensaver') ne 'SCREENSAVER.datetime') {
			Slim::Utils::Prefs::clientSet($client,'screensaver','SCREENSAVER.datetime');
			my ($line1, $line2) = (string('PLUGIN_SCREENSAVER_DATETIME'), string('PLUGIN_SCREENSAVER_DATETIME_ENABLING'));
			Slim::Display::Animation::showBriefly($client, $line1, $line2);
		} else {
			Slim::Utils::Prefs::clientSet($client,'screensaver','screensaver');
			my ($line1, $line2) = (string('PLUGIN_SCREENSAVER_DATETIME'), string('PLUGIN_SCREENSAVER_DATETIME_DISABLING'));
			Slim::Display::Animation::showBriefly($client, $line1, $line2);
		}
	},
	'stop' => sub {
		my $client = shift;
		Slim::Buttons::Common::pushMode($client, 'SCREENSAVER.datetime');
	}
);

sub lines {
	my $client = shift;
	my ($line1, $line2);
	$line1 = string('PLUGIN_SCREENSAVER_DATETIME');
	if (Slim::Utils::Prefs::clientGet($client,'screensaver') ne 'SCREENSAVER.datetime') {
		$line2 = string('PLUGIN_SCREENSAVER_DATETIME_ENABLE');
	} else {
		$line2 = string('PLUGIN_SCREENSAVER_DATETIME_DISABLE');
	};
	return ($line1, $line2);
}

sub getFunctions() {
	return \%functions;
}

sub handleIndex {
	my ($client, $params) = @_;
	my $body;

	$params->{'enable'} =
		(Slim::Utils::Prefs::clientGet($client,'screensaver') eq 'SCREENSAVER.datetime') ? 0 : 1;

	return Slim::Web::HTTP::filltemplatefile(
			'plugins/DateTime/index.html',
			$params,
		);
}

sub handleEnable {
	my ($client, $params) = @_;
	my $body;

	if ($params->{'enable'}) {
		Slim::Utils::Prefs::clientSet(
			$client,
			'screensaver',
			'SCREENSAVER.datetime');
	} else {
		Slim::Utils::Prefs::clientSet(
			$client,
			'screensaver',
			'screensaver');
	}
	return Slim::Web::HTTP::filltemplatefile(
			'plugins/DateTime/enable.html',
			$params,
		);
}

sub webPages-disabled {
	my %pages = (
		"index\.(?:htm|xml)" => \&handleIndex,
		"enable\.(?:htm|xml)" => \&handleEnable,
	);

	return (\%pages, "index.html");
}

###################################################################
### Section 3. Your variables for your screensaver mode go here ###
###################################################################

# First, Register the screensaver mode here.  Must make the call to addStrings in order to have plugin
# localization available at this point.
sub screenSaver() {
	#slim::Utils::Strings::addStrings(&strings());
	Slim::Buttons::Common::addSaver('SCREENSAVER.datetime', getScreensaverDatetime(), \&setScreensaverDateTimeMode,undef,string('PLUGIN_SCREENSAVER_DATETIME'));
}

my %screensaverDateTimeFunctions = (
	'done' => sub  {
					my ($client
		   			,$funct
		   			,$functarg) = @_;
					Slim::Buttons::Common::popMode($client);
					$client->update();
					#pass along ir code to new mode if requested
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

sub screensaverDateTimelines {
	my $client = shift;
	return Slim::Buttons::Common::dateTime($client);
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
