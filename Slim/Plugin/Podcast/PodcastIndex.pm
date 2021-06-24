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

use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::Strings qw(string cstring);

my $prefs = preferences('plugin.podcast');
my $log = logger('plugin.podcast');

$prefs->init( { podcastindex => {
	k => 'NTVhNTMzODM0MzU1NDM0NTQ1NTRlNDI1MTU5NTk1MzRhNDYzNzRkNA==',
	s => 'ODQzNjc1MDc3NmQ2NDQ4MzQ3OTc4NDczNzc1MzE3MTdlNTM3YzQzNTI2ODU1NWE0MzIyNjE2ZTU0MjMyOTdhN2U2ZTQyNWU0ODQ0MjM0NTU=',
} } );

# add a new episode menu to defaults
sub getMenuItems {
	my ($self, $client) = @_;

	return [ @{$self->SUPER::getMenuItems}, {
		title => cstring($client, 'PLUGIN_PODCAST_WHATSNEW', $prefs->get('newSince')),
		image => 'plugins/Podcast/html/images/podcastindex.png',
		type => 'link',
		url => \&newsHandler,
	} ];
}

sub getSearchParams {
	return ('https://api.podcastindex.org/api/1.0/search/byterm?q=' . $_[3] , getHeaders());
}

sub parseStart {
	return {
		index => 0,
		feeds => $_[1]->{feeds},
	};
}

sub parseNext {
	my ($self, $iterator) = @_;

	my $feed = $iterator->{feeds}->[$iterator->{index}++];
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
}

sub newsHandler {
	my ($client, $cb, $args, $passthrough) = @_;

	my $headers = getHeaders();
	my @feeds = @{$prefs->get('feeds')};
	my $count = scalar @feeds;

	return $cb->(undef) unless $count;

	my $items = [];

	$log->info("about to get updates for $count podcast feeds");

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

				unless (--$count) {
					$items = [ sort { $a->{date} < $b->{date} } @$items ];
					$cb->( { items => $items } );
				}
			},
			sub {
				$log->warn("can't get new episodes for $url ", shift->error);
				unless (--$count) {
					$items = [ sort { $a->{date} < $b->{date} } @$items ];
					$cb->( { items => $items } );
				}

			},
			{
				cache => 1,
				expires => 600,
				timeout => 15,
			},
		)->get($url, @$headers);
	}
}

sub getHeaders {
	my $config = $prefs->get('podcastindex');
	my $k = pack('H*', scalar(reverse(MIME::Base64::decode($config->{k}))));
	my $s = pack('H*', scalar(reverse(MIME::Base64::decode($config->{s}))));
	my $time = time;
	my $headers = [
		'X-Auth-Key', $k,
		'X-Auth-Date', $time,
		'Authorization', sha1_hex($k . $s . $time),
	];
}

sub getName { 'PodcastIndex'}


1;