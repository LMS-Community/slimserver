package Slim::Plugin::Picks::Plugin;

# $Id$

# Load Picks via an OPML file - so we can ride on top of the Podcast Browser

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Networking::SqueezeNetwork;

sub initPlugin {
	my $class = shift;

	Slim::Player::ProtocolHandlers->registerIconHandler(
		qr/(?:squeezenetwork|slimdevices)\.com.*\/picks\//, 
		sub { return $class->_pluginDataFor('icon'); }
	);

	$class->SUPER::initPlugin(
		feed   => Slim::Networking::SqueezeNetwork->url('/public/radio/picks'),
		tag    => 'picks',
		menu   => 'radios',
		weight => 10,
	);
}

sub getDisplayName {
	return 'PLUGIN_PICKS_MODULE_NAME';
}

1;
