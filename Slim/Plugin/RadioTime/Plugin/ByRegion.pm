package Slim::Plugin::RadioTime::Plugin::ByRegion;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased Slim::Plugin::RadioTime::Plugin);

sub baseURL { 'http://opml.radiotime.com/CategoryBrowse.aspx?type=location&title=Locations' }

sub initPlugin {
	my $class = shift;

	# Will call OPMLBased's initPlugin method
	$class->SUPER::initPlugin(
		tag    => 'region_radio',
		menu   => 'radios',
		weight => 60,
	);
}

sub getDisplayName { 'PLUGIN_RADIOTIME_BY_REGION' }

sub playerMenu { 'RADIO' }

# Use the RadioTime plugin data
sub _pluginDataFor {
	my $class = shift;
	return Slim::Plugin::RadioTime::Plugin->_pluginDataFor(@_);
}

1;