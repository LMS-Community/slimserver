package Slim::Plugin::Podcast::Search;

# Logitech Media Server Copyright 2005-2020 Logitech.

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
		setup => sub {
			my ($search, $request) = @_;
			my $key = 'GJMAQPVCCGAGCQ8RRGZY';
			my $time = time;
			my $headers = [
				'X-Auth-Key', $key,
				'X-Auth-Date', $time,
				# is there a secure storage?
				'Authorization', sha1_hex($key . 'Yg$hwNRPHuKhkzEzujjgmwWrAryprFjrrZg^QnTm' . $time),
			];
			return ('https://api.podcastindex.org/api/1.0/search/byterm?q=' . $search, $headers);
		},
	}, {
		name  => 'GPodder',
		title => 'title',
		feed  => 'url',
		image =>  ['scaled_logo_url', 'logo_url'],
		setup => sub {
			return ('https://gpodder.net/search.json?q=' . shift);
		},
	},
);

# this would be moved to a 3rd party plugin:
__PACKAGE__->registerProvider({
 	name   => 'Apple/iTunes',
	result => 'results',
	feed   => 'feedUrl',
	title  => 'collectionName',
	image  => ['artworkUrl600', 'artworkUrl100'],
	setup => sub {
		my $url = 'https://itunes.apple.com/search?media=podcast&term=' . shift;
		my $country = $prefs->get('country');
		$url .= "&country=$country" if $country;
		# iTunes kindly sends us in a redirection loop when we use default LMS user-agent
		return ($url, [ 'User-Agent', 'Mozilla/5.0' ]);
	},
});

sub registerProvider {
	my ($class, $provider) = @_;

	if (!grep { $provider->{name} eq $_->{name} } @providers) {
		push @providers, $provider;
	}
	else {
		$log->warn(sprintf('Podcast aggregator %s is already registered!', $provider->{name}));
	}
}

sub searchHandler {
	my ($client, $cb, $args) = @_;

	my ($provider) = grep { $_->{name} eq $prefs->get('provider') } @providers;
	$provider ||= $providers[0];

	my $search = encode('utf-8', $args->{search});
	my ($url, $headers) = $provider->{setup}->($search);

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

			$cb->( { items => $items } );
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


1;