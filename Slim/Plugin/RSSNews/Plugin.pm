package Slim::Plugin::RSSNews::Plugin;

# RSS News Browser
# Copyright 2006-2009 Logitech
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.
#
# This is a reimplementation of the old RssNews plugin based on
# the Podcast Browser plugin.
#
# $Id: Plugin.pm 11071 2007-01-01 15:47:59Z adrian $

use strict;
use base qw(Slim::Plugin::Base);

use HTML::Entities;
use XML::Simple;

use Slim::Buttons::XMLBrowser;
use Slim::Formats::XML;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.rssnews',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

if ( main::WEBUI ) {
 	require Slim::Plugin::RSSNews::Settings;
}

my $prefs = preferences('plugin.rssnews');

use constant FEED_VERSION => 3; # bump this number when changing the defaults below

# Default feed list
sub DEFAULT_FEEDS {[
	{
		name  => 'BBC News World Edition',
		value => 'http://news.bbc.co.uk/rss/newsonline_world_edition/front_page/rss.xml',
	},
	{
		name  => 'CNET News.com',
		value => 'http://news.com.com/2547-1_3-0-5.xml',
	},
	{
		name  => 'New York Times Home Page',
		value => 'http://www.nytimes.com/services/xml/rss/nyt/HomePage.xml',
	},
	{
		name  => 'Slashdot',
		value => 'http://rss.slashdot.org/Slashdot/slashdot',
	},
	{
		name  => 'Yahoo! News: Business',
		value => 'http://rss.news.yahoo.com/rss/business',
	},
];}

# migrate old prefs across
$prefs->migrate(1, sub {

	require Slim::Utils::Prefs::OldPrefs;

	my @names  = @{Slim::Utils::Prefs::OldPrefs->get('plugin_RssNews_names') || [] };
	my @values = @{Slim::Utils::Prefs::OldPrefs->get('plugin_RssNews_feeds') || [] };
	my @feeds;

	for my $name (@names) {
		push @feeds, { 'name' => $name, 'value' => shift @values };
	}

	if (@feeds) {
		$prefs->set('feeds', \@feeds);
		$prefs->set('modified', 1);
	}

	$prefs->set('items_per_feed', Slim::Utils::Prefs::OldPrefs->get('plugin_RssNews_items_per_feed') || 3);

	1;
});

# migrate to latest version of default feeds if they have not been modified
$prefs->migrate(FEED_VERSION, sub {
	$prefs->set('feeds', DEFAULT_FEEDS()) unless $prefs->get('modified');
	1;
});

# $refresh_sec is the minimum time in seconds between refreshes of the ticker from the RSS.
# Please do not lower this value. It prevents excessive queries to the RSS.
my $refresh_sec = 60 * 60;

# per-client screensaver state information
my $savers = {};

sub initPlugin {
	my $class = shift;

	main::INFOLOG && $log->info("Initializing.");

	$class->SUPER::initPlugin();

	if ( main::WEBUI ) {
		Slim::Plugin::RSSNews::Settings->new;
	}

	Slim::Buttons::Common::addMode('PLUGIN.RSS', getFunctions(), \&setMode);

#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F
    Slim::Control::Request::addDispatch(['rss', 'items', '_index', '_quantity'],
        [0, 1, 1, \&cliQuery]);

	Slim::Buttons::Common::addSaver(
		'SCREENSAVER.rssnews',
		getScreensaverRssNews(),
		\&setScreensaverRssNewsMode,
		\&leaveScreenSaverRssNews,
		'PLUGIN_RSSNEWS_SCREENSAVER'
	);

	if (main::DEBUGLOG && $log->is_debug) {

		$log->debug("RSS Feed Info:");

		for my $feed (@{ $prefs->get('feeds') }) {

			$log->debug(join(', ', ($feed->{'name'}, $feed->{'value'})));
		}

		$log->debug("");
	}

	updateOPMLCache( $prefs->get('feeds') );
}

sub getDisplayName {
	return 'PLUGIN_RSSNEWS';
}

# Don't add this item to any menu
sub playerMenu { }

sub getFunctions {
	return {};
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
		header => '{PLUGIN_RSSNEWS}',
		headerAddCount => 1,
		listRef => $prefs->get('feeds'),
		modeName => 'RSS Plugin',
		onRight => sub {
			my $client = shift;
			my $item = shift;
			my %params = (
				url     => $item->{'value'},
				title   => $item->{'name'},
				expires => $refresh_sec,
			);
			Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);
		},

		overlayRef => sub { return [ undef, shift->symbols('rightarrow') ] },
	);

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub cliQuery {
	my $request = shift;
	
	main::INFOLOG && $log->info("Begin Function");
	
	# Get OPML list of feeds from cache
	my $cache = Slim::Utils::Cache->new();
	my $opml = $cache->get( 'rss_opml' );
	Slim::Control::XMLBrowser::cliQuery('rss', $opml, $request, $refresh_sec);
}

# Update the hashref of RSS feeds for use with the web UI
sub updateOPMLCache {
	my $feeds = shift;
	
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
		'title' => string('PLUGIN_RSSNEWS'),
		'url'   => 'rss_opml',			# Used so XMLBrowser can look this up in cache
		'type'  => 'opml',
		'items' => $outline,
	};
		
	my $cache = Slim::Utils::Cache->new();
	$cache->set( 'rss_opml', $opml, '10days' );
}

################################
# ScreenSaver Mode

sub getScreensaverRssNews {

	return {
		'done' => sub  {
			my ($client, $funct, $functarg) = @_;

			Slim::Buttons::Common::popMode($client);
			$client->update;

			# pass along ir code to new mode if requested
			if (defined $functarg && $functarg eq 'passback') {
				Slim::Hardware::IR::resendButton($client);
			}
		}
	};
}

sub setScreensaverRssNewsMode {
	my $client = shift;

	# init params
	$savers->{$client} = {
		newfeed  => 1,
		line1    => 0,
	};

	$client->lines(\&blankLines);

	# start tickerUpdate in future after updates() caused by server mode change
	Slim::Utils::Timers::setTimer(
		$client, 
		Time::HiRes::time() + 0.5,
		\&tickerUpdate
	);
}

# kill tickerUpdate
sub leaveScreenSaverRssNews {
	my $client = shift;

	Slim::Utils::Timers::killTimers($client, \&tickerUpdate);
	Slim::Utils::Timers::killTimers($client, \&tickerUpdateCheck);

	delete $savers->{$client};
	
	main::INFOLOG && $log->info("Leaving screensaver mode");
}

sub tickerUpdate {
	my $client = shift;

	if ( $savers->{$client}->{newfeed} ) {
		# we need to fetch the next feed
		getNextFeed( $client );
	}
	else {
		tickerUpdateContinue( $client );
	}
}

sub getNextFeed {
	my $client = shift;

	my @feeds = @{ $prefs->get('feeds') };
	
	# select the next feed and fetch it
	my $index = $savers->{$client}->{feed_index} || 0;
	$index++;
	
	if ( $index > scalar @feeds ) {
		$index = 1;
		# reset error count after looping around to the beginning
		$savers->{$client}->{feed_error} = 0;
	}
	
	$savers->{$client}->{feed_index} = $index;
	
	my $url = $feeds[$index - 1]->{'value'};
	
	main::INFOLOG && $log->info("Fetching next feed: $url");
	
	if ( !$savers->{$client}->{current_feed} ) {
		$client->update( {
			'line' => [ 
				$client->string('PLUGIN_RSSNEWS'),
				$client->string('PLUGIN_RSSNEWS_WAIT')
			],
		} );
	}
	
	Slim::Formats::XML->getFeedAsync( 
		\&gotNextFeed,
		\&gotError,
		{
			'url'     => $url,
			'client'  => $client,
			'expires' => $refresh_sec,
		},
	);
}

sub gotNextFeed {
	my ( $feed, $params ) = @_;
	my $client = $params->{'client'};
	
	# Bug 3860, If the user left screensaver mode while we were fetching the feed, cancel out
	if ( !exists $savers->{$client} ) {
		return;
	}
	
	$savers->{$client}->{current_feed} = $feed;
	$savers->{$client}->{current_url}  = $params->{'url'};

	tickerUpdateContinue( $client );
}

sub gotError {
	my ( $error, $params ) = @_;
	my $client = $params->{'client'};
	my $url    = $params->{'url'};
	
	# Bug 3860, If the user left screensaver mode while we were fetching the feed, cancel out
	if ( !exists $savers->{$client} ) {
		return;
	}
	
	# Bug 1664, skip broken feeds in screensaver mode
	$log->error("While loading feed $url: $error, skipping!");
	
	my $errors = $savers->{$client}->{feed_error} || 0;
	$errors++;
	$savers->{$client}->{feed_error} = $errors;
	
	my @feeds =  @{ $prefs->get('feeds') };
	
	if ( $errors >= scalar @feeds ) {

		$log->error("All feeds failed, giving up!!");
		
		$client->update( {
			'line' => [
				$client->string('PLUGIN_RSSNEWS'),
				$client->string('PLUGIN_RSSNEWS_ERROR')
			],
		} );
	}
	else {	
		getNextFeed( $client );
	}
}

sub tickerUpdateContinue {
	my $client = shift;
	
	# Bug 3860, If the user left screensaver mode, cancel out
	if ( !exists $savers->{$client} ) {
		return;
	}
	
	$savers->{$client}->{line1} = 0;

	# add item to ticker
	$client->update( tickerLines($client) );

	my ($complete, $queue) = $client->scrollTickerTimeLeft();
	my $newfeed = $savers->{$client}->{newfeed};

	# schedule for next item as soon as queue drains if same feed or after ticker completes if new feed
	my $next = $newfeed ? $complete : $queue;

	Slim::Utils::Timers::setTimer(
		$client, 
		Time::HiRes::time() + ( ($next > 1) ? $next : 1),
		\&tickerUpdate
	);
}

# check to see if ticker is empty and schedule immediate ticker update if so
sub tickerUpdateCheck {
	my $client = shift;

	my ($complete, $queue) = $client->scrollTickerTimeLeft();

	if ( $queue == 0 && Slim::Utils::Timers::killTimers($client, \&tickerUpdate) ) {
		tickerUpdate($client);
	}
}

# lines when called by server - e.g. on screensaver start or change of font size
# add undef line2 item to ticker, schedule tickerUpdate to add to ticker if necessary
sub blankLines {
	my $client = shift;

	my $parts = {
		'line'   => [ $savers->{$client}->{line1} || '' ],
		'ticker' => [ undef, '' ],
	};

	# check after the update calling this function is complete to see if ticker is empty
	# (to refill ticker on font size change as this clears current ticker)
	Slim::Utils::Timers::killTimers( $client, \&tickerUpdateCheck );	
	Slim::Utils::Timers::setTimer(
		$client, 
		Time::HiRes::time() + 0.1,
		\&tickerUpdateCheck
	);

	return $parts;
}

# lines for tickerUpdate to add to ticker
sub tickerLines {
	my $client = shift;

	my $parts         = {};
	my $new_feed_next = 0; # use new feed next call

	# the current RSS feed
	my $feed = $savers->{$client}->{current_feed};
	my $url  = $savers->{$client}->{current_url};

	assert( ref $feed eq 'HASH', "current rss feed not set\n");

	# the current item within each feed.
	my $current_items = $savers->{$client}->{current_items};

	if ( !defined $current_items ) {

		$current_items = {
			$url => {
				'next_item'  => 0,
				'first_item' => 0,
			},
		};

	}
	elsif ( !defined $current_items->{$url} ) {

		$current_items->{$url} = {
			'next_item'  => 0,
			'first_item' => 0
		};
	}

	# add item to ticker or display error and wait for tickerUpdate to retrieve news
	if ( defined $feed ) {
	
		my $i = $current_items->{$url}->{'next_item'};

		# handle case of feed index no longer being valid (feed refetched with less items)
		if (!defined $feed->{'items'}->[$i]) {
			$i = 0;
			$current_items->{$url}->{'first_item'} = 0;
		}

		my $line1 = Slim::Formats::XML::unescapeAndTrim( $feed->{'title'} );
		my $line2;
		
		my $title       = Slim::Formats::XML::unescapeAndTrim( $feed->{'items'}->[$i]->{'title'} );
		my $description = Slim::Formats::XML::unescapeAndTrim( $feed->{'items'}->[$i]->{'description'} );

		if ($title && $description) {

			$line2 = "$title -- $description";

		} elsif ($title) {

			$line2 = $title;

		} elsif ($description) {

			$line2 = $description;

		} else {

			$line2 = '';
		}

		# we need to limit the number of characters we add to the ticker, 
		# because the server could crash rendering on pre-SqueezeboxG displays.
		my $screensaver_chars_per_item = 1024;

		if ( length $line2 > $screensaver_chars_per_item ) {

			$line2 = substr $line2, 0, $screensaver_chars_per_item;

			main::DEBUGLOG && $log->debug("Screensaver character limit exceeded - truncating.");
		}

		$current_items->{$url}->{'next_item'} = $i + 1;

		my $screensaver_items_per_feed = $prefs->get('items_per_feed') || 3;

		if ( !exists( $feed->{'items'}->[ $current_items->{$url}->{'next_item'} ] ) ) {

			$current_items->{$url}->{'next_item'}  = 0;
			$current_items->{$url}->{'first_item'} -= ($i + 1);

			if ( $screensaver_items_per_feed >= ($i + 1) ) {

				$new_feed_next = 1;

				$current_items->{$url}->{'first_item'} = 0;
			}
		}

		if ( ($current_items->{$url}->{'next_item'} - 
		      $current_items->{$url}->{'first_item'}) >= $screensaver_items_per_feed ) {

			# displayed $screensaver_items_per_feed of this feed, move on to next saving position
			$new_feed_next = 1;
			$current_items->{$url}->{'first_item'} = $current_items->{$url}->{'next_item'};
		}

		my $format = preferences('server')->get('timeFormat');
		$format =~ s/.\%S//i;
		
		my $overlay = Slim::Utils::DateTime::timeF(undef,$format);
		
		$parts = {
			'line'   => [ $line1 ],
			'overlay' => [ $overlay ],
			'ticker' => [ undef, $line2 ],
		};

		$savers->{$client}->{line1} = $line1;
		$savers->{$client}->{current_items} = $current_items;
	}
	else {

		$parts = {
			'line' => [ "RSS News - ". $feed->{'title'}, $client->string('PLUGIN_RSSNEWS_WAIT') ]
		};

		$new_feed_next = 1;
	}

	$savers->{$client}->{newfeed} = $new_feed_next;

	return $parts;
}

# SN only
sub feedsForClient {
	my $client = shift;
	
	my $userid = $client->playerData->userid->id;
	
	my @f = SDI::Service::Model::FavoriteFeed->search(
		userid => $userid,
		{ order_by => 'num' }
	);
													  
	my @feeds = map { 
		{ 
			name  => Slim::Utils::Unicode::utf8decode($_->title), 
			value => $_->url,
		}
	} @f;
	
	# check if the user deleted feeds so we don't load the defaults
	my $deletedFeeds = preferences('server')->client($client)->get('deleted_feeds');
	
	# Populate with all default feeds
	if ( !scalar @feeds && !$deletedFeeds ) {
		@feeds = map { 
			{ 
				name  => $_->title, 
				value => $_->url,
			}
		} SDI::Service::Model::FavoriteFeed->addDefaults( $userid );
	}
	
	return @feeds;
}

1;
