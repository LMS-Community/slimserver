package Slim::Plugin::RadioTime::Plugin::Presets;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased Slim::Plugin::RadioTime::Plugin);

sub baseURL { 'http://opml.radiotime.com/GroupList.aspx?type=favorite' }

sub initPlugin {
	my $class = shift;

	# Will call OPMLBased's initPlugin method
	$class->SUPER::initPlugin(
		tag    => 'radiotime_presets',
		menu   => 'radios',
		weight => 180,
	);
}

sub getDisplayName { 'PLUGIN_RADIOTIME_PRESETS' }

sub playerMenu { 'RADIO' }

# Only display this plugin if username is entered
sub condition {
	my ( $class, $client ) = @_;
	
	my $url = __PACKAGE__->feed($client);
	
	if ( $url =~ /username/ ) {
		return 1;
	}
	
	return 0;
}

# Use the RadioTime plugin data
sub _pluginDataFor {
	my $class = shift;
	return Slim::Plugin::RadioTime::Plugin->_pluginDataFor(@_);
}

1;