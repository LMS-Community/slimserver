package Slim::Plugin::Live365::Plugin;

# $Id$

# Browse Live365 via SqueezeNetwork

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Networking::SqueezeNetwork;
use Slim::Player::ProtocolHandlers;
use Slim::Plugin::Live365::ProtocolHandler;

sub initPlugin {
	my $class = shift;
	
	Slim::Player::ProtocolHandlers->registerHandler(
		live365 => 'Slim::Plugin::Live365::ProtocolHandler'
	);

	$class->SUPER::initPlugin(
		feed => Slim::Networking::SqueezeNetwork->url('/api/live365/v1/opml'),
		tag  => 'live365',
		menu => 'radio',
		'icon-id' => 'html/images/ServiceProviders/live365_56x56_p.png',
	);
}

sub getDisplayName {
	return 'PLUGIN_LIVE365_MODULE_NAME';
}

1;
