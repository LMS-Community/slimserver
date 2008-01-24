package Slim::Plugin::LMA::Plugin;

# $Id$

# Load Live Music Archive data via an OPML file - so we can ride on top of the Podcast Browser

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Networking::SqueezeNetwork;

sub initPlugin {
	my $class = shift;
	
	$class->SUPER::initPlugin(
		feed      => Slim::Networking::SqueezeNetwork->url( '/api/lma/v1/opml' ),
		tag       => 'lma',
		menu      => 'music_services',
		style     => 'albumcurrent',
		weight    => 50,
	);
}

sub getDisplayName {
	return 'PLUGIN_LMA_MODULE_NAME';
}

1;
