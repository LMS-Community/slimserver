package Slim::Plugin::AudioScrobbler::Plugin;

# $Id$

# This plugin handles submission of tracks to Last.fm's
# Audioscrobbler service.

# Logitech Media Server Copyright 2001-2011 Logitech.
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

if ( main::WEBUI ) {
	require Slim::Plugin::AudioScrobbler::Settings;
	require Slim::Plugin::AudioScrobbler::PlayerSettings;
}

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Timers;

use Digest::MD5 qw(md5_hex);
use JSON::XS::VersionOneAndTwo;
use URI::Escape qw(uri_escape_utf8 uri_unescape);

my $prefs = preferences('plugin.audioscrobbler');

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.audioscrobbler',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_AUDIOSCROBBLER_MODULE_NAME',
} );

use constant HANDSHAKE_URL => 'http://post.audioscrobbler.com/';
use constant CLIENT_ID     => main::SLIM_SERVICE ? 'snw' : 'ss7';
use constant CLIENT_VER    => 'sc' . $::VERSION;

sub getDisplayName {
	return 'PLUGIN_AUDIOSCROBBLER_MODULE_NAME';
}

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin();

	if ( main::WEBUI ) {
		Slim::Plugin::AudioScrobbler::Settings->new;
		Slim::Plugin::AudioScrobbler::PlayerSettings->new;
	}
	
	# init scrobbling prefs
	$prefs->init({
		enable_scrobbling => 1,
		include_radio     => 0,
		account           => 0,
	});
	
	# Subscribe to new song events
	Slim::Control::Request::subscribe(
		\&newsongCallback, 
		[['playlist'], ['newsong']],
	);
	
	# Track Info item for loving tracks
	Slim::Menu::TrackInfo->registerInfoProvider( lfm_love => (
		before => 'top',
		func   => \&infoLoveTrack,
	) );
	
	# A way for other things to notify us the user loves a track
	Slim::Control::Request::addDispatch(['audioscrobbler', 'loveTrack', '_url'],
		[0, 1, 1, \&loveTrack]);
	
	Slim::Control::Request::addDispatch(['audioscrobbler', 'banTrack', '_url', '_skip'],
		[0, 1, 1, \&banTrack]);
	
	Slim::Control::Request::addDispatch([ 'audioscrobbler', 'settings' ],
		[1, 1, 0, \&jiveSettingsMenu]);

	Slim::Control::Request::addDispatch([ 'audioscrobbler', 'account' ],
		[1, 0, 1, \&jiveSettingsCommand]);

	# Pref change hooks
	$prefs->setChange( sub {
		my $value  = $_[1];
		my $client = $_[2] || return;
		changeAccount( $client, $value );
	}, 'account' );
}

sub shutdownPlugin {
	Slim::Control::Request::unsubscribe( \&newsongCallback );
}

# Only show player UI settings menu if account is available
sub condition {
	my ( $class, $client ) = @_;
	
	my $accounts = getAccounts($client);
	
	if ( ref $accounts eq 'ARRAY' && scalar @{$accounts} ) {
		return 1;
	}
	
	return;
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
	
	my $accounts = getAccounts($client);
	
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
			
			return $client->string( 'PLUGIN_AUDIOSCROBBLER_USE_ACCOUNT', $account );
		},
		initialValue   => sub { $prefs->client(shift)->get('account'); },
		overlayRef     => sub {
			my ( $client, $account ) = @_;
			my $overlay;
			
			my $curAccount = $prefs->client($client)->get('account') || 0;

			if ( $account eq $curAccount ) {
				$overlay = Slim::Buttons::Common::radioButtonOverlay( $client, 1 );
			} else {
				$overlay = Slim::Buttons::Common::radioButtonOverlay( $client, 0 );
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
				
				my $curAccount = $prefs->client($client)->get('account') || 0;
				
				if ( $curAccount ne $$value ) {
					changeAccount( $client, $$value );

					$client->update();
				}
			}
			else {
				$client->bumpRight;
			}
		},
	} );
}

sub changeAccount {
	my ( $client, $account ) = @_;
	
	$prefs->client($client)->set( account => $account );

	if ( $account eq '0' ) {
		# Kill any timers so the current track is not scrobbled
		Slim::Utils::Timers::killTimers( $client, \&checkScrobble );
		Slim::Utils::Timers::killTimers( $client, \&submitScrobble );
		
		# Dump queue
		setQueue( $client, [] );
	}
	else {	
		# If you change accounts and have more than 1 track queued for scrobbling,
		# dump all but the most recent queued track
		my $queue = getQueue($client);
	
		my $count = scalar @{$queue};
		if ( $count > 1 ) {
			$log->warn( "Changed scrobble accounts with $count queued items, removing items:" );
		
			my $newQueue = [ pop @{$queue} ];
		
			for my $item ( @{$queue} ) {
				$log->warn( '  ' . uri_unescape( $item->{t} ) );
			}
		
			setQueue( $client, $newQueue );
		}
	}

	# Clear session
	clearSession($client);

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( "Changing account for player " . $client->id . " to $account" );
	}
}

sub clearSession {
	my $client = shift;
	
	# Reset our state
	$client->master->pluginData( session_id      => 0 );
	$client->master->pluginData( now_playing_url => 0 );
	$client->master->pluginData( submit_url      => 0 );
}

sub handshake {
	my $params = shift || {};
	
	if ( my $client = $params->{client} ) {
		clearSession( $client );
		
		# Get client's account information
		if ( !$params->{username} ) {
			$params->{username} = $prefs->client($client)->get('account');
			
			my $accounts = getAccounts($client);
			
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
			my $queue = getQueue($client);
			
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

sub newsongCallback {
	my $request = shift;
	my $client  = $request->client() || return;

	# Check if this player has an account selected
	if ( ! (my $account = $prefs->client($client)->get('account')) ) {
		
		# set a zero value so we don't need to query the DB any more in the future
		$prefs->client($client)->set('account', 0) if main::SLIM_SERVICE && !defined $account;
		
		return ;
	}
	
	# If synced, only listen to the master
	if ( $client->isSynced() ) {
		return unless Slim::Player::Sync::isMaster($client);
	}
	
	my $accounts = getAccounts($client);
	
	my $enable_scrobbling;
	
	if ( main::SLIM_SERVICE ) {
		# Get enable_scrobbling from the user_prefs table
		$enable_scrobbling = $prefs->client($client)->get( 'enable_scrobbling', undef, 'UserPref' );
	}
	else {
		$enable_scrobbling = $prefs->get('enable_scrobbling');
	}
	
	return unless $enable_scrobbling && scalar @{$accounts};

	my $url   = Slim::Player::Playlist::url($client);
	my $track = Slim::Schema->objectForUrl( { url => $url } );
	
	my $duration = $track->secs;
	
	if ( $track->remote ) {
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL($url);
		if ( $handler && $handler->can('getMetadataFor') ) {
			# this plugin provides track metadata, i.e. Pandora, Rhapsody
			my $meta = $handler->getMetadataFor( $client, $url, 'forceCurrent' );
			if ( $meta && $meta->{duration} ) {
				$duration = $meta->{duration};
			}
		}
	}
	
	# If this is a radio track (no track length) and contains a playlist index value
	# it is the newsong notification from the station title, which we want to ignore
	if ( !$duration && defined $request->getParam('_p3') ) {
		main::DEBUGLOG && $log->debug( 'Ignoring radio station newsong notification' );
		return;
	}
	
	# report all new songs as now playing
	my $queue = getQueue($client);
	
	if ( scalar @{$queue} && scalar @{$queue} <= 50 ) {
		# before we submit now playing, submit all queued tracks, so that
		# a scrobbled track doesn't clobber the now playing data
		main::DEBUGLOG && $log->debug( 'Submitting scrobble queue before now playing track' );
		
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
	if ( $duration && $duration < 30 ) {
		if ( main::DEBUGLOG && $log->is_debug ) {
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
				main::DEBUGLOG && $log->debug( "Protocol Handler didn't return an artist and title for " . $track->url . ", ignoring" );
				return;
			}

			# Save the title in the track object so we can compare it in checkScrobble
			$track->stash->{_plugin_title} = $title;
		}
		else {
			main::DEBUGLOG && $log->debug("Ignoring remote URL $url");
			return;
		}
	}
	
	# We check again at half the song's length or 240 seconds, whichever comes first
	my $checktime;
	if ( $duration ) {
		$checktime = $duration > 480 ? 240 : ( int( $duration / 2 ) );
	}
	else {
		# For internet radio, check again in 30 seconds
		$checktime = 30;
	}
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( "New track to scrobble: $title, will check in $checktime seconds" );
	}
	
	Slim::Utils::Timers::killTimers( $client, \&checkScrobble );
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time() + $checktime + 5,	# 5 seconds added to allow for startup and avoid unnecessary callback 
		\&checkScrobble,
		$track,
		$checktime,
	);
}

sub submitNowPlaying {
	my ( $client, $track, $retry ) = @_;
	
	# Abort if the user disabled scrobbling for this player
	return if !$prefs->client($client)->get('account');
	
	if ( !$client->master->pluginData('now_playing_url') ) {
		# Get a new session
		handshake( {
			client => $client,
			cb     => sub {
				submitNowPlaying( $client, $track, $retry );
			},
		} );
		return;
	}
	
	my $artist   = $track->artistName || '';
	my $album    = $track->album  ? $track->album->name  : '';
	my $title    = $track->title;
	my $tracknum = $track->tracknum || '';
	my $duration = $track->secs;
	
	if ( $track->remote ) {
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $track->url );
		if ( $handler && $handler->can('getMetadataFor') ) {
			# this plugin provides track metadata, i.e. Pandora, Rhapsody
			my $meta  = $handler->getMetadataFor( $client, $track->url, 'forceCurrent' );
			$artist   = $meta->{artist};
			$album    = $meta->{album} || '';
			$title    = $meta->{title};
			$tracknum = $meta->{tracknum} || '';
			$duration = $meta->{duration} || $track->secs;
			
			# Handler must return at least artist and title
			unless ( $meta->{artist} && $meta->{title} ) {
				main::DEBUGLOG && $log->debug( "Protocol Handler didn't return an artist and title for " . $track->url . ", ignoring" );
				return;
			}
		}
		else {
			main::DEBUGLOG && $log->debug( 'Ignoring remote URL ' . $track->url );
			return;
		}
	}
	
	my $post = 's=' . $client->master->pluginData('session_id')
		. '&a=' . uri_escape_utf8( $artist )
		. '&t=' . uri_escape_utf8( $title )
		. '&b=' . uri_escape_utf8( $album )
		. '&l=' . ( $duration ? int( $duration ) : '' )
		. '&n=' . $tracknum
		. '&m=' . ( $track->musicbrainz_id || '' );
	
	main::DEBUGLOG && $log->debug("Submitting Now Playing track to Last.fm: $post");

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
		main::DEBUGLOG && $log->debug("Now Playing track failed to submit after retry: $error, giving up");
		return;
	}
	
	main::DEBUGLOG && $log->debug("Now Playing track failed to submit: $error, retrying in 5 seconds");
	
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
	
	return unless $client && $track;
	
	# Make sure player is either playing or paused
	if ( $client->isStopped() ) {
		main::DEBUGLOG && $log->debug( $client->id . ' no longer playing or paused, not scrobbling' );
		return;
	}
	
	# Make sure the track is still the currently playing track
	my $cururl = Slim::Player::Playlist::url($client);
	
	my $artist   = $track->artistName || '';
	my $album    = $track->album  ? $track->album->name  : '';
	my $title    = $track->title;
	my $tracknum = $track->tracknum || '';
	my $duration = $track->secs;
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
			$duration = $meta->{duration} || $track->secs;
			
			# Handler must return at least artist and title
			unless ( $meta->{artist} && $meta->{title} ) {
				main::DEBUGLOG && $log->debug( "Protocol Handler didn't return an artist and title for $cururl, ignoring" );
				return;
			}
			
			# Make sure user is still listening to the same track
			if ( $track->stash->{_plugin_title} && $title ne $track->stash->{_plugin_title} ) {
				main::DEBUGLOG && $log->debug( $track->stash->{_plugin_title} . ' - Currently playing track has changed, not scrobbling' );
				return;
			}
			
			# Get the source type from the plugin
			if ( $handler->can('audioScrobblerSource') ) {
				$source = $handler->audioScrobblerSource( $client, $cururl );
				
				# Ignore radio tracks if requested, unless rating = L
				if ( !defined $rating || $rating ne 'L' ) {
					my $include_radio;
					if ( main::SLIM_SERVICE ) {
						$include_radio = $prefs->client($client)->get( 'include_radio', undef, 'UserPref' );
					}
					else {
						$include_radio = $prefs->get('include_radio');
					}
					
					if ( defined $include_radio && !$include_radio && $source =~ /^[RE]$/ ) {
						main::DEBUGLOG && $log->debug("Ignoring radio URL $cururl, scrobbling of radio is disabled");
						return;
					}
				}
			}
		}
		else {
			main::DEBUGLOG && $log->debug( 'Ignoring remote URL ' . $cururl );
			return;
		}
	}
	elsif ( $cururl ne $track->url ) {
		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug( $track->title . ' - Currently playing track has changed, not scrobbling' );
		}
		
		return;
	}
	
	# Check songtime for the song to see if they paused the track
	my $songtime = Slim::Player::Source::songTime($client);
	if ( $songtime < $checktime ) {
		my $diff = $checktime - $songtime;
		
		main::DEBUGLOG && $log->debug( "$title - Not yet reached $checktime playback seconds, waiting $diff more seconds" );
		
		Slim::Utils::Timers::killTimers( $client, \&checkScrobble );
		Slim::Utils::Timers::setTimer(
			$client,
			Time::HiRes::time() + $diff,
			\&checkScrobble,
			$track,
			$checktime,
			$rating,
		);
		
		return;
	}
	
	main::DEBUGLOG && $log->debug( "$title - Queueing track for scrobbling in $checktime seconds" );
	
	my $queue = getQueue($client);
	
	push @{$queue}, {
		_url => $cururl,
		a    => uri_escape_utf8( $artist ),
		t    => uri_escape_utf8( $title ),
		i    => int( $client->currentPlaylistChangeTime() ),
		o    => $source,
		r    => $rating || '', # L for thumbs-up for Pandora/Lastfm, B for Lastfm ban, S for Lastfm skip
		l    => ( $duration ? int( $duration ) : '' ),
		b    => uri_escape_utf8( $album ),
		n    => $tracknum,
		m    => ( $track->musicbrainz_id || '' ),
	};
	
	setQueue( $client, $queue );
	
	# If the URL wasn't a Last.fm station and the user loved the track, report the Love
	if ( $rating && $rating eq 'L' && $cururl !~ /^lfm/ ) {
		submitLoveTrack( $client, $queue->[-1] );
	}
	
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
	$params->{retry} ||= 0;
	
	my $cb = $params->{cb} || sub {};
	
	# Remove any other pending submit timers
	Slim::Utils::Timers::killTimers( $client, \&submitScrobble );

	my $queue = getQueue($client);
	
	if ( !scalar @{$queue} ) {
		# Queue was already submitted, probably by the Now Playing request
		return $cb->();
	}
	
	# Abort if the user disabled scrobbling for this player
	my $account = $prefs->client($client)->get('account');
	if ( !$account ) {
		main::DEBUGLOG && $log->debug( 'User disabled scrobbling for this player, wiping queue and not submitting' );
		
		setQueue( $client, [] );
		
		return $cb->();
	}

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
		if ( $current_track && stillPlaying( $client, $current_track, $item ) ) {
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
		setQueue( $client, $queue );
	
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

# Check if a track is still playing
sub stillPlaying {
	my ( $client, $track, $item ) = @_;
	
	my $artist   = $track->artistName || '';
	my $album    = $track->album  ? $track->album->name  : '';
	my $title    = $track->title;
	
	# Bug 12240: if we have stopped (probably at the end of the playlist) then we are not still playing
	if ($client->isStopped()) {
		return 0;
	}
	
	if ( $track->remote ) {
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $track->url );
		if ( $handler && $handler->can('getMetadataFor') ) {
			# this plugin provides track metadata, i.e. Pandora, Rhapsody
			my $meta  = $handler->getMetadataFor( $client, $track->url, 'forceCurrent' );			
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
		main::DEBUGLOG && $log->debug( 'Scrobble submit successful' );
		
		# If we had a callback on success, call it now
		if ( $params->{cb} ) {
			$params->{cb}->();
		}
	}
	elsif ( $content =~ /^BADSESSION/ ) {
		# put the tmpQueue items back into the main queue
		my $queue = getQueue($client);
		
		push @{$queue}, @{$tmpQueue};
		
		setQueue( $client, $queue );
		
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
	my $queue = getQueue($client);
	
	push @{$queue}, @{$tmpQueue};
	
	setQueue( $client, $queue );
	
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

sub loveTrack {
	my $request = shift;
	my $client  = $request->client || return;
	my $url     = $request->getParam('_url');
	
	# Ignore if not Scrobbling
	return if !$prefs->client($client)->get('account');
	
	my $enable_scrobbling;
	if ( main::SLIM_SERVICE ) {
		$enable_scrobbling  = $prefs->client($client)->get('enable_scrobbling');
	}
	else {
		$enable_scrobbling  = $prefs->get('enable_scrobbling');
	}
	
	return unless $enable_scrobbling;
	
	main::DEBUGLOG && $log->debug( "Loved: $url" );
	
	# Look through the queue and update the item we want to love
	my $queue = getQueue($client);
	
	for my $item ( @{$queue} ) {
		if ( $item->{_url} eq $url ) {
			$item->{r} = 'L';
			
			setQueue( $client, $queue );
			
			# If the URL wasn't a Last.fm station, report the Love
			if ( $url !~ /^lfm/ ) {
				submitLoveTrack( $client, $item );
			}
			
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

sub submitLoveTrack {
	my ( $client, $item ) = @_;
	
	my $username = $prefs->client($client)->get('account');
	my $accounts = getAccounts($client);
	my $password;
	
	for my $account ( @{$accounts} ) {
		if ( $account->{username} eq $username ) {
			$password = $account->{password};
			last;
		}
	}
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		sub {
			my $http = shift;
			main::DEBUGLOG && $log->debug( 'Love track response: ' . $http->content );
		},
		sub {
			my $http = shift;
			main::DEBUGLOG && $log->debug( 'Love track error: ' . $http->error );
		},
		{
			client => $client,
		},
	);
	
	my $url = Slim::Networking::SqueezeNetwork->url(
		'/api/lastfm/v1/scrobbling/love'
		. '?username='  . $username
		. '&authToken=' . md5_hex( $username . $password )
		. '&artist='    . $item->{a}
		. '&track='     . $item->{t}
	);
	
	main::DEBUGLOG && $log->debug( 'Submitting loved track to Last.fm' );
	
	$http->get( $url );
}

sub banTrack {
	my $request = shift;
	my $client  = $request->client || return;
	my $url     = $request->getParam('_url');
	my $skip    = $request->getParam('_skip') || 0;

	# Ban is only supported for Last.fm URLs
	return unless $url =~ /^lfm/;
	
	# Skip to the next track
	if ( $skip ) {
		$client->execute([ 'playlist', 'jump', '+1' ]);
	}
	
	# Ignore if not Scrobbling
	return if !$prefs->client($client)->get('account');
	
	my $enable_scrobbling;
	if ( main::SLIM_SERVICE ) {
		$enable_scrobbling  = $prefs->client($client)->get('enable_scrobbling');
	}
	else {
		$enable_scrobbling  = $prefs->get('enable_scrobbling');
	}
	
	return unless $enable_scrobbling;

	main::DEBUGLOG && $log->debug( "Banned: $url" );
	
	# Look through the queue and update the item we want to ban
	my $queue = getQueue($client);
	
	for my $item ( @{$queue} ) {
		if ( $item->{_url} eq $url ) {
			$item->{r} = 'B';
			
			setQueue( $client, $queue );
				
			return 1;
		}
	}
	
	# The track wasn't already in the queue, they probably rated the track
	# before getting halfway through.  Call checkScrobble with a checktime
	# of 0 to force it to be added to the queue with the rating of B
	my $track = Slim::Schema->objectForUrl( { url => $url } );
	
	Slim::Utils::Timers::killTimers( $client, \&checkScrobble );
	
	checkScrobble( $client, $track, 0, 'B' );
	
	return 1;
}	

# Return whether or not the given track will be scrobbled
sub canScrobble {
	my ( $class, $client, $track ) = @_;
	
	# Ignore if not Scrobbling
	return if !$prefs->client($client)->get('account');

	my $enable_scrobbling;
	if ( main::SLIM_SERVICE ) {
		$enable_scrobbling  = $prefs->client($client)->get('enable_scrobbling');
	}
	else {
		$enable_scrobbling  = $prefs->get('enable_scrobbling');
	}
	
	return unless $enable_scrobbling;
	
	if ( $track->remote ) {
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $track->url );
		if ( $handler ) {
			
			# Must be over 30 seconds
			if ( $handler->can('getMetadataFor') ) {
				my $meta = $handler->getMetadataFor( $client, $track->url, 'forceCurrent' );
				my $duration = $meta->{duration} || $track->secs;
				if ( $duration && $duration < 30 ) {
					return;
				}
			}
			
			# Must provide a source
			if ( $handler->can('audioScrobblerSource') ) {
				if ( my $source = $handler->audioScrobblerSource( $client, $track->url ) ) {
					return 1;
				}
			}
		}
	}
	else {
		# Must be over 30 seconds
		return if $track->secs && $track->secs < 30;
		
		return 1;
	}

	return;
}

sub getAccounts {
	my $client = shift;
	
	my $accounts;
	
	if ( main::SLIM_SERVICE ) {
		$accounts = $prefs->client($client)->get( 'accounts', undef, 'UserPref' ) || [];
	
		if ( !ref $accounts ) {
			$accounts = from_json( $accounts );
		}
	}
	else {	
		$accounts = $prefs->get('accounts') || [];
	}
	
	return $accounts;
}

sub getQueue {
	my $client = shift;
	
	my $queue;
	
	if ( main::SLIM_SERVICE ) {
		$queue = SDI::Service::Model::ScrobbleQueue->get( $client->playerData->id );
	}
	else {
		$queue = $prefs->client($client)->get('queue') || [];
	}
	
	return $queue;
}

sub setQueue {
	my ( $client, $queue ) = @_;
	
	if ( main::SLIM_SERVICE ) {
		SDI::Service::Model::ScrobbleQueue->set( $client->playerData->id, $queue );
	}
	else {
		$prefs->client($client)->set( queue => $queue );
	}
}

sub infoLoveTrack {
	my ( $client, $url, $track, $remoteMeta ) = @_;

	return unless $client;
	
	# Ignore if the current track can't be scrobbled
	if ( !__PACKAGE__->canScrobble( $client, $track ) ) {
		return;
	}
	
	# Ignore if this track isn't currently playing, you can only love
	# something that is playing and being scrobbled
	if ( $track->url ne Slim::Player::Playlist::url($client) ) {
		return;
	}
	
	return {
		type        => 'link',
		name        => $client->string('PLUGIN_AUDIOSCROBBLER_LOVE_TRACK'),
		url         => \&infoLoveTrackSubmit,
		passthrough => [ $url ],
		favorites   => 0,
	};
}

sub infoLoveTrackSubmit {
	my ( $client, $callback, undef, $url ) = @_;
	
	$client->execute( [ 'audioscrobbler', 'loveTrack', $url ] );
	
	$callback->( {
		type        => 'text',
		name        => $client->string('PLUGIN_AUDIOSCROBBLER_TRACK_LOVED'),
		showBriefly => 0,
		favorites   => 0,
	} );
}
		
sub jiveSettings {

	my $client = shift;

	return [ {
		stringToken    => getDisplayName(),
		id             => 'audioscrobbler',
		node           => 'advancedSettings',
		weight         => 100,
		actions => {
			go => {
				player => 0,
				cmd    => [ 'audioscrobbler', 'settings' ],
			},
		},
	} ];
}

sub jiveSettingsCommand {
	my $request = shift;
	my $client  = $request->client();
	my $account = $request->getParam('user');

	main::DEBUGLOG && $log->debug('Setting account to: ' . $account);
	changeAccount( $client, $account );

	$request->setStatusDone();

}
	
sub jiveSettingsMenu {

	my $request  = shift;
	my $client   = $request->client();
	my $accounts = getAccounts($client);
	my $enabled  = $prefs->get('enable_scrobbling');
	my $selected = $prefs->client($client)->get('account');

	my @menu     = ();

	for my $account (@$accounts) {
		my $item = {
			text    => $account->{username},
			radio   => ($selected eq $account->{username} && $enabled) + 0,
			actions => {
				do => {
					player => 0,
					cmd    => [ 'audioscrobbler' , 'account' ],
					params => {
						user => $account->{username},
					},
				},
			},
		};
		push @menu, $item;
	}

	# disable for this player
	my $disableItem = {
		text    => $client->string('PLUGIN_AUDIOSCROBBLER_SCROBBLING_DISABLED'),
		radio   => ($selected eq '0') + 0,
		actions => {
			do => {
				player => 0,
				cmd    => [ 'audioscrobbler' , 'account' ],
				params => {
					user => '0',
				},
			},
		},
	};
	push @menu, $disableItem;

	my $numitems = scalar(@menu);
	$request->addResult("count", $numitems);
	$request->addResult("offset", 0);
	my $cnt = 0;
	for my $eachItem (@menu[0..$#menu]) {
		$request->setResultLoopHash('item_loop', $cnt, $eachItem);
		$cnt++;
	}
	$request->setStatusDone();
}

1;
