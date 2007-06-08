package Slim::Plugin::RadioIO::Plugin;

# $Id: Plugin.pm 7196 2006-04-28 22:00:45Z andy $

# SlimServer Copyright (c) 2001-2004 Vidur Apparao, Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use base qw(Slim::Plugin::Base);

use MIME::Base64;
use URI::Escape qw(uri_escape);

use Slim::Plugin::RadioIO::Settings;

use Slim::Buttons::Common;
use Slim::Buttons::XMLBrowser;
use Slim::Player::ProtocolHandlers;
use Slim::Utils::Strings qw( string );
use Slim::Web::XMLBrowser;
use Slim::Utils::Prefs;

use Slim::Plugin::RadioIO::ProtocolHandler;

my $prefs = preferences('plugin.radioio');

my $FEED = 'http://www.radioio.com/opml/channelsLOGIN.php?device=Squeezebox&speed=high';
my $cli_next;

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin();

	# Backwards-compat with radioio:// protocol links
	Slim::Player::ProtocolHandlers->registerHandler('radioio', 'Slim::Plugin::RadioIO::ProtocolHandler');

	Slim::Plugin::RadioIO::Settings->new;

#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F
    Slim::Control::Request::addDispatch(['radioio', 'items', '_index', '_quantity'],
        [0, 1, 1, \&cliQuery]);
	Slim::Control::Request::addDispatch(['radioio', 'playlist', '_method' ],
		[1, 1, 1, \&cliQuery]);
	$cli_next=Slim::Control::Request::addDispatch(['radios', '_index', '_quantity' ],
		[0, 1, 1, \&cliRadiosQuery]);
}

sub getDisplayName {
	return 'PLUGIN_RADIOIO_MODULE_NAME';
}

sub setMode {
	my $class  = shift;
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {

		Slim::Buttons::Common::popMode($client);
		return;
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header   => 'PLUGIN_RADIOIO_LOADING',
		modeName => 'RadioIO Plugin',
		url      => radioIOURL($client),
		title    => $client->string(getDisplayName()),
	);

	Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);

	# we'll handle the push in a callback
	$client->modeParam('handledTransition',1);
}

sub radioIOURL {
	my $client = shift;
	
	my $username = $prefs->get('username');
	my $password = $prefs->get('password');
	
	my $url = $FEED;
	
	if ( $username && $password ) {
		$url .= '&membername=' . uri_escape($username) . '&pw=' . uri_escape( decode_base64( $password ) );
	}
	
	return $url;
}

# Web pages
sub webPages {
	my $class = shift;

	my $title = 'PLUGIN_RADIOIO_MODULE_NAME';
	my $url   = 'plugins/RadioIO/index.html';
	
	Slim::Web::Pages->addPageLinks('radio', { $title => $url });
	
	Slim::Web::HTTP::addPageFunction($url, sub {

		my $client = $_[0];
		my $url = radioIOURL($client);

		Slim::Web::XMLBrowser->handleWebIndex( {
			feed   => $url,
			title  => $title,
			args   => \@_
		} );
	});
}

sub cliQuery {
	my $request = shift;
	
	Slim::Buttons::XMLBrowser::cliQuery('radioio', radioIOURL(), $request);
}

sub cliRadiosQuery {
	my $request = shift;

	my $menu = $request->getParam('menu');

	my $data;
	# what we want the query to report about ourself
	if (defined $menu) {
		$data = {
			'text' => Slim::Utils::Strings::string(getDisplayName()),  # nice name
			'actions' => {
				'go' => {
					'cmd' => ['radioio', 'items'],
					'params' => {
						'menu' => 'radioio',
					},
				},
			},
		};
	}
	else {
		$data = {
			'cmd' => 'radioio',                    # cmd label
			'name' => Slim::Utils::Strings::string(getDisplayName()),  # nice name
			'type' => 'xmlbrowser',              # type
		};
	}
	
	# let our super duper function do all the hard work
	Slim::Control::Queries::dynamicAutoQuery($request, 'radios', $cli_next, $data);
}

###
# The below code for backwards-compat with old-style radioio:// protocol links

our %stations = (
	radioio70s       => 3,			
	radioio70sPOP    => 21,			
	radioio80s       => 39,
	radioio80sPOP    => 57,	
	radioio90s       => 75,
	radioioACOUSTIC  => 93,
	radioioAMBIENT   => 111,
	radioioBEAT      => 129,
	radioioCLASSICAL => 147,
	radioioCOUNTRY   => 165,
	radioioDEAD      => 183,
	radioioDISCO     => 202,				 
	radioioECLECTIC  => 220,
	radioioEDGE      => 238,
	radioioHISTORY   => 256,
	radioioJAM       => 274,
	radioioJAZZ      => 292,
	radioioPOP       => 310,
	radioioROCK      => 328,
	radioioSEASONS   => 346,
	radioioUNLIMITED => 364,
	radioioWORLD     => 382,
	radioioONE       => 400,
);

our @station_names = sort keys %stations;

sub getHTTPURL {
	my $key = shift;
	my $id  = $stations{$key} || return;
	
	return "http://streampoint.radioio.com/streams/$id/45ec8c85a2a8a/";
}

sub getRadioIOURL {
	my $num = shift;

	my $key = $station_names[$num];
	my $url = "radioio://" . $key . ".mp3";

	my %cacheEntry = (
		'TITLE' => $key,
		'CT'    => 'mp3',
		'VALID' => 1,
	);

	Slim::Music::Info::updateCacheEntry($url, \%cacheEntry);

	return $url;
}

1;
