package Slim::Plugin::OnlineLibrary::Libraries;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Music::VirtualLibraries;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

my $prefs = preferences('plugin.onlinelibrary');

sub initLibraries {
	my ($class) = @_;

	if ( $prefs->get('enablePreferLocalLibraryOnly') ) {
		Slim::Music::VirtualLibraries->registerLibrary({
			id     => 'preferLocalLibraryOnly',
			name   => string('PLUGIN_ONLINE_LIBRARY_DEDUPE_PREFER_LOCAL'),
			string => 'PLUGIN_ONLINE_LIBRARY_DEDUPE_PREFER_LOCAL',
			sql    => qq{
				INSERT OR IGNORE INTO library_track (library, track)
					SELECT '%s', tracks.id
					FROM tracks
					WHERE tracks.album IN (
						SELECT albums.id
						FROM albums
						WHERE albums.extid IS NULL
							OR	1 NOT IN (
								SELECT 1
								FROM albums otheralbums
								WHERE otheralbums.extid IS NULL
									AND LOWER(otheralbums.title) = LOWER(albums.title)
									AND otheralbums.contributor = albums.contributor
							)
					)
			}
		});
	}

	if ( $prefs->get('enableLocalTracksOnly') ) {
		Slim::Music::VirtualLibraries->registerLibrary({
			id     => 'localTracksOnly',
			name   => string('PLUGIN_ONLINE_LIBRARY_LOCAL_MUSIC_ONLY'),
			string => 'PLUGIN_ONLINE_LIBRARY_LOCAL_MUSIC_ONLY',
			sql    => qq{
				INSERT OR IGNORE INTO library_track (library, track)
					SELECT '%s', tracks.id
					FROM tracks
					WHERE tracks.remote != 1
			}
		});
	}
}

1;