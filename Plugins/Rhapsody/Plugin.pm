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
	my $action = shift;

	if ($device->modelName =~ /Rhapsody/) {
		
		my ($host, $port) = $device->location =~ m|//([0-9.]+):(\d+)|;
		
		if ( $action eq 'deviceAdded' ) {
			$ports->{ $host } = {
				'port'   => $port,
				'device' => $device,
			};
			$::d_plugins && msgf("Rhapsody: New server detected: %s (%s)\n",
				$device->friendlyName,
				$device->location,
			);
		}
		else {
			delete $ports->{ $host };
			$::d_plugins && msgf("Rhapsody: Server went away: %s (%s)\n",
				$device->friendlyName,
				$device->location,
			);
		}
		
		return ($device->friendlyName, 'Rhapsody');
	}
	
	return (undef, undef);
}

sub getPortForHost {
	my $host = shift;
	
	return $ports->{$host}->{'port'};
}

sub initPlugin {
	Slim::Player::ProtocolHandlers->registerHandler('rhap', 'Plugins::Rhapsody::ProtocolHandler');

	Slim::Utils::UPnPMediaServer::findServer(\&findCallback);
	
	# If Rhapsody crashes, it won't send out a byebye message, so we need to poll
	# periodically to see if all known servers are still alive
	Slim::Utils::Timers::setTimer( undef, time() + 60, \&checkServerHealth );
}

sub checkServerHealth {
	
	# Make an async HTTP request to all known servers to make sure they return 
	# a response.  Crashed servers will time out and be removed.
	for my $host ( keys %{$ports} ) {
		
		my $http = Slim::Networking::SimpleAsyncHTTP->new(
			sub {}, # we just ignore the response
			\&checkServerHealthError, 
			{
				'host'    => $host,
				'Timeout' => 5,
			}
		);
		$http->get( 'http://' . $host . ':' . $ports->{$host}->{'port'} );
	}
	
	Slim::Utils::Timers::setTimer( undef, time() + 60, \&checkServerHealth );
}

sub checkServerHealthError {
	my $http = shift;
	
	my $host   = $http->params('host');
	my $error  = $http->error;
	my $device = $ports->{$host}->{'device'};
	
	$::d_plugins && msg("Rhapsody server on $host failed to respond, removing. ($error)\n");
	
	# fake a message that the device has disconnected
	Slim::Utils::UPnPMediaServer::deviceCallback( undef, $device, 'deviceRemoved' );
}

sub shutdownPlugin {
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
