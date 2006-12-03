package Plugins::Rhapsody::Plugin;

# SlimServer Copyright (C) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Player::ProtocolHandlers;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Timers;
use Slim::Utils::UPnPMediaServer;
use Plugins::Rhapsody::ProtocolHandler;

# This holds a mapping between Rhapsody servers and dynamic port numbers
my $ports = {};

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.rhapsody',
	'defaultLevel' => 'WARN',
	'description'  => getDisplayName(),
});

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

			$log->info(sprintf("New server detected: %s (%s)",
				$device->getfriendlyname,
				$device->getlocation,
			));
		}
		else {
			delete $ports->{ $host };

			$log->info(sprintf("Server went away: %s (%s)",
				$device->getfriendlyname,
				$device->getlocation,
			));
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

1;


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
