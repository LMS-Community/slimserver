package Slim::Plugin::AudioScrobbler::Plugin;

# $Id$

# This plugin handles submission of tracks to Last.fm's
# Audioscrobbler service.

# SqueezeCenter Copyright 2001-2007 Logitech.
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
use URI::Escape qw(uri_escape_utf8 uri_unescape);

my $prefs = preferences('plugin.audioscrobbler');

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.audioscrobbler',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_AUDIOSCROBBLER_MODULE_NAME',
} );

use constant HANDSHAKE_URL => 'http://post.audioscrobbler.com/';
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
	
	# A way for other things to notify us the user loves a track
	Slim::Control::Request::addDispatch(['audioscrobbler', 'loveTrack', '_url'],
		[0, 1, 1, \&loveTrack]);
}

sub shutdownPlugin {
	Slim::Control::Request::unsubscribe( \&newsongCallback );
}

# Button interface to change account or toggle scrobbling
sub setMode {
	my $class  = shift;
	my $client = shift;
	my $method = shift;

	if ( $method eq 'pop' ) {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	
	my $listRef = [ 0 ];
	
	my $accounts = $prefs->get('accounts') || [];
	for my $account ( @{$accounts} ) {
		push @{$listRef}, $account->{username};
	}

	Slim::Buttons::Common::pushModeLeft( $client, 'INPUT.List', {

		header         => $client->string('PLUGIN_AUDIOSCROBBLER_MODULE_NAME'),
		headerAddCount => 1,
		listRef        => $listRef,
		externRef      => sub {
			my ( $client, $account ) = @_;
			
			if ( !$account ) {
				return $client->string('PLUGIN_AUDIOSCROBBLER_SCROBBLING_DISABLED');
			}
			
			my $accounts = $prefs->get('accounts') || [];
			return $client->string( 'PLUGIN_AUDIOSCROBBLER_USE_ACCOUNT', $accounts->[$account]->{username} );
		},
		initialValue   => sub { $prefs->client(shift)->get('account'); },
		overlayRef     => sub {
			my ( $client, $account ) = @_;
			my $overlay;
			
			my $curAccount = $prefs->client($client)->get('account') || 0;

			if ( $account eq $curAccount ) {
				$overlay = Slim::Buttons::Common::checkBoxOverlay( $client, 1 );
			} else {
				$overlay = Slim::Buttons::Common::checkBoxOverlay( $client, 0 );
			}
			
			return ( undef, $overlay );
		},
		callback      => sub { 
			my ( $client, $exittype ) = @_;

			$exittype = uc $exittype;

			if ( $exittype eq 'LEFT' ) {

				Slim::Buttons::Common::popModeRight($client);
			}
			elsif ( $exittype eq 'RIGHT' ) {
				my $value = $client->modeParam('valueRef');
				
				$prefs->client($client)->set( account => $$value );
				
				if ( $$value eq '0' ) {
					# Kill any timers so the current track is not scrobbled
					Slim::Utils::Timers::killTimers( $client, \&checkScrobble );
					Slim::Utils::Timers::killTimers( $client, \&submitScrobble ); 
				}

				$client->update();
			}
			else {
				$client->bumpRight;
			}
		},
	} );
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
	
	Slim::Utils::Timers::killTimers( $params, \&handshake );
	Slim::Utils::Timers::setTimer(
		$params,
		time() + ( $delay * 60 ),
		\&handshake,
	);
}

sub newsongCallback {
	my $request = shift;
	my $client  = $request->client() || return;
	
	# If synced, only listen to the master
	if ( Slim::Player::Sync::isSynced($client) ) {
		return unless Slim::Player::Sync::isMaster($client);
	}

	# Check if this player has an account selected
	return if !$prefs->client($client)->get('account');
	
	return unless $prefs->get('enable_scrobbling');

	my $url   = Slim::Player::Playlist::url($client);
	my $track = Slim::Schema->objectForUrl( { url => $url } );
	
	# If this is a radio track (no track length) and contains a playlist index value
	# it is the newsong notification from the station title, which we want to ignore
	if ( !$track->secs && defined $request->getParam('_p3') ) {
		$log->debug( 'Ignoring radio station newsong notification' );
		return;
	}
	
	# report all new songs as now playing
	my $queue = $prefs->client($client)->get('queue') || [];
	
	if ( scalar @{$queue} ) {
		# before we submit now playing, submit all queued tracks, so that
		# a scrobbled track doesn't clobber the now playing data
		$log->debug( 'Submitting scrobble queue before now playing track' );
		
		submitScrobble( $client, {
			cb => sub {
				# delay by 1 second so we don't hit the server too fast after
				# the submit call
				Slim::Utils::Timers::killTimers( $client, \&submitNowPlaying );
				Slim::Utils::Timers::setTimer(
					$client,
					time() + 1,
					\&submitNowPlaying,
					$track,
				);
			},
		} );
	}
	else {
		submitNowPlaying( $client, $track );
	}

	# Determine when we need to check again
	
	# Track must be > 30 seconds
	if ( $track->secs && $track->secs < 30 ) {
		if ( $log->is_debug ) {
			$log->debug( 'Ignoring track ' . $track->title . ', shorter than 30 seconds' );
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
	my $checktime;
	if ( $track->secs ) {
		$checktime = $track->secs > 480 ? 240 : ( int( $track->secs / 2 ) );
	}
	else {
		# For internet radio, check again in 30 seconds
		$checktime = 30;
	}
	
	if ( $log->is_debug ) {
		$log->debug( "New track to scrobble: $title, will check in $checktime seconds" );
	}
	
	Slim::Utils::Timers::killTimers( $client, \&checkScrobble );
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time() + $checktime,
		\&checkScrobble,
		$track,
		$checktime,
	);
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
	my $tracknum = $track->tracknum || '';
	
	if ( $track->remote ) {
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $track->url );
		if ( $handler && $handler->can('getMetadataFor') ) {
			# this plugin provides track metadata, i.e. Pandora, Rhapsody
			my $meta  = $handler->getMetadataFor( $client, $track->url, 'forceCurrent' );
			$artist   = $meta->{artist};
			$album    = $meta->{album} || '';
			$title    = $meta->{title};
			$tracknum = $meta->{tracknum} || '';
			
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
		. '&m=' . ( $track->musicbrainz_id || '' );
	
	$log->debug("Submitting Now Playing track to Last.fm: $post");

	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&_submitNowPlayingOK,
		\&_submitNowPlayingError,
		{
			client  => $client,
			track   => $track,
			retry   => $retry,
			timeout => 30,
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
	Slim::Utils::Timers::killTimers( $client, \&submitNowPlaying );
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time() + 5,
		\&submitNowPlaying,
		$track,
		'retry',
	);
}

sub checkScrobble {
	my ( $client, $track, $checktime, $rating ) = @_;
	
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
	my $tracknum = $track->tracknum || '';
	my $source   = 'P';
	
	if ( $track->remote ) {
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $cururl );
		if ( $handler && $handler->can('getMetadataFor') ) {
			# this plugin provides track metadata, i.e. Pandora, Rhapsody
			my $meta  = $handler->getMetadataFor( $client, $cururl, 'forceCurrent' );			
			$artist   = $meta->{artist};
			$album    = $meta->{album} || '';
			$title    = $meta->{title};
			$tracknum = $meta->{tracknum} || '';
			
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
				$source = $handler->audioScrobblerSource( $client, $cururl );
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
		_url => $cururl,
		a    => uri_escape_utf8( $artist ),
		t    => uri_escape_utf8( $title ),
		i    => int( $client->currentPlaylistChangeTime() ),
		o    => $source,
		r    => $rating, # L for thumbs-up for Pandora/Lastfm, B for Lastfm ban, S for Lastfm skip
		l    => ( $track->secs ? int( $track->secs ) : '' ),
		b    => uri_escape_utf8( $album ),
		n    => $tracknum,
		m    => ( $track->musicbrainz_id || '' ),
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
	
	my $current;
	my @tmpQueue;
	
	my $post = 's=' . $client->pluginData('session_id');
	
	my $index = 0;
	while ( my $item = shift @{$queue} ) {
		
		# Don't submit tracks that are still playing, to allow user
		# to rate the track
		if ( stillPlaying( $client, $item ) ) {
			$log->debug( "Track " . $item->{_url} . " is still playing, not submitting" );
			$current = $item;
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
	}
	
	# Add the currently playing track back to the queue
	if ( $current ) {
		unshift @{$queue}, $current;
		
		# Try again in a minute
		Slim::Utils::Timers::killTimers( $client, \&submitScrobble );
		Slim::Utils::Timers::setTimer(
			$client,
			time() + 60,
			\&submitScrobble,
		);
	}
	
	$prefs->client($client)->set( queue => $queue );
	
	if ( @tmpQueue ) {
		$log->debug( "Submitting: $post" );
	
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
			$client->pluginData('submit_url'),
			'Content-Type' => 'application/x-www-form-urlencoded',
			$post,
		);
	}
}

# Check if a track is still playing
sub stillPlaying {
	my ( $client, $item ) = @_;
	
	# Get the currently playing track
	my $url   = Slim::Player::Playlist::url($client);
	my $track = Slim::Schema->objectForUrl( { url => $url } );
	
	my $artist   = $track->artist ? $track->artist->name : '';
	my $album    = $track->album  ? $track->album->name  : '';
	my $title    = $track->title;
	
	if ( $track->remote ) {
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $url );
		if ( $handler && $handler->can('getMetadataFor') ) {
			# this plugin provides track metadata, i.e. Pandora, Rhapsody
			my $meta  = $handler->getMetadataFor( $client, $url, 'forceCurrent' );			
			$artist   = $meta->{artist};
			$album    = $meta->{album};
			$title    = $meta->{title};
		}
	}
	
	if ( $title ne uri_unescape( $item->{t} ) ) {
		return 0;
	}
	elsif ( $album ne uri_unescape( $item->{b} ) ) {
		return 0;
	}
	elsif ( $artist ne uri_unescape( $item->{a} ) ) {
		return 0;
	}
	
	return 1;
}

sub _submitScrobbleOK {
	my $http     = shift;
	my $content  = $http->content;
	my $tmpQueue = $http->params('tmpQueue') || [];
	my $params   = $http->params('params');
	my $client   = $http->params('client');
	
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
	my $client   = $http->params('client');
	
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
	Slim::Utils::Timers::killTimers( $client, \&submitScrobble );
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time() + 5,
		\&submitScrobble,
		$params,
	);
}

sub loveTrack {
	my $request = shift;
	my $client  = $request->client || return;
	my $url     = $request->getParam('_url');
	
	# Ignore if not Scrobbling
	return if !$prefs->client($client)->get('account');
	return unless $prefs->get('enable_scrobbling');
	
	$log->debug( "Loved: $url" );
	
	# Look through the queue and update the item we want to love
	my $queue = $prefs->client($client)->get('queue') || [];
	
	for my $item ( @{$queue} ) {
		if ( $item->{_url} eq $url ) {
			$item->{r} = 'L';
			
			$prefs->client($client)->set( queue => $queue );
			
			return 1;
		}
	}
	
	# The track wasn't already in the queue, they probably rated the track
	# before getting halfway through.  Call checkScrobble with a checktime
	# of 0 to force it to be added to the queue with the rating of L
	my $track = Slim::Schema->objectForUrl( { url => $url } );
	
	Slim::Utils::Timers::killTimers( $client, \&checkScrobble );
	
	checkScrobble( $client, $track, 0, 'L' );
	
	return 1;
}

# Return whether or not the given track will be scrobbled
sub canScrobble {
	my ( $class, $client, $track ) = @_;
	
	# Ignore if not Scrobbling
	return if !$prefs->client($client)->get('account');
	return unless $prefs->get('enable_scrobbling');
	
	# Must be over 30 seconds
	return if $track->secs && $track->secs < 30;
	
	# Remote tracks must provide a source
	if ( $track->remote ) {
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $track->url );
		if ( $handler && $handler->can('audioScrobblerSource') ) {
			if ( my $source = $handler->audioScrobblerSource( $client, $track->url ) ) {
				return 1;
			}
		}
	}
	else {
		return 1;
	}

	return;
}

1;
