package Slim::Plugin::ExtendedBrowseModes::Libraries;

# Logitech Media Server Copyright 2001-2014 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Music::VirtualLibraries;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

my $prefs = preferences('plugin.extendedbrowsemodes');

sub initPlugin {
	shift->initLibraries();
}

sub initLibraries {
	my ($class) = @_;
	
	if ( $prefs->get('enableLosslessPreferred') ) {
		Slim::Music::VirtualLibraries->registerLibrary({
			id     => 'losslessPreferred',
			name   => string('PLUGIN_EXTENDED_BROWSEMODES_LOSSLESS_PREFERRED'),
			string => 'PLUGIN_EXTENDED_BROWSEMODES_LOSSLESS_PREFERRED',
			sql    => qq{
				INSERT OR IGNORE INTO library_track (library, track)
					SELECT '%s', tracks.id
					FROM tracks, albums
					WHERE albums.id = tracks.album 
					AND (
						tracks.lossless 
						OR 1 NOT IN (
							SELECT 1
							FROM tracks other
							JOIN albums otheralbums ON other.album
							WHERE other.title = tracks.title
							AND other.lossless
							AND other.primary_artist = tracks.primary_artist
							AND other.tracknum = tracks.tracknum
							AND other.year = tracks.year
							AND otheralbums.title = albums.title
						)
					)
			}
		});
	}
}


1;