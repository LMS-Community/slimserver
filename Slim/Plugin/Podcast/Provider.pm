package Slim::Plugin::Podcast::Provider;

# Logitech Media Server Copyright 2005-2021 Logitech.

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Digest::SHA1 qw(sha1_hex);
use JSON::XS::VersionOneAndTwo;
use Encode qw(encode);

use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string cstring);

my $log   = logger('plugin.podcast');
my $prefs = preferences('plugin.podcast');

my @providers = ( {
		name   => 'PodcastIndex',
		result => 'feeds',
		feed   => 'url',
		title  => 'title',
		image  => ['artwork', 'image'],
		init => sub {
			$prefs->init( { podcastindex => {
				k => 'NTVhNTMzODM0MzU1NDM0NTQ1NTRlNDI1MTU5NTk1MzRhNDYzNzRkNA==',
				s => 'ODQzNjc1MDc3NmQ2NDQ4MzQ3OTc4NDczNzc1MzE3MTdlNTM3YzQzNTI2ODU1NWE0MzIyNjE2ZTU0MjMyOTdhN2U2ZTQyNWU0ODQ0MjM0NTU=',
			}});
		},
		menu => [ {
			query => sub {
				my ($self, $search) = @_;
				my $config = $prefs->get('podcastindex');
				my $k = pack('H*', scalar(reverse(MIME::Base64::decode($config->{k}))));
				my $s = pack('H*', scalar(reverse(MIME::Base64::decode($config->{s}))));
				my $time = time;
				my $headers = [
					'X-Auth-Key', $k,
					'X-Auth-Date', $time,
					'Authorization', sha1_hex($k . $s . $time),
				];
				return ('https://api.podcastindex.org/api/1.0/search/byterm?q=' . $search, $headers);
			},
		} ],
	}, {
		name  => 'GPodder',
		title => 'title',
		feed  => 'url',
		image =>  ['scaled_logo_url', 'logo_url'],
		menu => [ {
			query => sub {
				return ('https://gpodder.net/search.json?q=' . $_[1]);
			},
		} ],
	},
);

sub init {
	foreach my $provider (@providers) {
		$provider->{init}->() if $provider->{init};
	}
}

sub registerProvider {
	my ($class, $provider, $force) = @_;

	# remove existing provider if forced
	@providers = grep { $provider->{name} ne $_->{name} } @providers if $force;

	if (!grep { $provider->{name} eq $_->{name} } @providers) {
		push @providers, $provider;
	}
	else {
		$log->warn(sprintf('Podcast aggregator %s is already registered!', $provider->{name}));
	}
}

sub defaultHandler {
	my ($client, $cb, $args, $passthrough) = @_;

	my $provider = $passthrough->{provider};
	my $search = encode('utf-8', $args->{search});
	my ($url, $headers) = $passthrough->{query}->($provider, $search);

	Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $response = shift;
			my $result = eval { from_json( $response->content ) };
			$result = $result->{$provider->{result}} if $provider->{result};

			$log->error($@) if $@;
			main::DEBUGLOG && $log->is_debug && warn Data::Dump::dump($result);

			my $items = [];
			foreach my $feed (@$result) {
				next unless $feed->{$provider->{feed}};

				# find the image by order of preference
				my ($image) = grep { $feed->{$_} } @{$provider->{image}};

				push @$items, {
					name => $feed->{$provider->{title}},
					url  => $feed->{$provider->{feed}},
					image => $feed->{$image},
					parser => 'Slim::Plugin::Podcast::Parser',
				}
			}

			if (!scalar @$items) {
				return $cb->({ items => [{
					name => cstring($client, 'EMPTY')
				}] });
			}

			$cb->({
				items => $items,
				actions => {
					info => {
						command =>   ['podcastinfo', 'items'],
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

sub getProviders {
	my @list = map { $_->{name} } @providers;
	return \@list;
}

sub getCurrent {
	my ($provider) = grep { $_->{name} eq $prefs->get('provider') } @providers;
	return $provider || $providers[0];
}


1;