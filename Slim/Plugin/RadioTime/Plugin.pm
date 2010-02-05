package Slim::Plugin::RadioTime::Plugin;

# $Id: Plugin.pm 11021 2006-12-21 22:28:39Z dsully $

# Squeezebox Server Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Digest::MD5 ();
use URI;
use URI::QueryParam;
use Slim::Plugin::RadioTime::Metadata;

sub initPlugin {
	my $class = shift;
	
	# Initialize metadata handler
	Slim::Plugin::RadioTime::Metadata->init();
	
	if ( main::WEBUI ) {
		# Add a function to view trackinfo in the web
		Slim::Web::Pages->addPageFunction( 
			'plugins/radiotime/trackinfo.html',
			sub {
				my $client = $_[0];
				
				my $url = Slim::Player::Playlist::url($client);
				
				Slim::Web::XMLBrowser->handleWebIndex( {
					client  => $client,
					feed    => $class->trackInfoURL( $client, $url ),
					path    => 'plugins/radiotime/trackinfo.html',
					title   => Slim::Music::Info::title($url),
					timeout => 35,
					args    => \@_
				} );
			},
		);
	}
}

sub getDisplayName { 'PLUGIN_RADIOTIME_MODULE_NAME' }

# Don't add this item to any menu
sub playerMenu { }

sub trackInfo {
	my ( $class, $client, $track ) = @_;
	
	my $url = $track->url;

	# SN URL to fetch track info menu
	my $trackInfoURL = $class->trackInfoURL( $client, $url );
	
	# let XMLBrowser handle all our display
	my %params = (
		header   => 'PLUGIN_RADIOTIME_MODULE_NAME',
		modeName => 'RadioTime Now Playing',
		title    => Slim::Music::Info::getCurrentTitle( $client, $url ),
		url      => $trackInfoURL,
		remember => 0,
		timeout  => 35,
	);

	Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );
	
	$client->modeParam( 'handledTransition', 1 );
}

sub trackInfoURL {
	my ( $class, $client, $url ) = @_;
	
	# Bug 15569, special case for RadioTime stations, use their trackinfo menu
	my $rtinfo = URI->new($url)->query_form_hash;
	my $serial = Digest::MD5::md5_hex( $client->uuid || $client->id );
	
	my $uri = URI->new('http://opml.radiotime.com/Options.ashx');
	$uri->query_form( id => $rtinfo->{id}, partnerId => $rtinfo->{partnerId}, serial => $serial );
	
	return $uri->as_string;
}

1;