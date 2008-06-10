package Slim::Plugin::LastFM::ProtocolHandler;

# $Id$

# Handler for lastfm:// URLs

use strict;
use base qw(Slim::Player::Protocols::HTTP);

use JSON::XS qw(from_json);
use URI::Escape qw(uri_escape_utf8);

use Slim::Player::Playlist;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.lfm',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_LFM_MODULE_NAME',
} );

my $prefs = preferences('plugin.audioscrobbler');

# To support remote streaming (synced players, slimp3/SB1), we need to subclass Protocols::HTTP
sub new {
	my $class  = shift;
	my $args   = shift;

	my $client = $args->{client};
	my $url    = $args->{url};
	
	my $track  = $client->pluginData('currentTrack') || {};
	
	$log->debug( 'Remote streaming Last.fm track: ' . $track->{location} );

	return unless $track->{location};

	my $sock = $class->SUPER::new( {
		url     => $track->{location},
		client  => $client,
		bitrate => 128_000,
	} ) || return;
	
	${*$sock}{contentType} = 'audio/mpeg';

	# XXX: Time counter is not right, it starts from 0:00 as soon as next track 
	# begins streaming (slimp3/SB1 only)
	
	return $sock;
}

sub getFormatForURL () { 'mp3' }

sub isAudioURL () { 1 }

# Don't allow looping if the tracks are short
sub shouldLoop () { 0 }

sub canSeek { 0 }

# Source for AudioScrobbler (L = Last.fm)
# Must append trackauth value as well
sub audioScrobblerSource {
	my ( $class, $client, $url ) = @_;
	
	my $track = $client->pluginData('currentTrack');
	
	if ( $track ) {
		return 'L' . $track->{extension}->{trackauth};
	}
	
	return;
}

sub handleError {
    my ( $error, $client ) = @_;

	if ( $client ) {
		$client->unblock;
		
		Slim::Buttons::Common::pushModeLeft( $client, 'INPUT.Choice', {
			header  => '{PLUGIN_LFM_ERROR}',
			listRef => [ $error ],
		} );
		
		if ( $ENV{SLIM_SERVICE} ) {
		    logError( $client, $error );
		}
	}
}

sub logError {
	my ( $client, $error ) = @_;
	
	SDI::Service::EventLog->log( 
		$client, 'lastfm_error', $error,
	);
}

# Whether or not to display buffering info while a track is loading
sub showBuffering {
	my ( $class, $client, $url ) = @_;
	
	my $showBuffering = $client->pluginData('showBuffering');
	
	return ( defined $showBuffering ) ? $showBuffering : 1;
}

sub getNextTrack {
	my ( $client, $params ) = @_;
	
	my $station = $params->{station};
	
	# Get Scrobbling prefs
	my $enable_scrobbling;
	if ( $ENV{SLIM_SERVICE} ) {
		$enable_scrobbling = $prefs->client($client)->get('enable_scrobbling');
	}
	else {
		$enable_scrobbling = $prefs->get('enable_scrobbling');
	}
	
	my $account      = $prefs->client($client)->get('account');
	my $isScrobbling = ( $account && $enable_scrobbling ) ? 1 : 0;
	my $discovery    = $prefs->client($client)->get('discovery') || 0;
	
	# Talk to SN and get the next track to play
	my $trackURL = Slim::Networking::SqueezeNetwork->url(
		"/api/lastfm/v1/playback/getNextTrack?station=" . uri_escape_utf8($station)
		. "&isScrobbling=$isScrobbling"
		. "&discovery=$discovery"
		. "&account=" . uri_escape_utf8($account)
	);
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&gotNextTrack,
		\&gotNextTrackError,
		{
			client  => $client,
			params  => $params,
			timeout => 35,
		},
	);
	
	$log->debug("Getting next track from SqueezeNetwork ($trackURL)");
	
	$http->get( $trackURL );
}

sub gotNextTrack {
	my $http   = shift;
	my $client = $http->params->{client};
	my $params = $http->params->{params};
	
	my $track = eval { from_json( $http->content ) };
	
	if ( $@ || $track->{error} ) {
		# We didn't get the next track to play
		if ( $log->is_warn ) {
			$log->warn( 'Last.fm error getting next track: ' . ( $@ || $track->{error} ) );
		}
		
		my $url = Slim::Player::Playlist::url($client);

		setCurrentTitle( $client, $url, $track->{error} || $client->string('PLUGIN_LFM_NO_TRACKS') );
		
		$client->showBriefly( {
			line => [ 
				$client->string('PLUGIN_LFM_MODULE_NAME'),
				$track->{error} || $client->string('PLUGIN_LFM_NO_TRACKS')
			],
		},
		{
			scroll => 1,
			block  => 1,
		} );

		Slim::Player::Source::playmode( $client, 'stop' );
	
		return;
	}
	
	if ( $log->is_debug ) {
		$log->debug( 'Got Last.fm track: ' . Data::Dump::dump($track) );
	}
	
	# Watch for playlist commands
	Slim::Control::Request::subscribe( 
		\&playlistCallback, 
		[['playlist'], ['repeat', 'newsong']],
		$client,
	);
	
	# Save existing repeat setting
	my $repeat = Slim::Player::Playlist::repeat($client);
	if ( $repeat != 2 ) {
		$log->debug( "Saving existing repeat value: $repeat" );
		$client->pluginData( oldRepeat => $repeat );
	}
	
	# Force repeating
	$client->execute(["playlist", "repeat", 2]);
	
	# Save the previous track's metadata, in case the user wants track info
	# after the next track begins buffering
	$client->pluginData( prevTrack => $client->pluginData('currentTrack') );
	
	# Save metadata for this track, and save the previous track
	$client->pluginData( currentTrack => $track );
	
	my $cb = $params->{callback};
	$cb->();
}

sub gotNextTrackError {
	my $http   = shift;
	my $client = $http->params('client');
	
	handleError( $http->error, $client );
	
	# Make sure we re-enable readNextChunkOk
	$client->readNextChunkOk(1);
}

# Handle normal advances to the next track
sub onDecoderUnderrun {
	my ( $class, $client, $nextURL, $callback ) = @_;
	
	# Special handling needed when synced
	if ( Slim::Player::Sync::isSynced($client) ) {
		if ( !Slim::Player::Sync::isMaster($client) ) {
			# Only the master needs to fetch next track info
			$log->debug('Letting sync master fetch next Last.fm track');
			return;
		}
	}

	# Flag that we don't want any buffering messages while loading the next track,
	$client->pluginData( showBuffering => 0 );
	
	# Get next track
	my ($station) = $nextURL =~ m{^lfm://(.+)};
	
	getNextTrack( $client, {
		station  => $station,
		callback => $callback,
	} );
	
	return;
}

# On skip, load the next track before playback
sub onJump {
    my ( $class, $client, $nextURL, $callback ) = @_;

	# Display buffering info on loading the next track
	# unless we shouldn't (when rating down)
	if ( $client->pluginData('banMode') ) {
		$client->pluginData( showBuffering => 0 );
		$client->pluginData( banMode => 0 );
	}
	else {
		$client->pluginData( showBuffering => 1 );
	}
	
	# If synced and we already fetched a track in onDecoderUnderrun,
	# just callback, don't fetch another track.  Checks prevTrack to
	# make sure there is actually a track ready to be played.
	if ( Slim::Player::Sync::isSynced($client) && $client->pluginData('prevTrack') ) {
		$log->debug( 'onJump while synced, but already got the next track to play' );
		$callback->();
		return;
	}
	
	# Get next track
	my ($station) = $nextURL =~ m{^lfm://(.+)};
	
	getNextTrack( $client, {
		station  => $station,
		callback => $callback,
	} );
	
	return;
}

sub parseDirectHeaders {
	my $class   = shift;
	my $client  = shift || return;
	my $url     = shift;
	my @headers = @_;
	
	my $bitrate     = 128_000;
	my $contentType = 'mp3';
	
	# Clear previous duration, since we're using the same URL for all tracks
	Slim::Music::Info::setDuration( $url, 0 );
	
	# Grab content-length for progress bar
	my ($length, $redir);
	foreach my $header (@headers) {
		if ( $header =~ /^Content-Length:\s*(.*)/i ) {
			$length = $1;
		}
		elsif ( $header =~ /^Location:\s*(.*)/i ) {
			$redir = $1;
		}
	}
	
	if ( $redir ) {
		$client->pluginData( redir => $redir );
	}
	
	# title, bitrate, metaint, redir, type, length, body
	return (undef, $bitrate, 0, undef, $contentType, $length, undef);
}

# If an audio stream fails, keep playing
sub handleDirectError {
	my ( $class, $client, $url, $response, $status_line ) = @_;
	
	$log->info("Direct stream failed: [$response] $status_line");
	
	$client->showBriefly( {
		line => [ $client->string('PLUGIN_LFM_ERROR'), $client->string('PLUGIN_LFM_STREAM_FAILED') ]
	},
	{
		block  => 1,
		scroll => 1,
	} );
	
	# XXX: Stop after a certain number of errors in a row
	
	$client->execute([ 'playlist', 'play', $url ]);
}

# Check if player is allowed to skip, using canSkip value from SN
sub canSkip {
	my $client = shift;
	
	if ( my $track = $client->pluginData('currentTrack') ) {
		return $track->{canSkip};
	}
	
	return 1;
}

# Disallow skips after the limit is reached
sub canDoAction {
	my ( $class, $client, $url, $action ) = @_;
	
	if ( $action eq 'stop' && !canSkip($client) ) {
		# Is skip allowed?
		$log->debug("Last.fm: Skip limit exceeded, disallowing skip");

		$client->showBriefly( {
			line => [ $client->string('PLUGIN_LFM_MODULE_NAME'), $client->string('PLUGIN_LFM_SKIPS_EXCEEDED') ]
		},
		{
			scroll => 1,
			block  => 1,
		} );
				
		return 0;
	}
	elsif ( $action eq 'pause' ) {
		# Pausing not allowed, stop instead
		return 0;
	}
	
	return 1;
}

sub canDirectStream {
	my ( $class, $client, $url ) = @_;
	
	# We need to check with the base class (HTTP) to see if we
	# are synced or if the user has set mp3StreamingMethod
	my $base = $class->SUPER::canDirectStream( $client, $url );
	if ( !$base ) {
		return 0;
	}
	
	my $track = $client->pluginData('currentTrack') || {};
	
	return $track->{location} || 0;
}

sub playlistCallback {
	my $request = shift;
	my $client  = $request->client();
	my $cmd     = $request->getRequest(0);
	my $p1      = $request->getRequest(1);
	
	return unless defined $client;
	
	# ignore if user is not using Pandora
	my $url = Slim::Player::Playlist::url($client);
	
	if ( !$url || $url !~ /^lfm/ ) {
		# User stopped playing Last.fm, reset old repeat setting if any
		my $repeat = $client->pluginData('oldRepeat');
		if ( defined $repeat ) {
			$log->debug( "Stopped Last.fm, restoring old repeat setting: $repeat" );
			$client->execute(["playlist", "repeat", $repeat]);
		}
		
		$log->debug( "Stopped Last.fm, unsubscribing from playlistCallback" );
		Slim::Control::Request::unsubscribe( \&playlistCallback, $client );
		
		return;
	}
	
	$log->debug("Got playlist event: $p1");
	
	# The user has changed the repeat setting.  Pandora requires a repeat
	# setting of '2' (repeat all) to work properly, or it will cause the
	# "stops after every song" bug
	if ( $p1 eq 'repeat' ) {
		if ( $request->getParam('_newvalue') != 2 ) {
			$log->debug("User changed repeat setting, forcing back to 2");
		
			$client->execute(["playlist", "repeat", 2]);
		
			if ( $client->playmode =~ /playout/ ) {
				$client->playmode( 'playout-play' );
			}
		}
	}
	elsif ( $p1 eq 'newsong' ) {
		# A new song has started playing.  We use this to change titles
		my $track = $client->pluginData('currentTrack');
		
		my $title 
			= $track->{title} . ' ' . $client->string('BY') . ' '
			. $track->{creator};
		
		# Some Last.fm tracks don't have albums
		if ( $track->{album} ) {
			$title .= ' ' . $client->string('FROM') . ' ' . $track->{album};
		}
		
		setCurrentTitle( $client, $url, $title );
		
		# Remove the previous track metadata
		$client->pluginData( prevTrack => 0 );
	}
}

# Track Info menu
sub trackInfo {
	my ( $class, $client, $track ) = @_;
	
	my $url = $track->url;
	
	# SN URL to fetch track info menu
	my $trackInfoURL = $class->trackInfoURL( $client, $url );
	
	# let XMLBrowser handle all our display
	my %params = (
		header   => 'PLUGIN_LFM_GETTING_TRACK_DETAILS',
		modeName => 'Last.fm Now Playing',
		title    => Slim::Music::Info::getCurrentTitle( $client, $url ),
		url      => $trackInfoURL,
		remember => 0,
		timeout  => 35,
	);

	Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );
	
	$client->modeParam( 'handledTransition', 1 );
}

# URL used for CLI trackinfo queries
sub trackInfoURL {
	my ( $class, $client, $url ) = @_;
	
	my ($station) = $url =~ m{^lfm://(.+)};
	
	my $account = $prefs->client($client)->get('account');
	
	# Get the current track
	my $currentTrack = $client->pluginData('prevTrack') || $client->pluginData('currentTrack');
	
	# SN URL to fetch track info menu
	my $trackInfoURL = Slim::Networking::SqueezeNetwork->url(
		  '/api/lastfm/v1/opml/trackinfo?station=' . uri_escape_utf8($station)
		. '&trackId=' . $currentTrack->{identifier}
		. '&account=' . uri_escape_utf8($account)
	);
	
	return $trackInfoURL;
}

sub setCurrentTitle {
	my ( $client, $url, $title ) = @_;
	
	# We can't use the normal getCurrentTitle method because it would cause multiple
	# players playing the same station to get the same titles
	$client->pluginData( currentTitle => $title );
	
	# Call the normal setCurrentTitle method anyway, so it triggers callbacks to
	# update the display
	Slim::Music::Info::setCurrentTitle( $url, $title );
}

sub getCurrentTitle {
	my ( $class, $client, $url ) = @_;
	
	return $client->pluginData('currentTitle');
}

# Metadata for a URL, used by CLI/JSON clients
sub getMetadataFor {
	my ( $class, $client, $url, $forceCurrent ) = @_;
	
	my $track;
	
	if ( $forceCurrent ) {
		$track = $client->pluginData('currentTrack');
	}
	else {
		$track = $client->pluginData('prevTrack') || $client->pluginData('currentTrack')
	}
	
	return unless $track;
	
	my $icon = $class->getIcon();
	
	return {
		artist      => $track->{creator},
		album       => $track->{album},
		title       => $track->{title},
		cover       => $track->{image} || $icon,
		icon        => $icon,
		duration    => $track->{secs},
		bitrate     => '128k CBR',
		type        => 'MP3 (' . $client->string('PLUGIN_LFM_MODULE_NAME') . ')',
		info_link   => 'plugins/lastfm/trackinfo.html',
		buttons     => {
			# disable REW/Previous button
			rew => 0,

			# replace repeat with Love
			repeat  => {
				icon    => 'html/images/btn_lastfm_love.gif',
				tooltip => $client->string('PLUGIN_LFM_LOVE'),
				command => [ 'lfm', 'rate', 'L' ],
			},

			# replace shuffle with Ban
			shuffle => {
				icon    => 'html/images/btn_lastfm_ban.gif',
				tooltip => $client->string('PLUGIN_LFM_BAN'),
				command => [ 'lfm', 'rate', 'B' ],
			},
		}
	};
}

sub getIcon {
	my ( $class, $url ) = @_;

	return Slim::Plugin::LastFM::Plugin->_pluginDataFor('icon');
}

# SLIM_SERVICE
# Re-init Last.fm when a player reconnects
sub reinit {
	my ( $class, $client, $playlist ) = @_;
	
	my $url = $playlist->[0];
	
	if ( my $track = $client->pluginData('currentTrack') ) {
		# We have previous data about the currently-playing song
		
		$log->debug("Re-init Last.fm");
		
		# Re-add playlist item
		$client->execute( [ 'playlist', 'add', $url ] );
	
		# Reset track title
		my $title = $track->{title}   . ' ' . $client->string('BY')   . ' '
				  . $track->{creator} . ' ' . $client->string('FROM') . ' '
				  . $track->{album};
				
		setCurrentTitle( $client, $url, $title );
		
		# Back to Now Playing
		Slim::Buttons::Common::pushMode( $client, 'playlist' );
		
		# Reset song duration/progress bar
		if ( $track->{secs} ) {
			# On a timer because $client->currentsongqueue does not exist yet
			Slim::Utils::Timers::setTimer(
				$client,
				Time::HiRes::time(),
				sub {
					my $client = shift;
					
					$client->streamingProgressBar( {
						url      => $url,
						duration => $track->{secs},
					} );
				},
			);
		}
	}
	else {
		# No data, just restart the current station
		$log->debug("No data about playing track, restarting station");

		$client->execute( [ 'playlist', 'play', $url ] );
	}
	
	return 1;
}

1;
