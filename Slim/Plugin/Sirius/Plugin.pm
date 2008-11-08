package Slim::Plugin::Sirius::Plugin;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Plugin::Sirius::ProtocolHandler;
use Slim::Networking::SqueezeNetwork;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.sirius',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_SIRIUS_MODULE_NAME',
} );

sub initPlugin {
	my $class = shift;

	Slim::Player::ProtocolHandlers->registerHandler(
		sirius => 'Slim::Plugin::Sirius::ProtocolHandler'
	);
	
	$class->SUPER::initPlugin(
		feed   => Slim::Networking::SqueezeNetwork->url('/api/sirius/v1/opml'),
		tag    => 'sirius',
		menu   => 'radios',
		weight => 80,
	);
}

sub getDisplayName () {
	return 'PLUGIN_SIRIUS_MODULE_NAME';
}

1;
