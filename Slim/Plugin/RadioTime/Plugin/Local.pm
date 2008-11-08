package Slim::Plugin::RadioTime::Plugin::Local;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased Slim::Plugin::RadioTime::Plugin);

sub baseURL { 'http://opml.radiotime.com/Group.aspx?type=location' }

sub initPlugin {
	my $class = shift;

	# Will call OPMLBased's initPlugin method
	$class->SUPER::initPlugin(
		tag    => 'local_radio',
		menu   => 'radios',
		weight => 20,
	);
}

sub getDisplayName { 'PLUGIN_RADIOTIME_LOCAL' }

sub playerMenu { 'RADIO' }

# Use the RadioTime plugin data
sub _pluginDataFor {
	my $class = shift;
	return Slim::Plugin::RadioTime::Plugin->_pluginDataFor(@_);
}

1;