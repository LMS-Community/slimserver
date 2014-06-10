package Slim::Plugin::LibraryDemo::Plugin;

# Logitech Media Server Copyright 2001-2014 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Menu::BrowseLibrary;
use Slim::Music::VirtualLibraries;
use Slim::Utils::Log;
use Slim::Utils::Scanner::API;

my $library_id;

sub initPlugin {
	my $class = shift;
	
	$library_id ||= Slim::Music::VirtualLibraries->registerLibrary({
		id => 260370,
		name => Slim::Utils::Strings::string('PLUGIN_LIBRARY_DEMO'),
	});

	# importer is being used in the standalone scanner
#	Slim::Music::Import->addImporter('Slim::Plugin::LibraryDemo::Importer', {
#		'type'         => 'post',
#		'weight'       => 85,
#		'use'          => 1,
#	});

	# handlers called when a new/changed track is discovered
	Slim::Utils::Scanner::API->onNewTrack( { cb => \&checkTrack } );
	Slim::Utils::Scanner::API->onChangedTrack( { cb => \&checkTrack } );
	
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
	
	foreach (@menus) {
		Slim::Menu::BrowseLibrary->registerNode({
			type         => 'link',
			name         => $_->{name},
			params       => { library_id => $library_id },
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

# check single track inside LMS
sub checkTrack {
	my ( $trackid, $url ) = @_;

	my $track = Slim::Schema->find('Track', $trackid);
	
	return unless $track;
	
	if ($track->secs > 600) {
		my $dbh = Slim::Schema->dbh;
	
		my $sth_update_library = $dbh->prepare_cached( qq{
			INSERT OR IGNORE INTO library_track (library, track)
			VALUES (?, ?)
		} );
		
		$sth_update_library->execute($library_id, $trackid);
	}	
}

1;