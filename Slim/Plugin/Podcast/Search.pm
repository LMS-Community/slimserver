package Slim::Plugin::Podcast::Search;

# Logitech Media Server Copyright 2005-2020 Logitech.

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use JSON::XS::VersionOneAndTwo;
use XML::Simple;

use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string cstring);

my $log   = logger('plugin.podcast');
my $prefs = preferences('plugin.podcast');

my @providers = ( {
		name   => 'Apple/iTunes',
		result => 'results',
		feed   => 'feedUrl',
		title  => 'collectionName',
		image  => ['artworkUrl600', 'artworkUrl100'],
		setup => sub {
			my $url = 'https://itunes.apple.com/search?media=podcast&term=' . shift;
			my $country = $prefs->get('country');			
			return $url .= "&country=$country" if $country;
		},
	}, {
		name  => 'GPodder', 
		title => 'title',
		feed  => 'url',
		image =>  ['scaled_logo_url', 'logo_url'],
		setup => sub {
			return 'https://gpodder.net/search.json?q=' . shift;
		},
	}
);

sub searchHandler {
	my ($client, $cb, $args) = @_;

	my ($provider) = grep { $_->{name} eq $prefs->get('provider') } @providers;
	$provider ||= $providers[0];

	my $request = HTTP::Request->new('GET');
	my $url = $provider->{setup}->($args->{search}, $request);
	my $cache = Slim::Utils::Cache->new();
	
	# try to get these from cache
	if (my $items = $cache->get('podcast-search-' . $url)) {
		$cb->( { items => $items } );
		return;
	}

	# if not found in cache then re-acquire
	my $http = Slim::Networking::Async::HTTP->new;		
	$request->uri($url);
	$request->header('User-Agent' => 'Mozilla/5.0');

	$http->send_request( {
		# itunes kindly sends us in a redirection loop when we use default LMS uaer-agent
		request => $request, 
		onBody  => sub {
			my $result = eval { from_json( shift->response->content ) };
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
				
			# assume that new podcast *feeds* do not change too often
			$cache->set('podcast-search-' . $url, $items, '1day') if $items;

			$cb->( { items => $items } );
		},
		onError => sub {
			$log->error("Search failed $_[1]");
			$cb->({ items => [{ 
					type => 'text',
					name => cstring($client, 'PLUGIN_PODCAST_SEARCH_FAILED'), 
			}] });
		}
	} );
}

sub getProviders {
	my @list = map { $_->{name} } @providers;
	return \@list;
}


1;