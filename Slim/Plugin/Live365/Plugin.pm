package Slim::Plugin::Live365::Plugin;

# $Id$

# Browse Live365 via SqueezeNetwork

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Networking::SqueezeNetwork;
use Slim::Player::ProtocolHandlers;
use Slim::Plugin::Live365::ProtocolHandler;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.live365',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_LIVE365_MODULE_NAME',
} );

sub initPlugin {
	my $class = shift;
	
	Slim::Player::ProtocolHandlers->registerHandler(
		live365 => 'Slim::Plugin::Live365::ProtocolHandler'
	);
	
	$class->SUPER::initPlugin(
		feed   => Slim::Networking::SqueezeNetwork->url('/api/live365/v1/opml'),
		tag    => 'live365',
		is_app => 1,
	);

	Slim::Player::ProtocolHandlers->registerIconHandler(
		qr/mysqueezebox\.com.*\/live365\//, 
		sub { return $class->_pluginDataFor('icon'); }
	);
}

sub getDisplayName {
	return 'PLUGIN_LIVE365_MODULE_NAME';
}

# Don't add this item to any menu
sub playerMenu { }

1;
