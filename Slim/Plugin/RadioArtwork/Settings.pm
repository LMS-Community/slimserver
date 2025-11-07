package Slim::Plugin::RadioArtwork::Settings;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024-2025 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log = logger('plugin.radioartwork');
my $prefs = preferences('plugin.radioartwork');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_RADIO_ARTWORK');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/RadioArtwork/settings/basic.html');
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	if ( $params->{saveSettings} ) {
		my $ignoreList = [ split(/\s+/, $params->{pref_ignoreList} || '') ];

		main::INFOLOG && $log->is_info && $log->info("Saving ignore list: " . join(', ', @$ignoreList));

		Slim::Plugin::RadioArtwork::Plugin->updateIgnoreStationList($ignoreList);
	}

	$params->{ignoreList} = join("\n", @{$prefs->get('ignoreStations') || []});

	return $class->SUPER::handler( $client, $params, $callback, @args );
}


1;