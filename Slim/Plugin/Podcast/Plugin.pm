package Slim::Plugin::Podcast::Plugin;

# $Id$

# Copyright 2005-2009 Logitech

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

use constant FEED_VERSION => 2; # bump this number when changing the defaults below

sub DEFAULT_FEEDS {
	[
	{
		name  => 'Odeo',
		value => 'http://'
			. Slim::Networking::SqueezeNetwork->get_server('sn')
			. '/opml/odeo.opml',
	},
	{
		name  => 'PodcastAlley Top 50',
		value => 'http://podcastalley.com/PodcastAlleyTop50.opml'
	},
	{
		name  => 'PodcastAlley 10 Newest',
		value => 'http://podcastalley.com/PodcastAlley10Newest.opml'
	},
	];
}

# migrate old prefs across
$prefs->migrate(1, sub {
	my @names  = @{Slim::Utils::Prefs::OldPrefs->get('plugin_podcast_names') || [] };
	my @values = @{Slim::Utils::Prefs::OldPrefs->get('plugin_podcast_feeds') || [] };
	my @feeds;

	for my $name (@names) {
		push @feeds, { 'name' => $name, 'value' => shift @values };
	}

	if (@feeds) {
		$prefs->set('feeds', \@feeds);
		$prefs->set('modified', 1);
	}

	1;
});

# migrate to latest version of default feeds if they have not been modified
$prefs->migrate(FEED_VERSION, sub {
	$prefs->set('feeds', DEFAULT_FEEDS()) unless $prefs->get('modified');
	1;
});

if ( main::WEBUI ) {
 	require Slim::Plugin::Podcast::Settings;
}

my $cli_next;

sub initPlugin {
	my $class = shift;

	main::INFOLOG && $log->info("Initializing.");

	if ( main::WEBUI ) {
		Slim::Plugin::Podcast::Settings->new;
	}

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

	if (main::DEBUGLOG && $log->is_debug) {

		$log->debug("Feed Info:");

		for my $feed (@{$prefs->get('feeds')}) {

			$log->debug(join(', ', $feed->{'name'}, $feed->{'value'}));
		}

		$log->debug('');
	}

	my @item = ({
			stringToken    => getDisplayName(),
			text           => getDisplayName(),
			weight         => 20,
			id             => 'podcast',
			'icon-id'      => $class->_pluginDataFor('icon'),
			displayWhenOff => 0,
			window         => { 
				titleStyle	=> 'album',
				'icon-id'	=> $class->_pluginDataFor('icon'),
			},
			actions => {
				go =>      {
					'cmd' => ['podcast', 'items'],
					'params' => {
						'menu' => 'podcast',
					},
				},
			},
		});

	Slim::Control::Jive::registerAppMenu(\@item);
	
	if ( main::SLIM_SERVICE ) {
		# Feeds are per-client on SN, so don't try to load global feeds
		return;
	}

	updateOPMLCache( $prefs->get('feeds') );
}

sub getDisplayName {
	return 'PLUGIN_PODCAST';
}

# Don't add this item to any menu
sub playerMenu { }

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
	
	my @feeds = ();
	if ( main::SLIM_SERVICE ) {
		@feeds = feedsForClient($client);
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header => '{PLUGIN_PODCAST}',
		headerAddCount => 1,
		listRef => main::SLIM_SERVICE ? \@feeds : $prefs->get('feeds'),
		modeName => 'Podcast Plugin',
		onRight => sub {
			my $client = shift;
			my $item = shift;
			my %params = (
				url     => $item->{'value'},
				title   => $item->{'name'},
				timeout => 35,
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
			return [ undef, $client->symbols('rightarrow') ];
		},
	);

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub webPages {
	my $class = shift;

	my $title = getDisplayName();
	my $url   = 'plugins/Podcast/index.html';
	
	Slim::Web::Pages->addPageLinks('plugins', { $title => $url });
	
	Slim::Web::HTTP::CSRF->protectURI($url);

	Slim::Web::Pages->addPageFunction(
		$url => sub {
			my $client = $_[0];
			
			# Get OPML list of feeds from cache
			my $cache = Slim::Utils::Cache->new();
			my $opml = $cache->get( 'podcasts_opml' );
			Slim::Web::XMLBrowser->handleWebIndex( {
				client => $client,
				feed   => $opml,
				title  => $title,
				args   => \@_
			} );
		},
	);
}

sub cliQuery {
	my $request = shift;
	
	main::DEBUGLOG && $log->debug('Enter');
	
	if ( main::SLIM_SERVICE ) {
		my $client = $request->client;
		my @feeds  = feedsForClient($client);
		
		my $outline = [];
		
		for my $item ( @feeds ) {
			push @{$outline}, {
				name  => $item->{name},
				url   => $item->{value},
				value => $item->{value},
				type  => $item->{type} || 'link',
				items => [],
			};
		}

		my $opml = {
			title => $client->string('PLUGIN_PODCAST'),
			type  => 'opml',
			items => $outline,
		};
		
		Slim::Control::XMLBrowser::cliQuery('podcast', $opml, $request);
		return;
	}
	
	# Get OPML list of feeds from cache
	my $cache = Slim::Utils::Cache->new();
	my $opml = $cache->get( 'podcasts_opml' );
	Slim::Control::XMLBrowser::cliQuery('podcast', $opml, $request);
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

# SN only
sub feedsForClient {
	my $client = shift;
	
	my $userid = $client->playerData->userid->id;
	
	my @f = SDI::Service::Model::FavoritePodcast->search(
		userid => $userid,
		{ order_by => 'num' }
	);
													  
	my @feeds = map { 
		{ 
			name  => $_->title, 
			value => $_->url,
		}
	} @f;
	
	# check if the user deleted feeds so we don't load the defaults
	my $deletedFeeds = preferences('server')->client($client)->get('deleted_podcasts');
	
	# Populate with all default feeds
	if ( !scalar @feeds && !$deletedFeeds ) {
		@feeds = map { 
			{ 
				name  => $_->title, 
				value => $_->url,
			}
		} SDI::Service::Model::FavoritePodcast->addDefaults( $userid );
	}
	
	return @feeds;
}

1;
