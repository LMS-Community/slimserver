package Slim::Plugin::Webcasters::Plugin::DIFM;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased Slim::Plugin::Webcasters::Plugin);

sub feed { 'http://www.slimdevices.com/picks/split/DI.fm%20-%20Digitally%20Imported.opml' }

sub initPlugin {
	my $class = shift;

	# Will call OPMLBased's initPlugin method
	$class->SUPER::initPlugin(
		tag    => 'webcaster_difm',
		menu   => 'radios',
		weight => 130,
	);
}

sub getDisplayName { 'PLUGIN_WEBCASTERS_DIFM' }

sub playerMenu { 'RADIO' }

# Use the Webcaster plugin data
sub _pluginDataFor {
	my $class = shift;
	return Slim::Plugin::Webcasters::Plugin->_pluginDataFor(@_);
}

1;