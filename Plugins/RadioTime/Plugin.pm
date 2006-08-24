package Plugins::RadioTime::Plugin;

# $Id$

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;

use URI::Escape qw(uri_escape);

use Slim::Buttons::Common;
use Slim::Buttons::XMLBrowser;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw( string );
use Slim::Web::XMLBrowser;

my $FEED = 'http://opml.radiotime.com/Index.aspx';

sub enabled {
	return ($::VERSION ge '6.5');
}

sub initPlugin {
	$::d_plugins && msg("RadioTime Plugin initializing.\n");

	Slim::Buttons::Common::addMode('PLUGIN.RadioTime', getFunctions(), \&setMode);

#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F
    Slim::Control::Request::addDispatch(['radiotime', 'items', '_index', '_quantity'],
        [0, 1, 1, \&cliQuery]);
	Slim::Control::Request::addDispatch(['radiotime', 'playlist', '_method' ],
		[1, 1, 1, \&cliQuery]);
}

sub addMenu {
	return 'RADIO';
}

sub getDisplayName {
	return 'PLUGIN_RADIOTIME_MODULE_NAME';
}

sub getFunctions {
	return {};
}

sub setMode {
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
		title    => $client->string(getDisplayName()),
	);

	Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);

	# we'll handle the push in a callback
	$client->param('handledTransition',1);
}

sub radioTimeURL {
	my $client = shift;
	
	my $username;
	
	if ( $ENV{SLIM_SERVICE} ) { # SqueezeNetwork
		$username = $client->prefGet('plugin_radiotime_username', undef, 1);
	}
	else {
		$username = Slim::Utils::Prefs::get('plugin_radiotime_username');
	}
	
	my $url = $FEED;
	
	if ( $username ) {
		$url .= '?username=' . uri_escape($username);
	}
	
	return $url;
}

# Web pages

sub webPages {
	my $title = 'PLUGIN_RADIOTIME_MODULE_NAME';
	
	if (grep {$_ eq 'RadioTime::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins')) {
		Slim::Web::Pages->addPageLinks('radio', { $title => undef });
	} else {
		Slim::Web::Pages->addPageLinks('radio', { $title => 'plugins/RadioTime/index.html' });
	}
	
	my %pages = ( 
		'index.html' => sub {
			my $client = $_[0];
			my $url = radioTimeURL($client);
			Slim::Web::XMLBrowser->handleWebIndex( {
				feed   => $url,
				title  => $title,
				args   => \@_
			} );
		},
	);
	
	return \%pages;
}

sub cliQuery {
	my $request = shift;
	
	$::d_plugins && msg("RadioTime: cliQuery()\n");
	
	Slim::Buttons::XMLBrowser::cliQuery('radiotime', radioTimeURL(), $request);
}

sub setupGroup {
	my %Group = (
		PrefOrder => [
			'plugin_radiotime_username',
		],
		GroupHead => string( 'PLUGIN_RADIOTIME_MODULE_NAME' ),
		GroupDesc => string( 'SETUP_GROUP_PLUGIN_RADIOTIME_DESC' ),
		GroupLine => 1,
		GroupSub  => 1,
		Suppress_PrefSub  => 1,
		Suppress_PrefLine => 1,
	);

	my %Prefs = (
		plugin_radiotime_username => {},
	);

	return( \%Group, \%Prefs );
}

sub strings
{
	return "
PLUGIN_RADIOTIME_MODULE_NAME
	EN	RadioGuide™ by radiotime™

PLUGIN_RADIOTIME_MODULE_TITLE
	EN	radiotime™
	
PLUGIN_RADIOTIME_LOADING
	EN	Loading RadioGuide™ by radiotime™...
	
SETUP_GROUP_PLUGIN_RADIOTIME_DESC
	EN	Use <a href='http://www.radiotime.com' target='_new'>radiotime.com</a> to find your favorite local and global talk, sports, religious, and music radio — all <b>free</b>.

SETUP_PLUGIN_RADIOTIME_USERNAME
	EN	Enter your RadioTime username.

SETUP_PLUGIN_RADIOTIME_USERNAME_DESC
	EN	Visit <a href='http://www.radiotime.com' target='_new'>radiotime.com</a> to sign up for <b>free</b>.  Add stations and shows to My Radio then listen on your Squeezebox or Transporter.
";}

1;
