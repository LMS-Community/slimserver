package Slim::Plugin::RadioTime::Plugin;

# $Id: Plugin.pm 11021 2006-12-21 22:28:39Z dsully $

# Copyright 2001-2011 Logitech.
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
use URI::Escape qw(uri_escape_utf8);
use URI::QueryParam;
use Slim::Plugin::RadioTime::Metadata;
use Slim::Utils::Strings qw(cstring);

sub initPlugin {
	my $class = shift;
	
	# Initialize metadata handler
	Slim::Plugin::RadioTime::Metadata->init();
	
	# Track Info handler
	Slim::Menu::TrackInfo->registerInfoProvider( infoRadioTime => (
		before => 'playitem',
		func   => \&trackInfoHandler,
	) );

	# need a second trackinfo handler to add the On TuneIn item towards the bottom of the list
	Slim::Menu::TrackInfo->registerInfoProvider( onRadioTime => (
		before => 'middle',
		func   => \&trackInfoOnMenuHandler,
	) );
}

sub getDisplayName { 'PLUGIN_RADIOTIME_MODULE_NAME' }

# Don't add this item to any menu
sub playerMenu { }

sub trackInfoHandler {
	my ( $client, $url, $track ) = @_;
	
	return unless $client;

	my $item;
	
	if ( $url =~ m{^http://opml\.(?:radiotime|tunein)\.com} ) {
		$item = {
			name => cstring($client, 'PLUGIN_RADIOTIME_OPTIONS'),
			url  => __PACKAGE__->trackInfoURL( $client, $url ),
		};
	}
	
	return $item;
}

sub trackInfoOnMenuHandler {
	my ( $client, $url, $track, $remoteMeta ) = @_;
	
	return unless $client;

	my $item;
	
	if ( $url !~ m{^http://opml\.(?:radiotime|tunein)\.com} ) {
		my $artist = $track->remote ? $remoteMeta->{artist} : $track->artistName;
		my $title  = $track->remote ? $remoteMeta->{title}  : $track->title;
		
		if ( $artist || $title ) {
			my $snURL = Slim::Networking::SqueezeNetwork->url(
				'/api/tunein/v1/opml/context?artist='
					. uri_escape_utf8($artist)
					. '&track='
					. uri_escape_utf8($title)
			);
	
			$item = {
				type      => 'link',
				name      => $client->string('PLUGIN_RADIOTIME_ON_TUNEIN'),
				url       => $snURL,
				favorites => 0,
			};
		}
	}
	
	return $item;
}

sub trackInfoURL {
	my ( $class, $client, $url ) = @_;
	
	# Bug 15569, special case for RadioTime stations, use their trackinfo menu
	my $rtinfo = URI->new($url)->query_form_hash;
	my $serial = $class->getSerial($client);
	
	my $uri = URI->new('http://opml.radiotime.com/Options.ashx');
	$uri->query_form( id => $rtinfo->{id}, partnerId => $rtinfo->{partnerId}, serial => $serial, mode => $rtinfo->{mode} );
	
	return $uri->as_string;
}

sub getSerial {
	my ( $class, $client ) = @_;

	return '' unless $client;
	return Digest::MD5::md5_hex( $client->uuid || $client->id );
}

1;