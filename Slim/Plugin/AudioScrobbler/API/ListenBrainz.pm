package Slim::Plugin::AudioScrobbler::API::ListenBrainz;

# Lyrion Music Server Copyright 2024-2026 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;

use base qw(Slim::Plugin::AudioScrobbler::API);

use HTTP::Date qw(str2time);
use JSON::XS qw(decode_json encode_json);
use List::Util qw(max);
use Time::HiRes ();
use URI;
use URI::Escape qw(uri_escape_utf8 uri_unescape);

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Timers;

use constant API_URL => 'https://api.listenbrainz.org';
use constant MAX_FAILURES => 5;  # Maximum number of consecutive failures before giving up on submission

my $log = logger('plugin.audioscrobbler');
my $prefs = preferences('plugin.audioscrobbler');

my $failures = 0;
my @requests;
my $requestActive;
my $dispatchTimer;
my $nextRequestAt = 0;

sub _request {
	my ($method, $url, $apiKey, $cb, $ecb, $json, $isCurrent) = @_;

	push @requests, sub {
		return if $isCurrent && !$isCurrent->();

		my $http = Slim::Networking::SimpleAsyncHTTP->new(
			sub { _requestDone($cb, @_) },
			sub { _requestDone($ecb, @_) },
			{ timeout => 30 },
		);
		my @headers = (
			'User-Agent'    => "LyrionMusicServer/$::VERSION (https://lyrion.org/contact/)",
			'Authorization' => "Token $apiKey",
		);
		push @headers, 'Content-Type' => 'application/json', $json if defined $json;

		$requestActive = 1;
		$nextRequestAt = Time::HiRes::time() + 1;
		$http->$method($url, @headers);
		# Include HTTP setup time without shortening a cooldown set by an inline callback.
		$nextRequestAt = max($nextRequestAt, Time::HiRes::time() + 1);
		return 1;
	};
	_dispatchRequest();
}

sub _dispatchRequest {
	return if $requestActive || $dispatchTimer || !@requests;

	if (Time::HiRes::time() < $nextRequestAt) {
		$dispatchTimer = Slim::Utils::Timers::setTimer(undef, $nextRequestAt, sub {
			$dispatchTimer = undef;
			_dispatchRequest();
		});
		return;
	}

	while (my $request = shift @requests) {
		return if $request->();
	}
}

sub _requestDone {
	my ($cb, $http, undef, $response) = @_;

	# SimpleAsyncHTTP passes the response separately on HTTP errors.
	_applyCooldown($response || $http);
	eval { $cb->($http); 1 } or $log->error("ListenBrainz callback failed: $@");
	$requestActive = 0;
	_dispatchRequest();
}

sub _unsignedHeader {
	my ($value) = @_;
	return unless defined $value && $value =~ /\A\s*([0-9]+)\s*\z/;
	my $number = 0 + $1;
	return $number if $number < 'Inf';
}

sub _applyCooldown {
	my ($response) = @_;
	my $headers = $response->headers || return;
	my $now = Time::HiRes::time();
	my $retryAfter = $headers->header('Retry-After');
	my $delay = _unsignedHeader($retryAfter);
	my $retryAt = defined $delay ? $now + $delay : (str2time($retryAfter, 'GMT') // 0);
	my $remaining = _unsignedHeader($headers->header('X-RateLimit-Remaining'));

	if (($response->code || 0) == 429 || (defined $remaining && $remaining == 0)) {
		my $resetIn = _unsignedHeader($headers->header('X-RateLimit-Reset-In'));
		my $resetAt = $resetIn ? $now + $resetIn : (_unsignedHeader($headers->header('X-RateLimit-Reset')) // 0);
		$retryAt = max($retryAt, $resetAt);
		$retryAt = $now + 2 if $retryAt <= $now;
	}

	$nextRequestAt = max($nextRequestAt, $retryAt);
}

sub _apiUrl {
	my ($base, $endpoint) = @_;

	my $uri = URI->new(($base || API_URL) . $endpoint);

	my $path = $uri->path;
	$path =~ s{/1/1/}{/1/};
	$path =~ s{/+}{/}g;

	$uri->path($path);

	return $uri->as_string;
}

sub getMetadata {
	my ($self, $track) = @_;

	my $meta = $self->SUPER::getMetadata($track);
	$meta->{a} = uri_escape_utf8($meta->{artist} || '');
	$meta->{t} = uri_escape_utf8($meta->{title} || '');
	$meta->{b} = uri_escape_utf8($meta->{album} || '');
	$meta->{i} = time();
	$meta->{l} = $meta->{duration};
	$meta->{n} = $meta->{tracknum};
	$meta->{m} = $track->musicbrainz_id if $track->musicbrainz_id;

	return $meta;
}

sub _getTrackMetadata {
	my ($meta) = @_;

	my %additional_info = (
		media_player => 'Lyrion Media Server',
		media_player_version => $::VERSION || '',
		submission_client => 'Lyrion Media Server',
		submission_client_version => $::VERSION || '',
	);

	$additional_info{tracknumber} = $meta->{n} if defined $meta->{n};
	$additional_info{recording_mbid} = $meta->{m} if $meta->{m};
	$additional_info{duration} = int($meta->{l}) if $meta->{l};

	my $track_metadata = {
		artist_name  => uri_unescape($meta->{a} // ''),
		track_name   => uri_unescape($meta->{t} // ''),
		release_name => uri_unescape($meta->{b} // ''),
		additional_info => \%additional_info,
	};

	utf8::decode($track_metadata->{artist_name});
	utf8::decode($track_metadata->{track_name});
	utf8::decode($track_metadata->{release_name});

	return $track_metadata;
}

sub submitNowPlaying {
	my ($self, $track, $retry, $startedAt) = @_;

	my $clientId = $self->client || return;
	my $client = Slim::Player::Client::getClient($clientId) || return;

	my $account = $self->account;
	$startedAt //= $client->master()->trackStartTime();
	my $isCurrent = sub {
		my $current = Slim::Player::Client::getClient($clientId) || return;
		my $selected = Slim::Plugin::AudioScrobbler::Plugin::getAccount($current) || return;
		return $selected == $account && $prefs->get('enable_scrobbling') && !$current->isStopped()
			&& $current->master()->trackStartTime() == $startedAt
			&& (Slim::Player::Playlist::url($current) // '') eq $track->url;
	};
	return unless $isCurrent->();

	my $api_url = _apiUrl($account->{api_url}, '/1/submit-listens');
	my $api_key = $account->{password};

	my $meta = $self->getMetadata($track) || return;
	my $payload = {
		listen_type => 'playing_now',
		payload     => [{
			track_metadata => _getTrackMetadata($meta),
		}],
	};

	my $json = encode_json($payload);
	my $retryNowPlaying = $retry ? undef : sub { $self->submitNowPlaying($track, 1, $startedAt) };

	main::DEBUGLOG && $log->debug("Submitting Now Playing track to ListenBrainz: " . $meta->{title});

	_request(
		'post', $api_url, $api_key,
		\&_submitNowPlayingOK,
		sub { _submitNowPlayingError($_[0], $client, $retryNowPlaying) },
		$json, $isCurrent,
	);
}

sub _submitNowPlayingOK {
	my $http    = shift;
	my $content = $http->content;

	main::DEBUGLOG && $log->debug('ListenBrainz Now Playing track submitted successfully: ' . $content);
}

sub _submitNowPlayingError {
	my ($http, $client, $retry) = @_;

	main::DEBUGLOG && $log->debug('ListenBrainz Now Playing submission failed: ' . $http->error);
	return unless $retry;
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 5, $retry);
}

# Scrobbling to ListenBrainz API
sub submitScrobble {
	my ($self, $queue, $params) = @_;

	my $clientId = $self->client;
	my $api_url = _apiUrl($self->account->{api_url}, '/1/submit-listens');
	my $api_key = $self->account->{password};
	my $cb = $params->{cb} || sub {};

	my @listens;
	while ( my $item = shift @$queue ) {
		my $track_metadata = _getTrackMetadata($item);

		push @listens, {
			track_metadata => $track_metadata,
			listened_at => int($item->{i} || time()),
		};
	}

	Slim::Plugin::AudioScrobbler::Plugin::setQueue( $clientId, $queue );

	# Submit items one by one to avoid 400 errors with multiple items
	submitScrobbleItems(\@listens, $api_url, $api_key, $cb, $clientId);
}

# Helper function to submit ListenBrainz items one by one
sub submitScrobbleItems {
	my ($listens, $api_url, $api_key, $cb, $clientId) = @_;

	# If we've processed all items, call the callback
	if (!scalar @$listens) {
		$cb->() if $cb;
		return;
	}

	my $listen = $listens->[0];

	# Create payload with single listen
	my $payload = {
		listen_type => 'single',
		payload     => [$listen],
	};

	my $json = encode_json($payload);

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug("ListenBrainz: Submitting item 1 of " . scalar(@$listens) . ": " . $listen->{track_metadata}->{track_name});
	}

	my $next = sub { submitScrobbleItems($listens, $api_url, $api_key, $cb, $clientId) };
	_request(
		'post', $api_url, $api_key,
		sub { _submitScrobbleOK($_[0], $listens, $next) },
		sub { _submitScrobbleError($_[0], $cb, $next, $clientId, scalar @$listens) },
		$json,
	);
}

# Success callback for single ListenBrainz item submission
sub _submitScrobbleOK {
	my ($http, $listens, $next) = @_;

	main::DEBUGLOG && $log->debug("ListenBrainz: Item 1 submitted successfully : " . $http->content);

	$failures = 0;  # Reset failure count on success
	shift @$listens;  # Remove the first item from the list

	$next->();
}

# Error callback for single ListenBrainz item submission
sub _submitScrobbleError {
	my ($http, $cb, $next, $clientId, $unsent) = @_;

	my $wait = $nextRequestAt - Time::HiRes::time();
	my $delay = $wait > 0 ? sprintf(' (next request eligible in %.2f s)', $wait) : '';
	$log->error("ListenBrainz: Failed to submit listen for player $clientId: " . $http->error . $delay);

	$failures++;  # Increment failure count on error

	if ($failures >= MAX_FAILURES) {
		$log->error("ListenBrainz: Discarding batch for player $clientId after $failures consecutive failures (unsent listens: $unsent)");
		$failures = 0;  # Reset failure count
		$cb->() if $cb;
		return;
	}

	$next->();
}

sub validate {
	my ($class, $params) = @_;

	my $api_key = $params->{password};

	my $api_url = _apiUrl($params->{api_url}, '/1/validate-token');

	if (!$api_key) {
		if ( $params->{ecb} ) {
			$params->{ecb}->('Missing ListenBrainz API token');
		}
		return;
	}

	main::DEBUGLOG && $log->debug("Validating ListenBrainz token: $api_url");

	_request(
		'get', $api_url, $api_key,
		sub { _validateOK($_[0], $params) },
		sub { _validateError($_[0], $params) },
	);
}

sub _validateOK {
	my ($http, $params) = @_;

	my $content = $http->content;

	main::DEBUGLOG && $log->debug("ListenBrainz validation response: $content");

	# Parse JSON response
	my $response;
	eval {
		$response = decode_json($content);
	};

	my $ecb = $params->{ecb} || sub {};

	if ($@ || !$response) {
		$log->error("Failed to parse ListenBrainz validation response: $@");
		$ecb->(string('SETUP_PLUGIN_AUDIOSCROBBLER_VALIDATION_ERROR', 'Invalid response from ListenBrainz API'));
		return;
	}

	# Check if validation was successful
	if ($response->{valid} && ($response->{valid} eq 'true' || $response->{valid} == 1)) {
		main::DEBUGLOG && $log->debug('ListenBrainz token validation successful');

		$params->{cb}->(string('SETUP_AUDIOSCROBBLER_VALID_CREDENTIALS')) if $params->{cb};
	} else {
		my $error = string('SETUP_PLUGIN_AUDIOSCROBBLER_VALIDATION_ERROR', $response->{error} || 'Invalid ListenBrainz API token');
		$log->error($error);
		$ecb->($error);
	}
}

sub _validateError {
	my ($http, $params) = @_;
	my $error  = $http->error;

	$log->error("Error validating ListenBrainz token: $error");

	$params->{ecb}->(string('SETUP_PLUGIN_AUDIOSCROBBLER_VALIDATION_ERROR', $error)) if $params->{ecb};
}


1;
