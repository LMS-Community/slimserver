package Plugins::mc2Library::Plugin;

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
		id => 'mc2classica',
		name => 'Classica',
		# %s is being replaced with the library's ID
		sql => qq{
			INSERT OR IGNORE INTO library_track (library, track) 
				SELECT '%s', tracks.id 
				  FROM tracks 
				 WHERE url LIKE 'file:///E:/Classica/%'
		}
	},{
		id => 'mc2Jazz',
		name => 'Jazz',
		# %s is being replaced with the library's ID
		sql => qq{
			INSERT OR IGNORE INTO library_track (library, track) 
				SELECT '%s', tracks.id 
				  FROM tracks 
				 WHERE url LIKE 'file:///F:/Jazz/%' 
		}
	},{
		id => 'mc2Rock',
		name => 'Rock',
		# %s is being replaced with the library's ID
		sql => qq{
			INSERT OR IGNORE INTO library_track (library, track) 
				SELECT '%s', tracks.id 
				  FROM tracks 
				 WHERE url LIKE 'file:///F:/Rock/%'
		}
	},{
		id => 'mc2Blues',
		name => 'Blues',
		# %s is being replaced with the library's ID
		sql => qq{
			INSERT OR IGNORE INTO library_track (library, track) 
				SELECT '%s', tracks.id 
				  FROM tracks 
				 WHERE url LIKE 'file:///F:/Blues/%'
		}
	},{
		id => 'mc2Audiophile',
		name => 'Audiophile',
		# %s is being replaced with the library's ID
		sql => qq{
			INSERT OR IGNORE INTO library_track (library, track) 
				SELECT '%s', tracks.id 
				  FROM tracks 
				 WHERE url LIKE 'file:///F:/Audiophile/%'
		}
	},{
		id => 'mc2Disco',
		name => 'Disco',
		# %s is being replaced with the library's ID
		sql => qq{
			INSERT OR IGNORE INTO library_track (library, track) 
				SELECT '%s', tracks.id 
				  FROM tracks 
				 WHERE url LIKE 'file:///F:/Disco/%'
		}
	},{
		id => 'mc2Lounge',
		name => 'Lounge',
		# %s is being replaced with the library's ID
		sql => qq{
			INSERT OR IGNORE INTO library_track (library, track) 
				SELECT '%s', tracks.id 
				  FROM tracks 
				 WHERE url LIKE 'file:///F:/Lounge/%'
		}
	},{
		id => 'mc2Latina',
		name => 'Latina',
		# %s is being replaced with the library's ID
		sql => qq{
			INSERT OR IGNORE INTO library_track (library, track) 
				SELECT '%s', tracks.id 
				  FROM tracks 
				 WHERE url LIKE 'file:///F:/Latina/%'
		}
	},{
		id => 'mc2Other',
		name => 'Altro',
		scannerCB => sub {
			my $id = shift;
			
			# We could do some serious processing here. But for the sake of it we're
			# just going to run another SQL query:
			my $dbh = Slim::Schema->dbh;
		
			$dbh->do( qq{
				INSERT OR IGNORE INTO library_track (library, track)
					SELECT '$id', tracks.id
					FROM tracks 
					WHERE url NOT LIKE 'file:///F:/Latina/%'
                                          AND url NOT LIKE 'file:///F:/Lounge/%'
                                          AND url NOT LIKE 'file:///F:/Disco/%'
                                          AND url NOT LIKE 'file:///F:/Audiophile/%'
                                          AND url NOT LIKE 'file:///F:/Blues/%'
                                          AND url NOT LIKE 'file:///F:/Rock/%'
                                          AND url NOT LIKE 'file:///F:/Jazz/%'
                                          AND url NOT LIKE 'file:///E:/Classica/%'
			} );
		}
	} ) {
		Slim::Music::VirtualLibraries->registerLibrary($_);
	}
	
	my @menus = ( {
		name => 'PLUGIN_MC2_LIBRARY_CLASSICAL_ARTISTS',
		icon => 'html/images/artists.png',
		feed => \&Slim::Menu::BrowseLibrary::_artists,
		id   => 'artistsInMc2Classica',
		weight => 15,
	},{
		name => 'PLUGIN_MC2_LIBRARY_CLASSICAL_ALBUMS',
		icon => 'html/images/albums.png',
		feed => \&Slim::Menu::BrowseLibrary::_albums,
		id   => 'albumsInMc2Classica',
		weight => 16,
	} );
	
	# this demonstrates how to make use of libraries without switching 
	# the full browsing experience to one particular library
	# create some custom menu items based on one library
	foreach (@menus) {
		Slim::Menu::BrowseLibrary->registerNode({
			type         => 'link',
			name         => $_->{name},
			params       => { library_id => Slim::Music::VirtualLibraries->getRealId('mc2classica') },
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