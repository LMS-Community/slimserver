package Slim::Plugin::AudioScrobbler::Plugin;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2025 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# This plugin handles submission of tracks to Last.fm (Audioscrobbler v1.2)
# and ListenBrainz service.

# The basic algorithm used by this plugin is very simple:
# On newsong, figure out how long from now until half of song or 240 secs
# Set a timer for that time, the earliest possible time they could meet the criteria
# When timer fires, make sure same track is playing
# If not yet at the time (maybe they paused), recalc and set the timer again
# If time has passed, great, submit it

# https://www.last.fm/api/submissions
# https://listenbrainz.readthedocs.io/en/latest/users/api/core.html

# Thanks to the SlimScrobbler plugin for inspiration and feature ideas.
# http://slimscrobbler.sourceforge.net/

use strict;
use base qw(Slim::Plugin::Base);

use Scalar::Util qw(blessed);

use Slim::Player::ProtocolHandlers;
use Slim::Player::Source;

if ( main::WEBUI ) {
	require Slim::Plugin::AudioScrobbler::Settings;
	require Slim::Plugin::AudioScrobbler::PlayerSettings;
}

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);
use Slim::Utils::Timers;

use URI::Escape qw(uri_escape_utf8 uri_unescape);

my $prefs = preferences('plugin.audioscrobbler');

# Migration from version 0 to 1: add api_type and api_url to existing accounts
$prefs->migrate(1, sub {
	my $accounts = $prefs->get('accounts') || [];

	for my $account (@{$accounts}) {
		# Add api_type if missing, defaulting to lastfm
		if (!exists $account->{api_type}) {
			$account->{api_type} = 'lastfm';
		}

		# Add api_url if missing, defaulting to empty string
		if (!exists $account->{api_url}) {
			$account->{api_url} = '';
		}
	}

	# Save the updated accounts
	$prefs->set('accounts', $accounts);
	1;
});

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.audioscrobbler',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_AUDIOSCROBBLER_MODULE_NAME',
} );

my $loveHandler;

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
		ignoreTitles      => '',
		ignoreGenres      => '',
		ignoreArtists     => '',
		ignoreAlbums      => '',
	});

	# Subscribe to new song events
	Slim::Control::Request::subscribe(
		\&newsongCallback,
		[['playlist'], ['newsong']],
	);

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

# to be used by 3rd party plugins providing this feature
sub registerLoveHandler {
	$loveHandler = shift;

	# Track Info item for loving tracks
	if ($loveHandler) {
		main::INFOLOG && $log->is_info && $log->info("Got a Last.fm handler registration.");

		Slim::Menu::TrackInfo->registerInfoProvider( lfm_love => (
			before => 'top',
			func   => \&infoLoveTrack,
		) );

		# A way for other things to notify us the user loves a track
		Slim::Control::Request::addDispatch(['audioscrobbler', 'loveTrack', '_url'],
			[0, 1, 1, \&loveTrack]);
	}
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

	$client = Slim::Player::Client::getClient($client) if !blessed $client;

	# Reset our state
	$client->master->pluginData( session_id      => 0 );
	$client->master->pluginData( now_playing_url => 0 );
	$client->master->pluginData( submit_url      => 0 );
}

sub newsongCallback {
	my $request = shift;
	my $client  = $request->client() || return;

	# Check if this player has an account selected
	my $account = $prefs->client($client)->get('account');
	if ( !$account ) {
		return ;
	}

	# If synced, only listen to the master
	if ( $client->isSynced() ) {
		return unless Slim::Player::Sync::isMaster($client);
	}

	return unless $prefs->get('enable_scrobbling') && scalar @{ getAccounts($client) };

	my $url   = Slim::Player::Playlist::url($client);
	my $track = Slim::Schema->objectForUrl( { url => $url } );

	my $duration = $track->secs;
	my $meta;

	if ( $track->remote ) {
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL($url);
		if ( $handler && $handler->can('getMetadataFor') ) {
			# this plugin provides track metadata
			$meta = $handler->getMetadataFor( $client, $url, 'forceCurrent' );
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

	# Track must be > 30 seconds - check this early to avoid submitting short tracks for Now Playing
	if ( $duration && $duration < 30 ) {
		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug( 'Ignoring track ' . $track->title . ', shorter than 30 seconds' );
		}

		return;
	}

	# report all new songs as now playing (for Last.fm)
	my $queue = getQueue($client);

	my $api = Slim::Plugin::AudioScrobbler::API->getAPI($client);

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
					undef,
					$api,
				);
			},
		} );
	} else {
		$api->submitNowPlaying($track);
	}

	# Determine when we need to check again

	my $title = $track->title;

	if ( $track->can('stash') ) {
		if ( $meta ) {
			$title = $meta->{title};

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

	$meta ||= {};

	my @ignoreTitles  = split(/\s*,\s*/, $prefs->get('ignoreTitles'));
	my @ignoreAlbums  = split(/\s*,\s*/, $prefs->get('ignoreAlbums'));
	my @ignoreArtists = split(/\s*,\s*/, $prefs->get('ignoreArtists'));
	my @ignoreGenres  = split(/\s*,\s*/, $prefs->get('ignoreGenres'));

	if ( (scalar @ignoreTitles && grep { $title =~ /\Q$_\E/i } @ignoreTitles)
		|| (scalar @ignoreArtists && grep { ($track->artistName || $meta->{artist} || '') =~ /\Q$_\E/i } @ignoreArtists)
		|| (scalar @ignoreAlbums && grep { ($track->albumname || $meta->{album} || '') =~ /\Q$_\E/i } @ignoreAlbums)
	) {
		main::DEBUGLOG && $log->debug( sprintf("Ignoring %s, it's failing one of the ignored items tests: %s, %s", $title, $track->artistName || $meta->{artist}, $track->albumname || $meta->{album}) );
		return;
	}

	if (scalar @ignoreGenres) {
		my @trackGenres = map { $_->name } $track->genres;
		if (!@trackGenres && $meta->{genre}) {
			push @trackGenres, $meta->{genre};
		}

		if (scalar @trackGenres) {
			foreach my $trackGenre (@trackGenres) {
				if (grep { $trackGenre =~ /\Q$_\E/i } @ignoreGenres) {
					main::DEBUGLOG && $log->debug( sprintf("Ignoring %s due to genre match: %s", $title, join(', ', @trackGenres)) );
					return;
				}
			}
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
	my ($client, $track, $retry, $api) = @_;
	$api->submitNowPlaying($track, $retry) if $api;
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

	my $meta = _getMetadata($client, $track, $cururl);

	my $source = 'P';

	if ( $track->can('stash') ) {
		if (!$meta) {
			main::DEBUGLOG && $log->debug( 'Ignoring remote URL ' . $cururl );
			return;
		}

		# Handler must return at least artist and title
		elsif ( $meta->{msg} ) {
			main::DEBUGLOG && $log->debug( $meta->{msg} );
			return;
		}

		# Make sure user is still listening to the same track
		elsif ( $track->stash->{_plugin_title} && $meta->{title} ne $track->stash->{_plugin_title} ) {
			main::DEBUGLOG && $log->debug( $track->stash->{_plugin_title} . ' - Currently playing track has changed, not scrobbling' );
			return;
		}

		my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $cururl );
		# Get the source type from the plugin
		if ( $handler->can('audioScrobblerSource') ) {
			$source = $handler->audioScrobblerSource( $client, $cururl );

			# Ignore radio tracks if requested, unless rating = L
			if ( !defined $rating || $rating ne 'L' ) {
				my $include_radio = $prefs->get('include_radio');

				if ( defined $include_radio && !$include_radio && $source =~ /^[RE]$/ ) {
					main::DEBUGLOG && $log->debug("Ignoring radio URL $cururl, scrobbling of radio is disabled");
					return;
				}
			}
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

		main::DEBUGLOG && $log->debug( $meta->{title} . " - Not yet reached $checktime playback seconds, waiting $diff more seconds" );

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

	main::DEBUGLOG && $log->debug( $meta->{title} . " - Queueing track for scrobbling in $checktime seconds" );

	my $queue = getQueue($client);

	push @{$queue}, {
		_url => $cururl,
		a    => uri_escape_utf8( $meta->{artist} ),
		t    => uri_escape_utf8( $meta->{title} ),
		i    => int( $client->currentPlaylistChangeTime() ),
		o    => $source,
		r    => $rating || '', # L for thumbs-up for Pandora/Lastfm, B for Lastfm ban, S for Lastfm skip
		l    => ( $meta->{duration} ? int( $meta->{duration} ) : '' ),
		b    => uri_escape_utf8( $meta->{album} ),
		n    => $meta->{tracknum},
		'm'  => ( $track->musicbrainz_id || '' ),
	};

	setQueue( $client, $queue );

	# If the URL wasn't a Last.fm station and the user loved the track, report the Love
	if ( $loveHandler && $rating && $rating eq 'L' && $cururl ) {
		submitLoveTrack( $client, $queue->[-1] );
	}

	main::DEBUGLOG && $log->is_debug && $log->debug("Queue is now: " . Data::Dump::dump($queue));

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

	my $api = Slim::Plugin::AudioScrobbler::API->getAPI($client);

	main::DEBUGLOG && $log->is_debug && $log->debug("Submitting to: account=$account");

	$api->submitScrobble( $queue, $params );
}

# Check if a track is still playing
sub stillPlaying {
	my ( $client, $track, $item ) = @_;

	# Bug 12240: if we have stopped (probably at the end of the playlist) then we are not still playing
	if ($client->isStopped()) {
		return 0;
	}

	my $meta = _getMetadata($client, $track) || return 1;

	if ( $meta->{title} ne uri_unescape( $item->{t} ) ) {
		return 0;
	}
	elsif ( $meta->{album} ne uri_unescape( $item->{b} ) ) {
		return 0;
	}
	elsif ( $meta->{artist} ne uri_unescape( $item->{a} ) ) {
		return 0;
	}

	return 1;
}

sub _getMetadata {
	my ($client, $track, $url) = @_;

	$url ||= $track->url;

	$track = Slim::Schema->objectForUrl( { url => $url } ) if $url && !ref $track;

	return unless ref $track;

	$client = Slim::Player::Client::getClient($client) if !blessed $client;

	my $meta = {
		artist   => $track->artistName || '',
		album    => ($track->album && $track->album->get_column('title')) || '',
		title    => $track->title,
		tracknum => $track->tracknum || '',
		duration => $track->secs,
	};

	if ( $track->remote ) {
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $url );
		if ( $handler && $handler->can('getMetadataFor') ) {
			# this plugin provides track metadata
			my $meta2 = $handler->getMetadataFor( $client, $url, 'forceCurrent' );

			# Handler must return at least artist and title
			unless ( $meta2->{artist} && $meta2->{title} ) {
				return {
					msg => "Protocol Handler didn't return an artist and title for $url, ignoring"
				};
			}

			$meta->{artist}   = $meta2->{artist};
			$meta->{album}    = $meta2->{album} || '';
			$meta->{title}    = $meta2->{title};
			$meta->{tracknum} = $meta2->{tracknum} || '';
			$meta->{duration} = $meta2->{duration} || $track->secs;
		}
		else {
			main::DEBUGLOG && $log->debug( 'Ignoring remote URL ' . $url );
			return;
		}
	}

	return $meta;
}

sub loveTrack { if ($loveHandler) {
	my $request = shift;
	my $client  = $request->client || return;
	my $url     = $request->getParam('_url');

	# Ignore if not Scrobbling
	return if !$prefs->client($client)->get('account');

	return unless $prefs->get('enable_scrobbling');

	main::DEBUGLOG && $log->debug( "Loved: $url" );

	# Look through the queue and update the item we want to love
	my $queue = getQueue($client);

	if ( my ($item) = grep { $_->{_url} eq $url } @$queue ) {
		submitLoveTrack( $client, $item );
		return 1;
	}

	# The track wasn't already in the queue, they probably rated the track
	# before getting halfway through.  Call checkScrobble with a checktime
	# of 0 to force it to be added to the queue with the rating of L
	my $track = Slim::Schema->objectForUrl( { url => $url } );

	Slim::Utils::Timers::killTimers( $client, \&checkScrobble );

	checkScrobble( $client, $track, 0, 'L' );

	return 1;
} }

sub submitLoveTrack { if ($loveHandler) {
	$loveHandler->(@_);
} }

# Return whether or not the given track will be scrobbled
sub canScrobble {
	my ( $class, $client, $track ) = @_;

	# Ignore if not Scrobbling
	return if !$prefs->client($client)->get('account');

	return unless $prefs->get('enable_scrobbling');

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
	return $prefs->get('accounts') || [];
}

sub getAccount {
	my $client = shift;

	my $username = $prefs->client($client)->get('account');

	return unless $username;

	my $accounts = getAccounts($client) || return;

	my ($account) = grep { $_->{username} eq $username } @{$accounts};
	return $account;
}


sub getQueue {
	my $client = shift;

	return $prefs->client($client)->get('queue') || [];
}

sub setQueue {
	my ( $client, $queue ) = @_;

	$client = Slim::Player::Client::getClient($client) if !blessed $client;
	$prefs->client($client)->set( queue => $queue );
}

sub infoLoveTrack { if ($loveHandler) {
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
} }

sub infoLoveTrackSubmit { if ($loveHandler) {
	my ( $client, $callback, undef, $url ) = @_;

	$client->execute( [ 'audioscrobbler', 'loveTrack', $url ] );

	$callback->( {
		type        => 'text',
		name        => $client->string('PLUGIN_AUDIOSCROBBLER_TRACK_LOVED'),
		showBriefly => 0,
		favorites   => 0,
	} );
} }

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
