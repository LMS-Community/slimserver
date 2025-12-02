package Slim::Plugin::AudioScrobbler::API;

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

use base qw(Slim::Utils::Accessor);

use Scalar::Util qw(blessed);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

__PACKAGE__->mk_accessor( rw => qw(
	account client
) );

my $prefs = preferences('plugin.audioscrobbler');
my $log = logger('plugin.audioscrobbler');

sub getAPI {
	my ($class, $client) = @_;

	# Get client's account information
	my $account = Slim::Plugin::AudioScrobbler::Plugin::getAccount($client);
	my $api_type = $account->{api_type} if $account;

	if ($api_type && $api_type eq 'listenbrainz') {
		require Slim::Plugin::AudioScrobbler::API::ListenBrainz;
		return Slim::Plugin::AudioScrobbler::API::ListenBrainz->new($client, $account);
	} else {
		require Slim::Plugin::AudioScrobbler::API::LastFM;
		return Slim::Plugin::AudioScrobbler::API::LastFM->new($client, $account);
	}
}

sub new {
	my ($class, $client, $account) = @_;
	my $self = $class->SUPER::new();

	$self->account($account);
	$self->client($client->id) if $client;

	return $self;
}

sub getMetadata {
	my ($self, $track) = @_;

	my $meta = Slim::Plugin::AudioScrobbler::Plugin::_getMetadata($self->client, $track);

	if (!$meta) {
		main::DEBUGLOG && $log->debug( 'Ignoring remote URL ' . $track->url );
		return;
	}

	elsif ( $meta->{msg} ) {
		main::DEBUGLOG && $log->debug( $meta->{msg} );
		return;
	}

	return $meta;
}

sub _submitNowPlayingError {
	my ($self, $http) = @_;
	my $error  = $http->error;
	my $client = $http->params('client');
	my $track  = $http->params('track');
	my $retry  = $http->params('retry');

	if ( $retry ) {
		warn $http->url;
		main::DEBUGLOG && $log->debug("Now Playing track failed to submit after retry: $error, giving up");
		return;
	}

	$client = Slim::Player::Client::getClient($client) if !blessed $client;

	main::DEBUGLOG && $log->debug("Now Playing track failed to submit: $error, retrying in 5 seconds");

	# Retry once after 5 seconds
	Slim::Utils::Timers::killTimers( $client, \&Slim::Plugin::AudioScrobbler::Plugin::submitNowPlaying );
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time() + 5,
		\&Slim::Plugin::AudioScrobbler::Plugin::submitNowPlaying,
		$track,
		'retry',
		$self,
	);
}


1;