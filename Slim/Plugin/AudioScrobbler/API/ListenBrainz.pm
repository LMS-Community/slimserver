package Slim::Plugin::AudioScrobbler::API::ListenBrainz;

# Lyrion Music Server Copyright 2024 Lyrion Community.
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

use JSON::XS::VersionOneAndTwo;
use Scalar::Util qw(blessed);
use URI;
use URI::Escape qw(uri_escape_utf8 uri_unescape);

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Timers;

use constant API_URL => 'https://api.listenbrainz.org';

my $log = logger('plugin.audioscrobbler');
my $prefs = preferences('plugin.audioscrobbler');

sub _apiUrl {
	my ($self, $url) = @_;

	$url = $self->account->{api_url} . '/' . $url if $url !~ m{^https?://} && blessed $self;

	# Normalize ListenBrainz endpoint to always end with /1/submit-listens
	# Remove everything after /1/ and add the correct endpoint
	my $uri = URI->new($url);

	my $path = $uri->path;
	$path =~ s{/1/1/}{/1/};
	$path =~ s{/+}{/}g;

	$uri->path($path);

	return $uri->as_string;
}

sub new {
	my ($class, $client, $account) = @_;

	# Set default API URL if not provided
	$account->{api_url} ||= API_URL;

	return $class->SUPER::new($client, $account);
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

	return {
		artist_name  => uri_unescape($meta->{a} // ''),
		track_name   => uri_unescape($meta->{t} // ''),
		release_name => uri_unescape($meta->{b} // ''),
		additional_info => \%additional_info,
	};
}

sub submitNowPlaying {
	my ( $self, $track, $retry ) = @_;

	my $client = $self->client || return;
	$client = Slim::Player::Client::getClient($client) if !blessed $client;

	# Abort if the user disabled scrobbling for this player
	return if !$prefs->client($client)->get('account');

	my $api_url = $self->_apiUrl('/1/submit-listens');
	my $api_key = $self->account->{password};

	my $meta = $self->getMetadata($track) || return;
	my $payload = {
		listen_type => 'playing_now',
		payload     => [{
			track_metadata => _getTrackMetadata($meta),
		}],
	};

	my $json = to_json($payload);

	main::DEBUGLOG && $log->debug("Submitting Now Playing track to ListenBrainz: " . $meta->{title});

	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&_submitNowPlayingOK,
		\&_submitNowPlayingError,
		{
			client  => $client,
			track   => $track,
			retry   => $retry,
			api     => $self,
			timeout => 30,
		}
	);

	$http->post(
		$api_url,
		'Content-Type'  => 'application/json',
		'Authorization' => "Token $api_key",
		$json,
	);
}

sub _submitNowPlayingOK {
	my $http    = shift;
	my $content = $http->content;

	main::DEBUGLOG && $log->debug('ListenBrainz Now Playing track submitted successfully: ' . $content);
}

sub _submitNowPlayingError {
	my $http = shift;
	my $api  = $http->params('api') || return;

	$api->SUPER::_submitNowPlayingError($http);
}

# Scrobbling to ListenBrainz API
sub submitScrobble {
	my ($self, $queue, $params) = @_;

	my $api_url = $self->_apiUrl('/1/submit-listens');
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

	Slim::Plugin::AudioScrobbler::Plugin::setQueue( $self->client, $queue );

	# Submit items one by one to avoid 400 errors with multiple items
	submitScrobbleItems(\@listens, $api_url, $api_key, $cb);
}

# Helper function to submit ListenBrainz items one by one
sub submitScrobbleItems {
	my ($listens, $api_url, $api_key, $cb) = @_;

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

	my $json = to_json($payload);

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug("ListenBrainz: Submitting item 1 of " . scalar(@$listens) . ": " . $listen->{track_metadata}->{track_name});
	}

	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&_submitScrobbleOK,
		\&_submitScrobbleError,
		{
			timeout => 30,
			cb      => $cb,
			listens => $listens,
			api_url => $api_url,
			api_key => $api_key,
		},
	);

	$http->post(
		$api_url,
		'Content-Type'  => 'application/json',
		'Authorization' => "Token $api_key",
		$json,
	);
}

# Success callback for single ListenBrainz item submission
sub _submitScrobbleOK {
	my $http = shift;
	my $cb = $http->params('cb');
	my $listens = $http->params('listens');
	my $api_url = $http->params('api_url');
	my $api_key = $http->params('api_key');

	main::DEBUGLOG && $log->debug("ListenBrainz: Item 1 submitted successfully : " . $http->content);

	shift @$listens;  # Remove the first item from the list

	# Submit next item with a small delay to avoid hitting rate limits
	Slim::Utils::Timers::setTimer(
		undef,
		time() + 0.1,  # 100ms delay between submissions
		sub { submitScrobbleItems($listens, $api_url, $api_key, $cb); }
	);
}

# Error callback for single ListenBrainz item submission
sub _submitScrobbleError {
	my $http = shift;
	my $cb = $http->params('cb');
	my $listens = $http->params('listens');
	my $api_url = $http->params('api_url');
	my $api_key = $http->params('api_key');

	$log->error("ListenBrainz: Failed to submit item 1: " . $http->error);

	# Continue with next item even if this one failed
	Slim::Utils::Timers::setTimer(
		undef,
		time() + 0.1,  # 100ms delay between submissions
		sub { submitScrobbleItems($listens, $api_url, $api_key, $cb); }
	);
}

sub validate {
	my ($class, $params) = @_;

	my $api_key = $params->{password};

	# Normalize ListenBrainz endpoint to always end with /1/validate-token
	# Remove everything after /1/ and add the correct endpoint
	my $api_url = $class->_apiUrl(($params->{api_url} || API_URL) . '/1/validate-token');

	if (!$api_key) {
		if ( $params->{ecb} ) {
			$params->{ecb}->('Missing ListenBrainz API token');
		}
		return;
	}

	main::DEBUGLOG && $log->debug("Validating ListenBrainz token: $api_url");

	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&_validateOK,
		\&_validateError,
		{
			params  => $params,
			timeout => 30,
		},
	);

	$http->get(
		$api_url,
		'Authorization' => "Token $api_key",
	);
}

sub _validateOK {
	my $http   = shift;
	my $params = $http->params('params');

	my $content = $http->content;

	main::DEBUGLOG && $log->debug("ListenBrainz validation response: $content");

	# Parse JSON response
	my $response;
	eval {
		$response = from_json($content);
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
	my $http   = shift;
	my $error  = $http->error;
	my $params = $http->params('params');

	$log->error("Error validating ListenBrainz token: $error");

	$params->{ecb}->(string('SETUP_PLUGIN_AUDIOSCROBBLER_VALIDATION_ERROR', $error)) if $params->{ecb};
}


1;