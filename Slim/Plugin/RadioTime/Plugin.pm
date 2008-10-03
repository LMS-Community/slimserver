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
use base qw(Slim::Plugin::Base);

use URI::Escape qw(uri_escape);

if ( !main::SLIM_SERVICE ) {
 	require Slim::Plugin::RadioTime::Settings;
}

use Slim::Buttons::Common;
use Slim::Buttons::XMLBrowser;

if ( !main::SLIM_SERVICE ) {
 	require Slim::Web::XMLBrowser;
}

use Slim::Utils::Prefs;

my $FEED = 'http://opml.radiotime.com/Index.aspx';
my $cli_next;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.radiotime',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

my $prefs = preferences('plugin.radiotime');

sub initPlugin {
	my $class = shift;

	$class->initJive();

	$class->SUPER::initPlugin();

	Slim::Player::ProtocolHandlers->registerIconHandler(
		qr/radiotime\.com/, 
		sub { return $class->_pluginDataFor('icon'); }
	);

	if ( !main::SLIM_SERVICE ) {
		Slim::Plugin::RadioTime::Settings->new;
	}

#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F
    Slim::Control::Request::addDispatch(['radiotime', 'items', '_index', '_quantity'],
        [1, 1, 1, \&cliQuery]);
	Slim::Control::Request::addDispatch(['radiotime', 'playlist', '_method' ],
		[1, 1, 1, \&cliQuery]);
	$cli_next = Slim::Control::Request::addDispatch(['radios', '_index', '_quantity' ],
		[0, 1, 1, \&cliRadiosQuery]);
		
	if ( !main::SLIM_SERVICE ) {
		Slim::Web::HTTP::protectCommand([qw|radiotime radios|]);
	}
}

# add "hidden" item to Jive home menu 
# this allows RadioTime to be optionally added to the 
# top-level menu through the CustomizeHomeMenu applet
sub initJive {
	my ( $class ) = @_;

	my $icon     =  Slim::Plugin::RadioTime::Plugin->_pluginDataFor('icon'),
	my $name     = $class->getDisplayName();
        my @jiveMenu = ({
		stringToken    => $name,
		id             => 'pluginRadiotime',
		node           => 'radios',
		displayWhenOff => 0,
		window         => { 
				'icon-id' => $icon,
				titleStyle => 'album',
		},
		actions => {
			go =>          {
				player => 0,
				cmd    => [ 'radiotime', 'items' ],
				params => {
					menu => 'radiotime',
				},
			},
		},
	});

	Slim::Control::Jive::registerPluginMenu(\@jiveMenu);
}

sub getDisplayName {
	return 'PLUGIN_RADIOTIME_MODULE_NAME';
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
		header   => 'PLUGIN_RADIOTIME_LOADING',
		modeName => 'RadioTime Plugin',
		url      => radioTimeURL($client),
		title    => $client->string( getDisplayName() ),
	);

	Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);

	# we'll handle the push in a callback
	$client->modeParam('handledTransition', 1);
}

sub radioTimeURL {
	my $client = shift;
	
	my $username;
	
	if ( main::SLIM_SERVICE ) {
		$username = preferences('server')->client($client)->get('plugin_radiotime_username', 'force');
	}
	else {
		$username = $prefs->get('username');
	}
	
	my $url = $FEED;
	
	if ( $username ) {
		$url .= '?username=' . uri_escape($username);
	}
	
	# RadioTime's listing defaults to giving us mp3 and wma streams.
	# If AlienBBC is installed we can ask for Real streams too.
	if ( exists $INC{'Plugins/Alien/Plugin.pm'} ) {
		$url .= ( $url =~ /\?/ ) ? '&' : '?';
		$url .= 'formats=mp3,wma,real';
	}
	
	return $url;
}

# Web pages

sub webPages {
	my $class = shift;

	my $title = getDisplayName();
	my $url   = 'plugins/RadioTime/index.html';
	
	Slim::Web::Pages->addPageLinks('radios', { $title => $url });
	
	Slim::Web::HTTP::protectURI($url);
	
	Slim::Web::HTTP::addPageFunction($url, sub {

		my $client = $_[0];
		my $url = radioTimeURL($client);

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
	my $client  = $request->client;
	
	Slim::Control::XMLBrowser::cliQuery('radiotime', radioTimeURL($client), $request);
}

sub cliRadiosQuery {
	my $request = shift;
	
	my $menu = $request->getParam('menu');

	my $data;
	# what we want the query to report about ourself
	if (defined $menu) {
		$data = {
			'text'    => $request->string( getDisplayName() ),  # nice name
			weight    => 30,
			'icon-id' => Slim::Plugin::RadioTime::Plugin->_pluginDataFor('icon'),
			'actions' => {
				'go' => {
					'cmd' => ['radiotime', 'items'],
					'params' => {
						'menu' => 'radiotime',
					},
				},
			},
			window    => {
				titleStyle => 'album',
			},
		};
		
		if ( main::SLIM_SERVICE ) {
			# Bug 7110, icons are full URLs so we must use icon not icon-id
			$data->{icon} = delete $data->{'icon-id'};
			
			# Bug 7230, send pre-thumbnailed URL
			$data->{icon} =~ s/\.png$/_56x56_p\.png/;
		}
	}
	else {
		$data = {
			'cmd'  => 'radiotime',
			'name' => $request->string( getDisplayName() ),
			'type' => 'xmlbrowser',
		};
	}
	
	# let our super duper function do all the hard work
	Slim::Control::Queries::dynamicAutoQuery($request, 'radios', $cli_next, $data);
}

1;
