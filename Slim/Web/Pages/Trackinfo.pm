package Slim::Web::Pages::Trackinfo;

# $Id: Trackinfo.pm 30446 2010-03-31 12:11:29Z ayoung1 $

# Logitech Media Server Copyright 2003-2010 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Slim::Utils::Misc;
use Slim::Web::Pages;
use Slim::Menu::TrackInfo;
use Slim::Utils::Favorites;

sub init {

	Slim::Web::Pages->addPageFunction( qr/^(?:songinfo|trackinfo)\.(?:htm|xml)/, \&trackinfo);

}

sub trackinfo {
	my $client = shift;
	my $params = shift;
	
	my $id    = $params->{sess} || $params->{item};
	my $track = Slim::Schema->find( Track => $id );
	
	my $menu = Slim::Menu::TrackInfo->menu( $client, $track->url, $track ) if $track;
	
	# some additional parameters for the nice favorites button at the top
	$params->{isFavorite} = defined Slim::Utils::Favorites->new($client)->findUrl($track->url);
	$params->{itemUrl}    = $track->url;

	# Pass-through track ID as sess param
	$params->{sess} = $id;
	
	# Include track cover image
	$params->{image} = $menu->{cover};
	
	Slim::Web::XMLBrowser->handleWebIndex( {
		client => $client,
		path   => 'trackinfo.html',
		title  => sprintf('%s (%s)', Slim::Utils::Strings::string('SONG_INFO'), $menu->{'name'}),
		feed   => $menu,
		args   => [ $client, $params, @_ ],
	} );
}

1;
