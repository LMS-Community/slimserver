package Slim::Web::Settings::Server::Behavior;

# $Id$

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

sub name {
	return 'BEHAVIOR_SETTINGS';
}

sub page {
	return 'settings/behavior.html';
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	my @prefs = qw(
		displaytexttimeout
		checkVersion
		noGenreFilter
		playtrackalbum
		searchSubString
		ignoredarticles
		splitList
		browseagelimit
		groupdiscs
		persistPlaylists
		reshuffleOnRepeat
		saveShuffled
		composerInArtists
		conductorInArtists
		bandInArtists
		variousArtistAutoIdentification
		useBandAsAlbumArtist
		variousArtistsString
	);

	my %scanOn = map { $_ => 1 } qw(splitList ignoredarticles groupDiscs);

	for my $pref (@prefs) {

		# If this is a settings update
		if ($paramRef->{'submit'}) {

			if (exists $scanOn{$pref} && $paramRef->{$pref} ne Slim::Utils::Prefs::get($pref)) {

				logWarning("$pref changed - starting wipe scan");

				Slim::Utils::Prefs::set($pref, $paramRef->{$pref});

				Slim::Control::Request::executeRequest($client, ['wipecache']);

			} else {

				Slim::Utils::Prefs::set($pref, $paramRef->{$pref});
			}
		}

		$paramRef->{$pref} = Slim::Utils::Prefs::get($pref);
	}
	
	return $class->SUPER::handler($client, $paramRef, $pageSetup);
}

1;

__END__
