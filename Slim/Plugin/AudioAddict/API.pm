package Slim::Plugin::AudioAddict::API;

use strict;

use JSON::XS qw(decode_json);
use Tie::Cache::LRU::Expires;
use URI::Escape qw(uri_escape_utf8);

use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

use constant API_URL   => 'https://api.audioaddict.com/v1/';
use constant CACHE_TTL => 60 * 60 * 24; # 1 day
use constant NOW_PLAYING_CACHE_TTL => 3600;

my $cache = Slim::Utils::Cache->new();
my $log = logger('plugin.audioaddict');
my $prefs = preferences('plugin.audioaddict');

# in-memory cache for now playing metadata, keyed by network_channelId_metadata
tie our %metaDataCache, 'Tie::Cache::LRU::Expires', EXPIRES => NOW_PLAYING_CACHE_TTL, ENTRIES => 16;

# Auth a user/pass, returns basic member information and current subscription(s)
sub authenticate {
	my ( $class, $args, $cb ) = @_;

	# Avoid duplicate calls if we already know the listen key
	if ( my $listenKey = $prefs->get('listen_key') ) {
		$cb->({
			listen_key => $listenKey,
			subscriptions => $prefs->get('subscriptions'),
		});
	}
	else {
		_call(
			POST => '/members/authenticate',
			{
				username => $args->{username},
				password => $args->{password},
				_network => $args->{network},
			},
			sub {
				if ( my $res = shift ) {
					my $listenKey = $res->{listen_key};
					my $subscriptions = $res->{subscriptions};

					if ($listenKey && $subscriptions) {
						$prefs->set('listen_key', $listenKey);
						$prefs->set('subscriptions', $subscriptions);

						return $cb->({
							listen_key => $listenKey,
							subscriptions => $subscriptions,
						});
					}
				}

				$cb->();
			},
		);
	}
}


# Get channels organized by genre
sub channelFilters {
	my ( $class, $network, $cb ) = @_;

	# Check cache
	if ( my $cached = $cache->get('audioaddict_channel_filters_' . $network) ) {
		return $cb->($cached);
	}

	_call(
		GET => '/channel_filters',
		{
			_network => $network,
		},
		sub {
			if ( my $res = shift ) {
				$cache->set( 'audioaddict_channel_filters_' . $network, $res, CACHE_TTL );
				$cb->( $res || [] );
			}
			else {
				$cb->([]);
			}
		},
	);
}

sub nowPlaying {
	my ( $class, $network, $channelId, $metadata, $forceUpdate, $cb ) = @_;

	$network = 'radiotunes' if $network eq 'sky';
	$forceUpdate ||= !$metadata; # if we don't have metadata, we should force an update

	my $cacheKey = join('_', 'audioaddict_now_playing', $network, $channelId, $metadata);

	if ( !$forceUpdate && (my $cached = $metaDataCache{$cacheKey} || $cache->get($cacheKey)) ) {
		return $cb->($cached) if ref $cached eq 'HASH';
	}

	_call(
		GET => '/track_history/channel/' . $channelId,
		{
			_network => $network,
		},
		sub {
			if ( my $res = shift ) {
				my $entry = ref $res eq 'ARRAY' ? $res->[0] : $res;
				delete $entry->{votes};
				$metaDataCache{$cacheKey} = $entry;
				# only cache to disk if we had metadata - we don't want this to survive a server restart
				$cache->set( $cacheKey, $entry, NOW_PLAYING_CACHE_TTL ) if $metadata;
				$cb->($entry);
			}
			else {
				# don't cache in memory, but disk only, for a short time, to avoid hammering the API with repeated requests for the same channel if it's down or having issues
				$cache->set( $cacheKey, {}, 10 );
				$cb->(undef);
			}
		},
	);
}

sub _call {
	my ( $method, $path, $params, $cb ) = @_;

	my $url = API_URL;

	# Add network key and API path to URL, network is one of 'di', 'sky', 'jazzradio', 'classicalradio'
	$url .= $params->{_network} . $path;

	$params ||= {};

	my @keys = sort keys %{$params};
	my @params;
	for my $key ( @keys ) {
		next if $key =~ /^_/;
		push @params, $key . '=' . uri_escape_utf8( $params->{$key} );
	}

	my $content = join( '&', @params );

	if ( $method eq 'GET' && $content ) {
		$url .= '?' . $content;
		$content = '';
	}

	main::INFOLOG && $log->is_info && $log->info("API call: $method $url");
	main::DEBUGLOG && $log->is_debug && $content && $log->debug($content);

	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $response = shift;

			my $result = eval { decode_json($response->content) };

			$@ && $log->error($@);
			main::DEBUGLOG && $log->is_debug && $log->debug("got: " . Data::Dump::dump($result));

			$cb->($result);
		},
		sub {
			my ($http, $error) = @_;

			$log->error("Error: $error ($url)");
			$cb->();
		},
		{
			timeout => 15,
		},
	);

	if ($method eq 'POST') {
		$http->post($url, $content);
	}
	else {
		$http->get($url);
	}
}


1;
