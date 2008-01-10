package Slim::Plugin::Picks::Plugin;

# $Id$

# Load Picks via an OPML file - so we can ride on top of the Podcast Browser

use strict;
use base qw(Slim::Plugin::OPMLBased);

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(
		feed => 'http://www.slimdevices.com/picks/split/picks.opml',
		tag  => 'picks',
		menu => 'radios',
	);
}

sub getDisplayName {
	return 'PLUGIN_PICKS_MODULE_NAME';
}

1;
