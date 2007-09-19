package Slim::Plugin::LMA::Plugin;

# $Id$

# Load Live Music Archive data via an OPML file - so we can ride on top of the Podcast Browser

use strict;
use base qw(Slim::Plugin::OPMLBased);

sub initPlugin {
	my $class = shift;
	
	$class->SUPER::initPlugin(
		feed => 'http://content.us.squeezenetwork.com:8080/lma/artists.opml',
		tag  => 'lma',
		menu => 'music_on_demand',
	);
}

sub getDisplayName {
	return 'PLUGIN_LMA_MODULE_NAME';
}

1;
