package Slim::Plugin::RadioTime::Plugin::Talk;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased Slim::Plugin::RadioTime::Plugin);

sub baseURL { 'http://opml.radiotime.com/GroupList.aspx?type=channel&channel=talk' }

sub initPlugin {
	my $class = shift;

	# Will call OPMLBased's initPlugin method
	$class->SUPER::initPlugin(
		tag    => 'talk_radio',
		menu   => 'radios',
		weight => 40,
	);
}

sub getDisplayName { 'PLUGIN_RADIOTIME_TALK' }

sub playerMenu { 'RADIO' }

# Use the RadioTime plugin data
sub _pluginDataFor {
	my $class = shift;
	return Slim::Plugin::RadioTime::Plugin->_pluginDataFor(@_);
}

1;