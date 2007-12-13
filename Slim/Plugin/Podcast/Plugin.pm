package Slim::Plugin::Podcast::Plugin;

# $Id$

# Copyright 2005-2007 Logitech

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Plugin::Base);

use HTML::Entities;
use XML::Simple;

use Slim::Formats::XML;
use Slim::Utils::Cache;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.podcast',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

my $prefs = preferences('plugin.podcast');

use Slim::Plugin::Podcast::Settings;

my $cli_next;

sub initPlugin {
	my $class = shift;

	$log->info("Initializing.");

	Slim::Plugin::Podcast::Settings->new;

	$class->SUPER::initPlugin();

	Slim::Buttons::Common::addMode('PLUGIN.Podcast', getFunctions(), \&setMode);

#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F
	Slim::Control::Request::addDispatch(['podcast', 'items', '_index', '_quantity'],
        [0, 1, 1, \&cliQuery]);
	Slim::Control::Request::addDispatch(['podcast', 'playlist', '_method' ],
		[1, 1, 1, \&cliQuery]);
	$cli_next=Slim::Control::Request::addDispatch(['radios', '_index', '_quantity' ],
		[0, 1, 1, \&cliRadiosQuery]);

	if ($log->is_debug) {

		$log->debug("Feed Info:");

		for my $feed (@{$prefs->get('feeds')}) {

			$log->debug(join(', ', $feed->{'name'}, $feed->{'value'}));
		}

		$log->debug('');
	}

	updateOPMLCache( $prefs->get('feeds') );
}

sub getDisplayName {
	return 'PLUGIN_PODCAST';
}

sub getFunctions {
	return {};
}

sub setMode {
	my $class =  shift;
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header => '{PLUGIN_PODCAST} {count}',
		listRef => $prefs->get('feeds'),
		modeName => 'Podcast Plugin',
		onRight => sub {
			my $client = shift;
			my $item = shift;
			my %params = (
				url => $item->{'value'},
				title => $item->{'name'},
			);
			Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);
		},
		onPlay => sub {
			my $client = shift;
			my $item = shift;
			# url is also a playlist
			$client->execute(['playlist', 'play', $item->{'value'}, $item->{'name'}]);
		},
		onAdd => sub {
			my $client = shift;
			my $item = shift;
			# url is also a playlist
			$client->execute(['playlist', 'add', $item->{'value'}, $item->{'name'}]);
		},

		overlayRef => sub {
			my $client = shift;
			return [ undef, $client->symbols('notesymbol') . $client->symbols('rightarrow') ];
		},
	);

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub webPages {
	my $class = shift;

	my $title = getDisplayName();
	my $url   = 'plugins/Podcast/index.html';
	
	Slim::Web::Pages->addPageLinks('radio', { $title => $url });
	Slim::Web::Pages->addPageLinks('icons', { $title => 'html/images/ServiceProviders/podcast.png' });
	
	Slim::Web::HTTP::protectURI($url);

	Slim::Web::HTTP::addPageFunction(
		$url => sub {
			# Get OPML list of feeds from cache
			my $cache = Slim::Utils::Cache->new();
			my $opml = $cache->get( 'podcasts_opml' );
			Slim::Web::XMLBrowser->handleWebIndex( {
				feed   => $opml,
				title  => $title,
				args   => \@_
			} );
		},
	);
}

sub cliQuery {
	my $request = shift;
	
	$log->debug('Enter');
	
	# Get OPML list of feeds from cache
	my $cache = Slim::Utils::Cache->new();
	my $opml = $cache->get( 'podcasts_opml' );
	Slim::Buttons::XMLBrowser::cliQuery('podcast', $opml, $request);
}

sub cliRadiosQuery {
	my $request = shift;
	
	my $menu = $request->getParam('menu');

	my $data;
	# what we want the query to report about ourself
	if (defined $menu) {
		$data = {
			'text'    => Slim::Utils::Strings::string(getDisplayName()),  # nice name
			'icon-id' => 'html/images/ServiceProviders/podcast.png',
			'actions' => {
				'go' => {
					'cmd' => ['podcast', 'items'],
					'params' => {
						'menu' => 'podcast',
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
			'cmd' => 'podcast',                    # cmd label
			'name' => Slim::Utils::Strings::string(getDisplayName()),  # nice name
			'type' => 'xmlbrowser',              # type
		};
	}
	
	# let our super duper function do all the hard work
	Slim::Control::Queries::dynamicAutoQuery($request, 'radios', $cli_next, $data);
}

# Update the hashref of podcast feeds for use with the web UI
sub updateOPMLCache {
	my $feeds = shift;

	my $outline = [];

	for my $item ( @{$feeds} ) {
		push @{$outline}, {
			'name'  => $item->{'name'},
			'url'   => $item->{'value'},
			'value' => $item->{'value'},
			'type'  => $item->{'type'} || 'lnk',
			'items' => [],
		};
	}
	
	my $opml = {
		'title' => string('PLUGIN_PODCAST'),
		'url'   => 'podcasts_opml',			# Used so XMLBrowser can look this up in cache
		'type'  => 'opml',
		'items' => $outline,
	};
		
	my $cache = Slim::Utils::Cache->new();
	$cache->set( 'podcasts_opml', $opml, '10days' );
}

1;
