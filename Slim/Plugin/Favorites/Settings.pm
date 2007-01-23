package Slim::Plugin::Favorites::Settings;

# SlimServer Copyright (C) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

my $default = 'http://wiki.slimdevices.com/plugin/attachments/RadioStationOPMLs/directory.opml';

sub name {
	return 'FAVORITES';
}

sub page {
	return 'plugins/Favorites/settings/basic.html';
}

sub handler {
	my ($class, $client, $params) = @_;

	if ($params->{'reset'}) {
		Slim::Utils::Prefs::delete('plugin_favorites_directories');
		Slim::Utils::Prefs::push('plugin_favorites_directories', $default);
	}

	if ($params->{'saveSettings'}) {

		if ($params->{'plugin_favorites_directories'}) {
			# Only add urls to opml files as first level of validation
			my @directories = grep { $_ =~ /^http:\/\/.*\.opml$/ } @{$params->{'plugin_favorites_directories'}};
			Slim::Utils::Prefs::set('plugin_favorites_directories', @directories ? \@directories : undef);
		}

		Slim::Utils::Prefs::set('plugin_favorites_advanced', exists $params->{'advanced'});
		Slim::Utils::Prefs::set('plugin_favorites_opmleditor', exists $params->{'opmleditor'});

		Slim::Plugin::Favorites::Plugin::addEditLink();
	}

	my @directories = Slim::Utils::Prefs::getArray('plugin_favorites_directories');

	$params->{'dirs'} = \@directories;
	$params->{'advanced'} = Slim::Utils::Prefs::get('plugin_favorites_advanced');
	$params->{'opmleditor'} = Slim::Utils::Prefs::get('plugin_favorites_opmleditor');

	return $class->SUPER::handler($client, $params);
}

1;

__END__
