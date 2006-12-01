package Plugins::Rescan::Plugin;

# Rescan.pm by Andrew Hedges (andrew@hedges.me.uk) October 2002
# Timer functions added by Kevin Deane-Freeman (kevindf@shaw.ca) June 2004
# $Id$

# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Time::HiRes;

use Plugins::Rescan::Settings;

use Slim::Control::Request;
use Slim::Utils::Log;

our $interval = 1; # check every x seconds
our @browseMenuChoices;
our %menuSelection;
our %searchCursor;
our %functions;

sub getDisplayName {
	return 'PLUGIN_RESCAN_MUSIC_LIBRARY';
}

sub enabled {
	return ($::VERSION ge '6.1');
}

sub initPlugin {

	%functions = (
		'play' => sub {
			my $client = shift;

			if ($browseMenuChoices[$menuSelection{$client}] eq $client->string('PLUGIN_RESCAN_PRESS_PLAY')) {

				my @pargs=('rescan');
				$client->execute(\@pargs, undef, undef);

				$client->showBriefly( {
					'line' => [ $client->string('PLUGIN_RESCAN_MUSIC_LIBRARY'),
							$client->string('PLUGIN_RESCAN_RESCANNING') ]
				});

			} else {

				$client->bumpRight();
			}
		}
	);

	Plugins::Rescan::Settings->new;

	Slim::Buttons::Common::addMode('scantimer', getFunctions(), \&setMode);
	setTimer();
}

sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	@browseMenuChoices = (
		'PLUGIN_RESCAN_TIMER_SET',
		'PLUGIN_RESCAN_TIMER_OFF',
		'PLUGIN_RESCAN_TIMER_TYPE',
		'PLUGIN_RESCAN_PRESS_PLAY',
	);

	# get previous alarm time or set a default
	if (!defined Slim::Utils::Prefs::get("rescan-time")) {

		Slim::Utils::Prefs::set("rescan-time", 9 * 60 * 60 );
	}
	
	my %params = (
		'listRef'        => \@browseMenuChoices,
		'externRefArgs'  => 'CV',
		'header'         => 'PLUGIN_RESCAN_MUSIC_LIBRARY',
		'headerAddCount' => 1,
		'stringHeader'   => 1,
		'callback'       => \&rescanExitHandler,
		'overlayRef'     => sub { return (undef, Slim::Display::Display::symbol('rightarrow')) },
		'overlayRefArgs' => '',
		'externRef'      => sub {
			my $client = shift;
			my $value  = shift;
			
			if (Slim::Utils::Prefs::get("rescan-scheduled") && $value eq 'PLUGIN_RESCAN_TIMER_OFF') {

				return $client->string('PLUGIN_RESCAN_TIMER_ON');
			}

			return $client->string($value);
		},
	);
		
	Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);
}

sub rescanExitHandler {
	my ($client,$exittype) = @_;
	
	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {
		my $valueref = $client->modeParam('valueRef');
	
		if ($$valueref eq 'PLUGIN_RESCAN_TIMER_SET') {
			my $value = Slim::Utils::Prefs::get("rescan-time");
			
			my %params = (
				'header' => $client->string('PLUGIN_RESCAN_TIMER_SET'),
				'valueRef' => \$value,
				'cursorPos' => 1,
				'pref' => 'rescan-time',
				'callback' => \&settingsExitHandler
			);
			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Time',\%params);
	
		} elsif ($$valueref eq 'PLUGIN_RESCAN_TIMER_OFF') {
	
			Slim::Utils::Prefs::set("rescan-scheduled", 1);
			$$valueref = 'PLUGIN_RESCAN_TIMER_ON';
			$client->showBriefly( {
				'line1' => $client->string('PLUGIN_RESCAN_TIMER_TURNING_ON'),
			});
			setTimer($client);
	
		} elsif ($$valueref eq 'PLUGIN_RESCAN_TIMER_ON') {
	
			Slim::Utils::Prefs::set("rescan-scheduled", 0);
			$$valueref = 'PLUGIN_RESCAN_TIMER_OFF';
			$client->showBriefly( {
				'line' => [ $client->string('PLUGIN_RESCAN_TIMER_TURNING_OFF') ]
			});
			setTimer($client);
		
		} elsif ($$valueref eq 'PLUGIN_RESCAN_TIMER_TYPE') {
			my $value = Slim::Utils::Prefs::get("rescan-type");
			
			my %params = (
	
				'header' => 'PLUGIN_RESCAN_TIMER_TYPE',
				'headerAddCount' => 1,
				'stringHeader' => 1,
				'listRef' => ['1rescan','2wipedb','3playlist'],
				'externRef' => [qw(SETUP_STANDARDRESCAN SETUP_WIPEDB SETUP_PLAYLISTRESCAN)],
				'stringExternRef' => 1,
				'valueRef' => \$value,
				'cursorPos' => 1,
				'pref' => 'rescan-type',
				'callback' => \&settingsExitHandler,
			);

			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List',\%params);
		}
	}
}

sub settingsExitHandler {
	my ($client,$exittype) = @_;

	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		Slim::Utils::Prefs::set($client->modeParam('pref'),${$client->modeParam('valueRef')});

		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {

		$client->bumpRight();
	}
}

sub getFunctions() {
	return \%functions;
}

sub setTimer {
	# timer to check alarms on an interval
	Slim::Utils::Timers::setTimer(0, Time::HiRes::time() + $interval, \&checkScanTimer);
}

sub checkScanTimer {

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

	my $time = $hour * 60 * 60 + $min * 60;

	if ($sec == 0) { # once we've reached the beginning of a minute, only check every 60s
		$interval = 60;
	}

	if ($sec >= 50) { # if we end up falling behind, go back to checking each second
		$interval = 1;
	}

	if (Slim::Utils::Prefs::get("rescan-scheduled")) {

		my $scantime =  Slim::Utils::Prefs::get("rescan-time");

		if ($scantime) {

			# alarm is done, so reset to find the beginning of a minute
			if ($time == $scantime + 60) {
				$interval = 1;
			}

			my $rescanType = ['rescan'];
			my $rescanPref = Slim::Utils::Prefs::get('rescan-type') || '';

			if ($rescanPref eq '2wipedb') {

				$rescanType = ['wipecache'];

			} elsif ($rescanPref eq '3playlist') {

				$rescanType = [qw(rescan playlists)];
			}

			if ($time == $scantime && !Slim::Music::Import->stillScanning()) {

				logger('scan.scanner')->info("Initiating scan of type: ", $rescanType->[0]);

				Slim::Control::Request::executeRequest(undef, $rescanType);
			}
		}
	}

	setTimer();
}

sub strings {
	return q^
PLUGIN_RESCAN_MUSIC_LIBRARY
	CS	Aktualizovat informace z hudebního archivu
	DE	Musikverzeichnis erneut durchsuchen
	EN	Rescan Music Library
	ES	Recopilar nuevamente la Colección Musical
	FI	Sekoitukseen haluamasi tyylilajit:
	FR	Répertorier musique
	HE	תוסף סריקת הסיפריה
	IT	Rianalisi della libreria musicale
	NL	Opnieuw scannen muziekcollectie

PLUGIN_RESCAN_RESCANNING
	CS	Server právě aktualizuje informace z hudebního archivu
	DE	Server durchsucht Verzeichnisse...
	EN	Server now rescanning...
	ES	El server está recopilando...
	FI	Palvelin lukee hakemistojen sisältöä...
	FR	Répertoriage en cours...
	NL	Server bezig met herscannen...

PLUGIN_RESCAN_PRESS_PLAY
	CS	Stiskněte PLAY a aktualizujte informace z  hudebního archivu.
	DE	Drücke Play, um Durchsuchen zu starten
	EN	Press PLAY to rescan now.
	ES	Presionar PLAY para recopilar ahora.
	FI	Paina "PLAY" lukeaksesi hakemiston sisältö nyt.
	FR	Appuyez sur PLAY pour répertorier
	NL	Druk op PLAY voor nu herscannen.

PLUGIN_RESCAN_TIMER_NAME
	CS	Časovač aktualizace
	DE	Automatisches Durchsuchen
	EN	Rescan Timer
	ES	Timer de Recopilación
	FR	Répertorier musique
	HE	מצב התוסף
	NL	Herscan timer

PLUGIN_RESCAN_TIMER_SET
	CS	Nastavte čas pravidelné aktualizace
	DE	Startzeit für erneutes Durchsuchen
	EN	Set Rescan Time
	ES	Establecer Horario de Recopilación
	FR	Heure répertoriage
	HE	שעת הסריקה
	NL	Stel herscan tijd in

PLUGIN_RESCAN_TIMER_TURNING_OFF
	CS	Vypínám automatickou aktualizaci...
	DE	Automatisches Durchsuchen deaktivieren...
	EN	Turning rescan timer off...
	ES	Apagando el timer de recopilación...
	FR	Activation répertoriage...
	HE	מכבה טיימר סריקה
	NL	Uitzetten herscan timer...

PLUGIN_RESCAN_TIMER_TURNING_ON
	CS	Zapínám automatickou aktualizaci...
	DE	Automatisches Durchsuchen aktivieren...
	EN	Turning rescan timer on...
	ES	Encendiendo el timer de recopilación...
	FR	Désactivation répertoriage...
	HE	מדליק טיימר סריקה
	NL	Aanzetten herscan timer...

PLUGIN_RESCAN_TIMER_ON
	CS	Časovač aktualizace zapnut
	DE	Automatisches Durchsuchen EIN
	EN	Rescan Timer ON
	ES	Timer de Recopilación ENCENDIDO
	FR	Répertoriage activé
	HE	הדלק סריקת ספרייה אוטומטית
	NL	Herscan timer AAN

PLUGIN_RESCAN_TIMER_DESC
	CS	Můžete zvolit automatickou denní aktualizaci informací z hudebního archivu. Nastavte čas, kdy se má aktualizace provést a volbou ON tuto funkci aktivujte.
	DE	Sie können ihre Musiksammlung automatisch alle 24h durchsuchen lassen. Setzen Sie den Zeitpunkt, und schalten Sie die Automatik ein oder aus.
	EN	You can choose to allow a scheduled rescan of your music library every 24 hours.  Set the time, and set the Rescan Timer to ON to use this feature.
	ES	Se puede elegir tener una recopilación programada de la colección musical cada 24 horas. Establecer la hora, y poner el Timer de Recopilación en ENCENDIDO para utilizar esta característica.
	FR	Vous pouvez faire en sorte que le SlimServer répertorie à nouveau le contenu de votre bibliothèque toutes les 24 heures. Entrez l'heure et activez Répertorier musique pour utiliser cette fonctionnalité.
	HE	תוסף זה מעדכן את הסיפריה בכל 24 שעות
	NL	Je kunt het gepland herscannen van je muziekcollectie instellen per 24 uur. Stel de tijd in en zet de herscan timer op AAN om deze optie te gebruiken.

PLUGIN_RESCAN_TIMER_OFF
	CS	Časovač aktualizace vypnut
	DE	Automatisches Durchsuchen AUS
	EN	Rescan Timer OFF
	ES	Timer de Recopilación APAGADO
	FR	Répertoriage désactivé
	HE	כבה סריקת ספרייה אוטומטית
	NL	Herscan timer UIT

PLUGIN_RESCAN_TIMER_TYPE
	DE	Art des Scans
	EN	Rescan Type
	FR	Type répertoriage
	NL	Herscan type
^;
}

1;
