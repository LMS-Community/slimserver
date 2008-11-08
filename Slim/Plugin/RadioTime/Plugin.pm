package Slim::Plugin::RadioTime::Plugin;

# $Id: Plugin.pm 11021 2006-12-21 22:28:39Z dsully $

# SqueezeCenter Copyright 2001-2007 Logitech.
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

use URI::Escape qw(uri_escape);

if ( !main::SLIM_SERVICE ) {
 	require Slim::Plugin::RadioTime::Settings;
}

use Slim::Utils::Prefs;

use Slim::Plugin::RadioTime::Plugin::Local;
use Slim::Plugin::RadioTime::Plugin::Music;
use Slim::Plugin::RadioTime::Plugin::Talk;
use Slim::Plugin::RadioTime::Plugin::ByRegion;
use Slim::Plugin::RadioTime::Plugin::Search;
use Slim::Plugin::RadioTime::Plugin::Presets;

my $prefs = preferences('plugin.radiotime');

sub baseURL { 'http://opml.radiotime.com/Index.aspx' }

sub initPlugin {
	my $class = shift;

	Slim::Player::ProtocolHandlers->registerIconHandler(
		qr/radiotime\.com/, 
		sub { return $class->_pluginDataFor('icon'); }
	);

	if ( !main::SLIM_SERVICE ) {
		Slim::Plugin::RadioTime::Settings->new;
	}
	
	# Load other sub-plugins
	Slim::Plugin::RadioTime::Plugin::Local->initPlugin();
	Slim::Plugin::RadioTime::Plugin::Music->initPlugin();
	Slim::Plugin::RadioTime::Plugin::Talk->initPlugin();
	Slim::Plugin::RadioTime::Plugin::ByRegion->initPlugin();
	Slim::Plugin::RadioTime::Plugin::Search->initPlugin();
	Slim::Plugin::RadioTime::Plugin::Presets->initPlugin();
}

sub getDisplayName { 'PLUGIN_RADIOTIME_MODULE_NAME' }

sub playerMenu { 'RADIO' }

sub feed {
	my ( $class, $client ) = @_;
	
	my $username;
	
	if ( main::SLIM_SERVICE ) {
		$username = preferences('server')->client($client)->get('plugin_radiotime_username', 'force');
	}
	else {
		$username = $prefs->get('username');
	}
	
	my $url = $class->baseURL();
	
	if ( $username ) {
		$url .= ( $url =~ /\?/ ) ? '&' : '?';
		$url .= 'username=' . uri_escape($username);
	}
	
	# RadioTime's listing defaults to giving us mp3 and wma streams.
	# If AlienBBC is installed we can ask for Real streams too.
	if ( exists $INC{'Plugins/Alien/Plugin.pm'} ) {
		$url .= ( $url =~ /\?/ ) ? '&' : '?';
		$url .= 'formats=mp3,wma,real';
	}
	
	return $url;
}

1;