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
	{ 'type' => 'server', 'name' => 'timertask',    'monitor' => \$Slim::Utils::Timers::timerTask,          },
	{ 'type' => 'server', 'name' => 'request',      'monitor' => \$Slim::Control::Request::requestTask,     },
	{ 'type' => 'server', 'name' => 'schedulertask','monitor' => \$Slim::Utils::Scheduler::schedulerTask,   },
	{ 'type' => 'server', 'name' => 'dbaccess',     'monitor' => \$Slim::Schema::Storage::dbAccess,         },
	{ 'type' => 'server', 'name' => 'pagebuild',    'monitor' => \$Slim::Web::HTTP::pageBuild,              },
	{ 'type' => 'server', 'name' => 'proctemplate', 'monitor' => \$Slim::Web::Template::Context::procTemplate },
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

		if (!$client->display->isa("Slim::Display::Graphics")) {
			$params->{'nettest_notsupported'} = 1;
			
		} elsif (Slim::Buttons::Common::mode($client) eq 'PLUGIN.Health::Plugin') {
			# network test currently running on this player
			my $modeParam = $client->modeParam('Health.NetTest');
			if ($stoptest) {
				# stop tests
				Plugins::Health::NetTest::exitMode($client);
				Slim::Buttons::Common::popMode($client);
				$client->update();
				$refresh = 2;
			} elsif (defined($newtest)) {
				# change test rate
				Plugins::Health::NetTest::setTest($client, undef, $newtest, $modeParam);
				$refresh = 2;
			} 
			if (!$stoptest && defined($modeParam) && ref($modeParam) eq 'HASH' && defined $modeParam->{'log'}) { 
				# display current results
				$params->{'nettest_rate'} = $modeParam->{'rate'};
				$params->{'nettest_graph'} = $modeParam->{'log'}->sprint();
			}

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

		if (defined $params->{'monitor'} && ($params->{'monitor'} eq $mon->{'name'} || $params->{'monitor'} eq 'all') ) {
			if (exists($params->{'setwarn'})) {
				$monitor->setWarnHigh(Slim::Utils::Validate::number($params->{'warnhi'}));
				$monitor->setWarnLow(Slim::Utils::Validate::number($params->{'warnlo'}));
				$monitor->setWarnBt($params->{'warnbt'});
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
			'warnbt'=> $monitor->warnBt(),
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
	FR	Contrôle serveur et réseau
	HE	תקינות השרת
	NL	Server- en netwerktoestand

PLUGIN_HEALTH_PERF_ENABLE
	DE	Leistungsüberwachung aktivieren
	EN	Enable Performance Monitoring
	ES	Habilitar Monitoreo de Perfomance
	FR	Activer le contrôle des performances
	NL	Schakel prestatiemonitoring in

PLUGIN_HEALTH_PERF_DISABLE
	DE	Leistungsüberwachung deaktivieren
	EN	Disable Performance Monitoring
	ES	Deshabilitar Monitoreo de Perfomance
	FR	Désactiver le contrôle des performances
	NL	Schakel prestatiemonitoring uit

PLUGIN_HEALTH_NETTEST
	EN	Network Test
	ES	Test de Red
	FR	Test réseau
	NL	Netwerk test

PLUGIN_HEALTH_NETTEST_SELECT_RATE
	EN	Press Up/Down to select rate
	ES	Elegir tasa: pres. Arriba/Abajo
	FR	Haut/Bas pour changer le taux
	NL	Selecteer snelheid met op/neer

PLUGIN_HEALTH_NETTEST_NOT_SUPPORTED
	EN	Not Supported on this Player
	ES	No soportado en este Reproductor
	FR	Non supporté sur cette platine
	NL	Niet ondersteund op deze speler

PLUGIN_HEALTH_NETTEST_DESC1
	EN	You may test the network performance between your server and this player.  This will enable you to confirm the highest data rate that your network will support and identify network problems.  To start a test select one of the data rates below.<p><b>Warning</b> Running a network test will stop all other activity for this player including streaming.
	FR	Vous pouvez tester les performances du réseau entre le serveur et cette platine afin de déterminer le débit maximum supporté par votre réseau et/ou diagnostiquer des problèmes réseau. Pour lancer un test, sélectionnez un débit ci-dessous.    Note : le lancement d\'un test réseau arrêtera toutes les fonctions en cours sur la platine, y compris la diffusion à distance.
	NL	Je kunt de netwerkprestatie tussen je server en deze speler testen. Hiermee kun je zien wat de hoogste snelheid is die je netwerk ondersteunt en om problemen te identificeren. Om de test te starten kies je een testsnelheid.  <br>  <b>Waarschuwing</b> Tijdens de netwerktest stoppen alle andere activiteiten van de speler, ook het streamen.

PLUGIN_HEALTH_NETTEST_DESC2
	EN	You are currently running a network test on this player.  This disables reporting other player statistics.  You may change the test rate by selecting a new rate above.  To stop the test and return to other player performance information select Stop Test above.<p>The graph below records the percentage of the test rate which is sucessfully sent to the player.  It is updated once per second with the performance measured over the last second.  The result for the last second and long term average at this rate are also shown on the player display while a test is running.  Leave the test running for a period of time at a fixed rate.  The graph will record how frequently the network performance drops below 100% at this rate.
	FR	Vous être actuellement en train d\'effectuer un test réseau sur cette platine. L\'envoi d\'autres statistiques depuis cette platine est temporairement désactivé. Vous pouvez modifier le débit de test en sélectionnant une valeur ci-dessus. Pour arrêter le test et revenir à l\'état précédent, cliquez sur Arrêter le test.    Le graphique ci-dessous indique le pourcentage du débit de test qui est correctement reçu par la platine. Il est mis à jour une fois par seconde avec les valeurs mesurées lors de la seconde écoulée. Le résultat de la dernière seconde mesurée ainsi que la moyenne à long terme ("Avg") sont également indiqués sur l\'afficheur de la platine durant le test.
	NL	Je laat nu een netwerk test lopen voor deze speler. Andere spelerstatistieken zijn nu uitgeschakeld. Je kunt de testsnelheid wijzigen door hierboven een andere testsnelheid te kiezen. Om de test te stoppen en terug te keren naar de andere spelerstatistieken selecteer je Stop test hierboven.  <br>  De grafiek hieronder toont het percentage van de testsnelheid dat succesvol is verstuurd naar de speler. Elke seconde wordt het resultaat van de laatste seconde bijgewerkt. Het resultaat van de laatste seconde en het resultaat over een langere periode worden ook getoond op het scherm van de speler. Laat de test een tijdje lopen op een gekozen testsnelheid. De grafiek zal registreren hoe frequent de netwerksnelheid onder de 100% komt.

PLUGIN_HEALTH_NETTEST_DESC3
	EN	The highest test rate which achieves 100% indicates the maximum rate you can stream at.  If this is below the bitrate of your files you should consider configuring bitrate limiting for this player.<p>A Squeezebox2/3 attached to a wired network should be able to achieve at least 3000 kbps at 100% (Squeezebox1 1500 kbps).  A player attached to a wireless network may also reach up to this rate depending on your wireless network.  Rates significantly below this indicate poor network performance.  Wireless networks may record occasional lower percentages due to interference.  Use the graph above to understand how your network performs.  If the rate drops frequently you should investigate your network.
	FR	La valeur de débit de test la plus élevée à atteindre 100 % est le débit le plus élevé auquel votre équipement peut assurer la Diffusion à distance. Si cette valeur est inférieure au débit d\'encodage de vos fichiers audio, il est préférable de modifier la Limite de transcodage pour cette platine.    Notez qu\'une Squeezebox2/3 connectée à un réseau filaire doit normalement atteindre au moins 3000 Kbps à 100 % (1500 Kbps pour une Squeezebox1). Une platine connectée à un réseau sans-fil peut théoriquement atteindre ces mêmes valeurs, hors baisse de débit dûes à des interférences, si votre réseau est correctement configuré. Des taux nettement inférieurs indiquent probablement un problème réseau.
	NL	De hoogste testsnelheid waar je 100% haalt is de maximale snelheid waarmee je een stream kunt sturen. Als dit onder de bitrate is van je bestanden moet je overwegen om een bitrate limiet in te stellen.  <br> Een Squeezebox2/3 verbonden via een bedraad netwerk moet op zijn minst 3000 kbps op 100% halen (Squeezebox 1 1500 kbps). Een speler gekoppeld aan een draadloos netwerk kan ook deze snelheid halen, afhankelijk van je draadloze netwerk. Snelheden die significant onder de bovenstaande waarden liggen wijzen op een slechte netwerkperformance. Draadloze netwerken kunnen af en toe lagere percentages geven door interferentie. Gebruik de bovenstaande grafiek om na te gaan hoe je netwerkperformance is. Als de snelheid regelmatig laag is moet je het netwerk controleren.

PLUGIN_HEALTH_NETTEST_PLAYERNOTSUPPORTED
	EN	Network tests are not supported on this player.
	FR	Les tests réseau ne sont pas supportés par cette platine.
	NL	Netwerk testen zijn niet ondersteund op deze speler.

PLUGIN_HEALTH_NETTEST_CURRENTRATE
	EN	Current Test Rate
	FR	Débit de test actif
	NL	Huidige testsnelheid

PLUGIN_HEALTH_NETTEST_TESTRATE
	EN	Test Rate
	FR	Débit de test
	NL	Testsnelheid

PLUGIN_HEALTH_NETTEST_STOPTEST
	EN	Stop Test
	FR	Arrêter le test
	NL	Stop test

PLUGIN_HEALTH_PERF_SUMMARY
	EN	Performance Summary
	FR	Résumé
	NL	Prestatie samenvatting

PLUGIN_HEALTH_PERF_SUMMARY_DESC
	EN	Please queue up several tracks to play on this player and start them playing.  Then press the Reset link below to clear the statistics and update this display.
	FR	Ajoutez plusieurs morceaux à la liste de lecture de cette platine et jouez-les, puis cliquez sur le bouton Réinitialiser ci-dessus pour mettre à jour les statistiques.
	NL	Selecteer verschillende liedjes om achter elkaar af te spelen op deze speler en start het spelen.<BR> Druk dan op de Reset link hieronder om de statistieken leeg te maken en weer bij te werken.

PLUGIN_HEALTH_PERF_RESET
	EN	Reset
	FR	Réinitialiser

PLUGIN_HEALTH_SUMMARY
	EN	Summary
	ES	Sumario
	FR	Résumé
	NL	Samenvatting

PLUGIN_HEALTH_WARNINGS
	EN	Warnings
	ES	Advertencias
	FR	Alertes
	NL	Waarschuwingen

PLUGIN_HEALTH_PERF_STATISTICS
	EN	Performance Statistics
	FR	Statistiques performance
	NL	Prestatiestatistieken

PLUGIN_HEALTH_PLAYER
	EN	Player Statistics
	FR	Statistiques platine
	NL	Speler statistieken

PLUGIN_HEALTH_SERVER
	EN	Server Statistics
	FR	Statistiques serveur
	NL	Server statistieken

PLUGIN_HEALTH_OK
	EN	OK

PLUGIN_HEALTH_CONGEST
	EN	Congested
	ES	Congestionado
	FI	Ruuhkautunut
	FR	Engorgée
	NL	Congestie

PLUGIN_HEALTH_FAIL
	EN	Fail
	ES	Falla
	FR	Erreur
	NL	Gefaald

PLUGIN_HEALTH_INACTIVE
	EN	Inactive
	ES	Inactivo
	FI	Ei aktiivinen
	FR	Pas activé
	IT	Inattivo
	NL	Inactief

PLUGIN_HEALTH_CONTROLCONGEST_DESC
	EN	The control connection to this player has experienced congestion.  This usually is an indication of poor network connectivity (or the player being recently being disconnected from the network).
	ES	La conexión de control a este reproductor ha experimentado congestión. Esto generalmente es indicador de una mala conectividad en la red (también puede deberse a que el reproductor se desconectó recientemente de la red).
	FR	La connexion de contrôle de cette platine est engorgée. Ceci est généralement dû à une mauvaise connectivité du réseau ou à une déconnexion de la platine.
	HE	הקישור בין הנגן לשרת נקטע מספר פעמים. בדוק רשת
	NL	De controleconnectie naar deze speler heeft last gehad van congestie. Dit is meestal een indicatie van een slechte netwerkconnectie (of een speler die recent van het netwerk losgekoppeld is geweest).

PLUGIN_HEALTH_CONTROLFAIL_DESC
	EN	There is no currently active control connection to this player.  Please check the player is powered on.  If the player is unable to establish a connection, please check your network and and/or server firewall do not block connections to TCP & UDP port 3483.
	ES	No existe una conexión de control activa a este reproductor. Por favor, verificar que el reproductor esté encendido. Si el reproductor no puede establecer una conexión,  por favor, verificar que la red y/o el firewall del servidor no estén bloqueando las conexiones TCP y UDP  en el puerto 3483.
	FR	Il n\'y a actuellement aucune connexion de contrôle active pour cette platine. Vérifiez que la platine est en marche. Si la connexion de la platine est impossible, vérifiez l\'intégrité de votre réseau et/ou que votre pare-feu ne bloque pas les ports TCP et UDP 3483.
	HE	הנגן לא מחובר. בדוק אם הוא מחובר לחשמל
	NL	Er is momenteel geen actieve controleconnectie naar deze speler. Controleer of de speler aan staat. Controleer of je netwerk en/of server firewall geen connecties blokkeren naar TCP & UDP poort 3483 als je speler geen connectie kan maken.

PLUGIN_HEALTH_STREAMINACTIVE_DESC
	EN	There is currently no active connection for streaming to this player.  A connection is required to stream a file to your player.  Squeezebox2/3 may close the streaming connection towards the end of a track once it is transfered to the buffer within the player.  This is not cause for concern.<p>If you experiencing problems playing files and never see an active streaming connection, then this may indicate a network problem.  Please check that your network and/or server firewall do not block connections to TCP port 9000.
	FR	Il n\'y a actuellement aucune connexion de flux active pour cette platine. Une connexion de flux est requise lors de la lecture d\'un fichier depuis le serveur (mais pas lors de la lecture d\'un flux distant sur une Squeezebox2).    Si vous tentez de lire un fichier local sur cette platine, ceci indique un problème réseau. Vérifiez l\'intégrité de votre réseau et/ou que votre pare-feu ne bloque pas le port TCP 9000.
	NL	Er is op dit moment geen actieve connectie voor het streamen naar deze speler. Een connectie is altijd nodig om bestanden te spelen vanaf de server (maar niet als je een radiostream op afstand gebruikt bij een Squeezebox2 of 3)  <br>  Als je een lokaal bestand probeert af te spelen dan wijst dit op een netwerkprobleem. Controleer of je netwerk en/of server firewall niet TCP poort 9000 blokkeren.

PLUGIN_HEALTH_SIGNAL_INTERMIT
	EN	Good, but Intermittent Drops
	ES	Buena, pero con Cortes Intermitentes
	FI	Hyvä, mutta satunnaisia katkoja
	FR	OK, erreurs intermittentes
	NL	Goed maar af en toe haperingen

PLUGIN_HEALTH_SIGNAL_INTERMIT_DESC
	EN	The signal strength received by this player is normally good, but occasionally drops.  This may be caused by other wireless networks, cordless phones or microwaves nearby.  If you hear occasional audio dropouts on this player, you should investigate what is causing drops in signal strength.
	ES	La energía de la señal recibida por este reproductor es normalmente buena, pero con cortes ocasionalmente. Esto puede estar causado por otras redes inalámbricas, teléfonos inalámbricos u hornos de microondas cercanos. Si se escuchan interrupciones de audio ocasionales en este reproductor, se debería investigar cuál es la causa de las caídas en la energía de la señal.
	FR	Le signal reçu par cette platine est normal, mais s\'interrompt par intermittence, ce qui peut causer des coupures audio. Ce problème peut être dû à la présence d\'autres réseaux sans fil ou d\'appareils tels que téléphones sans fil ou fours micro-ondes.
	NL	De signaalsterkte ontvangen door de speler is goed met af en toe haperingen. De oorzaak kunnen andere draadloze netwerken zijn, draadloze telefoons of magnetrons die dichtbij zijn. Als je haperingen hoort in de audio moet je de oorzaak onderzoeken van de haperingen in de signaalsterkte.

PLUGIN_HEALTH_SIGNAL_POOR
	EN	Poor
	ES	Pobre
	FR	Faible
	NL	Matig

PLUGIN_HEALTH_SIGNAL_POOR_DESC
	EN	The signal strength received by this player is poor for significant periods, please check your wireless network.
	ES	La energía de la señal recibida por este reproductor es pobre durante períodos importantes, por favor verificar la red inalámbrica.
	FR	Le signal reçu par cette platine est anormalement faible pendant de longues périodes. Vérifiez votre réseau sans fil.
	NL	De signaalsterkte ontvangen door de speler is matig over een langere periode. Controleer je draadloze netwerk.

PLUGIN_HEALTH_SIGNAL_BAD
	EN	Bad
	ES	Mala
	FR	Mauvais
	FI	Huono
	NL	Slecht

PLUGIN_HEALTH_SIGNAL_BAD_DESC
	EN	The signal strength received by this player is bad for significant periods, please check your wireless network.
	ES	La energía de la señal recibida por este reproductor es mala durante períodos importantes, por favor verificar la red inalámbrica.
	FR	Le signal reçu par cette platine est anormalement faible pendant de longues périodes. Vérifiez votre réseau sans fil.
	NL	De signaalsterkte ontvangen door je speler is slecht over een  aanzienlijke periode. Controleer je draadloze netwerk.

PLUGIN_HEALTH_CONTROL
	EN	Control Connection
	ES	Conexión de Control
	FI	Hallintayhteys
	FR	Connexion de contrôle
	NL	Controleconnectie

PLUGIN_HEALTH_STREAM
	EN	Streaming Connection
	ES	Conexión para Streaming
	FR	Connexion de flux
	NL	Streaming connectie

PLUGIN_HEALTH_SIGNAL
	EN	Signal Strength
	FR	Signal de la platine
	NL	Signaalsterkte

PLUGIN_HEALTH_BUFFER_LOW
	EN	Low
	ES	Bajo
	FI	Matala
	FR	Bas
	NL	Laag

PLUGIN_HEALTH_BUFFER_LOW_DESC1
	EN	The playback buffer for this player is occasionally falling lower than ideal.  This may result in audio dropouts especually if you are streaming as WAV/AIFF.  If you are hearing these, please check your network signal strength and server response times.
	ES	El buffer de reproducción de este reproductor tiene, ocasionalmente, niveles por debajo del ideal. Esto puede producir interrupciones en el audio, especialmente si se está transmitiendo en formato WAV/AIFF. Si se escuchan estos, por favor, controlar la potencia de señal de red y los tiempos de respuesta del servidor.
	FR	Le tampon de lecture de cette platine tombe occasionnellement à un niveau plus bas que la normale, ce qui peut générer des pertes audio, notamment avec un flux WAV/AIFF. Si ce problème se produit, vérifiez l\'intégrité de votre réseau ainsi que le temps de réponse du serveur.
	HE	לנגן יש בעיות לקבל מידע מהשרת. בדוק רשת
	NL	De afspeelbuffer van deze speler is af en toe minder gevuld dan in de ideale situatie. Dit kan resulteren in audio haperingen, zeker als je WAV/AIFF streamt. Controleer de netwerksignaalsterkte en de snelheid waarmee de server reageert als je haperingen hoort.

PLUGIN_HEALTH_BUFFER_LOW_DESC2
	EN	The playback buffer for this player is occasionally falling lower than ideal.  This is a Squeezebox2/3 and so the buffer fullness is expected to drop at the end of each track.  You may see this warning if you are playing lots of short tracks.  If you are hearing audio dropouts, please check our network signal strength.
	ES	El buffer de reproducción de este reproductor tiene, ocasionalmente, niveles por debajo del ideal. Este es un Squeezebox2/3 y por lo tanto es esperable que el buffer se vacíe al final de cada pista. Se puede recibir esta advertencia si se están reproduciendo muchas pistas de corta duración. Si se escuchan interrupciones de audio, por favor, controlar la potencia de señal de red.
	FR	Le tampon de lecture de cette platine tombe occasionnellement à un niveau plus bas que la normale. La platine étant une Squeezebox2, il est normal que le tampon se vide à la fin de chaque morceau. Il est possible que cette alerte apparaisse si vous jouez un grand nombre de morceaux courts. Si le flux audio s\'interrompt, vérifiez l\'intégrité de votre réseau.
	HE	לנגן יש בעיות לקבל מידע מהשרת. בדוק רשת
	NL	De afspeelbuffer van deze speler is af en toe minder gevuld dan in de ideale situatie. Dit is een Squeezebox2. Daar mag het bufferniveau laag zijn aan het einde van een liedje. Je kunt deze waarschuwing krijgen als je veel korte liedjes afspeelt. Controleer de netwerksignaalsterkte als je haperingen hoort in het geluid.

PLUGIN_HEALTH_BUFFER
	EN	Buffer Fullness
	ES	Llenado del Buffer
	FI	Puskurin täyttöaste
	FR	Remplissage du tampon
	NL	Bufferniveau

PLUGIN_HEALTH_SLIMP3_DESC
	EN	This is a SLIMP3 player.  Full performance measurements are not available for this player.
	ES	Este es un reproductor SLIMP3. Medidas completas de perfomance no están disponibles para este reproductor.
	FR	Cette platine est un SLIMP3 ; toutes les fonctions de mesure de performances ne sont pas disponibles.
	NL	Dit is een Slimp3 speler. Volledige prestatiemonitoring is niet beschikbaar voor deze speler.

PLUGIN_HEALTH_NO_PLAYER_DESC
	EN	Slimserver cannot find a player.  If you own a player this could be due to your network blocking connection between the player and server.  Please check your network and/or server firewall does not block connection to TCP & UDP port 3483.
	ES	Slimserver no puede encontrar ningón reproductor. Si existe un reproductor esto puede deberse a bloqueos de conexión de red entre el servidor y el reproductor. Por favor, verificar que la red y/o el firewall del servidor no estén bloqueando las conexiones TCP y UDP en el puerto 3483.
	FR	Le SlimServer ne trouve pas de platine connectée. Vérifiez que votre réseau permet la connexion entre le serveur et la platine et que votre pare-feu ne bloque pas les ports TCP et UDP 3483.
	HE	השרת לא מוצא נגן, בדוק רשת וחומת אש
	NL	SlimServer kan geen speler vinden. Als je een speler hebt kan dit komen door een netwerk dat connecties blokkeert tussen de speler en server. Controleer of je netwerk en/of server firewall niet TCP & UDP poort 3483 blokkeert.

PLUGIN_HEALTH_RESPONSE
	EN	Server Response Time
	ES	Tiempo de Respuesta del Servidor
	FR	Réponse du serveur
	NL	Serverreactietijd

PLUGIN_HEALTH_RESPONSE_INTERMIT
	EN	Occasional Poor Response
	ES	Ocasionalmente Respuesta Pobre
	FI	Satunnaista huonoa vastetta
	FR	Faible par intermittence
	NL	Af en toe slechte reactietijd

PLUGIN_HEALTH_RESPONSE_INTERMIT_DESC
	EN	Your server response time is occasionally longer than desired.  This may cause audio dropouts, especially on Slimp3 and Squeezebox1 players.  It may be due to background load on your server or a slimserver task taking longer than normal.
	ES	El tiempo de respuesta del servidor es ocasionalmente más alto que el deseado. Esto puede causar interrupciones audio, especialmente en los reproductores Slimp3 y Squeezebox1. Puede deberse a una carga de procesos de fondo, o a que una tarea de Slimserver está tomando más tiempo que el normal.
	FR	Le temps de réponse du serveur est anormalement élevé par intermittence, ce qui peut causer des coupures audio, notamment avec un SLIMP3 ou une Squeezebox1. Ceci peut être causé par une charge élevée ou une opération complexe sur le serveur.
	HE	זמן התגובה של השרת ארוך מהרצוי, בדוק אם השרת עמוס
	NL	De serverreactietijd is af en toe lager dan gewenst. Dit kan audio haperingen veroorzaken, zeker bij de Slimp3 en Squeezebox1 spelers. De oorzaak kunnen de overige programma\'s zijn die op je server draaien of een SlimServer taak die langer duurt dan normaal.

PLUGIN_HEALTH_RESPONSE_POOR
	EN	Poor Response
	ES	Respuesta Pobre
	FI	Huono vaste
	FR	Faible
	NL	Slechte reactietijd

PLUGIN_HEALTH_RESPONSE_POOR_DESC
	EN	Your server response time is regularly falling below normal performance levels.  This may lead to audio dropouts, especially on Slimp3 and Squeezebox1 players.  Please check the performance of your server.  If this is OK, then check slimserver is not running intensive tasks (e.g. scanning music library) or a Plugin is not causing this.
	ES	El tiempo de respuesta del servidor es regularmente más bajo que los niveles de perfomance normales. Esto puede causar interrupciones de  audio, especialmente en los reproductores Slimp3 y Squeezebox1. Por favor, verificar la perfomance del servidor. Si esto está OK, entonces verificar que Slimserver no está corriendo tareas intensivas (por ej. recopilando la colección musical) o que algón plugin no está causando esto.
	FR	Le temps de réponse du serveur est anormalement élevé, ce qui peut causer des coupures audio, notamment avec un SLIMP3 ou une Squeezebox1. Vérifiez les performances de votre serveur. Si celles-ci sont normales, assurez-vous qu\'un module d\'extension ou une tâche complexe (comme le répertoriage de la bibliothèque musicale) n\'est pas à l\'origine du problème.
	HE	זמן התגובה של השרת ארוך מהרצוי, בדוק אם השרת עמוס
	NL	De serverreactietijd is regelmatig lager dan gewenst. Dit kan audio haperingen veroorzaken, zeker bij de Slimp3 en Squeezebox1 spelers. Controleer de prestatie van je server. Is die goed, controleer dan of SlimServer geen intensieve taken draait (zoals scannen van de muziekcollectie) of dat een plugin dit veroorzaakt.

PLUGIN_HEALTH_NORMAL
	EN	This player is performing normally.
	ES	Este reproductor está funcionando normalmente.
	FI	Tämä soitin toimii normaalisti.
	FR	Les performances de cette platine sont normales.
	NL	Deze speler functioneert normaal.

PLUGIN_HEALTH_REFRESH
	EN	Refresh
	FR	Actualiser
	NL	Ververs

PLUGIN_HEALTH_CLEAR
	EN	Clear
	FR	Réinitialiser
	NL	Legen

PLUGIN_HEALTH_CLEAR_ALL
	EN	Clear All
	FR	Réinitialiser tout
	NL	Leeg alles

PLUGIN_HEALTH_SET
	EN	Set
	FR	Modifier
	NL	Instellen

PLUGIN_HEALTH_SET_ALL
	EN	Set All
	FR	Modifier tout
	NL	Alles instellen

PLUGIN_HEALTH_WARNING_THRESHOLDS
	EN	Warning Thresholds
	FR	Seuils d\'alerte
	NL	Waarschuwingsniveau

PLUGIN_HEALTH_LOW
	EN	Low
	FR	Bas
	NL	Laag

PLUGIN_HEALTH_HIGH
	EN	High
	FR	Haut
	NL	Hoog

PLUGIN_HEALTH_BT
	EN	Backtrace
	FR	Traçage
	NL	Terugtraceren

PLUGIN_HEALTH_GRAPHS_DESC_PLAYER
	EN	The server is currently collecting performance statistics for this player.  
	FR	Le serveur est actuellement en train de collecter des statistiques de performance pour cette platine.
	NL	De server is op dit moment bezig om de prestatiegegevens op te halen voor deze speler.

PLUGIN_HEALTH_GRAPHS_DESC_SERVER
	EN	The server is currently collecting performance statistics for various internal server functions.  These graphs are intended to be used to help diagnose performance issues with the server and its plugins.
	FR	Le serveur est actuellement en train de collecter des statistiques de performance pour différentes fonctions internes du serveur. Ces graphiques permettent de diagnostiques d\'éventuels problèmes de performance avec le serveur et/ou les modules d\'extension.
	NL	De server is nu bezig om de prestatiegegevens te verzamelen voor diverse interne server functies. <BR>Deze grafieken zijn bedoeld om te helpen bij het analyseren van prestatieproblemen van de server en de plugins.

PLUGIN_HEALTH_WARNING_DESC
	EN	You may set warning thresholds for each measurement.  This will record in the server log whenever the threshold is exceeded.  The most recent log entries can be viewed <a href="/log.txt" target="log"><u>here</u></a>.
	FR	Vous pouvez fixer des seuils d\'alerte pour chaque mesure. Ceux-ci seront enregistrés dans le log du serveur s\'ils sont atteints. Vous pouvez visualiser le contenu le plus récent du log <a href="/log.txt">ici</a>.
	NL	Je kunt waarschuwingsniveaus instellen voor elke meetinstelling. Vervolgens wordt bijgehouden in de server log wanneer een waarschuwingsniveau is overschreden. <BR>De meest recente log kun je <a href="/log.txt" target="log"><u>hier</u></a> bekijken.

PLUGIN_HEALTH_SIGNAL_DESC
	EN	This graph shows the strength of the wireless signal received by your player.  Higher signal strength is better.  The player reports signal strength while it is playing.
	ES	Este gráfico muestra la energía de la señal inalámbrica recibida por tu reproductor. Un valor alto de energía es mejor.El reproductor reporta la energía de la señal mientras está reproduciendo.
	FR	Ce graphique montre la puissance du signal sans fil reçu par la platine lorsque celle-ci est en lecture.
	NL	Deze grafiek toont de signaalsterkte van je draadloze netwerk zoals ontvangen door je speler. Hogere signaalsterkte is beter. De speler rapporteert de signaalsterkte tijdens het afspelen.

PLUGIN_HEALTH_BUFFER_DESC
	EN	This graph shows the fill of the player\'s buffer.  Higher buffer fullness is better.  Note the buffer is only filled while the player is playing tracks.<p>Squeezebox1 uses a small buffer and it is expected to stay full while playing.  If this value drops to 0 it will result in audio dropouts.  This is likely to be due to network problems.<p>Squeezebox2/3 uses a large buffer.  This drains to 0 at the end of each track and then refills for the next track.  You should only be concerned if the buffer fill is not high for the majority of the time a track is playing.<p>Playing remote streams can lead to low buffer fill as the player needs to wait for data from the remote server.  This is not a cause for concern.
	ES	Este gráfico muestra el llenado del buffer del reproductor. Cuanto más lleno esté mejor es. Notar que el buffer solo se llena cuando el reproductor está reproduciendo pistas.    Squeezebox1 utiliza un buffer pequeño y se espera que permanezca lleno mientras se reproduce. Si este valor cae a 0 se producirán interrupciones en el audio. Esto se debe muy probablemente a problemas de red.    Squeezebox2/3 utiliza un buffer grande. Este se vacía (vuelve a 0) al final de cada pista y luego se llena nuevamente para la próxima pista. Solo debería precupar el caso en que el llenado del buffer no tiene un nivel alto durante la mayoría del tiempo en que se esta reproduciendo una pista.    El reproducir streams remotos puede producir que el buffer tenga un nivel de llenado bajo, ya que el reproductor necesitas esperar que lleguen datos del servidor remoto. Esto no es causa para preocuparse.
	FR	Ce graphique montre le taux de remplissage du tampon de la platine. Plus le tampon est rempli, moins le flux audio risque d\'être interrompu. Notez que le tampon n\'est rempli que lors de la lecture.    La Squeezebox1 utilise un tampon réduit qui reste normalement rempli durant toute la lecture. Si le taux de remplissage tombe à 0, typiquement à cause d\'un problème réseau, le flux audio sera interrompu.    La Squeezebox2 utilise un tampon plus important, qui se vide à la fin de chaque morceau et se remplit à nouveau au début du suivant. Un taux de remplissage fluctuant est donc normal.    La lecture de flux à distance peut générer des taux de remplissage du tampon peu élevés lorsque la platine est en attente de données de la part du serveur distant ; ce comportement est normal.
	HE	תצוגה גרפית של סטטיסטיקות
	NL	Deze grafiek toont bufferniveau. Hoger niveau is beter. De buffer is alleen gevuld tijdens het afspelen van muziek.  <br>Squeezebox1 gebruikt een kleine buffer die normaal gesproken altijd vol is. Als het niveau naar 0 gaat zal er hapering in het geluid optreden. Dit komt vaak door netwerkproblemen.  <br>Squeezebox2/3 gebruikt een grote buffer. Hier loopt het bufferniveau naar 0 toe aan het einde van een liedje en vult zich weer aan het begin van het volgende liedje. Alleen als de buffer de meeste tijd niet gevuld is tijdens het spelen moet je actie nemen.  <br>Het spelen van streams op afstand (Internet radio) geeft een laag bufferniveau omdat de speler moet wachten op de server op afstand. Dit is geen gevolg van problemen.

PLUGIN_HEALTH_CONTROL_DESC
	EN	This graph shows the number of messages queued up to send to the player over the control connection.  A measurement is taken every time a new message is sent to the player.  Values above 1-2 indicate potential network congestion or that the player has become disconnected.
	ES	Esta gráfico muestra el nómero de mensajes encolados para ser enviados al reproductor sobre la conexión de control. Una medición se toma cada vez que un nuevo mensaje es enviado hacia el reproductor. Los valores mayores a 1-2 indican una congestión potencial de la red o que el reprodcutor se ha desconectado.
	FR	Ce graphique montre le nombre de messages de contrôle à envoyer à la platine. La valeur est mise à jour à chaque nouveau message de contrôle. Une valeur supérieure à 1 ou 2 peut indiquer un problème d\'engorgement du réseau ou une perte de connexion avec la platine.
	HE	אם הערכים בגרף הם מעל 1 או 2 בדוק רשת
	NL	Deze grafiek toont de hoeveelheid boodschappen in de rij gezet om te versturen naar de speler over de controleconnectie. Bij elke verstuurde boodschap wordt een meting gedaan. Waarden boven 1-2 geven een potentieel een netwerkcongestie aan of dat de speler losgekoppeld is van het netwerk.

PLUGIN_HEALTH_RESPONSE_DESC
	EN	The response time of the server - the time between successive calls to select.  
	FR	Ce graphique montre le laps de temps en secondes nécessaire au serveur pour répondre aux instructions de la ou des platine(s) connectée(s). Plus la valeur est basse, plus le serveur est réactif. Des valeurs supérieures à 1 seconde sont susceptibles d\'altérer les performances audio.    Les temps de réponse trop élevés peuvent être le résultat d\'autres tâches ou de tâches complexes en cours d\'éxécution sur le serveur.
	NL	De responstijd van de server. De tijd tussen de successievelijk te selecteren calls.

PLUGIN_HEALTH_SELECTTASK
	EN	Select Task Duration
	FR	Durée tâche sélectionnée
	NL	Selecteer taakduur

PLUGIN_HEALTH_SELECTTASK_DESC
	EN	The length of time taken by each task run by select.
	FR	La durée écoulée pour chaque tâche sélectionnée.
	NL	De lengte in tijd die elke geselecteerde taak neemt.

PLUGIN_HEALTH_SCHEDULERTASK
	EN	Scheduler Task Duration
	FR	Durée tâche planifiée
	NL	Taakplanner taakduur

PLUGIN_HEALTH_SCHEDULERTASK_DESC
	EN	The length of time taken by each scheduled task.
	FR	La durée écoulée pour chaque tâche planifiée.
	NL	De lengte in tijd die elke geplande taak neemt.

PLUGIN_HEALTH_TIMERTASK
	EN	Timer Task Duration
	FR	Durée tâche automatique
	NL	Timertaakduur

PLUGIN_HEALTH_TIMERTASK_DESC
	EN	The length of time taken by each timer task.
	FR	La durée de chaque tâche automatique.
	NL	De lengte in tijd genomen door elke timertaak.

PLUGIN_HEALTH_TIMERLATE
	EN	Timer Lateness
	FR	Précision de la programmation
	NL	Timerlaatheid

PLUGIN_HEALTH_TIMERLATE_DESC
	EN	The time between when a timer task was scheduled and when it is run.
	FR	Le SlimServer utilise un mécanisme de programmation pour déclencher certaines tâches, comme la mise à jour de l\'interface utilisateur. Ce graphique montre le décalage en secondes entre le déclenchement programmé d\'une tâche et son déclenchement réel.    Deux tâches programmées ne pouvant s\'éxécuter simultanément, il est possible que certaines tâches soient déclenchées par le serveur après un délai d\'attente. Si celui-ci est trop important, la réactivité de l\'interface utilisateur peut en être affectée.
	NL	De tijd tussen wanneer een timer taak was gepland en was uitgevoerd.

PLUGIN_HEALTH_REQUEST
	EN	Execute / Notification Task Duration
	FR	Durée exécution/notification
	NL	Uitvoeren / notificatie taakduur

PLUGIN_HEALTH_REQUEST_DESC
	EN	The length of time taken by each execute command or notification callback.
	FR	La durée écoulée pour chaque commande d\'exécution ou rappel de notification.
	NL	De lengte van de tijd bij elk uitgevoerde commando of terugroepnotificatie.

PLUGIN_HEALTH_PAGEBUILD
	EN	Web Page Build
	FR	Génération page web
	NL	Web pagina opbouw

PLUGIN_HEALTH_PAGEBUILD_DESC
	EN	The length of time taken to build each web page.
	FR	La durée écoulée pour générer chaque page web.
	NL	De tijd nodig om een webpagina op te bouwen.

PLUGIN_HEALTH_IRQUEUE
	EN	IR Queue Length
	FR	Taille queue IR
	NL	Infrarood (IR) rij lengte

PLUGIN_HEALTH_IRQUEUE_DESC
	EN	The delay between an IR key press being received and being processed.
	FR	Le délai entre l\'émision d\'une commande infrarouge et son exécution.
	NL	Vertraging tussen een infrarood (IR) toetsdruk ontvangen en het verwerkt zijn.

PLUGIN_HEALTH_DBACCESS
	EN	Database Access
	FR	Accès base de données
	NL	Database toegang

PLUGIN_HEALTH_DBACCESS_DESC
	EN	The time taken for information to be retrieved from the database.
	FR	Le temps écoulé pour accéder à une information depuis la base de données.
	NL	De tijd om informatie op te halen uit de database.

PLUGIN_HEALTH_PROCTEMPLATE
	EN	Process Template
	FR	Exécution Template
	NL	Proces sjabloon

PLUGIN_HEALTH_PROCTEMPLATE_DESC
	EN	The time to process each Template Toolkit template when building web pages.
	FR	La durée d\'exécution de chaque Template Toolkit lors de la génération d\'une page web.
	NL	De tijd om elk gereedschapsjabloon uit te voeren bij het opbouwen van webpagina\'s.
'
}

1;

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
