# Plugin for Slimserver to monitor Server and Network Health

# $Id$

# This code is derived from code with the following copyright message:
#
# SlimServer Copyright (C) 2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

package Plugins::Health::Plugin;

use strict;

use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

use Plugins::Health::NetTest;


sub enabled {
	return ($::VERSION ge '6.5');
}

# Main web interface
sub webPages {
	my %pages = ("index\.(?:htm|xml)"         => \&handleIndex,
				 "player|server\.(?:htm|xml)" => \&handleGraphs);

	if (grep {$_ eq 'Health::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins')) {
		Slim::Web::Pages->addPageLinks("help", { 'PLUGIN_HEALTH' => undef });
	} else {
		Slim::Web::Pages->addPageLinks("help", { 'PLUGIN_HEALTH' => "plugins/Health/index.html" });
	}

	return (\%pages);
}

# Player inteface for network test - shows up on player as 'NetTest'
sub getDisplayName {
	return('PLUGIN_HEALTH_NETTEST');
}

sub setMode {
	return Plugins::Health::NetTest::setMode(@_);
}

sub getFunctions {
	return \%Plugins::Health::NetTest::functions;
}

#################################################################################################### 

# Perfmon logs managed by this plugin
my @perfmonLogs = (
	{ 'type' => 'server', 'name' => 'response',     'monitor' => \$Slim::Networking::Select::responseTime,  },
	{ 'type' => 'server', 'name' => 'timerlate',    'monitor' => \$Slim::Utils::Timers::timerLate,          },
	{ 'type' => 'server', 'name' => 'selecttask',   'monitor' => \$Slim::Networking::Select::selectTask,    },
	{ 'type' => 'server', 'name' => 'schedulertask','monitor' => \$Slim::Utils::Scheduler::schedulerTask,   },
	{ 'type' => 'server', 'name' => 'timertask',    'monitor' => \$Slim::Utils::Timers::timerTask,          },
	{ 'type' => 'server', 'name' => 'request',      'monitor' => \$Slim::Control::Request::requestTask,     },
	{ 'type' => 'server', 'name' => 'pagebuild',    'monitor' => \$Slim::Web::HTTP::pageBuild,              },
	{ 'type' => 'server', 'name' => 'irqueue',      'monitor' => \$Slim::Hardware::IR::irPerf,              },
	{ 'type' => 'player', 'name' => 'signal',       'monitor' => \&Slim::Player::Client::signalStrengthLog, },
	{ 'type' => 'player', 'name' => 'buffer',       'monitor' => \&Slim::Player::Client::bufferFullnessLog, },
	{ 'type' => 'player', 'name' => 'control',      'monitor' => \&Slim::Player::Client::slimprotoQLenLog,  },
);

sub clearAllCounters {

	foreach my $mon (@perfmonLogs) {
		if ($mon->{'type'} eq 'server') {
			${$mon->{'monitor'}}->clear();
		} elsif ($mon->{'type'} eq 'player') {
			foreach my $client (Slim::Player::Client::clients()) {
				my $perfmon = $mon->{'monitor'}($client);
				$perfmon->clear();
			}
		}
	}
	$Slim::Networking::Select::endSelectTime = undef;
	$Slim::Utils::Timers::timerLate->clear();
	$Slim::Utils::Timers::timerLength->clear();
}

# Summary info which attempts to categorise common problems based on performance measurments taken
sub summary {
	my $client = shift;
	
	my ($summary, @warn);

	if (defined($client) && $client->isa("Slim::Player::Squeezebox")) {

		my ($control, $stream, $signal, $buffer);

		if ($client->tcpsock() && $client->tcpsock()->opened()) {
			if ($client->slimprotoQLenLog()->percentAbove(2) < 5) {
				$control = string("PLUGIN_HEALTH_OK");
			} else {
				$control = string("PLUGIN_HEALTH_CONGEST");
				push @warn, string("PLUGIN_HEALTH_CONTROLCONGEST_DESC");
			}
		} else {
			$control = string("PLUGIN_HEALTH_FAIL");
			push @warn, string("PLUGIN_HEALTH_CONTROLFAIL_DESC");
		}

		if ($client->streamingsocket() && $client->streamingsocket()->opened()) {
			$stream = string("PLUGIN_HEALTH_OK");
		} else {
			$stream = string("PLUGIN_HEALTH_INACTIVE");
			push @warn, string("PLUGIN_HEALTH_STREAMINACTIVE_DESC");
		}

		if ($client->signalStrengthLog()->percentBelow(30) < 1) {
			$signal = string("PLUGIN_HEALTH_OK");
		} elsif ($client->signalStrengthLog()->percentBelow(30) < 5) {
			$signal = string("PLUGIN_HEALTH_SIGNAL_INTERMIT");
			push @warn, string("PLUGIN_HEALTH_SIGNAL_INTERMIT_DESC");
		} elsif ($client->signalStrengthLog()->percentBelow(30) < 20) {
			$signal = string("PLUGIN_HEALTH_SIGNAL_POOR");
			push @warn, string("PLUGIN_HEALTH_SIGNAL_POOR_DESC");
		} else {
			$signal = string("PLUGIN_HEALTH_SIGNAL_BAD");
			push @warn, string("PLUGIN_HEALTH_SIGNAL_BAD_DESC");
		}

		$summary .= sprintf "%-22s : %s\n", string('PLUGIN_HEALTH_CONTROL'), $control;
		$summary .= sprintf "%-22s : %s\n", string('PLUGIN_HEALTH_STREAM'), $stream;
		$summary .= sprintf "%-22s : %s\n", string('PLUGIN_HEALTH_SIGNAL'), $signal;

		if (Slim::Player::Source::playmode($client) eq 'play') {

			if ($client->isa("Slim::Player::Squeezebox2")) {
				if ($client->bufferFullnessLog()->percentBelow(30) < 15) {
					$buffer = string("PLUGIN_HEALTH_OK");
				} else {
					$buffer = string("PLUGIN_HEALTH_BUFFER_LOW");
					push @warn, string("PLUGIN_HEALTH_BUFFER_LOW_DESC2");
				}
			} else {
				if ($client->bufferFullnessLog()->percentBelow(50) < 5) {
					$buffer = string("PLUGIN_HEALTH_OK");
				} else {
					$buffer = string("PLUGIN_HEALTH_BUFFER_LOW");
					push @warn, string("PLUGIN_HEALTH_BUFFER_LOW_DESC1");
				}
			}			
			$summary .= sprintf "%-22s : %s\n", string('PLUGIN_HEALTH_BUFFER'), $buffer;
		}
	} elsif (defined($client) && $client->isa("Slim::Player::SLIMP3")) {
		push @warn, string("PLUGIN_HEALTH_SLIMP3_DESC");
	} else {
		push @warn, string("PLUGIN_HEALTH_NO_PLAYER_DESC");
	}

	if ($Slim::Networking::Select::responseTime->percentAbove(1) < 0.01 || 
		$Slim::Networking::Select::responseTime->above(1) < 3 ) {
		$summary .= sprintf "%-22s : %s\n", string("PLUGIN_HEALTH_RESPONSE"), string("PLUGIN_HEALTH_OK");
	} elsif ($Slim::Networking::Select::responseTime->percentAbove(1) < 0.5) {
		$summary .= sprintf "%-22s : %s\n", string("PLUGIN_HEALTH_RESPONSE"), string("PLUGIN_HEALTH_RESPONSE_INTERMIT");
		push @warn, string("PLUGIN_HEALTH_RESPONSE_INTERMIT_DESC");
	} else {
		$summary .= sprintf "%-22s : %s\n", string("PLUGIN_HEALTH_RESPONSE"), string("PLUGIN_HEALTH_RESPONSE_POOR");
		push @warn, string("PLUGIN_HEALTH_RESPONSE_POOR_DESC");
	}

	if (defined($client) && scalar(@warn) == 0) {
		push @warn, string("PLUGIN_HEALTH_NORMAL");
	}

	return ($summary, \@warn);
}

# Main page
sub handleIndex {
	my ($client, $params) = @_;
	
	my $refresh = 60; # default refresh of 60s 
	my ($newtest, $stoptest);

	# process input parameters

	if ($params->{'perf'}) {
		if ($params->{'perf'} eq 'on') {
			$::perfmon = 1;
			clearAllCounters();
			$refresh = 1;
		} elsif ($params->{'perf'} eq 'off') {
			$::perfmon = 0;
		}
		if ($params->{'perf'} eq 'clear') {
			clearAllCounters();
			$refresh = 1;
		}
	}

	if (defined($params->{'test'})) {
		if ($params->{'test'} eq 'stop') {
			$stoptest = 1;
		} else {
			$newtest = $params->{'test'};
		}
	}

	# create params to build new page

	# status of perfmon
	if ($::perfmon) {
		$params->{'perfon'} = 1;
	} else {
		$params->{'perfoff'} = 1;
		$refresh = undef;
	}

	# summary section
	($params->{'summary'}, $params->{'warn'}) = summary($client);
	
	# client specific details
	if (defined($client)) {

		$params->{'playername'} = $client->name();
		$params->{'nettest_options'} = \@Plugins::Health::NetTest::testRates;

	$params->{'response'} = $Slim::Networking::Select::selectPerf->sprint();
	$params->{'timerlate'} = $Slim::Utils::Timers::timerLate->sprint();
	$params->{'timerlength'} = $Slim::Utils::Timers::timerLength->sprint();

		} elsif (defined($newtest)) {
			# start tests - power on if necessary
			$client->power(1) if !$client->power();
			Slim::Buttons::Common::pushMode($client, 'PLUGIN.Health::Plugin');
			my $modeParam = $client->modeParam('Health.NetTest');
			Plugins::Health::NetTest::setTest($client, undef, $newtest, $modeParam);
			if (defined($modeParam) && ref($modeParam) eq 'HASH' && defined $modeParam->{'log'}) { 
				$params->{'nettest_rate'} = $modeParam->{'rate'};
				$params->{'nettest_graph'} = $modeParam->{'log'}->sprint();
			}
			$refresh = 2;
		}
	}

	$params->{'refresh'} = $refresh;

	return Slim::Web::HTTP::filltemplatefile('plugins/Health/index.html',$params);
}

# Statistics pages
sub handleGraphs {
	my ($client, $params) = @_;
	my @graphs;

	my $type = ($params->{'path'} =~ /server/) ? 'server' : 'player';

	foreach my $mon (@perfmonLogs) {

		next if ($type ne $mon->{'type'});

		my $monitor = ($type eq 'server') ? ${$mon->{'monitor'}} : $mon->{'monitor'}($client);

		if ($params->{'monitor'} eq $mon->{'name'} || $params->{'monitor'} eq 'all') {
			if (exists($params->{'setwarn'})) {
				$monitor->setWarnHigh(Slim::Utils::Validate::number($params->{'warnhi'}));
				$monitor->setWarnLow(Slim::Utils::Validate::number($params->{'warnlo'}));
			}
			if (exists($params->{'clear'})) {
				$monitor->clear();
			}
		}

		push @graphs, {
			'name'  => $mon->{'name'},
			'graph' => $monitor->sprint(),
			'warnlo'=> $monitor->warnLow(),
			'warnhi'=> $monitor->warnHigh(),
		};
	}

	$params->{'playername'} = $client->name();
	$params->{'type'} = $type;
	$params->{'graphs'} = \@graphs;

	return Slim::Web::HTTP::filltemplatefile("plugins/Health/graphs.html",$params);
}

#
# Strings for Heath Web page & Network Test player interface
#

sub strings {
	return '
PLUGIN_HEALTH
	DE	Server & Netzwerk Zustand
	EN	Server & Network Health
	ES	Salud del Servidor y la Red
	FI	Palvelimen ja verkon tila
	HE	תקינות השרת
	NL	Server- en netwerktoestand

PLUGIN_HEALTH_PERF_ENABLE
	DE	Leistungsüberwachung aktivieren
	EN	Enable Performance Monitoring
	ES	Habilitar Monitoreo de Perfomance
	NL	Schakel prestatiemonitoring in

PLUGIN_HEALTH_PERF_DISABLE
	DE	Leistungsüberwachung deaktivieren
	EN	Disable Performance Monitoring
	ES	Deshabilitar Monitoreo de Perfomance
	NL	Schakel prestatiemonitoring uit

PLUGIN_HEALTH_NETTEST
	DE	Netzwerktest
	EN	Network Test
	ES	Test de Red
	NL	Netwerk test

PLUGIN_HEALTH_NETTEST_SELECT_RATE
	DE	Bitte mit auf/ab Rate wählen
	EN	Press Up/Down to select rate
	ES	Elegir tasa: pres. Arriba/Abajo
	NL	Selecteer snelheid met op/neer

PLUGIN_HEALTH_NETTEST_NOT_SUPPORTED
	DE	Wird auf diesem Player nicht unterstützt.
	EN	Not Supported on this Player
	ES	No soportado en este Reproductor
	NL	Niet ondersteund op deze speler

PLUGIN_HEALTH_NETTEST_DESC1
	DE	Sie können die Netzwerk-Leistung zwischen dem Server und diesem Player testen. Das erlaubt es ihnen, die höchst mögliche Datenrate zu bestimmen, die ihr Netzwerk übertragen kann. Auch kann es beim Aufspüren von Netzwerkproblemen dienen. Um einen Test zu starten, wählen Sie eine der folgenden Datenraten.<p><b>Achtung:</b> das Durchführen eines Netzwerktests unterbricht alle anderen Aktivitäten auf diesem Gerät.
	EN	You may test the network performance between your server and this player.  This will enable you to confirm the highest data rate that your network will support and identify network problems.  To start a test select one of the data rates below.<p><b>Warning</b> Running a network test will stop all other activity for this player including streaming.
	NL	Je kunt de netwerkprestatie tussen je server en deze speler testen. Hiermee kun je zien wat de hoogste snelheid is die je netwerk ondersteunt en om problemen te identificeren. Om de test te starten kies je een testsnelheid.  <br>  <b>Waarschuwing</b> Tijdens de netwerktest stoppen alle andere activiteiten van de speler, ook het streamen.

PLUGIN_HEALTH_NETTEST_DESC2
	DE	Es läuft derzeit ein Netzwerktest auf diesem Gerät. Dies unterbindet die Erstellung anderer Statistiken. Sie können unten eine neu Testrate definieren. Um den Test zu stoppen und zu den anderen Geräteleistungs-Informationen zu gelangen, wählen Sie "Test anhalten".<p>Die Graphik zeigt den erfolgreich übetragenen Anteil an der Testrate in Prozent an. Sie wird einmal pro Sekunde aktualisiert. Es werden das Resultat für die letzte Sekunde sowie der längerfristige Durchschnitt auch auf dem Display des Players angezeigt. Lassen Sie den Test eine Weile auf einer bestimmten Datenrate laufen. Die Grafik zeigt dann an, wie oft der Datendurchsatz unter 100% der gewünschten Rate gefallen ist.
	EN	You are currently running a network test on this player.  This disables reporting other player statistics.  You may change the test rate by selecting a new rate above.  To stop the test and return to other player performance information select Stop Test above.<p>The graph below records the percentage of the test rate which is sucessfully sent to the player.  It is updated once per second with the performance measured over the last second.  The result for the last second and long term average at this rate are also shown on the player display while a test is running.  Leave the test running for a period of time at a fixed rate.  The graph will record how frequently the network performance drops below 100% at this rate.
	NL	Je laat nu een netwerk test lopen voor deze speler. Andere spelerstatistieken zijn nu uitgeschakeld. Je kunt de testsnelheid wijzigen door hierboven een andere testsnelheid te kiezen. Om de test te stoppen en terug te keren naar de andere spelerstatistieken selecteer je Stop test hierboven.  <br>  De grafiek hieronder toont het percentage van de testsnelheid dat succesvol is verstuurd naar de speler. Elke seconde wordt het resultaat van de laatste seconde bijgewerkt. Het resultaat van de laatste seconde en het resultaat over een langere periode worden ook getoond op het scherm van de speler. Laat de test een tijdje lopen op een gekozen testsnelheid. De grafiek zal registreren hoe frequent de netwerksnelheid onder de 100% komt.

PLUGIN_HEALTH_NETTEST_DESC3
	DE	Die höchste Datenrate, die zu 100% übertragen wird, ist die höchste Rate, die für Streaming zur Verfügung steht. Falls diese geringer ist als die Bitrate ihrer Dateien, so sollten Sie eine Beschränkung der Bitrate in Betracht ziehen.<p>Squeezebox2/3, die per Kabel ans Netzwerk angeschlossen sind, sollten mindestens 3000kbps zu 100% erreichen, die Squeezebox1 ca. 1500kbps. Drahtlos angeschlossene Geräte können ebenfalls solche Werte erreichen, doch hängt das Resultat stark vom Netzwerk ab. Werte, die erheblich niedriger sind, deuten auf Netzwerkprobleme hin. Wireless Netzwerke können durchaus geringere Werte erreichen. Benutzen Sie die Grafik, um die Leistung zu verstehen. Falls die Datenrate häufig absinkt, dann sollten Sie das Netzwerk überprüfen.
	EN	The highest test rate which achieves 100% indicates the maximum rate you can stream at.  If this is below the bitrate of your files you should consider configuring bitrate limiting for this player.<p>A Squeezebox2/3 attached to a wired network should be able to achieve at least 3000 kbps at 100% (Squeezebox1 1500 kbps).  A player attached to a wireless network may also reach up to this rate depending on your wireless network.  Rates significantly below this indicate poor network performance.  Wireless networks may record occasional lower percentages due to interference.  Use the graph above to understand how your network performs.  If the rate drops frequently you should investigate your network.
	NL	De hoogste testsnelheid waar je 100% haalt is de maximale snelheid waarmee je een stream kunt sturen. Als dit onder de bitrate is van je bestanden moet je overwegen om een bitrate limiet in te stellen.  <br> Een Squeezebox2/3 verbonden via een bedraad netwerk moet op zijn minst 3000 kbps op 100% halen (Squeezebox 1 1500 kbps). Een speler gekoppeld aan een draadloos netwerk kan ook deze snelheid halen, afhankelijk van je draadloze netwerk. Snelheden die significant onder de bovenstaande waarden liggen wijzen op een slechte netwerkperformance. Draadloze netwerken kunnen af en toe lagere percentages geven door interferentie. Gebruik de bovenstaande grafiek om na te gaan hoe je netwerkperformance is. Als de snelheid regelmatig laag is moet je het netwerk controleren.

PLUGIN_HEALTH_NETTEST_PLAYERNOTSUPPORTED
	DE	Dieser Player unterstützt keine Netzwerktests.
	EN	Network tests are not supported on this player.
	NL	Netwerk testen zijn niet ondersteund op deze speler.

PLUGIN_HEALTH_NETTEST_CURRENTRATE
	DE	Aktuelle Testrate
	EN	Current Test Rate
	NL	Huidige testsnelheid

PLUGIN_HEALTH_NETTEST_TESTRATE
	DE	Test Datenrate
	EN	Test Rate
	NL	Testsnelheid

PLUGIN_HEALTH_NETTEST_STOPTEST
	DE	Test anhalten
	EN	Stop Test
	NL	Stop test

PLUGIN_HEALTH_PERF_SUMMARY
	EN	Performance Summary

PLUGIN_HEALTH_PERF_SUMMARY_DESC
	EN	Please queue up several tracks to play on this player and start them playing.  Then press the Reset link below to clear the statistics and update this display.

PLUGIN_HEALTH_PERF_RESET
	EN	Reset

PLUGIN_HEALTH_SUMMARY
	DE	Zusammenfassung
	EN	Summary
	ES	Sumario
	NL	Samenvatting

PLUGIN_HEALTH_WARNINGS
	DE	Warnungen
	EN	Warnings
	ES	Advertencias
	NL	Waarschuwingen

PLUGIN_HEALTH_PERF_STATISTICS
	EN	Performance Statistics

PLUGIN_HEALTH_PLAYER
	EN	Player Statistics

PLUGIN_HEALTH_SERVER
	EN	Server Statistics

PLUGIN_HEALTH_OK
	EN	OK

PLUGIN_HEALTH_CONGEST
	DE	Überlastung
	EN	Congested
	ES	Congestionado
	FI	Ruuhkautunut
	NL	Congestie

PLUGIN_HEALTH_FAIL
	DE	Gestört
	EN	Fail
	ES	Falla
	NL	Gefaald

PLUGIN_HEALTH_INACTIVE
	DE	Inaktiv
	EN	Inactive
	ES	Inactivo
	FI	Ei aktiivinen
	IT	Inattivo
	NL	Inactief

PLUGIN_HEALTH_CONTROLCONGEST_DESC
	DE	Die Kontroll-Verbindung zu diesem Player hat Überlastungen erfahren. Dies ist üblicherweise ein Hinweis auf schlechte Netzwerkverbindung, oder dass das Gerät vor kurzem vom Netz genommen wurde.
	EN	The control connection to this player has experienced congestion.  This usually is an indication of poor network connectivity (or the player being recently being disconnected from the network).
	ES	La conexión de control a este reproductor ha experimentado congestión. Esto generalmente es indicador de una mala conectividad en la red (también puede deberse a que el reproductor se desconectó recientemente de la red).
	HE	הקישור בין הנגן לשרת נקטע מספר פעמים. בדוק רשת
	NL	De controleconnectie naar deze speler heeft last gehad van congestie. Dit is meestal een indicatie van een slechte netwerkconnectie (of een speler die recent van het netwerk losgekoppeld is geweest).

PLUGIN_HEALTH_CONTROLFAIL_DESC
	DE	Derzeit ist keine aktive Kontroll-Verbindung für diesen Player vorhanden. Bitte stellen Sie sicher, dass das Gerät eingeschaltet ist. Falls der Player keine Netzwerkverbindung aufbauen kann, überprüfen sie bitte die Netzwerkkonfiguration und/oder Firewall. Diese darf TCP und UPD Ports 3483 nicht blockieren.
	EN	There is no currently active control connection to this player.  Please check the player is powered on.  If the player is unable to establish a connection, please check your network and and/or server firewall do not block connections to TCP & UDP port 3483.
	ES	No existe una conexión de control activa a este reproductor. Por favor, verificar que el reproductor esté encendido. Si el reproductor no puede establecer una conexión,  por favor, verificar que la red y/o el firewall del servidor no estén bloqueando las conexiones TCP y UDP  en el puerto 3483.
	HE	הנגן לא מחובר. בדוק אם הוא מחובר לחשמל
	NL	Er is momenteel geen actieve controleconnectie naar deze speler. Controleer of de speler aan staat. Controleer of je netwerk en/of server firewall geen connecties blokkeren naar TCP & UDP poort 3483 als je speler geen connectie kan maken.
PLUGIN_HEALTH_STREAMINACTIVE_DESC
	DE	Derzeit existiert keine aktive Verbindung zu diesem Gerät. Eine Verbindung ist notwendig, um eine Datei zum Player übertragen zu können. Squeezebox2/3 können die Streaming-Verbindung gegen Ende eines Liedes schliessen, sobald die Daten im Puffer auf dem Gerät angekommen sind. Das ist kein Grund zur Beunruhigung.<p>Falls Sie Probleme haben, Musikdateien abzuspielen und Sie nie eine aktive Verbindung sehen, dann kann das auf Netzwerkprobleme hindeuten. Bitte verifizieren Sie, dass das Netzwerk und/oder die Firewall Verbindungen auf Port 9000 nicht blockieren.
	EN	There is currently no active connection for streaming to this player.  A connection is required to stream a file to your player.  Squeezebox2/3 may close the streaming connection towards the end of a track once it is transfered to the buffer within the player.  This is not cause for concern.<p>If you experiencing problems playing files and never see an active streaming connection, then this may indicate a network problem.  Please check that your network and/or server firewall do not block connections to TCP port 9000.
	NL	Er is op dit moment geen actieve connectie voor het streamen naar deze speler. Een connectie is altijd nodig om bestanden te spelen vanaf de server (maar niet als je een radiostream op afstand gebruikt bij een Squeezebox2 of 3)  <br>  Als je een lokaal bestand probeert af te spelen dan wijst dit op een netwerkprobleem. Controleer of je netwerk en/of server firewall niet TCP poort 9000 blokkeren.

PLUGIN_HEALTH_SIGNAL_INTERMIT
	DE	Gut, aber mit vereinzelten Ausfällen
	EN	Good, but Intermittent Drops
	ES	Buena, pero con Cortes Intermitentes
	FI	Hyvä, mutta satunnaisia katkoja
	NL	Goed maar af en toe haperingen

PLUGIN_HEALTH_SIGNAL_INTERMIT_DESC
	DE	Die Signalstärke dieses Players ist im Grossen und Ganzen gut, hatte aber vereinzelte Ausfälle. Dies kann auf andere Wireless Netzwerke, kabellose Telephone oder Mikrowellen-Öfen zurückzuführen sein. Falls Sie vereinzelte Ton-Aussetzer wahrnehmen, so sollten Sie der Ursache des Problems nachgehen.
	EN	The signal strength received by this player is normally good, but occasionally drops.  This may be caused by other wireless networks, cordless phones or microwaves nearby.  If you hear occasional audio dropouts on this player, you should investigate what is causing drops in signal strength.
	ES	La energía de la señal recibida por este reproductor es normalmente buena, pero con cortes ocasionalmente. Esto puede estar causado por otras redes inalámbricas, teléfonos inalámbricos u hornos de microondas cercanos. Si se escuchan interrupciones de audio ocasionales en este reproductor, se debería investigar cuál es la causa de las caídas en la energía de la señal.
	NL	De signaalsterkte ontvangen door de speler is goed met af en toe haperingen. De oorzaak kunnen andere draadloze netwerken zijn, draadloze telefoons of magnetrons die dichtbij zijn. Als je haperingen hoort in de audio moet je de oorzaak onderzoeken van de haperingen in de signaalsterkte.

PLUGIN_HEALTH_SIGNAL_POOR
	DE	Schwach
	EN	Poor
	ES	Pobre
	NL	Matig

PLUGIN_HEALTH_SIGNAL_POOR_DESC
	DE	Die Signalstärke dieses Players ist grösstenteils schwach. Bitte überprüfen Sie das Wireless Netzwerk.
	EN	The signal strength received by this player is poor for significant periods, please check your wireless network.
	ES	La energía de la señal recibida por este reproductor es pobre durante períodos importantes, por favor verificar la red inalámbrica.
	NL	De signaalsterkte ontvangen door de speler is matig over een langere periode. Controleer je draadloze netwerk.

PLUGIN_HEALTH_SIGNAL_BAD
	DE	Schlecht
	EN	Bad
	ES	Mala
	FI	Huono
	NL	Slecht

PLUGIN_HEALTH_SIGNAL_BAD_DESC
	DE	Die Signalstärke dieses Players ist grösstenteils schlecht. Bitte überprüfen Sie das Wireless Netzwerk.
	EN	The signal strength received by this player is bad for significant periods, please check your wireless network.
	ES	La energía de la señal recibida por este reproductor es mala durante períodos importantes, por favor verificar la red inalámbrica.
	NL	De signaalsterkte ontvangen door je speler is slecht over een  aanzienlijke periode. Controleer je draadloze netwerk.

PLUGIN_HEALTH_CONTROL
	DE	Kontrollverbindung
	EN	Control Connection
	ES	Conexión de Control
	FI	Hallintayhteys
	NL	Controleconnectie

PLUGIN_HEALTH_STREAM
	DE	Streaming-Verbindung
	EN	Streaming Connection
	ES	Conexión para Streaming
	NL	Streaming connectie

PLUGIN_HEALTH_SIGNAL
	DE	Signalstärke
	EN	Signal Strength

PLUGIN_HEALTH_BUFFER_LOW
	DE	Niedrig
	EN	Low
	ES	Bajo
	FI	Matala
	NL	Laag

PLUGIN_HEALTH_BUFFER_LOW_DESC1
	DE	Der Wiedergabe-Puffer dieses Players ist zeitweise niedriger als wünschenswert. Dies kann zu Tonaussetzern führen, v.a. falls Sie WAV oder AIFF verwenden. Falls Sie solche Aussetzer wahrnehmen, überprüfen Sie bitte die Signalstärke und Server Antwortzeiten.
	EN	The playback buffer for this player is occasionally falling lower than ideal.  This may result in audio dropouts especually if you are streaming as WAV/AIFF.  If you are hearing these, please check your network signal strength and server response times.
	ES	El buffer de reproducción de este reproductor tiene, ocasionalmente, niveles por debajo del ideal. Esto puede producir interrupciones en el audio, especialmente si se está transmitiendo en formato WAV/AIFF. Si se escuchan estos, por favor, controlar la potencia de señal de red y los tiempos de respuesta del servidor.
	HE	לנגן יש בעיות לקבל מידע מהשרת. בדוק רשת
	NL	De afspeelbuffer van deze speler is af en toe minder gevuld dan in de ideale situatie. Dit kan resulteren in audio haperingen, zeker als je WAV/AIFF streamt. Controleer de netwerksignaalsterkte en de snelheid waarmee de server reageert als je haperingen hoort.

PLUGIN_HEALTH_BUFFER_LOW_DESC2
	DE	Der Wiedergabe-Puffer dieses Players ist zeitweise niedriger als wünschenswert. Dies ist eine Squeezebox2/3, es ist daher normal, dass der Puffer am Ende eines Liedes geleert wird. Diese Warnung wird ev. angezeigt, falls Sie viele kurze Lieder wiedergeben. Falls Sie Tonaussetzer feststellen, überprüfen Sie bitte die Signalstärke.
	EN	The playback buffer for this player is occasionally falling lower than ideal.  This is a Squeezebox2/3 and so the buffer fullness is expected to drop at the end of each track.  You may see this warning if you are playing lots of short tracks.  If you are hearing audio dropouts, please check our network signal strength.
	ES	El buffer de reproducción de este reproductor tiene, ocasionalmente, niveles por debajo del ideal. Este es un Squeezebox2/3 y por lo tanto es esperable que el buffer se vacíe al final de cada pista. Se puede recibir esta advertencia si se están reproduciendo muchas pistas de corta duración. Si se escuchan interrupciones de audio, por favor, controlar la potencia de señal de red.
	HE	לנגן יש בעיות לקבל מידע מהשרת. בדוק רשת
	NL	De afspeelbuffer van deze speler is af en toe minder gevuld dan in de ideale situatie. Dit is een Squeezebox2. Daar mag het bufferniveau laag zijn aan het einde van een liedje. Je kunt deze waarschuwing krijgen als je veel korte liedjes afspeelt. Controleer de netwerksignaalsterkte als je haperingen hoort in het geluid.

PLUGIN_HEALTH_BUFFER
	DE	Puffer-Füllstand
	EN	Buffer Fullness
	ES	Llenado del Buffer
	FI	Puskurin täyttöaste
	NL	Bufferniveau

PLUGIN_HEALTH_SLIMP3_DESC
	DE	Sie verwenden einen SliMP3 Player. Für diesen stehen nicht die vollen Messungen zur Verfügung.
	EN	This is a SLIMP3 player.  Full performance measurements are not available for this player.
	ES	Este es un reproductor SLIMP3. Medidas completas de perfomance no están disponibles para este reproductor.
	NL	Dit is een Slimp3 speler. Volledige prestatiemonitoring is niet beschikbaar voor deze speler.

PLUGIN_HEALTH_NO_PLAYER_DESC
	DE	SlimServer kann keinen Player finden. Falls einer angeschlossen ist, so kann dies durch eine blockierte Netzwerkverbindung ausgelöst werden. Überprüfen sie bitte die Netzwerkkonfiguration und/oder Firewall. Diese darf TCP und UPD Ports 3483 nicht blockieren.
	EN	Slimserver cannot find a player.  If you own a player this could be due to your network blocking connection between the player and server.  Please check your network and/or server firewall does not block connection to TCP & UDP port 3483.
	ES	Slimserver no puede encontrar ningón reproductor. Si existe un reproductor esto puede deberse a bloqueos de conexión de red entre el servidor y el reproductor. Por favor, verificar que la red y/o el firewall del servidor no estén bloqueando las conexiones TCP y UDP en el puerto 3483.
	HE	השרת לא מוצא נגן, בדוק רשת וחומת אש
	NL	SlimServer kan geen speler vinden. Als je een speler hebt kan dit komen door een netwerk dat connecties blokkeert tussen de speler en server. Controleer of je netwerk en/of server firewall niet TCP & UDP poort 3483 blokkeert.

PLUGIN_HEALTH_RESPONSE
	DE	Server Antwortzeiten
	EN	Server Response Time
	ES	Tiempo de Respuesta del Servidor
	NL	Serverreactietijd

PLUGIN_HEALTH_RESPONSE_INTERMIT
	DE	Teilweise schlechte Antwortzeiten
	EN	Occasional Poor Response
	ES	Ocasionalmente Respuesta Pobre
	FI	Satunnaista huonoa vastetta
	NL	Af en toe slechte reactietijd

PLUGIN_HEALTH_RESPONSE_INTERMIT_DESC
	DE	Die Antwortzeiten des Servers sind zeitweise länger als wünschenswert. Dies kann zu hörbaren Tonaussetzern führen, v.a. auf SliMP3 und Squeezebox1 Playern. Gründe hierfür können andere laufene Programme im Hintergrund oder komplexe Aufgaben im Slimserver sein.
	EN	Your server response time is occasionally longer than desired.  This may cause audio dropouts, especially on Slimp3 and Squeezebox1 players.  It may be due to background load on your server or a slimserver task taking longer than normal.
	ES	El tiempo de respuesta del servidor es ocasionalmente más alto que el deseado. Esto puede causar interrupciones audio, especialmente en los reproductores Slimp3 y Squeezebox1. Puede deberse a una carga de procesos de fondo, o a que una tarea de Slimserver está tomando más tiempo que el normal.
	HE	זמן התגובה של השרת ארוך מהרצוי, בדוק אם השרת עמוס
	NL	De serverreactietijd is af en toe lager dan gewenst. Dit kan audio haperingen veroorzaken, zeker bij de Slimp3 en Squeezebox1 spelers. De oorzaak kunnen de overige programma\'s zijn die op je server draaien of een SlimServer taak die langer duurt dan normaal.

PLUGIN_HEALTH_RESPONSE_POOR
	DE	Schlechte Antwortzeiten
	EN	Poor Response
	ES	Respuesta Pobre
	FI	Huono vaste
	NL	Slechte reactietijd

PLUGIN_HEALTH_RESPONSE_POOR_DESC
	DE	Die Antwortzeiten des Servers sind oft länger als wünschenswert. Dies kann zu hörbaren Tonaussetzern führen, v.a. auf SliMP3 und Squeezebox1 Playern. Überprüfen Sie bitte die Leistung ihres Servers. Falls diese ok ist, vergewissern Sie sich, ob SlimServer komplexe Aufgaben (z.B. Durchsuchen der Musiksammlung) durchführt oder ein Plugin die Ursache für das Problem darstellt.
	EN	Your server response time is regularly falling below normal performance levels.  This may lead to audio dropouts, especially on Slimp3 and Squeezebox1 players.  Please check the performance of your server.  If this is OK, then check slimserver is not running intensive tasks (e.g. scanning music library) or a Plugin is not causing this.
	ES	El tiempo de respuesta del servidor es regularmente más bajo que los niveles de perfomance normales. Esto puede causar interrupciones de  audio, especialmente en los reproductores Slimp3 y Squeezebox1. Por favor, verificar la perfomance del servidor. Si esto está OK, entonces verificar que Slimserver no está corriendo tareas intensivas (por ej. recopilando la colección musical) o que algón plugin no está causando esto.
	HE	זמן התגובה של השרת ארוך מהרצוי, בדוק אם השרת עמוס
	NL	De serverreactietijd is regelmatig lager dan gewenst. Dit kan audio haperingen veroorzaken, zeker bij de Slimp3 en Squeezebox1 spelers. Controleer de prestatie van je server. Is die goed, controleer dan of SlimServer geen intensieve taken draait (zoals scannen van de muziekcollectie) of dat een plugin dit veroorzaakt.

PLUGIN_HEALTH_NORMAL
	DE	Dieser Player verhält sich normal.
	EN	This player is performing normally.
	ES	Este reproductor está funcionando normalmente.
	FI	Tämä soitin toimii normaalisti.
	NL	Deze speler functioneert normaal.

PLUGIN_HEALTH_REFRESH
	EN	Refresh

PLUGIN_HEALTH_CLEAR
	EN	Clear

PLUGIN_HEALTH_CLEAR_ALL
	EN	Clear All

PLUGIN_HEALTH_SET
	EN	Set

PLUGIN_HEALTH_SET_ALL
	EN	Set All

PLUGIN_HEALTH_WARNING_THRESHOLDS
	EN	Warning Thresholds

PLUGIN_HEALTH_LOW
	EN	Low

PLUGIN_HEALTH_HIGH
	EN	High

PLUGIN_HEALTH_GRAPHS_DESC_PLAYER
	EN	The server is currently collecting performance statistics for this player.  

PLUGIN_HEALTH_GRAPHS_DESC_SERVER
	EN	The server is currently collecting performance statistics for various internal server functions.  These graphs are intended to be used to help diagnose performance issues with the server and its plugins.

PLUGIN_HEALTH_WARNING_DESC
	EN	You may set warning thresholds for each measurement.  This will record in the server log whenever the threshold is exceeded.  The most recent log entries can be viewed <a href="/log.txt" target="log">here</a>.

PLUGIN_HEALTH_SIGNAL_DESC
	DE	Diese Graphik zeigt die Signalstärke der Wireless Netzwerkverbindung ihres Players. Höhere Werte sind besser. Der Player gibt die Signalstärke während der Wiedergabe zurück.
	EN	This graph shows the strength of the wireless signal received by your player.  Higher signal strength is better.  The player reports signal strength while it is playing.
	ES	Este gráfico muestra la energía de la señal inalámbrica recibida por tu reproductor. Un valor alto de energía es mejor.El reproductor reporta la energía de la señal mientras está reproduciendo.
	NL	Deze grafiek toont de signaalsterkte van je draadloze netwerk zoals ontvangen door je speler. Hogere signaalsterkte is beter. De speler rapporteert de signaalsterkte tijdens het afspelen.

PLUGIN_HEALTH_BUFFER_DESC
	DE	Diese Graphik zeigt den Puffer-Füllstand ihres Players. Höhere Werte sind besser. Beachten Sie bitte, dass der Puffer nur während der Wiedergabe gefüllt wird.<p>Die Squeezebox1 besitzt nur einen kleinen Puffer, der während der Wiedergabe stets voll sein sollte. Fällt der Wert auf 0, so ist mit Aussetzern in der Wiedergabe zu rechnen. Dies wäre vermutlich auf Netzwerkprobleme zurückzuführen.<p>Die Squeezebox2/3 verwendet einen grossen Puffer. Dieser wird am Ende jedes wiedergegebenen Liedes geleert (Füllstand 0) um dann wieder aufzufüllen. Der Füllstand sollte also meist hoch sein.<p>Die Wiedergabe von Online-Radiostationen kann zu niedrigem Puffer-Füllstand führen, da der Player auf die Daten von einem entfernten Server warten muss. Dies ist normales Verhalten und kein Grund zur Beunruhigung.
	EN	This graph shows the fill of the player\'s buffer.  Higher buffer fullness is better.  Note the buffer is only filled while the player is playing tracks.<p>Squeezebox1 uses a small buffer and it is expected to stay full while playing.  If this value drops to 0 it will result in audio dropouts.  This is likely to be due to network problems.<p>Squeezebox2/3 uses a large buffer.  This drains to 0 at the end of each track and then refills for the next track.  You should only be concerned if the buffer fill is not high for the majority of the time a track is playing.<p>Playing remote streams can lead to low buffer fill as the player needs to wait for data from the remote server.  This is not a cause for concern.
	ES	Este gráfico muestra el llenado del buffer del reproductor. Cuanto más lleno esté mejor es. Notar que el buffer solo se llena cuando el reproductor está reproduciendo pistas.    Squeezebox1 utiliza un buffer pequeño y se espera que permanezca lleno mientras se reproduce. Si este valor cae a 0 se producirán interrupciones en el audio. Esto se debe muy probablemente a problemas de red.    Squeezebox2/3 utiliza un buffer grande. Este se vacía (vuelve a 0) al final de cada pista y luego se llena nuevamente para la próxima pista. Solo debería precupar el caso en que el llenado del buffer no tiene un nivel alto durante la mayoría del tiempo en que se esta reproduciendo una pista.    El reproducir streams remotos puede producir que el buffer tenga un nivel de llenado bajo, ya que el reproductor necesitas esperar que lleguen datos del servidor remoto. Esto no es causa para preocuparse.
	HE	תצוגה גרפית של סטטיסטיקות
	NL	Deze grafiek toont bufferniveau. Hoger niveau is beter. De buffer is alleen gevuld tijdens het afspelen van muziek.  <br>Squeezebox1 gebruikt een kleine buffer die normaal gesproken altijd vol is. Als het niveau naar 0 gaat zal er hapering in het geluid optreden. Dit komt vaak door netwerkproblemen.  <br>Squeezebox2/3 gebruikt een grote buffer. Hier loopt het bufferniveau naar 0 toe aan het einde van een liedje en vult zich weer aan het begin van het volgende liedje. Alleen als de buffer de meeste tijd niet gevuld is tijdens het spelen moet je actie nemen.  <br>Het spelen van streams op afstand (Internet radio) geeft een laag bufferniveau omdat de speler moet wachten op de server op afstand. Dit is geen gevolg van problemen.

PLUGIN_HEALTH_CONTROL_DESC
	DE	Diese Graphik zeigt die Anzahl von aufgestauten Meldungen, die über die Kontroll-Verbindung zum Player geschickt werden sollten. Die Messung findet statt, wenn eine Meldung zum Player geschickt wird. Werte über 1-2 weisen auf eine mögliche Netzwerk-Überlastung hin, oder dass die Verbindung zum Player unterbrochen wurde.
	EN	This graph shows the number of messages queued up to send to the player over the control connection.  A measurement is taken every time a new message is sent to the player.  Values above 1-2 indicate potential network congestion or that the player has become disconnected.
	ES	Esta gráfico muestra el nómero de mensajes encolados para ser enviados al reproductor sobre la conexión de control. Una medición se toma cada vez que un nuevo mensaje es enviado hacia el reproductor. Los valores mayores a 1-2 indican una congestión potencial de la red o que el reprodcutor se ha desconectado.
	HE	אם הערכים בגרף הם מעל 1 או 2 בדוק רשת
	NL	Deze grafiek toont de hoeveelheid boodschappen in de rij gezet om te versturen naar de speler over de controleconnectie. Bij elke verstuurde boodschap wordt een meting gedaan. Waarden boven 1-2 geven een potentieel een netwerkcongestie aan of dat de speler losgekoppeld is van het netwerk.

PLUGIN_HEALTH_RESPONSE_DESC
	DE	Diese Graphik zeigt die Zeitdauer, die zwischen zwei Anfragen von beliebigen Playern vergeht. Die Masseinheit ist Sekunden. Geringere Werte sind besser. Antwortzeiten über einer Sekunde können zu Problemen bei der Audio-Wiedergabe führen.<p>Gründe für solche Verzögerungen können andere ausgeführte Programme oder komplexe Verarbeitungen im SlimServer sein.
	EN	This graph shows the length of time between slimserver responding to requests from any player.  It is measured in seconds. Lower numbers are better.  If you notice response times of over 1 second this could lead to problems with audio performance.<p>The cause of long response times could be either other programs running on the server or slimserver processing a complex task.
	ES	Este gráfico muestra el tiempo de respuesta de Slimserver a requerimientos de cualquier reproductor. Se mide en segundos. Valores bajos son mejores. Si se nota tiempos de respuesta de más de 1 segundo esto puede producir problemas con la perfomance de audio.    La causa de tiempos de respuesta grandes puede ser o bien otros programas corriendo en el servidor, o bien que Slimserver esté procesando una tarea compleja.
	HE	במידה וגרף זה מציג זמנים מעל שניה אחת יש בעיה ברשת או שהשרת עמוס
	NL	Deze grafiek toont de tijd waarbinnen SlimServer reageert op verzoeken van de speler. De uitkomst is in seconden. Lagere waardes zijn beter. Als je reactietijden hebt van meer dan 1 seconde kan dit leiden tot problemen bij afspelen van audio.  <br>De oorzaak van lange reactietijden kan liggen bij andere programma\'s die draaien op de server of dat SlimServer een complexe taak uitvoert.

PLUGIN_HEALTH_RESPONSE_DESC
	EN	The response time of the server - the time between successive calls to select.  

PLUGIN_HEALTH_SELECTTASK
	EN	Select Task Duration

PLUGIN_HEALTH_SELECTTASK_DESC
	EN	The length of time taken by each task run by select.

PLUGIN_HEALTH_SCHEDULERTASK
	EN	Scheduler Task Duration

PLUGIN_HEALTH_SCHEDULERTASK_DESC
	EN	The length of time taken by each scheduled task.

PLUGIN_HEALTH_TIMERTASK
	EN	Timer Task Duration

PLUGIN_HEALTH_TIMERTASK_DESC
	EN	The length of time taken by each timer task.

PLUGIN_HEALTH_TIMERLATE
	EN	Timer Lateness

PLUGIN_HEALTH_TIMERLATE_DESC
	EN	The time between when a timer task was scheduled and when it is run.

PLUGIN_HEALTH_REQUEST
	EN	Execute / Notification Task Duration

PLUGIN_HEALTH_REQUEST_DESC
	EN	The length of time taken by each execute command or notification callback.

PLUGIN_HEALTH_PAGEBUILD
	EN	Web Page Build

PLUGIN_HEALTH_PAGEBUILD_DESC
	EN	The length of time taken to build each web page.

PLUGIN_HEALTH_IRQUEUE
	EN	IR Queue Length

PLUGIN_HEALTH_IRQUEUE_DESC
	EN	The delay between an IR key press being received and being processed.

'
}

1;

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
