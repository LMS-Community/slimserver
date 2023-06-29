package Slim::Plugin::AudioAddict::API;

use strict;

use JSON::XS::VersionOneAndTwo;
use URI::Escape qw(uri_escape_utf8);

use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

use constant API_URL   => 'https://api.audioaddict.com/v1/';
use constant CACHE_TTL => 60 * 60 * 24; # 1 day

my $cache = Slim::Utils::Cache->new();
my $log = logger('plugin.audioaddict');
my $prefs = preferences('plugin.audioaddict');

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

			my $result = eval { from_json($response->content) };

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