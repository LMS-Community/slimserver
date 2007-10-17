package Slim::Plugin::RadioIO::Plugin;

# $Id: Plugin.pm 7196 2006-04-28 22:00:45Z andy $

# SqueezeCenter Copyright (c) 2001-2007 Vidur Apparao, Logitech.
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
use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Strings qw( string );
use Slim::Web::XMLBrowser;
use Slim::Utils::Prefs;

my $prefs = preferences('plugin.radioio');

my $FEED = Slim::Networking::SqueezeNetwork->url( '/api/radioio/v1/opml' );
my $cli_next;

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin();

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
	Slim::Web::HTTP::protectCommand([qw|radioio radios|]);
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
		$url .= '?username=' . uri_escape($username) . '&password=' . uri_escape( decode_base64( $password ) );
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
			client => $client,
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
			'text'    => Slim::Utils::Strings::string(getDisplayName()),  # nice name
			'icon-id' => 'html/images/ServiceProviders/radioio_56x56_f.png', # f looks nicer than p right now on this one
			'actions' => {
				'go' => {
					'cmd' => ['radioio', 'items'],
					'params' => {
						'menu' => 'radioio',
					},
				},
			},
			window    => {
				titleStyle => 'album',
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

1;
