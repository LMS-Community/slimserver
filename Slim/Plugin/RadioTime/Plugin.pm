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
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);

use constant ICONS => {
	presets  => '/plugins/RadioTime/html/images/radiopresets.png',
	local    => '/plugins/RadioTime/html/images/radiolocal.png',
	music    => '/plugins/RadioTime/html/images/radiomusic.png',
	news     => '/plugins/RadioTime/html/images/radionews.png',
	sports   => '/plugins/RadioTime/html/images/radiosports.png',
	talk     => '/plugins/RadioTime/html/images/radiotalk.png',
	location => '/plugins/RadioTime/html/images/radioworld.png',
	language => '/plugins/RadioTime/html/images/radioworld.png',
	world    => '/plugins/RadioTime/html/images/radioworld.png',
	search   => '/plugins/RadioTime/html/images/radiosearch.png',
	podcast  => '/plugins/RadioTime/html/images/podcasts.png',
	default  => '/plugins/RadioTime/html/images/radio.png',
};

use constant MAIN_URL => 'http://opml.radiotime.com/Index.aspx?partnerId=' . $Slim::Plugin::RadioTime::Metadata::PARTNERID;

my $log   = logger('plugin.radio');
my $prefs = preferences('plugin.radiotime');

sub initPlugin {
	my $class = shift;
	
	# Initialize metadata handler
	Slim::Plugin::RadioTime::Metadata->init();

	if ( main::WEBUI ) {
		require Slim::Plugin::RadioTime::Settings;
		Slim::Plugin::RadioTime::Settings->new;
	}

	# Track Info handler
	Slim::Menu::TrackInfo->registerInfoProvider( infoRadioTime => (
		before => 'playitem',
		func   => \&trackInfoHandler,
	) );
}

sub mainUrl {
	return MAIN_URL;
}

sub getDisplayName { 'PLUGIN_RADIOTIME_MODULE_NAME' }

# Don't add this item to any menu
sub playerMenu { }

sub parseMenu {
	my ($class, $opml) = @_;
	
	if ( $log->is_debug ) {
		$log->debug( 'Got radio menu from TuneIn: ' . Data::Dump::dump($opml) );
	}

	my $menu = [];

	if ( $opml && $opml->{items} ) {
		my $weight = 10;

		# customize TuneIn's main opml stream to get artwork etc.
		for my $item ( @{ $opml->{items} } ) {
			$item->{key} = 'search' if !$item->{key} && $item->{type} eq 'search';
			
			# remap 'location' to 'world' so it gets merged with mysb's menu if needed
			my $key = delete $item->{key};
			$item->{class} = $key eq 'location' ? 'world' : $key;
			
			$item->{URL}   = delete $item->{url};
			$item->{icon}  = ICONS->{$item->{class}} || ICONS->{'default'};
			$item->{iconre} = 'radiotime';
			$item->{weight} = ++$weight;
			push @$menu, $item;
			
			# TTP 864, Use the string token for name instead of whatever translated name we get
			$item->{name} = 'PLUGIN_RADIOTIME_' . uc( $item->{class} );
		}
		
		# Add special My Presets item that shows up for users with an account
		# TODO - deal with username/password
		unshift @{$menu}, {
			URL    => 'http://opml.radiotime.com/Browse.ashx?c=presets&partnerId=16',
			class  => 'presets',
			icon   => ICONS->{presets} || ICONS->{default},
			iconre => 'radiotime',
			items  => [],
			name   => 'PLUGIN_RADIOTIME_MY_PRESETS',
			type   => 'link',
			weight => 5,
		};
	}
	
	return $menu;
}

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

sub getUsername {
	my ( $class, $client ) = @_;
	
	if ( main::SLIM_SERVICE && $client ) {
		if ( my $json = preferences('server')->client($client)->get( 'plugin_radiotime_accounts', 'force', 'UserPref' ) ) {
			if ( my $accounts = eval { from_json($json) } ) {
				if ( my $username = $accounts->[0]->{username} ) {
					return $username;
				}
			}
		}
	}
	else {
		return $prefs->get('username');
	}
}

1;