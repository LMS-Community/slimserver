package Slim::Plugin::Favorites::Settings;

# Logitech Media Server Copyright 2001-2016 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.favorites');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('FAVORITES');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/Favorites/settings/basic.html');
}

sub prefs {
	my @prefs = ('opmleditor', 'dont_browsedb');
	
	if ( Slim::Utils::PluginManager->isEnabled('Slim::Plugin::DontStopTheMusic::Plugin') ) {
		push @prefs, 'registerDSTM';
	}
	
	return ($prefs, @prefs);
}

sub handler {
	my ($class, $client, $params) = @_;

	my $ret = $class->SUPER::handler($client, $params);

	if ($params->{'saveSettings'}) {

		Slim::Plugin::Favorites::Plugin::addEditLink();
	}

	return $ret;
}

1;

__END__
