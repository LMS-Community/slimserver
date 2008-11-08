package Slim::Plugin::RadioTime::Plugin::Search;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased Slim::Plugin::RadioTime::Plugin);

sub baseURL { 'http://opml.radiotime.com/Search.aspx?query={QUERY}' }

sub initPlugin {
	my $class = shift;

	# Will call OPMLBased's initPlugin method
	$class->SUPER::initPlugin(
		tag    => 'search_radio',
		menu   => 'radios',
		weight => 70,
		type   => 'search',
	);
}

sub getDisplayName { 'PLUGIN_RADIOTIME_SEARCH' }

sub playerMenu { 'RADIO' }

# Use the RadioTime plugin data
sub _pluginDataFor {
	my $class = shift;
	return Slim::Plugin::RadioTime::Plugin->_pluginDataFor(@_);
}

1;