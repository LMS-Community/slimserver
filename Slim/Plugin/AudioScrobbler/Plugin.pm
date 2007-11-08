package Slim::Plugin::AudioScrobbler::Plugin;

# $Id$

# This plugin handles submission of tracks to Last.fm's
# Audioscrobbler service.

# SqueezeCenter Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# The basic algorithm used by this plugin is very simple:
# On newsong, figure out how long from now until half of song or 240 secs
# Set a timer for that time, the earliest possible time they could meet the criteria
# When timer fires, make sure same track is playing
# If not yet at the time (maybe they paused), recalc and set the timer again
# If time has passed, great, submit it

# Thanks to the SlimScrobbler plugin for inspiration and feature ideas.
# http://slimscrobbler.sourceforge.net/

use strict;
use base qw(Slim::Plugin::Base);

use Slim::Player::ProtocolHandlers;
use Slim::Player::Source;
use Slim::Plugin::AudioScrobbler::Settings;
use Slim::Plugin::AudioScrobbler::PlayerSettings;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Timers;

use Digest::MD5 qw(md5_hex);
use URI::Escape qw(uri_escape_utf8);

my $prefs = preferences('plugin.audioscrobbler');

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.audioscrobbler',
	defaultLevel => 'WARN',
	description  => 'PLUGIN_AUDIOSCROBBLER_MODULE_NAME',
} );

use constant HANDSHAKE_URL => 'http://post.audioscrobbler.com';
use constant CLIENT_ID     => 'ss7';
use constant CLIENT_VER    => 'sc' . $::VERSION;

sub getDisplayName {
	return 'PLUGIN_AUDIOSCROBBLER_MODULE_NAME';
}

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin();

	Slim::Plugin::AudioScrobbler::Settings->new;
	Slim::Plugin::AudioScrobbler::PlayerSettings->new;
	
	# Subscribe to new song events
	Slim::Control::Request::subscribe(
		\&newsongCallback, 
		[['playlist'], ['newsong']],
	);
}

sub shutdownPlugin {
	Slim::Control::Request::unsubscribe( \&newsongCallback );
}

sub clear_session {
	my $client = shift;
	
	# Reset our state
	$client->pluginData( session_id      => 0 );
	$client->pluginData( now_playing_url => 0 );
	$client->pluginData( submit_url      => 0 );
}

sub handshake {
	my $params = shift || {};
	
	if ( my $client = $params->{client} ) {
		clear_session( $client );
		
		# Get client's account information
		if ( !$params->{username} ) {
			$params->{username} = $prefs->client($client)->get('account');
			
			my $accounts = $prefs->get('accounts') || [];
			for my $account ( @{$accounts} ) {
				if ( $account->{username} eq $params->{username} ) {
					$params->{password} = $account->{password};
					last;
				}
			}
		}
	}
	
	my $time = time();
	
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
	
	$log->debug("Handshaking with Last.fm: $url");
	
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
		
		$log->debug( "Handshake OK, session id: $session_id, np URL: $now_playing_url, submit URL: $submit_url" );
		
		if ( $client ) {
			$client->pluginData( session_id      => $session_id );
			$client->pluginData( now_playing_url => $now_playing_url );
			$client->pluginData( submit_url      => $submit_url );
			$client->pluginData( handshake_delay => 0 );
		
			# If there are any tracks pending in the queue, send them now
			my $queue = $prefs->client($client)->get('queue') || [];
			if ( scalar @{$queue} ) {
				submitScrobble( $client );
			}
		}
	}
	elsif ( $content =~ /^BANNED/ ) {
		$error = string('PLUGIN_AUDIOSCROBBLER_BANNED');
	}
	elsif ( $content =~ /^BADAUTH/ ) {
		$error = string('PLUGIN_AUDIOSCROBBLER_BADAUTH');
	}
	elsif ( $content =~ /^BADTIME/ ) {
		$error = string('PLUGIN_AUDIOSCROBBLER_BADTIME');
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
	
	if ( $params->{ecb} ) {
		$params->{ecb}->($error);
	}
	
	return unless $client;
	
	my $delay;
	
	if ( $delay = $client->pluginData('handshake_delay') ) {
		$delay *= 2;
		if ( $delay > 120 ) {
			$delay = 120;
		}
	}
	else {
		$delay = 1;
	}
	
	$client->pluginData( handshake_delay => $delay );
	
	$log->warn("Error handshaking with Last.fm: $error, retrying in $delay minute(s)");
	
	Slim::Utils::Timers::setTimer(
		$params,
		time() + ( $delay * 60 ),
		\&handshake,
	);
}

sub newsongCallback {
	my $request = shift;
	my $client  = $request->client() || return;
	my $idx     = $request->getParam('_p3');
	
	# If synced, only listen to the master
	if ( Slim::Player::Sync::isSynced($client) ) {
		return unless Slim::Player::Sync::isMaster($client);
	}

	# Check if this player has an account selected
	return if !$prefs->client($client)->get('account');
	
	my $enable_now_playing = $prefs->get('enable_now_playing');
	my $enable_scrobbling  = $prefs->get('enable_scrobbling');
	
	return unless $enable_now_playing || $enable_scrobbling;

	my $url   = Slim::Player::Playlist::url( $client, $idx );
	my $track = Slim::Schema->objectForUrl( { url => $url } );
	
	# If now_playing is enabled, report all new songs
	if ( $enable_now_playing ) {
		my $queue = $prefs->client($client)->get('queue') || [];
		
		if ( scalar @{$queue} ) {
			# before we submit now playing, submit all queued tracks, so that
			# a scrobbled track doesn't clobber the now playing data
			$log->debug( 'Submitting scrobble queue before now playing track' );
			
			submitScrobble( $client, {
				cb => sub {
					# delay by 1 second so we don't hit the server too fast after
					# the submit call
					Slim::Utils::Timers::setTimer(
						undef,
						time() + 1,
						sub {
							submitNowPlaying( $client, $track );
						},
					);
				},
			} );
		}
		else {
			submitNowPlaying( $client, $track );
		}
	}

	# If scrobbling is enabled, determine when we need to check again
	if ( $enable_scrobbling ) {
		# Track must be > 30 seconds
		if ( !$track->secs || $track->secs < 30 ) {
			if ( $log->is_debug ) {
				$log->debug( 'Ignoring track ' . $track->title . ', shorter than 30 seconds or unknown length' );
			}
			
			return;
		}
		
		my $title = $track->title;
		
		if ( $track->remote ) {
			my $handler = Slim::Player::ProtocolHandlers->handlerForURL($url);
			if ( $handler && $handler->can('getMetadataFor') ) {
				# this plugin provides track metadata, i.e. Pandora, Rhapsody
				my $meta = $handler->getMetadataFor( $client, $url, 'forceCurrent' );
				$title   = $meta->{title};
				
				# Handler must return at least artist and title
				unless ( $meta->{artist} && $meta->{title} ) {
					$log->debug( "Protocol Handler didn't return an artist and title for " . $track->url . ", ignoring" );
					return;
				}
	
				# Save the title in the track object so we can compare it in checkScrobble
				$track->{_plugin_title} = $title;
			}
			else {
				$log->debug("Ignoring remote URL $url");
				return;
			}
		}
		
		# We check again at half the song's length or 240 seconds, whichever comes first
		my $checktime = $track->secs > 480 ? 240 : ( int( $track->secs / 2 ) );
		
		if ( $log->is_debug ) {
			$log->debug( "New track to scrobble: $title, will check in $checktime seconds" );
		}
		
		Slim::Utils::Timers::setTimer(
			$client,
			Time::HiRes::time() + $checktime,
			\&checkScrobble,
			$track,
			$checktime,
		);
	}			
}

sub submitNowPlaying {
	my ( $client, $track, $retry ) = @_;
	
	# Abort if the user disabled scrobbling for this player
	return if !$prefs->client($client)->get('account');
	
	if ( !$client->pluginData('now_playing_url') ) {
		# Get a new session
		handshake( {
			client => $client,
			cb     => sub {
				submitNowPlaying( $client, $track, $retry );
			},
		} );
		return;
	}
	
	my $artist   = $track->artist ? $track->artist->name : '';
	my $album    = $track->album  ? $track->album->name  : '';
	my $title    = $track->title;
	my $tracknum = $track->tracknum;
	
	if ( $track->remote ) {
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $track->url );
		if ( $handler && $handler->can('getMetadataFor') ) {
			# this plugin provides track metadata, i.e. Pandora, Rhapsody
			my $meta  = $handler->getMetadataFor( $client, $track->url, 'forceCurrent' );
			$artist   = $meta->{artist};
			$album    = $meta->{album};
			$title    = $meta->{title};
			$tracknum = $meta->{tracknum};
			
			# Handler must return at least artist and title
			unless ( $meta->{artist} && $meta->{title} ) {
				$log->debug( "Protocol Handler didn't return an artist and title for " . $track->url . ", ignoring" );
				return;
			}
		}
		else {
			$log->debug( 'Ignoring remote URL ' . $track->url );
			return;
		}
	}
	
	my $post = 's=' . $client->pluginData('session_id')
		. '&a=' . uri_escape_utf8( $artist )
		. '&t=' . uri_escape_utf8( $title )
		. '&b=' . uri_escape_utf8( $album )
		. '&l=' . ( $track->secs ? int( $track->secs ) : '' )
		. '&n=' . $tracknum
		. '&m=' . $track->musicbrainz_id;
	
	$log->debug("Submitting Now Playing track to Last.fm: $post");

	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&_submitNowPlayingOK,
		\&_submitNowPlayingError,
		{
			client => $client,
			track  => $track,
			retry  => $retry,
		}
	);
	
	$http->post(
		$client->pluginData('now_playing_url'),
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
	
	if ( $content =~ /^OK/ ) {
		$log->debug('Now Playing track submitted successfully');
	}
	elsif ( $content =~ /^BADSESSION/ ) {
		$log->debug('Now Playing failed to submit: bad session');
		
		# Re-handshake and retry once
		handshake( {
			client => $client,
			cb     => sub {
				if ( !$retry ) {
					$log->debug('Retrying failed Now Playing submission');				
					submitNowPlaying( $client, $track, 'retry' );
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
	my $error  = $http->error;
	my $client = $http->params('client');
	my $track  = $http->params('track');
	my $retry  = $http->params('retry');
	
	if ( $retry ) {
		$log->debug("Now Playing track failed to submit after retry: $error, giving up");
		return;
	}
	
	$log->debug("Now Playing track failed to submit: $error, retrying in 5 seconds");
	
	# Retry once after 5 seconds
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time() + 5,
		\&submitNowPlaying,
		$track,
		'retry',
	);
}

sub checkScrobble {
	my ( $client, $track, $checktime ) = @_;
	
	return unless $client;
	
	# Make sure player is either playing or paused
	if ( $client->playmode !~ /play|pause/ ) {
		$log->debug( $client->id . ' no longer playing or paused, not scrobbling' );
		return;
	}
	
	# Make sure the track is still the currently playing track
	my $cururl = Slim::Player::Playlist::url($client);
	
	my $artist   = $track->artist ? $track->artist->name : '';
	my $album    = $track->album  ? $track->album->name  : '';
	my $title    = $track->title;
	my $tracknum = $track->tracknum;
	my $source   = 'P';
	
	if ( $track->remote ) {
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $cururl );
		if ( $handler && $handler->can('getMetadataFor') ) {
			# this plugin provides track metadata, i.e. Pandora, Rhapsody
			my $meta  = $handler->getMetadataFor( $client, $cururl, 'forceCurrent' );			
			$artist   = $meta->{artist};
			$album    = $meta->{album};
			$title    = $meta->{title};
			$tracknum = $meta->{tracknum};
			
			# Handler must return at least artist and title
			unless ( $meta->{artist} && $meta->{title} ) {
				$log->debug( "Protocol Handler didn't return an artist and title for $cururl, ignoring" );
				return;
			}
			
			# Make sure user is still listening to the same track
			if ( $title ne $track->{_plugin_title} ) {
				$log->debug( $track->{_plugin_title} . ' - Currently playing track has changed, not scrobbling' );
				return;
			}
			
			# Get the source type from the plugin
			if ( $handler->can('audioScrobblerSource') ) {
				$source = $handler->audioScrobblerSource( $cururl );
			}
		}
		else {
			$log->debug( 'Ignoring remote URL ' . $cururl );
			return;
		}
	}
	elsif ( $cururl ne $track->url ) {
		if ( $log->is_debug ) {
			$log->debug( $track->title . ' - Currently playing track has changed, not scrobbling' );
		}
		
		return;
	}
	
	# Check songtime for the song to see if they paused the track
	my $songtime = Slim::Player::Source::songTime($client);
	if ( $songtime < $checktime ) {
		my $diff = $checktime - $songtime;
		
		$log->debug( "$title - Not yet reached $checktime playback seconds, waiting $diff more seconds" );
		
		Slim::Utils::Timers::killTimers( $client, \&checkScrobble );
		Slim::Utils::Timers::setTimer(
			$client,
			Time::HiRes::time() + $diff,
			\&checkScrobble,
			$track,
			$checktime,
		);
		
		return;
	}
	
	$log->debug( "$title - Queueing track for scrobbling in $checktime seconds" );
	
	my $queue = $prefs->client($client)->get('queue') || [];
	
	push @{$queue}, {
		a => uri_escape_utf8( $artist ),
		t => uri_escape_utf8( $title ),
		i => int( $client->currentPlaylistChangeTime() ),
		o => $source,
		r => '', # XXX: use L for thumbs-up for Pandora/Lastfm, B for Lastfm ban, S for Lastfm skip
		l => ( $track->secs ? int( $track->secs ) : '' ),
		b => uri_escape_utf8( $album ),
		n => $tracknum,
		m => $track->musicbrainz_id,
	};
	
	# save queue as a pref
	$prefs->client($client)->set( queue => $queue );
	
	#warn "Queue is now: " . Data::Dump::dump($queue) . "\n";
	
	# Scrobble in $checktime seconds, the reason for this delay is so we can report
	# thumbs up/down status.  The reason for the extra 10 seconds is so if there is a
	# Now Playing request from the next track, it will do the submit instead.
	Slim::Utils::Timers::killTimers( $client, \&submitScrobble );
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time() + $checktime + 10,
		\&submitScrobble,
	);
}

sub submitScrobble {
	my ( $client, $params ) = @_;
	
	$params ||= {};
	
	# Remove any other pending submit timers
	Slim::Utils::Timers::killTimers( $client, \&submitScrobble );
	
	# Abort if the user disabled scrobbling for this player
	return if !$prefs->client($client)->get('account');
	
	$params->{retry} ||= 0;
	
	if ( !$client->pluginData('submit_url') ) {
		# Get a new session
		handshake( {
			client => $client,
			cb     => sub {
				submitScrobble( $client, $params );
			},
		} );
		return;
	}
	
	my $queue = $prefs->client($client)->get('queue') || [];
	
	if ( !scalar @{$queue} ) {
		# Queue was already submitted, probably by the Now Playing request
		return;
	}
	
	if ( $log->is_debug ) {
		$log->debug( 'Scrobbling ' . scalar( @{$queue} ) . ' queued item(s)' );
		#$log->debug( Data::Dump::dump($queue) );
	}
	
	my @tmpQueue;
	
	my $post = 's=' . $client->pluginData('session_id');
	
	my $index = 0;
	while ( my $item = shift @{$queue} ) {
		push @tmpQueue, $item;
		
		for my $p ( keys %{$item} ) {
			# each value is already uri-escaped as needed
			$post .= '&' . $p . '[' . $index . ']=' . $item->{ $p };
		}
		
		$index++;
	}
	
	$prefs->client($client)->set( queue => $queue );
	
	$log->debug( "Submitting: $post" );
	
	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&_submitScrobbleOK,
		\&_submitScrobbleError,
		{
			tmpQueue => \@tmpQueue,
			params   => $params,
		},
	);
	
	$http->post(
		$client->pluginData('submit_url'),
		'Content-Type' => 'application/x-www-form-urlencoded',
		$post,
	);
}

sub _submitScrobbleOK {
	my $http     = shift;
	my $content  = $http->content;
	my $tmpQueue = $http->params('tmpQueue') || [];
	my $params   = $http->params('params');
	my $client   = $params->{client};
	
	if ( $content =~ /^OK/ ) {
		$log->debug( 'Scrobble submit successful' );
		
		# If we had a callback on success, call it now
		if ( $params->{cb} ) {
			$params->{cb}->();
		}
	}
	elsif ( $content =~ /^BADSESSION/ ) {
		# put the tmpQueue items back into the main queue
		my $queue = $prefs->client($client)->get('queue') || [];
		push @{$queue}, @{$tmpQueue};
		$prefs->client($client)->set( queue => $queue );
		
		$log->debug( 'Scrobble submit failed: invalid session, re-handshaking' );
		
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
	my $client   = delete $params->{client};
	
	# put the tmpQueue items back into the main queue
	my $queue = $prefs->client($client)->get('queue') || [];
	push @{$queue}, @{$tmpQueue};
	$prefs->client($client)->set( queue => $queue );
	
	if ( $params->{retry} == 3 ) {
		# after 3 failures, give up and handshake
		$log->debug( "Scrobble submit failed after 3 tries, re-handshaking" );
		handshake( { client => $client } );
		return;
	}
	
	my $tries = 3 - $params->{retry};
	$log->debug( "Scrobble submit failed: $error, will retry in 5 seconds ($tries tries left)" );
	
	# Retry after a short delay
	$params->{retry}++;
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time() + 5,
		\&submitScrobble,
		$params,
	);
}

1;