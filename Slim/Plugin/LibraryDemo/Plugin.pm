package Slim::Plugin::LibraryDemo::Plugin;

# Logitech Media Server Copyright 2001-2014 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Menu::BrowseLibrary;
use Slim::Plugin::LibraryDemo::Importer;
use Slim::Utils::Log;

sub initPlugin {
	my $class = shift;
	
	Slim::Plugin::LibraryDemo::Importer->initPlugin();
	
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
#	},{
#		name => 'Playlists with long tracks',
#		icon => 'html/images/playlists.png',
#		feed => \&Slim::Menu::BrowseLibrary::_playlists,
#		id   => 'playlistsWithFrickinLongTracks',
#		weight => 85,
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