package Plugins::Rhapsody::Plugin;

# SlimServer Copyright (C) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Player::ProtocolHandlers;
use Slim::Utils::Misc;
use Slim::Utils::Timers;
use Slim::Utils::UPnPMediaServer;
use Plugins::Rhapsody::ProtocolHandler;

# This holds a mapping between Rhapsody servers and dynamic port numbers
my $ports = {};

sub getDisplayName {
	return 'PLUGIN_RHAPSODY_MODULE_NAME';
}

sub enabled {
	return ($::VERSION ge '6.5');
}

sub getFunctions {
	return '';
}

sub findCallback {
	my $device = shift;
	my $event = shift;

	if ( $device->getmodelname =~ /Rhapsody/ ) {
		
		my ($host, $port) = $device->getlocation =~ m|//([0-9.]+):(\d+)|;
		
		if ( $event eq 'add' ) {
			$ports->{ $host } = {
				'port'   => $port,
				'device' => $device,
			};
			$::d_plugins && msgf("Rhapsody: New server detected: %s (%s)\n",
				$device->getfriendlyname,
				$device->getlocation,
			);
		}
		else {
			delete $ports->{ $host };
			$::d_plugins && msgf("Rhapsody: Server went away: %s (%s)\n",
				$device->getfriendlyname,
				$device->getlocation,
			);
		}
	}
	
	return;
}

sub getPortForHost {
	my $host = shift;
	
	return $ports->{$host}->{'port'};
}

sub initPlugin {
	unless ( $::noupnp ) {
		Slim::Player::ProtocolHandlers->registerHandler('rhap', 'Plugins::Rhapsody::ProtocolHandler');
	
		Slim::Utils::UPnPMediaServer::registerCallback( \&findCallback );
	}
}

sub strings {
	return "
PLUGIN_RHAPSODY_MODULE_NAME
	EN	Real Rhapsody

RHAPSODY
	EN	Rhapsody

PLUGIN_RHAPSODY_ERROR_UNAUTH
	DE	Rhapsody: Unberechtigte Anfrage.
	EN	Rhapsody: Unauthorized request.
	NL	Rhapsody: Verzoek niet toegestaan.

PLUGIN_RHAPSODY_ERROR_FORBIDDEN
	DE	Rhapsody: Verbotene Anfrage.
	EN	Rhapsody: Request forbidden.
	NL	Rhapsody: Verzoek niet toegestaan.
	
PLUGIN_RHAPSODY_ERROR_FILE_NOT_FOUND
	DE	Rhapsody: Datei nicht gefunden.
	EN	Rhapsody: File not found.
	NL	Rhapsody: Bestand niet gevonden.

PLUGIN_RHAPSODY_ERROR_BUSY
	DE	Rhapsody: Die Anwendung ist ausgelastet.
	EN	Rhapsody: Application is busy.
	NL	Rhapsody: Programma is bezig.

PLUGIN_RHAPSODY_ERROR_STALE
	DE	Rhapsody: Bitte überprüfen Sie die Anwendung.
	EN	Rhapsody: Session has timed out.
	NL	Rhapsody: Sessie time-out.

PLUGIN_RHAPSODY_ERROR_INTERNAL
	DE	Rhapsody: Interner Serverfehler, bitte überprüfen Sie die Rhapsody Anwendung.
	EN	Rhapsody: Internal server error, please check the Rhapsody application.
	NL	Rhapsody: Interne serverfout, controleer het Rhapsody programma.
";
}

1;


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
