package Slim::Plugin::RadioTime::Plugin;

# $Id: Plugin.pm 11021 2006-12-21 22:28:39Z dsully $

# Logitech Media Server Copyright 2001-2011 Logitech.
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
}

sub getDisplayName { 'PLUGIN_RADIOTIME_MODULE_NAME' }

# Don't add this item to any menu
sub playerMenu { }

sub trackInfoHandler {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( $url =~ m{^http://opml\.(?:radiotime|tunein)\.com} ) {
		$item = {
			name => cstring($client, 'PLUGIN_RADIOTIME_OPTIONS'),
			url  => __PACKAGE__->trackInfoURL( $client, $url ),
		};
	}
	
	return $item;
}

sub trackInfoURL {
	my ( $class, $client, $url ) = @_;
	
	# Bug 15569, special case for RadioTime stations, use their trackinfo menu
	my $rtinfo = URI->new($url)->query_form_hash;
	my $serial = $class->getSerial($client);
	
	my $uri = URI->new('http://opml.radiotime.com/Options.ashx');
	$uri->query_form( id => $rtinfo->{id}, partnerId => $rtinfo->{partnerId}, serial => $serial );
	
	return $uri->as_string;
}

sub getSerial {
	my ( $class, $client ) = @_;

	return '' unless $client;
	return Digest::MD5::md5_hex( $client->uuid || $client->id );
}

1;