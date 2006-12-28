package Plugins::Podcast::Plugin;

# $Id$

# Copyright (c) 2005-2006 Slim Devices, Inc. (www.slimdevices.com)

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Plugin::Base);

use constant FEEDS_VERSION => 1;

use HTML::Entities;
use XML::Simple;

use Plugins::Podcast::Settings;

use Slim::Formats::XML;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.podcast',
	'defaultLevel' => 'WARN',
	'description'  => getDisplayName(),
});

# default can be overridden by prefs.  See initPlugin()
# TODO: come up with a better list of defaults.
our @default_feeds = (
	{
		name => 'Odeo',
		value => 'http://content.us.squeezenetwork.com:8080/opml/odeo.opml',
	},
	{
		name => 'PodcastAlley Top 50',
		value => 'http://podcastalley.com/PodcastAlleyTop50.opml'
	},
	{
		name => 'PodcastAlley 10 Newest',
		value => 'http://podcastalley.com/PodcastAlley10Newest.opml'
	},
);

our @feeds = ();
our %feed_names; # cache of feed names
my $cli_next;

sub initPlugin {
	my $class = shift;

	$log->info("Initializing.");

	Plugins::Podcast::Settings->new;

	$class->SUPER::initPlugin();

	Slim::Buttons::Common::addMode('PLUGIN.Podcast', getFunctions(), \&setMode);

	my @feedURLPrefs = Slim::Utils::Prefs::getArray("plugin_podcast_feeds");
	my @feedNamePrefs = Slim::Utils::Prefs::getArray("plugin_podcast_names");
	my $feedsModified = Slim::Utils::Prefs::get("plugin_podcast_feeds_modified");
	my $version = Slim::Utils::Prefs::get("plugin_podcast_feeds_version");

	@feeds = ();

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


	# No prefs set or we've had a version change and they weren't modified, 
	# so we'll use the defaults
	if (scalar(@feedURLPrefs) == 0 || (!$feedsModified && (!$version  || $version != FEEDS_VERSION))) {

		# use defaults
		# set the prefs so the web interface will work.
		revertToDefaults();

	} else {

		# use prefs
		for (my $i = 0; $i < scalar(@feedNamePrefs); $i++) {

			push @feeds, {
				name  => $feedNamePrefs[$i],
				value => $feedURLPrefs[$i],
				type  => 'link',
			};
		}
	}

	if ($log->is_debug) {

		$log->debug("Feed Info:");

		for my $feed (@feeds) {

			$log->debug(join(', ', $feed->{'name'}, $feed->{'value'}));
		}

		$log->debug('');
	}

	updateOPMLCache( \@feeds );
}

sub revertToDefaults {
	@feeds = @default_feeds;

	my @urls  = map { $_->{'value'}} @feeds;
	my @names = map { $_->{'name'}} @feeds;

	Slim::Utils::Prefs::set('plugin_podcast_feeds', \@urls);
	Slim::Utils::Prefs::set('plugin_podcast_names', \@names);
	Slim::Utils::Prefs::set('plugin_podcast_feeds_version', FEEDS_VERSION);

	updateOPMLCache( \@feeds );
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
		listRef => \@feeds,
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

		overlayRef => [
			undef,
			Slim::Display::Display::symbol('notesymbol') .
			Slim::Display::Display::symbol('rightarrow') 
		],
	);

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub webPages {
	my $class = shift;

	my $title = 'PLUGIN_PODCAST';
	my $url   = 'plugins/Podcast/index.html';
	
	Slim::Web::Pages->addPageLinks('radio', { $title => $url });

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
	
	$log->debug('Enter');
	
	# what we want the query to report about ourself
	my $data = {
		'cmd' => 'podcast',                    # cmd label
		'name' => Slim::Utils::Strings::string(getDisplayName()),  # nice name
		'type' => 'xmlbrowser',              # type
	};
	
	# let our super duper function do all the hard work
	Slim::Control::Queries::dynamicAutoQuery($request, 'radios', $cli_next, $data);
}

# Update the hashref of podcast feeds for use with the web UI
sub updateOPMLCache {
	my $feeds = shift;

	# feed_names should reflect current names
	%feed_names = ();

	map { $feed_names{$_->{'value'}} = $_->{'name'} } @feeds;
	
	my $outline = [];

	for my $item ( @{$feeds} ) {
		push @{$outline}, {
			'name'  => $item->{'name'},
			'url'   => $item->{'value'},
			'value' => $item->{'value'},
			'type'  => $item->{'type'},
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

sub updateFeedNames {
	my @feedURLPrefs  = Slim::Utils::Prefs::getArray("plugin_podcast_feeds");
	my @feedNamePrefs = ();

	# verbose debug
	if ($log->is_debug) {

		$log->debug("URLs: " . Data::Dump::dump(\@feedURLPrefs));
	}

	# case 1: we're reverting to default
	if (scalar(@feedURLPrefs) == 0) {

		revertToDefaults();
		return;
	}

	# case 2: url list edited
	my $i = 0;
	while ($i < scalar(@feedURLPrefs)) {

		my $url = $feedURLPrefs[$i];
		my $name = $feed_names{$url};

		if ($name && $name !~ /^http\:/) {

			# no change
			$feedNamePrefs[$i] = $name;

		} elsif ($url =~ /^http\:/) {

			# does a synchronous get
			my $xml = Slim::Formats::XML->getFeedSync($url);

			if ($xml && exists $xml->{'channel'}->{'title'}) {

				# here for podcasts and RSS
				$feedNamePrefs[$i] = Slim::Formats::XML::unescapeAndTrim($xml->{'channel'}->{'title'});

			} elsif ($xml && exists $xml->{'head'}->{'title'}) {

				# here for OPML
				$feedNamePrefs[$i] = Slim::Formats::XML::unescapeAndTrim($xml->{'head'}->{'title'});

			} else {
				# use url as title since we have nothing else
				$feedNamePrefs[$i] = $url;
			}

		} else {
			# use url as title since we have nothing else
			$feedNamePrefs[$i] = $url;
		}

		$i++;
	}

	# if names array contains more than urls, delete the extras
	while ($feedNamePrefs[$i]) {
		delete $feedNamePrefs[$i];
		$i++;
	}

	# save updated names to prefs
	Slim::Utils::Prefs::set('plugin_podcast_names', \@feedNamePrefs);

	# runtime list must reflect changes
	@feeds = ();

	for (my $i = 0; $i < scalar(@feedNamePrefs); $i++) {

		push @feeds, {
			name  => $feedNamePrefs[$i],
			value => $feedURLPrefs[$i],
			type  => 'link',
		};
	}

	updateOPMLCache( \@feeds );
}

1;
