package Slim::Plugin::Webcasters::Plugin::SkyFM;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased Slim::Plugin::Webcasters::Plugin);

sub feed { 'http://www.slimdevices.com/picks/split/SKY.fm.opml' }

sub initPlugin {
	my $class = shift;

	# Will call OPMLBased's initPlugin method
	$class->SUPER::initPlugin(
		tag    => 'webcaster_skyfm',
		menu   => 'radios',
		weight => 170,
	);
}

sub getDisplayName { 'PLUGIN_WEBCASTERS_SKYFM' }

sub playerMenu { 'RADIO' }

# Use the Webcaster plugin data
sub _pluginDataFor {
	my $class = shift;
	return Slim::Plugin::Webcasters::Plugin->_pluginDataFor(@_);
}

1;