package Slim::Web::Settings::Server::Behavior;

# $Id$

# SlimServer Copyright (c) 2001-2006 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

sub name {
	return 'BEHAVIOR_SETTINGS';
}

sub page {
	return 'settings/server/behavior.html';
}

sub prefs {
	return (preferences('server'),
			qw(displaytexttimeout checkVersion noGenreFilter playtrackalbum searchSubString ignoredarticles splitList
			   browseagelimit groupdiscs persistPlaylists reshuffleOnRepeat saveShuffled composerInArtists conductorInArtists
			   bandInArtists variousArtistAutoIdentification useBandAsAlbumArtist variousArtistsString)
		   );
}

1;

__END__
