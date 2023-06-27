package Slim::Plugin::Deezer::API;

# Logitech Media Server Copyright 2003-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use JSON::XS::VersionOneAndTwo;
use URI::Escape qw(uri_escape_utf8);

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Log;

use constant GET_ARTIST_URL => '/api/deezer/v1/opml/artist_by_name_or_id?id=%s&name=%s';
use constant API_BASE_URL   => 'https://api.deezer.com';

my $log = logger('plugin.deezer');


sub getArtistMenu {
	my ($class, $client, $args, $cb) = @_;

	$class->_call(sprintf(GET_ARTIST_URL, $args->{id}, uri_escape_utf8($args->{name})), $client, sub {
		my $info = shift;

		my $items = eval { $info->{body}->{outline} };
		$@ && $log->error("Failed to parse Deezer's response: $@");

		$cb->($items);
	});
}

sub _call {
	my ($class, $url, $client, $cb) = @_;

	Slim::Networking::SqueezeNetwork->new(
		sub {
			my $http   = shift;
			my $client = $http->params->{client};

			my $info = eval { from_json( $http->content ) };
			$@ && $log->error("Failed to parse Deezer's response: $@");

			$cb->($info);
		},
		sub {
			my $http   = shift;
			my $client = $http->params('client');
			my $error  = $http->error;

			$log->warn("Error getting track metadata from SN: $error");

			$cb->();
		},
		{
			client  => $client,
			timeout => 60,
		},
	)->get( Slim::Networking::SqueezeNetwork->url($url) );
}

sub getTrack {
	my ($class, $id, $cb) = @_;

	return $cb->() unless $id;

	$class->_apiDirectCall('GET', "/track/$id", {
		cache   => 1,
		expires => 86400 * 30,
	}, sub {
		my ($track) = @_;

		if ($track && ref $track && ref $track eq	'HASH' && !$track->{error}) {
			my $trackInfo = {
				id       => $id,
				artist   => $track->{artist}->{name},
				artist_name => $track->{artist}->{name},
				album    => $track->{album}->{title},
				album_name => $track->{album}->{title},
				title    => $track->{title},
				cover    => _artwork_getUrl($track->{album}),
				duration => $track->{duration},
			};

			return $cb->($trackInfo);
		}

		$cb->($track);
	});
}

sub _artwork_getUrl {
	my ($item, $nofallback) = @_;

	if ( my $image_url = $item->{picture_xl} ) {
		return $image_url;
	}

	if ( my $image_url = ($item->{picture} || $item->{cover}) ) {
		return $image_url . '?size=xl';
	}

	return;
}

my $nextAttempt = 0;
my $lastError;

sub _apiDirectCall {
	my ($class, $method, $path, $params, $cb) = @_;

	if (time() < $nextAttempt) {
		$log->warn("Skipping request due to too many requests");
		return $cb->($lastError);
	}

	$params ||= {};
	$params->{timeout} ||= 10;

	$lastError = undef;
	$nextAttempt = 0;

	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $response = shift;

			my $result = eval { from_json($response->content) } || {};

			$@ && $log->error($@);

			if ($result->{error} && ref $result->{error}) {
				$log->error("Failure calling API: " . ($result->{error}->{message} || 'unknown'));

				if ($result->{error}->{code} == 4) {
					$nextAttempt = time() + 5;
					$lastError = $result;
				}
			}

			main::DEBUGLOG && $log->is_debug && $log->debug("got: " . Data::Dump::dump($result));

			$cb->($result);
		},
		sub {
			$log->warn("Error getting track metadata from SN: " . @_);
			main::DEBUGLOG && $log->(Data::Dump::dump(@_));
			$cb->();
		},
		$params,
	)->get(API_BASE_URL . $path);
}

1;
