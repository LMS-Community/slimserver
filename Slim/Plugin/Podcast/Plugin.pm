package Slim::Plugin::Podcast::Plugin;

# Logitech Media Server Copyright 2005-2020 Logitech.

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::OPMLBased);

use XML::Simple;
use JSON::XS::VersionOneAndTwo;
use Encode qw(encode);

use Slim::Plugin::Podcast::Parser;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string cstring);
use Slim::Utils::Timers;

use Slim::Plugin::Podcast::ProtocolHandler;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.podcast',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

tie my %recentlyPlayed, 'Tie::Cache::LRU', 50;

my $prefs = preferences('plugin.podcast');
my $cache;

my %providers = ();

# migrate old prefs across
$prefs->migrate(1, sub {
	require Slim::Utils::Prefs::OldPrefs;
	my @names  = @{Slim::Utils::Prefs::OldPrefs->get('plugin_podcast_names') || [] };
	my @values = @{Slim::Utils::Prefs::OldPrefs->get('plugin_podcast_feeds') || [] };
	my @feeds;

	for my $name (@names) {
		push @feeds, { 'name' => $name, 'value' => shift @values };
	}

	if (@feeds) {
		$prefs->set('feeds', \@feeds);
	}

	1;
});

sub initPlugin {
	my $class = shift;

	$cache = Slim::Utils::Cache->new();

	registerProvider('Slim::Plugin::Podcast::PodcastIndex');
	registerProvider('Slim::Plugin::Podcast::GPodder');

	$prefs->init({
		feeds => [],
		skipSecs => 15,
		recent => [],
		provider => Slim::Plugin::Podcast::PodcastIndex->getName(),
		newSince => 7,
		maxNew => 7,
		country => '',
	});

	if (main::WEBUI) {
		require Slim::Plugin::Podcast::Settings;
		Slim::Plugin::Podcast::Settings->new();
	}

	# Track Info item: jump back X seconds
	Slim::Menu::TrackInfo->registerInfoProvider( podcastRew => (
		before => 'top',
		func   => \&trackInfoMenu,
	) );

	# create wrapped pseudo-tracks for recently played to have title during scanUrl
	foreach my $item (@{$prefs->get('recent')}) {
		my $track = Slim::Schema->updateOrCreate( {
			url        => wrapUrl($item->{url}),
			attributes => {
				TITLE => $item->{title},
				ARTWORK => $item->{cover},
			},
		} );
	}

	%recentlyPlayed = map { $_->{url} => $_ } reverse @{$prefs->get('recent')};

	Slim::Control::Request::addDispatch(
		[ 'podcastinfo', 'items', '_index', '_quantity' ],
		[ 0, 1, 1, \&showInfo ]
	);

	Slim::Control::Request::addDispatch(
		[ 'podcasts', 'addshow', '_url', '_name' ],
		[ 0, 0, 0, \&addShow ]
	);

	Slim::Control::Request::addDispatch(
		[ 'podcasts', 'delshow', '_url' ],
		[ 0, 0, 0, \&delShow ]
	);

	$class->SUPER::initPlugin(
		feed   => \&handleFeed,
		tag    => 'podcasts',
		menu   => 'apps',
	);
}

sub shutdownPlugin {
	my @played = values %recentlyPlayed;

	$prefs->set('recent', \@played);
}

sub updateRecentlyPlayed {
	my ($class, $client, $song) = @_;
	my $track = $song->currentTrack;
	my ($url) = unwrapUrl($track->url);

	$recentlyPlayed{$url} = {
		url      => $url,
		title    => Slim::Music::Info::getCurrentTitle($client, $track->url),
		# this is not great as we should not know that...
		cover    => $cache->get('remote_image_' . $track->url) || Slim::Player::ProtocolHandlers->iconForURL($track->url, $client),
		duration => $song->duration,
	};
}

sub handleFeed {
	my ($client, $cb, $params, $args) = @_;

	my $items = [];
	my $provider = getProviderByName();

	# populate provider's custom menu
	foreach my $item (@{$provider->getMenuItems($client)}) {
		$item->{name}  ||= cstring($client, 'PLUGIN_PODCAST_SEARCH');
		$item->{type}  ||= 'search';
		$item->{url}   ||= \&searchHandler unless $item->{enclosure};
		$item->{passthrough} ||= [ { provider => $provider, item => $item } ];

		if (!$item->{image} || ref $item->{image}) {
			$item->{image} = 'html/images/search.png';
		}

		push @$items, $item;
	}

	# then add recently played
	push @$items, {
		name  => cstring($client, 'PLUGIN_PODCAST_RECENTLY_PLAYED'),
		url   => \&recentHandler,
		type  => 'link',
		image => __PACKAGE__->_pluginDataFor('icon'),
	};

	# then existing feeds
	my @feeds = @{$prefs->get('feeds')};
	my @need;
	my $fetch;

	foreach ( @feeds ) {
		my $url = $_->{value};
		my $image = $cache->get('podcast-rss-' . $url);

		push @$items, {
			name => $_->{name},
			url  => $url,
			favorites_url => $url,
			favorites_type => 'link',
			parser => 'Slim::Plugin::Podcast::Parser',
			image => $image || __PACKAGE__->_pluginDataFor('icon'),
			playlist => $url,
		};

		# if pre-cached feed data is missing, initiate retrieval
		unless ($image && $cache->get('podcast_moreInfo_' . $url)) {
			# cache a placeholder image & moreInfo to guard against retrieving
			# the feed multiple times while browsing within the podcast menu
			# they will be replaced with real data after feed is successfully retrieved
			$cache->set('podcast-rss-' . $url, __PACKAGE__->_pluginDataFor('icon'), '1days');
			$cache->set('podcast_moreInfo_' . $url, {}, '1days');
			push (@need, $url);
		}
	}

	# get missing cache images & moreinfo if any
	# each feed is retrieved and parsed sequentially, to limit loading on modestly powered servers
	$fetch = sub {
		my $url = pop @need;
		Slim::Formats::XML->getFeedAsync(
			sub {
				# called by feed parser, so not needed here
				# precacheFeedData($url, $_[0]);
				$fetch->();
			},
			sub {
				$log->warn("can't get $url RSS feed information: ", $_[0]);
				$fetch->();
			},
			{
				parser  => 'Slim::Plugin::Podcast::Parser',
				url     => $url,
			}
		) if $url;
	};
	$fetch->();

	$cb->({
		items => $items,
		actions => {
			info => {
				command   => ['podcastinfo', 'items'],
				variables => [ 'url', 'url', 'name', 'name', 'image', 'image' ],
			},
		}
	});
}

sub recentHandler {
	my ($client, $cb) = @_;
	my @menu;

	foreach my $item(reverse values %recentlyPlayed) {
		my $from = $cache->get('podcast-' . $item->{url});

		# every entry here has a remote_image_ cached item so we can have
		# a direct play entry all the time, even if it has played fully
		my $entry = {
			title => $item->{title},
			image => $item->{cover},
			type  => 'audio',
			play  => wrapUrl($item->{url}),
			on_select => 'play',
		};

		if ( $from && $from < $item->{duration} - 15 ) {
			my $position = Slim::Utils::DateTime::timeFormat($from);
			$position =~ s/^0+[:\.]//;

			$entry->{type} = 'link',

			$entry->{items} = [ {
				title => cstring($client, 'PLUGIN_PODCAST_PLAY_FROM_POSITION_X', $position),
				cover => $item->{cover},
				enclosure => {
					type  => 'audio',
					url   => wrapUrl($item->{url}, $from),
				},
			},{
				title => cstring($client, 'PLUGIN_PODCAST_PLAY_FROM_BEGINNING'),
				cover => $item->{cover},
				enclosure => {
					type  => 'audio',
					# little trick to make sure "play from" url is not the main url
					url   => wrapUrl($item->{url}, 0),
				},
			}],
		}

		unshift @menu, $entry;
	}

	push @menu, { name => cstring($client, 'EMPTY') } if !scalar @menu;

	$cb->({ items => \@menu });
}

sub searchHandler {
	my ($client, $cb, $args, $passthrough) = @_;

	my $provider = $passthrough->{provider};
	my $search = encode('utf-8', $args->{search});
	my ($url, $headers) = $provider->getSearchParams($client, $passthrough->{item}, $search);

	Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $response = shift;
			my $result = eval { from_json( $response->content ) };

			$log->error($@) if $@;
			main::DEBUGLOG && $log->is_debug && warn Data::Dump::dump($result);

			my $items = [];
			my $next = $provider->getFeedsIterator($result);

			while ( my $feed = $next->() ) {
				# add parser if missing then add the feed to the list
				$feed->{parser} ||= 'Slim::Plugin::Podcast::Parser';
				push @$items, $feed;

				precacheFeedData($feed->{url}, $feed);
			}

			push @$items, { name => cstring($client, 'EMPTY') } if !scalar @$items;

			$cb->({
				items => $items,
				actions => {
					info => {
						command   => ['podcastinfo', 'items'],
						variables => [ 'url', 'url', 'name', 'name', 'image', 'image' ],
					},
				}
			});
		},
		sub {
			$log->error("Search failed $_[1]");
			$cb->({ items => [{
					type => 'text',
					name => cstring($client, 'PLUGIN_PODCAST_SEARCH_FAILED'),
			}] });
		},
		{
			cache => 1,
			expires => 86400,
		}
	)->get($url, @$headers);
}

sub precacheFeedData {
	my ($url, $feed) = @_;
	# sanity check
	unless (defined($url) && (ref($feed) eq 'HASH')) {
		$log->error("Unexpected feed data for URL '$url'");
		return;
	}

	# keep image for around 90 days, randomizing cache period to
	# avoid flood of simultaneous requests in future
	# it is not mandatory that a podcast include an image, so set
	# suitable default
	my $image = $feed->{image} || __PACKAGE__->_pluginDataFor('icon');
	my $cacheTime = sprintf("%.3f days", 80 + rand(20));
	$cache->set('podcast-rss-' . $url, $image, $cacheTime);

	# pre-cache some additional information to be shown in feed info menu
	my %moreInfo;

	foreach (qw(language author description)) {
		if (my $value = $feed->{$_}) {
			$moreInfo{$_} = $value;
		}
	}

	# keep moreInfo for around 90 days, same as image
	# it will not change often
	$cache->set('podcast_moreInfo_' . $url, \%moreInfo, $cacheTime);
}

sub registerProvider {
	my ($class, $force) = @_;

	eval "require $class";

	# in case somebody provides a faulty plugin
	if ($@) {
		$log->warn("cannot load $class");
		return;
	}

	my $name = $class->getName;

	# load if not already there or forced
	if (!$providers{$name} || $force) {
		$providers{$name} = $class->new;
		return $providers{$name};
	}

	$log->warn(sprintf('Podcast aggregator %s is already registered!', $name));
	return;
}

sub getProviders {
	my @list = keys %providers;
	return \@list;
}

sub getProviderByName {
	my $name = shift || $prefs->get('provider');
	return $providers{$name} || $providers{(keys %providers)[0]};
}

sub getDisplayName {
	return 'PLUGIN_PODCAST';
}

sub trackInfoMenu {
	my ( $client, $url, $track, $remoteMeta ) = @_;

	return unless unwrapUrl($url) && $client && $client->isPlaying;

	my $song = Slim::Player::Source::playingSong($client);
	return unless $song && $song->canSeek;

	my $title = $client->string('PLUGIN_PODCAST_SKIP_BACK', $prefs->get('skipSecs'));

	return [{
		name => $title,
		url  => sub {
			my ($client, $cb, $params) = @_;

			my $position = Slim::Player::Source::songTime($client);
			my $newPos   = $position > $prefs->get('skipSecs') ? $position - $prefs->get('skipSecs') : 0;

			main::DEBUGLOG && $log->is_debug && $log->debug(sprintf("Skipping from position %s back to %s", $position, $newPos));

			Slim::Player::Source::gototime($client, $newPos);

			$cb->({
				items => [{
					name        => $title,
					showBriefly => 1,
					nowPlaying  => 1, # then return to Now Playing
				}]
			});
		},
		nextWindow => 'parent',
	}];
}

sub showInfo {
	my $request = shift;

	$request->addParam('_index', 0);
	$request->addParam('_quantity', 10);

	my $client = $request->client;
	my $url    = $request->getParam('url');
	my $name   = $request->getParam('name');
	my $image  = $request->getParam('image');

	$cache->set('podcast-rss-' . $url, $image, '90days') if $image && $url;

	if ($name && $client) {
		$client->pluginData(showName => $name);
	}
	elsif ($client) {
		$name = $client->pluginData('showName');
	}

	if (ref $url || $url !~ /^http/) {
		return Slim::Control::XMLBrowser::cliQuery('podcastinfo', {
			name => $name,
			items => [{
				name => $name
			}]
		}, $request);
	}

	my $menuTitle = cstring($client, 'PLUGIN_PODCAST_SUBSCRIBE', Slim::Utils::Unicode::utf8decode($name));
	my $menuAction = 'addshow';

	if (grep { $_->{value} eq $url } @{$prefs->get('feeds') || []}) {
		$menuTitle = cstring($client, 'PLUGIN_PODCAST_UNSUBSCRIBE', Slim::Utils::Unicode::utf8decode($name));
		$menuAction = 'delshow';
	}

	my $item;
	if ($request->getParam('menu')) {
		$item = {
			type => 'link',
			name => $menuTitle,
			isContextMenu => 1,
			refresh => 1,
			jive => {
				actions => {
					go => {
						player => 0,
						cmd    => [ 'podcasts', $menuAction, $url, $name ],
					}
				},
				nextWindow => 'parent'
			},
		};
	}
	else {
		$item = {
			type => 'link',
			name => $menuTitle,
			url => sub {
				my ($client, $cb, $params, $args) = @_;

				Slim::Control::Request::executeRequest(undef, ['podcasts', $menuAction, $url, $name]);

				$cb->({
					items => [{
						type => 'text',
						name => cstring($client, 'PLUGIN_PODCAST_DONE'),
					}],
				});
			},
		};
	}

	my $items = [ $item ];

	my $moreInfo = $cache->get('podcast_moreInfo_' . $url);
	if (keys %$moreInfo) {
		if (my $desc = $moreInfo->{'description'}) {
			$desc = Slim::Formats::XML::unescapeAndTrim($desc);
			$desc =~ s/\s+/ /sg;

			push @$items, {
				type => 'text',
				name => Slim::Utils::Unicode::utf8decode($desc)
			};
		}

		if (my $author = $moreInfo->{'author'}) {
			push @$items, {
				type => 'text',
				name => cstring($client, 'PLUGIN_PODCAST_AUTHOR') . ' ' . Slim::Utils::Unicode::utf8decode($author)
			};
		}

		if (my $lang = $moreInfo->{'language'}) {
			push @$items, {
				type => 'text',
				name => cstring($client, 'LANGUAGE') . cstring($client, 'COLON') . ' ' . $lang
			};
		}
	}

	Slim::Control::XMLBrowser::cliQuery('podcastinfo', {
		name => $name,
		items => $items
	}, $request);
}

sub addShow {
	my $request = shift;

	my $url = $request->getParam('_url');
	my $name = $request->getParam('_name');

	my $feeds = $prefs->get('feeds');

	push @$feeds, {
		name  => $name,
		value => $url,
	} unless grep { $_->{value} eq $url } @$feeds;

	$prefs->set( feeds => $feeds );

	$request->setStatusDone();
}

sub delShow {
	my $request = shift;

	my $url = $request->getParam('_url');

	my $feeds = $prefs->get('feeds');

	@$feeds = grep { $_->{value} ne $url } @$feeds;

	$prefs->set( feeds => $feeds );

	$request->setStatusDone();
}

sub unwrapUrl {
	return shift =~ m|^podcast://([^{]+)(?:{from=(\d+)}$)?|;
}

sub wrapUrl {
	my ($url, $from) = @_;

	return 'podcast://' . $url . (defined $from ? "{from=$from}" : '');
}


1;