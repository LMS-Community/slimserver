package Slim::Plugin::LibraryDemo::Plugin;

# Logitech Media Server Copyright 2001-2014 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Menu::BrowseLibrary;
use Slim::Music::Import;
use Slim::Utils::Log;

sub initPlugin {
	my $class = shift;

	# Define some virtual libraries.
	# - id:        the library's ID. Use something specific to your plugin to prevent dupes.
	# - name:      the user facing name, shown in menus and settings
	# - sql:       a SQL statement which creates the records in library_track
	# - scannerCB: a sub ref to some code creating the records in library_track. Use scannerCB
	#              if your library logic is a bit more complex than a simple SQL statement.
	foreach ( {
		id => 'demoLongTracks',
		name => 'Longish tracks only',
		# %s is being replaced with the library's ID
		sql => qq{
			INSERT OR IGNORE INTO library_track (library, track)
				SELECT '%s', tracks.id 
				FROM tracks 
				WHERE tracks.secs > 600
		}
	},{
		id => 'demoFLACOnly',
		name => 'FLAC files only',
		sql => qq{
			INSERT OR IGNORE INTO library_track (library, track)
				SELECT '%s', tracks.id 
				FROM tracks 
				WHERE tracks.content_type = 'flc'
		}
	},{
		id => 'loveThisDemo',
		name => 'Love is in the air (and in album/track titles)',
		scannerCB => sub {
			my $id = shift;
			
			# We could do some serious processing here. But for the sake of it we're
			# just going to run another SQL query:
			my $dbh = Slim::Schema->dbh;
		
			$dbh->do( qq{
				INSERT OR IGNORE INTO library_track (library, track)
					SELECT '$id', tracks.id
					FROM tracks 
					JOIN albums ON tracks.album = albums.id 
					WHERE tracks.titlesearch LIKE '%%LOVE%%' OR albums.titlesearch LIKE '%%LOVE%%'
			} );
		}
	} ) {
		Slim::Music::VirtualLibraries->registerLibrary($_);
	}
	
	my @menus = ( {
		name => 'PLUGIN_LIBRARY_DEMO_ARTISTS',
		icon => 'html/images/artists.png',
		feed => \&Slim::Menu::BrowseLibrary::_artists,
		id   => 'artistsWithFrickinLongTracks',
		weight => 15,
	},{
		name => 'PLUGIN_LIBRARY_DEMO_ALBUMS',
		icon => 'html/images/albums.png',
		feed => \&Slim::Menu::BrowseLibrary::_albums,
		id   => 'albumsWithFrickinLongTracks',
		weight => 25,
	} );
	
	# this demonstrates how to make use of libraries without switching 
	# the full browsing experience to one particular library
	# create some custom menu items based on one library
	foreach (@menus) {
		Slim::Menu::BrowseLibrary->registerNode({
			type         => 'link',
			name         => $_->{name},
			params       => { library_id => Slim::Music::VirtualLibraries->getRealId('demoLongTracks') },
			feed         => $_->{feed},
			icon         => $_->{icon},
			jiveIcon     => $_->{icon},
			homeMenuText => $_->{name},
			condition    => \&Slim::Menu::BrowseLibrary::isEnabledNode,
			id           => $_->{id},
			weight       => $_->{weight},
			cache        => 1,
		});
	}
	
	$class->SUPER::initPlugin(@_);
}

1;