package Slim::Plugin::Podcast::Plugin;

# Logitech Media Server Copyright 2005-2020 Logitech.

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::OPMLBased);

use XML::Simple;

use Slim::Plugin::Podcast::Parser;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string cstring);
use Slim::Utils::Timers;

use Slim::Plugin::Podcast::ProtocolHandler;
use Slim::Plugin::Podcast::Search;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.podcast',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

tie my %recentlyPlayed, 'Tie::Cache::LRU', 50;

my $prefs = preferences('plugin.podcast');
my $cache;

$prefs->init({
	feeds => [],
	skipSecs => 15,
	recent => [],
});

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

	$class->SUPER::initPlugin(
		feed   => \&handleFeed,
		tag    => 'podcasts',
		menu   => 'apps',
	);

	$class->addNonSNApp();
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

sub unwrapUrl {
	return shift =~ m|^podcast://([^{]+)(?:{from=(\d+)}$)?|;
}

sub wrapUrl {
	my ($url, $from) = @_;

	return 'podcast://' . $url . (defined $from ? "{from=$from}" : '');
}

sub handleFeed {
	my ($client, $cb, $params, $args) = @_;

	my @feeds = @{$prefs->get('feeds')};
	my $items = [ {
			name   => cstring($client, 'PLUGIN_PODCAST_SEARCH'),
			type   => 'search',
			url    => \&Slim::Plugin::Podcast::Search::searchHandler,
		}, {
			name  => cstring($client, 'PLUGIN_PODCAST_RECENTLY_PLAYED'),
			url   => \&recentHandler,
			type  => 'link',
			image => __PACKAGE__->_pluginDataFor('icon'),
		}
	];

	foreach ( @feeds ) {
		my $url = $_->{value};
		my $image = $cache->get('podcast-rss-' . $url);

		push @$items, {
			name => $_->{name},
			url  => $url,
			parser => 'Slim::Plugin::Podcast::Parser',
			image => $image || __PACKAGE__->_pluginDataFor('icon'),
		};

		unless ($image) {
			# always cache image avoid sending a flood of requests
			$cache->set('podcast-rss-' . $url, __PACKAGE__->_pluginDataFor('icon'), '1days');

			Slim::Networking::SimpleAsyncHTTP->new(
				sub {
					eval {
						my $xml = XMLin(shift->content);
						my $image = $xml->{channel}->{image}->{url} || $xml->{channel}->{'itunes:image'}->{href};
						$cache->set('podcast-rss-' . $url, $image, '90days') if $image;
					};

					$log->warn("can't parse $url RSS for feed icon: ", $@) if $@;
				},
				sub {
					$log->warn("can't get $url RSS feed icon: ", shift->error);
				},
			)->get($_->{value});
		}
	}

	$cb->({
		items => $items,
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

	$cb->({ items => \@menu });
}

sub getDisplayName {
	return 'PLUGIN_PODCAST';
}

sub trackInfoMenu {
	my ( $client, $url, $track, $remoteMeta ) = @_;

	return unless $url && $client && $client->isPlaying;

	my $song = Slim::Player::Source::playingSong($client);
	return unless $song && $song->canSeek;

	if ( $url && defined $cache->get('podcast-' . $url) ) {
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

	return;
}

1;