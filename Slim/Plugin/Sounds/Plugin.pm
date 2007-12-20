package Slim::Plugin::Sounds::Plugin;

# $Id$

# Browse Sounds & Effects

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Networking::SqueezeNetwork;
use Slim::Player::ProtocolHandlers;
use Slim::Plugin::Sounds::ProtocolHandler;

sub initPlugin {
	my $class = shift;
	
	Slim::Player::ProtocolHandlers->registerHandler(
		loop => 'Slim::Plugin::Sounds::ProtocolHandler'
	);

	$class->SUPER::initPlugin(
		feed => Slim::Networking::SqueezeNetwork->url( '/api/sounds/v1/opml' ),
		tag  => 'sounds',
		menu => 'plugins',
	);
}

sub getDisplayName {
	return 'PLUGIN_SOUNDS_MODULE_NAME';
}

1;