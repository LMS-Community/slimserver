package Slim::Plugin::RadioArtwork::TrackInfo;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024-2025 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);

my $log = logger('plugin.radioartwork');
my $prefs = preferences('plugin.radioartwork');

sub trackInfoMenu {
	my ( $client, $url, $track, $remoteMeta ) = @_;

	return unless $client && $url && $track && $url =~ /^https?:/i && !$track->duration;

	my $title = Slim::Plugin::RadioArtwork::Plugin->ignoreStation($url)
		? cstring($client, 'PLUGIN_ARTWORK_SEARCH_FOR_ARTWORK')
		: cstring($client, 'PLUGIN_ARTWORK_DONT_SEARCH_FOR_ARTWORK');

	return [{
		name => $title,
		url  => sub {
			my ($client, $cb, $params) = @_;

			my $ignoreList = $prefs->get('ignoreStations') || [];
			if (Slim::Plugin::RadioArtwork::Plugin->ignoreStation($url)) {
				# remove from ignore list
				$ignoreList = [ grep { lc($_) ne lc($url) } @$ignoreList ];
				$title = cstring($client, 'PLUGIN_ARTWORK_REMOVED_FROM_IGNORELIST');
			} else {
				# add to ignore list
				push @$ignoreList, $url;
				$title = cstring($client, 'PLUGIN_ARTWORK_ADDED_TO_IGNORELIST');
			}

			Slim::Plugin::RadioArtwork::Plugin->updateIgnoreStationList($ignoreList);

			$cb->({
				items => [{
					name        => $title,
					showBriefly => 1,
					nowPlaying  => 1, # then return to Now Playing
				}]
			});
		},
		nextWindow => 'parent',
	}];
}

1;