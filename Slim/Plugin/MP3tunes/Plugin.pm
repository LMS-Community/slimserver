package Slim::Plugin::MP3tunes::Plugin;

# $Id$

# Browse MP3tunes via SqueezeNetwork

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Networking::SqueezeNetwork;

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(
		feed => Slim::Networking::SqueezeNetwork->url('/api/mp3tunes/opml'),
		tag  => 'mp3tunes',
		menu => 'music_on_demand',
	);
}

sub playerMenu () {
	return 'MUSIC_ON_DEMAND';
}

sub getDisplayName () {
	return 'PLUGIN_MP3TUNES_MODULE_NAME';
}

1;