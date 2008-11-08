package Slim::Plugin::Webcasters::Plugin::AccuRadio;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased Slim::Plugin::Webcasters::Plugin);

sub feed { 'http://www1.accuradio.com/shoutcast/accuradio.opml' }

sub initPlugin {
	my $class = shift;

	# Will call OPMLBased's initPlugin method
	$class->SUPER::initPlugin(
		tag    => 'webcaster_accuradio',
		menu   => 'radios',
		weight => 110,
	);
}

sub getDisplayName { 'PLUGIN_WEBCASTERS_ACCURADIO' }

sub playerMenu { 'RADIO' }

# Use the Webcaster plugin data
sub _pluginDataFor {
	my $class = shift;
	return Slim::Plugin::Webcasters::Plugin->_pluginDataFor(@_);
}

1;