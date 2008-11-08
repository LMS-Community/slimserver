package Slim::Plugin::RadioTime::Plugin::Music;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased Slim::Plugin::RadioTime::Plugin);

sub baseURL { 'http://opml.radiotime.com/GroupList.aspx?type=channel&channel=music' }

sub initPlugin {
	my $class = shift;

	# Will call OPMLBased's initPlugin method
	$class->SUPER::initPlugin(
		tag    => 'music_radio',
		menu   => 'radios',
		weight => 30,
	);
}

sub getDisplayName { 'PLUGIN_RADIOTIME_MUSIC' }

sub playerMenu { 'RADIO' }

# Use the RadioTime plugin data
sub _pluginDataFor {
	my $class = shift;
	return Slim::Plugin::RadioTime::Plugin->_pluginDataFor(@_);
}

1;