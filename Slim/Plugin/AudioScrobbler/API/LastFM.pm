package Slim::Plugin::AudioScrobbler::API::LastFM;

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

use Digest::MD5 qw(md5_hex);
use Scalar::Util qw(blessed);
use URI::Escape qw(uri_escape_utf8 uri_unescape);

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Player::Client;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string cstring);
use Slim::Utils::Timers;

use constant HANDSHAKE_URL => 'http://post.audioscrobbler.com/';
use constant CLIENT_ID     => 'ss7';
use constant CLIENT_VER    => 'sc' . $::VERSION;

my $log = logger('plugin.audioscrobbler');
my $prefs = preferences('plugin.audioscrobbler');

sub handshake {
	my $params = shift;

	if ( my $client = $params->{client} ) {
		Slim::Plugin::AudioScrobbler::Plugin::clearSession( $client );

		# Get client's account information
		if ( !$params->{username} && (my $account = Slim::Plugin::AudioScrobbler::Plugin::getAccount($client)) ) {
			$params->{password} = $account->{password};
			$params->{username} = $account->{username};
		}
	}

	my $time = time();

	# Get URL with defaulting
	my $api_url = $params->{api_url};

	my $url = HANDSHAKE_URL
		. '?hs=true&p=1.2'
		. '&c=' . CLIENT_ID
		. '&v=' . CLIENT_VER
		. '&u=' . $params->{username}
		. '&t=' . $time
		. '&a=' . md5_hex( $params->{password} . $time );

	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&_handshakeOK,
		\&_handshakeError,
		{
			params  => $params,
			timeout => 30,
		},
	);

	main::DEBUGLOG && $log->debug("Handshaking with Last.fm: $url");

	$http->get( $url );
}

sub _handshakeOK {
	my $http   = shift;
	my $params = $http->params('params');
	my $client = $params->{client};

	my $content = $http->content;
	my $error;

	if ( $content =~ /^OK/ ) {
		my (undef, $session_id, $now_playing_url, $submit_url) = split /\n/, $content, 4;

		main::DEBUGLOG && $log->debug( "Handshake OK, session id: $session_id, np URL: $now_playing_url, submit URL: $submit_url" );

		if ( $client ) {
			$client->master->pluginData( session_id      => $session_id );
			$client->master->pluginData( now_playing_url => $now_playing_url );
			$client->master->pluginData( submit_url      => $submit_url );
			$client->master->pluginData( handshake_delay => 0 );

			# If there are any tracks pending in the queue, send them now
			my $queue = Slim::Plugin::AudioScrobbler::Plugin::getQueue($client);

			if ( scalar @{$queue} ) {
				submitScrobble( $client );
			}
		}
	}
	elsif ( $content =~ /^BANNED/ ) {
		$error = cstring($client, 'PLUGIN_AUDIOSCROBBLER_BANNED');
	}
	elsif ( $content =~ /^BADAUTH/ ) {
		$error = cstring($client, 'PLUGIN_AUDIOSCROBBLER_BADAUTH');
	}
	elsif ( $content =~ /^BADTIME/ ) {
		$error = cstring($client, 'PLUGIN_AUDIOSCROBBLER_BADTIME');
	}
	else {
		# Other error that requires a retry
		chomp $content;
		$error = $content;
		$http->error( $error );

		if ( $client ) {
			_handshakeError( $http );
		}
	}

	if ( $error ) {
		$log->error($error);
		if ( $params->{ecb} ) {
			$params->{ecb}->($error);
		}
	}
	else {
		# Callback to success function
		if ( $params->{cb} ) {
			$params->{cb}->();
		}
	}
}

sub _handshakeError {
	my $http   = shift;
	my $error  = $http->error;
	my $params = $http->params('params');
	my $client = $params->{client};

	$log->error("Error handshaking with Last.fm: $error");

	if ( $params->{ecb} ) {
		$params->{ecb}->($error);
	}

	return unless $client;

	my $delay;

	if ( $delay = $client->master->pluginData('handshake_delay') ) {
		$delay *= 2;
		if ( $delay > 120 ) {
			$delay = 120;
		}
	}
	else {
		$delay = 1;
	}

	$client->master->pluginData( handshake_delay => $delay );

	$log->warn("  retrying in $delay minute(s)");

	Slim::Utils::Timers::killTimers( $params, \&handshake );
	Slim::Utils::Timers::setTimer(
		$params,
		time() + ( $delay * 60 ),
		\&handshake,
	);
}

sub submitNowPlaying {
	my ( $self, $track, $retry ) = @_;

	my $client = $self->client || return;

	$client = Slim::Player::Client::getClient($client) if !blessed $client;

	# Abort if the user disabled scrobbling for this player
	return if !$prefs->client($client)->get('account');

	if ( !$client->master->pluginData('now_playing_url') ) {
		# Get a new session
		handshake( {
			client => $client,
			cb     => sub {
				$self->submitNowPlaying( $track, $retry );
			},
		} );

		return;
	}

	my $meta = $self->getMetadata($track) || return;

	my $post = 's=' . $client->master->pluginData('session_id')
		. '&a=' . uri_escape_utf8( $meta->{artist} )
		. '&t=' . uri_escape_utf8( $meta->{title} )
		. '&b=' . uri_escape_utf8( $meta->{album} )
		. '&l=' . ( $meta->{duration} ? int( $meta->{duration} ) : '' )
		. '&n=' . $meta->{tracknum}
		. '&m=' . ( $track->musicbrainz_id || '' );

	main::DEBUGLOG && $log->debug("Submitting Now Playing track to Last.fm: $post");

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
		$client->master->pluginData('now_playing_url'),
		'Content-Type' => 'application/x-www-form-urlencoded',
		$post,
	);
}


sub _submitNowPlayingOK {
	my $http    = shift;
	my $content = $http->content;
	my $client  = $http->params('client');
	my $track   = $http->params('track');
	my $retry   = $http->params('retry');
	my $api     = $http->params('api');

	if ( $content =~ /^OK/ ) {
		main::DEBUGLOG && $log->debug('Now Playing track submitted successfully');
	}
	elsif ( $content =~ /^BADSESSION/ ) {
		main::DEBUGLOG && $log->debug('Now Playing failed to submit: bad session');

		# Re-handshake and retry once
		handshake( {
			client => $client,
			cb     => sub {
				if ( !$retry ) {
					main::DEBUGLOG && $log->debug('Retrying failed Now Playing submission');
					$api->submitNowPlaying( $track, 'retry' );
				}
			},
		} );
	}
	else {
		# Treat it as an error
		chomp $content;
		if ( !$content ) {
			$content = 'Unknown error';
		}
		$http->error( $content );
		_submitNowPlayingError( $http );
	}
}

sub _submitNowPlayingError {
	my $http   = shift;
	my $api    = $http->params('api') || return;

	$api->SUPER::_submitNowPlayingError($http);
}

sub submitScrobble {
	my ($self, $queue, $params) = @_;

	my $client = $self->client || return;

	$client = Slim::Player::Client::getClient($client) if !blessed $client;

	# Check for submit_url and possible handshake
	if ( !$client->master->pluginData('submit_url') ) {
		# Get a new session
		handshake( {
			client => $client,
			cb     => sub {
				submitScrobble( $client, $params );
			},
		} );
		return;
	}

	# Logging the number of items in the queue
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( 'Scrobbling ' . scalar( @{$queue} ) . ' queued item(s)' );
		#$log->debug( Data::Dump::dump($queue) );
	}

	# Get the currently playing track
	my $current_track;
	if ( my $url = Slim::Player::Playlist::url($client) ) {
		$current_track = Slim::Schema->objectForUrl( { url => $url } );
	}

	my $current_item;
	my @tmpQueue;

	my $post = 's=' . $client->master->pluginData('session_id');

	my $index = 0;
	while ( my $item = shift @{$queue} ) {
		# Don't submit tracks that are still playing, to allow user
		# to rate the track
		if ( $current_track && Slim::Plugin::AudioScrobbler::Plugin::stillPlaying( $client, $current_track, $item ) ) {
			main::DEBUGLOG && $log->debug( "Track " . $item->{t} . " is still playing, not submitting" );
			$current_item = $item;
			next;
		}

		push @tmpQueue, $item;

		for my $p ( keys %{$item} ) {
			# Skip internal items i.e. _url
			next if $p =~ /^_/;

			# each value is already uri-escaped as needed
			$post .= '&' . $p . '[' . $index . ']=' . $item->{ $p };
		}

		$index++;

		# Max size of each scrobble request is 50 items
		last if $index == 50;
	}

	# Add the currently playing track back to the queue
	if ( $current_item ) {
		unshift @{$queue}, $current_item;
	}

	if ( @tmpQueue ) {
		# Only setQueue if tmpQueue is nonempty
		# otherwise it means we didn't shift anything out of queue into tmpQueue
		# and $queue is therefore unchanged. prevents disk writes enabling some disks to spindown
		Slim::Plugin::AudioScrobbler::Plugin::setQueue( $client, $queue );

		main::DEBUGLOG && $log->debug( "Submitting: $post" );

		my $http = Slim::Networking::SimpleAsyncHTTP->new(
			\&_submitScrobbleOK,
			\&_submitScrobbleError,
			{
				tmpQueue => \@tmpQueue,
				params   => $params,
				client   => $client,
				timeout  => 30,
			},
		);

		$http->post(
			$client->master->pluginData('submit_url'),
			'Content-Type' => 'application/x-www-form-urlencoded',
			$post,
		);
	}

	# If there are still items left in the queue, scrobble again in a minute
	if ( scalar @{$queue} ) {
		Slim::Utils::Timers::killTimers( $client, \&submitScrobble );
		Slim::Utils::Timers::setTimer(
			$client,
			time() + 60,
			\&submitScrobble,
			$params,
		);
	}

}

sub _submitScrobbleOK {
	my $http     = shift;
	my $content  = $http->content;
	my $tmpQueue = $http->params('tmpQueue') || [];
	my $params   = $http->params('params');
	my $client   = $http->params('client');

	if ( $content =~ /^OK/ ) {
		main::DEBUGLOG && $log->debug( 'Scrobble submit successful' );

		# If we had a callback on success, call it now
		if ( $params->{cb} ) {
			$params->{cb}->();
		}
	}
	elsif ( $content =~ /^BADSESSION/ ) {
		# put the tmpQueue items back into the main queue
		my $queue = Slim::Plugin::AudioScrobbler::Plugin::getQueue($client);

		push @{$queue}, @{$tmpQueue};

		Slim::Plugin::AudioScrobbler::Plugin::setQueue( $client, $queue );

		main::DEBUGLOG && $log->debug( 'Scrobble submit failed: invalid session, re-handshaking' );

		# re-handshake, this will cause a submit to occur after success
		handshake( { client => $client } );
	}
	elsif ( $content =~ /^FAILED (.+)/ ) {
		# treat as an error
		$http->error( $1 );
		_submitScrobbleError( $http );
	}
	else {
		# treat as an error
		chomp $content;
		$http->error( $content );
		_submitScrobbleError( $http );
	}
}

sub _submitScrobbleError {
	my $http     = shift;
	my $error    = $http->error;
	my $tmpQueue = $http->params('tmpQueue') || [];
	my $params   = $http->params('params');
	my $client   = $http->params('client');

	# put the tmpQueue items back into the main queue
	my $queue = Slim::Plugin::AudioScrobbler::Plugin::getQueue($client);

	push @{$queue}, @{$tmpQueue};

	Slim::Plugin::AudioScrobbler::Plugin::setQueue( $client, $queue );

	if ( $params->{retry} == 3 ) {
		# after 3 failures, give up and handshake
		main::DEBUGLOG && $log->debug( "Scrobble submit failed after 3 tries, re-handshaking" );
		handshake( { client => $client } );
		return;
	}

	my $tries = 3 - $params->{retry};
	main::DEBUGLOG && $log->debug( "Scrobble submit failed: $error, will retry in 5 seconds ($tries tries left)" );

	# Retry after a short delay
	$params->{retry}++;
	Slim::Utils::Timers::killTimers( $client, \&submitScrobble );
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time() + 5,
		\&submitScrobble,
		$params,
	);
}

sub validate {
	my ($class, $params) = @_;

	handshake({
		username => $params->{username},
		password => $params->{password},
		cb       => sub {
			$params->{cb}->(string('PLUGIN_AUDIOSCROBBLER_VALID_LOGIN'));
		},
		ecb      => sub {
			my $error = shift;
			$params->{ecb}->(string('SETUP_PLUGIN_AUDIOSCROBBLER_LOGIN_ERROR', $error));
		},
	})
}

1;