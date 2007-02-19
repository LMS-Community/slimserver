package Slim::Plugin::Favorites::Settings;

# SlimServer Copyright (C) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

sub name {
	return 'FAVORITES';
}

sub page {
	return 'plugins/Favorites/settings/basic.html';
}

sub handler {
	my ($class, $client, $params) = @_;

	if ($params->{'saveSettings'}) {

		Slim::Utils::Prefs::set('plugin_favorites_opmleditor', exists $params->{'opmleditor'});

		Slim::Plugin::Favorites::Plugin::addEditLink();
	}

	$params->{'opmleditor'} = Slim::Utils::Prefs::get('plugin_favorites_opmleditor');

	delete $params->{'playerid'};

	return $class->SUPER::handler($client, $params);
}

1;

__END__
