package Slim::Plugin::Podcast::PodcastIndex;

# Logitech Media Server Copyright 2005-2021 Logitech.

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Plugin::Podcast::Provider);

use JSON::XS::VersionOneAndTwo;
use Digest::SHA1 qw(sha1_hex);
use MIME::Base64;
use URI::Escape;

use Slim::Utils::Cache;
use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::Strings qw(string cstring);

use constant NEWS_TTL => 60;
use constant NEWS_CACHE_KEY => 'podcast_index_news';

my $cache = Slim::Utils::Cache->new();
my $prefs = preferences('plugin.podcast');
my $log = logger('plugin.podcast');

my $authtime = time;

$prefs->init( { podcastindex => {
	k => 'NTVhNTMzODM0MzU1NDM0NTQ1NTRlNDI1MTU5NTk1MzRhNDYzNzRkNA==',
	s => 'ODQzNjc1MDc3NmQ2NDQ4MzQ3OTc4NDczNzc1MzE3MTdlNTM3YzQzNTI2ODU1NWE0MzIyNjE2ZTU0MjMyOTdhN2U2ZTQyNWU0ODQ0MjM0NTU=',
} } );

$prefs->setChange( sub {
	$cache->remove(NEWS_CACHE_KEY);
}, 'newSince', 'maxNew');

# add a new episode menu to defaults
sub getMenuItems {
	my ($self, $client) = @_;

	return [ @{$self->SUPER::getMenuItems}, {
		name => cstring($client, 'PLUGIN_PODCAST_WHATSNEW', $prefs->get('newSince')),
		image => 'plugins/Podcast/html/images/podcastindex.png',
		type => 'link',
		url => \&newsHandler,
	} ];
}

sub getSearchParams {
	return ('https://api.podcastindex.org/api/1.0/search/byterm?q=' . $_[3] , getHeaders());
}

sub getFeedsIterator {
	my ($self, $feeds) = @_;

	my $index;
	$feeds = $feeds->{feeds};

	# iterator on feeds
	return sub {
		my $feed = $feeds->[$index++];
		return unless $feed;

		my ($image) = grep { $feed->{$_} } qw(artwork image);

		return {
			name         => $feed->{title},
			url          => $feed->{url},
			image        => $feed->{$image},
			description  => $feed->{description},
			author       => $feed->{author},
			language     => $feed->{language},
		};
	};
}

sub newsHandler {
	my ($client, $cb, $args, $passthrough) = @_;

	if (my $cached = $cache->get(NEWS_CACHE_KEY)) {
		main::INFOLOG && $log->is_info && $log->info("Returning cached PodcastIndex news");
		return $cb->({ items => $cached });
	}

	my $headers = getHeaders();
	my @feeds = @{$prefs->get('feeds')};
	my $count = scalar @feeds;

	return $cb->(undef) unless $count;

	my $items = [];

	$log->info("about to get updates for $count podcast feeds");

	my $cb2 = sub {
		if (!--$count) {
			main::INFOLOG && $log->is_info && $log->info("Done getting updates");
			$items = [ sort { $b->{date} <=> $a->{date} } @$items ];
			$cache->set(NEWS_CACHE_KEY, $items, NEWS_TTL);
			$cb->( { items => $items } );
		};
	};

	foreach my $feed (@feeds) {
		my $url = 'https://api.podcastindex.org/api/1.0/episodes/byfeedurl?url=' . uri_escape($feed->{value});
		$url .= '&since=-' . $prefs->get('newSince')*3600*24 . '&max=' . $prefs->get('maxNew');
		Slim::Networking::SimpleAsyncHTTP->new(
			sub {
				my $response = shift;
				my $result = eval { from_json( $response->content ) };

				$log->warn("error parsing new episodes for $url", $@) if $@;
				main::INFOLOG && $log->is_info && $log->info("found $result->{count} for $url");

				foreach my $item (@{$result->{items}}) {
					push @$items, {
						name  => $item->{title},
						enclosure => { url => Slim::Plugin::Podcast::Plugin::wrapUrl($item->{enclosureUrl}) },
						image => $item->{image} || $item->{feedImage},
						date  => $item->{datePublished},
						type  => 'audio',
					};
				}

				$cb2->();
			},
			sub {
				$log->warn("can't get new episodes for $url ", shift->error);
				$cb2->();
			},
			{
				cache => 1,
				expires => 900,
				timeout => 30,
			},
		)->get($url, @$headers);
	}
}

sub getHeaders {
	my $config = $prefs->get('podcastindex');
	my $k = pack('H*', scalar(reverse(MIME::Base64::decode($config->{k}))));
	my $s = pack('H*', scalar(reverse(MIME::Base64::decode($config->{s}))));
	# try to fit in a 5 minutes window for cache
	my $now = time;
	$authtime = $now if $now - $authtime >= 300;

	my $headers = [
		'X-Auth-Key', $k,
		'X-Auth-Date', $authtime,
		'Authorization', sha1_hex($k . $s . $authtime),
	];
}

sub getName { 'PodcastIndex'}


1;