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
use Tie::IxHash;
use URI;
use URI::QueryParam;
use URI::Escape qw(uri_escape_utf8);

use Slim::Plugin::RadioTime::Metadata;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);

use constant MENUS => {
	presets => {
		icon   => '/plugins/RadioTime/html/images/radiopresets.png',
		weight => 5,
	},
	local => {
		icon   => '/plugins/RadioTime/html/images/radiolocal.png',
		weight => 20,
	},
	music => {
		icon   => '/plugins/RadioTime/html/images/radiomusic.png',
		weight => 30,
	},
	sports => {
		icon   => '/plugins/RadioTime/html/images/radiosports.png',
		weight => 40,
	},
	news => {
		icon   => '/plugins/RadioTime/html/images/radionews.png',
		weight => 45,
	},
	talk => {
		icon   => '/plugins/RadioTime/html/images/radiotalk.png',
		weight => 50,
	},
	location => {
		icon   => '/plugins/RadioTime/html/images/radioworld.png',
		weight => 55,
	},
	language => {
		icon   => '/plugins/RadioTime/html/images/radioworld.png',
		weight => 56,
	},
	world => {
		icon   => '/plugins/RadioTime/html/images/radioworld.png',
		weight => 60,
	},
	podcast => {
		icon   => '/plugins/RadioTime/html/images/podcasts.png',
		weight => 70,
	},
	search => {
		icon   => '/plugins/RadioTime/html/images/radiosearch.png',
		weight => 110,
	},
	default => {
		icon => '/plugins/RadioTime/html/images/radio.png',
	},
};

use constant PARTNER_ID  => 16;
use constant MAIN_URL    => 'http://opml.radiotime.com/Index.aspx?partnerId=' . PARTNER_ID;
use constant ERROR_URL   => 'http://opml.radiotime.com/Report.ashx?c=stream&partnerId=' . PARTNER_ID;
use constant PRESETS_URL => 'http://opml.radiotime.com/Browse.ashx?c=presets&partnerId=' . PARTNER_ID;
use constant OPTIONS_URL => 'http://opml.radiotime.com/Options.ashx?partnerId=' . PARTNER_ID . '&id=';

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
		my $weight = 0;

		# customize TuneIn's main opml stream to get artwork etc.
		for my $item ( @{ $opml->{items} } ) {
			$item->{key} = 'search' if !$item->{key} && $item->{type} eq 'search';
			
			# remap 'location' to 'world' so it gets merged with mysb's menu if needed
			my $key = delete $item->{key};
			my $class = $key eq 'location' ? 'world' : $key;
			$item->{class} = ucfirst($class);
			
			$weight = MENUS->{$class}->{weight} || ++$weight;
			
			$item->{URL}   = delete $item->{url};
			$item->{icon}  = MENUS->{$class}->{icon} || MENUS->{'default'}->{icon};
			$item->{iconre} = 'radiotime';
			$item->{weight} = $weight;
			push @$menu, $item;
			
			# TTP 864, Use the string token for name instead of whatever translated name we get
			$item->{name} = 'RADIOTIME_' . uc($class);
		}
		
		# Add special My Presets item that shows up for users with an account
		unshift @{$menu}, {
			URL    => PRESETS_URL,
			class  => 'presets',
			icon   => MENUS->{presets}->{icon},
			iconre => 'radiotime',
			name   => 'RADIOTIME_MY_PRESETS',
			type   => 'link',
			weight => MENUS->{presets}->{weight},
		};
	}
	
	return $menu;
}

sub fixUrl {
	my ($class, $feed, $client) = @_;
	
	# In order of preference
	tie my %rtFormats, 'Tie::IxHash', (
		aac     => 'aac',
		ogg     => 'ogg',
		mp3     => 'mp3',
		wmpro   => 'wmap',
		wma     => 'wma',
		wmvoice => 'wma',
		# Real Player is supported through the AlienBBC plugin
		real    => 'rtsp',
	);

	my @formats = keys %rtFormats;
	
	if ($client) {
		my %playerFormats = map { $_ => 1 } $client->formats;
	
		# RadioTime's listing defaults to giving us mp3 and wma streams only,
		# but we support a few more
		@formats = grep {
		
			# format played natively on player?
			my $canPlay = $playerFormats{$rtFormats{$_}};
				
			if ( !$canPlay && main::TRANSCODING ) {
				require Slim::Player::TranscodingHelper;
	
				foreach my $supported (keys %playerFormats) {
					
					if ( Slim::Player::TranscodingHelper::checkBin(sprintf('%s-%s-*-*', $rtFormats{$_}, $supported)) ) {
						$canPlay = 1;
						last;
					}
	
				}
			}
	
			$canPlay;
	
		} keys %rtFormats;
	}

	my $uri    = URI->new($feed);
	my $rtinfo = $uri->query_form_hash;
	
	$rtinfo->{serial}    ||= $class->getSerial($client);
	$rtinfo->{partnerId} ||= PARTNER_ID;
	$rtinfo->{username}  ||= $class->getUsername if $feed =~ /presets/;
	$rtinfo->{formats}     = join(',', @formats);
	$rtinfo->{id}          = $rtinfo->{sid} || $rtinfo->{id};
	
	# don't pass the query, as our {QUERY} placeholder would become URI encoded, which is confusing xmlbrowser
	my $query = delete $rtinfo->{query};
	
	$uri->query_form( %$rtinfo );

	return $uri->as_string . ($query ? "&query=$query" : '');
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

# Bug 15569, special case for RadioTime stations, use their trackinfo menu
sub trackInfoURL {
	my ( $class, $client, $url ) = @_;
	
	my $rtinfo = URI->new($url)->query_form_hash;
	
	return $class->fixUrl(OPTIONS_URL . ($rtinfo->{sid} || $rtinfo->{id}), $client);
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

# set username as parsed form mysb.com url (unless it's already defined)
sub setUsername {
	my ( $class, $username ) = @_;
	
	return if main::SLIM_SERVICE || !$username || $prefs->get('username');
	
	$prefs->set('username', $username);
}

sub reportError {
	my ($class, $url, $error) = @_;
	
	return unless $error && $url =~ /(?:radiotime|tunein)\.com/;
		
	my ($id) = $url =~ /id=([^&]+)/;
	if ( $id ) {
		my $reportUrl = ERROR_URL
			. '&id=' . uri_escape_utf8($id)
			. '&message=' . uri_escape_utf8($error);
	
		main::INFOLOG && $log->is_info && $log->info("Reporting stream failure to RadioTime: $reportUrl");
	
		my $http = Slim::Networking::SimpleAsyncHTTP->new(
			sub {
				main::INFOLOG && $log->is_info && $log->info("RadioTime failure report OK");
			},
			sub {
				my $http = shift;
				main::INFOLOG && $log->is_info && $log->info( "RadioTime failure report failed: " . $http->error );
			},
			{
				timeout => 30,
			},
		);
	
		$http->get($reportUrl);
		
		if ( main::SLIM_SERVICE ) {
			# Let's log these on SN too
			$error =~ s/"/'/g;
			SDI::Util::Syslog::error("service=RadioTime-Error rtid=${id} error=\"${error}\"");
		}
	}
}

1;