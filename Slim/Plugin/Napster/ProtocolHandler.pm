package Slim::Plugin::Napster::ProtocolHandler;

# $Id$

# Napster handler for napster:// URLs.

use strict;
use base qw(Slim::Player::Protocols::MMS);

use JSON::XS::VersionOneAndTwo;
use Scalar::Util qw(blessed);
use URI::Escape qw(uri_escape_utf8);

use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Cache;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

use constant SN_DEBUG => 0;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.napster',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_NAPSTER_MODULE_NAME',
} );

my $prefs = preferences('server');

sub isRemote { 1 }

sub getFormatForURL { 'wma' }

sub canSeek {
	my ( $class, $client, $song ) = @_;
	
	# No seeking on radio tracks
	if ( $song->track()->url =~ /\.nsr$/ ) {
		return 0;
	}
	
	return 1;
}

# To support remote streaming (synced players), we need to subclass Protocols::MMS
sub new {
	my $class  = shift;
	my $args   = shift;

	my $client = $args->{client};
	
	my $song      = $args->{song};
	my $streamUrl = $song->streamUrl() || return;
	
	main::DEBUGLOG && $log->debug( 'Remote streaming Napster track: ' . $streamUrl );

	my $sock = $class->SUPER::new( {
		url     => $streamUrl,
		song    => $args->{song},
		client  => $client,
		bitrate => 128_000,
	} ) || return;
	
	${*$sock}{contentType} = 'audio/x-ms-wma';

	return $sock;
}

# Avoid scanning
sub scanUrl {
	my ( $class, $url, $args ) = @_;
	$args->{cb}->( $args->{song}->currentTrack() );
}

# Source for AudioScrobbler
sub audioScrobblerSource {
	my ( $class, $client, $url ) = @_;

	if ( $url =~ /\.nsr$/ ) {
		# R = Non-personalised broadcast
		return 'R';
	}

	# P = Chosen by the user
	return 'P';
}

# parseHeaders is used for proxied streaming
sub parseHeaders {
	my ( $self, @headers ) = @_;
	
	__PACKAGE__->parseDirectHeaders( $self->client, $self->url, @headers );
	
	return $self->SUPER::parseHeaders( @headers );
}

sub parseDirectHeaders {
	my ( $class, $client, $url, @headers ) = @_;
	
	my $length;
	
	# Clear previous duration, since we're using the same URL for all tracks
	if ( $url =~ /\.nsr$/ ) {
		Slim::Music::Info::setDuration( $url, 0 );
	}
	
	my $bitrate = 128_000;

	$client->streamingSong->bitrate($bitrate);

	# ($title, $bitrate, $metaint, $redir, $contentType, $length, $body)
	return (undef, $bitrate, 0, '', 'wma', $length, undef);
}

# Don't allow looping
sub shouldLoop { 0 }

sub isRepeatingStream {
	my ( undef, $song ) = @_;
	
	return $song->track()->url =~ /\.nsr$/;
}

sub canDoAction {
	my ( $class, $client, $url, $action ) = @_;
	
	# Don't allow pause or rew on radio
	if ( $url =~ /\.nsr$/ ) {
		if ( $action eq 'pause' || $action eq 'rew' ) {
			return 0;
		}
	}
	
	return 1;
}

sub handleDirectError {
	my ( $class, $client, $url, $response, $status_line ) = @_;
	
	main::DEBUGLOG && $log->debug("Direct stream failed: [$response] $status_line\n");
	
	if ( main::SLIM_SERVICE && SN_DEBUG ) {
		SDI::Service::EventLog->log(
			$client, 'napster_error', "$response - $status_line"
		);
	}
	
	$client->controller()->playerStreamingFailed($client, 'PLUGIN_NAPSTER_STREAM_FAILED');
}

sub _handleClientError {
	my ( $error, $client, $params ) = @_;
	
	my $song    = $params->{song};
	
	return if $song->pluginData('abandonSong');
	
	# Tell other clients to give up
	$song->pluginData( abandonSong => 1 );
	
	$params->{errorCb}->($error);
}

sub getNextTrack {
	my ($class, $song, $successCb, $errorCb) = @_;
	
	my $client = $song->master();
	my $url    = $song->track()->url;
	
	$song->pluginData( radioTrackURL => undef );
	$song->pluginData( radioTitle    => undef );
	$song->pluginData( radioTrack    => undef );
	$song->pluginData( abandonSong   => 0 );
	
	my $params = {
		song      => $song,
		url       => $url,
		successCb => $successCb,
		errorCb   => $errorCb,
	};
	
	# 1. If this is a radio-station then get next track info
	if ( $class->isRepeatingStream($song) ) {
		_getNextRadioTrack($params);
	}
	else {
		_getTrack($params);
	}
	
	# 2. For each player in sync-group:
	# 2.1 Get mediaURL
}

# 1. If this is a radio-station then get next track info
sub _getNextRadioTrack {
	my ($params) = @_;
		
	my ($stationId) = $params->{url} =~ m{napster://(.+)\.nsr};
	
	# Talk to SN and get the next track to play
	my $radioURL = Slim::Networking::SqueezeNetwork->url(
		"/api/napster/v1/radio/getNextTrack?stationId=$stationId"
	);
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&_gotNextRadioTrack,
		\&_gotNextRadioTrackError,
		{
			client  => $params->{song}->master(),
			params  => $params,
			timeout => 30,
		},
	);
	
	main::DEBUGLOG && $log->debug("Getting next radio track from SqueezeNetwork");
	
	$http->get( $radioURL );
}

# 1.1a If this is a radio-station then get next track info
sub _gotNextRadioTrack {
	my $http   = shift;
	my $client = $http->params->{client};
	my $params = $http->params->{params};
	my $song   = $params->{song};
	my $url    = $song->track()->url;
	
	my $track = eval { from_json( $http->content ) };
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( 'Got next radio track: ' . Data::Dump::dump($track) );
	}
	
	if ( $track->{error} ) {
		# We didn't get the next track to play
		
		my $error = ( $client->isPlaying(1) && $client->playingSong()->track()->url =~ /\.nsr/ )
					? 'PLUGIN_NAPSTER_NO_NEXT_TRACK'
					: 'PLUGIN_NAPSTER_NO_TRACK';
		
		$params->{errorCb}->( $error, $url );

		# Set the title after the errro callback so the current title
		# is still the radio-station name during the callback
		Slim::Music::Info::setCurrentTitle( $url, $client->string('PLUGIN_NAPSTER_NO_TRACK') );
			
		return;
	}
	
	# set metadata for track, will be set on playlist newsong callback
	$url      = 'napster://' . $track->{id} . '.wma';
	my $title = $track->{title} . ' ' . 
			$client->string('BY') . ' ' . $track->{artist} . ' ' . 
			$client->string('FROM') . ' ' . $track->{album};
	
	$song->pluginData( radioTrackURL => $url );
	$song->pluginData( radioTitle    => $title );
	$song->pluginData( radioTrack    => $track );
	
	# We already have the metadata for this track, so can save calling getTrack
	my $meta = {
		artist    => $track->{artist},
		album     => $track->{album},
		title     => $track->{title},
		duration  => $track->{duration},
		cover     => $track->{cover},
		bitrate   => '128k CBR',
		type      => 'WMA (Napster)',
		info_link => 'plugins/napster/trackinfo.html',
		icon      => Slim::Plugin::Napster::Plugin->_pluginDataFor('icon'),
		buttons   => {
			# disable REW/Previous button in radio mode
			rew => 0,
		},
	};
	
	$song->duration( $track->{duration} );
	
	my $cache = Slim::Utils::Cache->new;
	$cache->set( 'napster_meta_' . $track->{id}, $meta, 86400 );
	
	$params->{url} = $url;
	
	_gotTrackInfo( $client, $track, $params );
}

# 1.1b If this is a radio-station then get next track info
sub _gotNextRadioTrackError {
	my $http   = shift;
	my $client = $http->params('client');
	
	_handleClientError( $http->error, $client, $http->params->{params} );
}

# 2. For each player in sync-group: get track-info
sub _getTrack {
	my $params  = shift;
	
	my $song    = $params->{song};
	my @players = $song->master()->syncGroupActiveMembers();
	
	# Fetch the track info
	_getTrackInfo( $song->master(), undef, $params );
}

# 2.1 Get mediaURL
sub _getTrackInfo {
    my ( $client, undef, $params ) = @_;

	my $song = $params->{song};
	
	return if $song->pluginData('abandonSong');

	# Get track URL for the next track
	my ($trackId) = $params->{url} =~ m{napster://(.+)\.wma};
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		sub {
			my $http = shift;
			my $info = eval { from_json( $http->content ) };
			if ( $@ || $info->{error} ) {
				if ( main::DEBUGLOG && $log->is_debug ) {
					$log->debug( 'getTrackInfo failed: ' . ( $@ || $info->{error} ) );
					$log->debug( '      data received: ' . Data::Dump::dump($info) );
				}
				
				_gotTrackError( $@ || $info->{error}, $client, $params );
			}
			else {
				if ( main::DEBUGLOG && $log->is_debug ) {
					$log->debug( 'getTrackInfo ok: ' . Data::Dump::dump($info) );
				}
				
				_gotTrackInfo( $client, $info, $params );
			}
		},
		sub {
			my $http  = shift;
			
			if ( main::DEBUGLOG && $log->is_debug ) {
				$log->debug( 'getTrackInfo failed: ' . $http->error );
			}
			
			_gotTrackError( $http->error, $client, $params );
		},
		{
			client => $client,
		},
	);
	
	main::DEBUGLOG && $log->is_debug && $log->debug('Getting next track playback info from SN');
	
	$http->get(
		Slim::Networking::SqueezeNetwork->url(
			'/api/napster/v1/playback/getMediaURL?trackId=' . uri_escape_utf8($trackId)
		)
	);
}

# 2.1a Get mediaURL 
sub _gotTrackInfo {
	my ( $client, $info, $params ) = @_;
	
    my $song = $params->{song};
    
    return if $song->pluginData('abandonSong');
	
	# Save the media URL for use in strm
	$song->streamUrl( delete $info->{url} );
	
	# Cache the rest of the track's metadata
	my $meta = {
		artist    => $info->{artist},
		album     => $info->{album},
		title     => $info->{title},
		cover     => $info->{cover},
		duration  => $info->{duration},
		bitrate   => '128k CBR',
		type      => 'WMA (Napster)',
		info_link => 'plugins/napster/trackinfo.html',
		icon      => Slim::Plugin::Napster::Plugin->_pluginDataFor('icon'),
	};
	
	$song->duration( $info->{duration} );
	
	my $cache = Slim::Utils::Cache->new;
	$cache->set( 'napster_meta_' . $info->{id}, $meta, 86400 );
	
	$params->{successCb}->();
}

# 2.1b Get mediaURL 
sub _gotTrackError {
	my ( $error, $client, $params ) = @_;
	
	main::DEBUGLOG && $log->debug("Error during getTrackInfo: $error");

	return if $params->{song}->pluginData('abandonSong');

	_handleClientError( $error, $client, $params );
}
	
# Metadata for a URL, used by CLI/JSON clients
sub getMetadataFor {
	my ( $class, $client, $url ) = @_;
	
	my $icon = $class->getIcon();
	
	if ( $url =~ /\.nsr$/ ) {
		my $song = $client->currentSongForUrl($url);
		if ( !$song || !( $url = $song->pluginData('radioTrackURL') ) ) {
			return {
				bitrate   => '128k CBR',
				type      => 'WMA (Napster)',
				icon      => $icon,
				cover     => $icon,
			};
		}
	}
	
	return {} unless $url;
	
	my $cache = Slim::Utils::Cache->new;
	
	# If metadata is not here, fetch it so the next poll will include the data
	my ($trackId) = $url =~ m{napster://(.+)\.wma};
	my $meta      = $cache->get( 'napster_meta_' . $trackId );
	
	if ( !$meta && !$client->master->pluginData('fetchingMeta') ) {
		# Go fetch metadata for all tracks on the playlist without metadata
		my @need;
		
		for my $track ( @{ Slim::Player::Playlist::playList($client) } ) {
			my $trackURL = blessed($track) ? $track->url : $track;
			if ( $trackURL =~ m{napster://(.+)\.wma} ) {
				my $id = $1;
				if ( !$cache->get("napster_meta_$id") ) {
					push @need, $id;
				}
			}
		}
		
		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug( "Need to fetch metadata for: " . join( ', ', @need ) );
		}
		
		$client->master->pluginData( fetchingMeta => 1 );
		
		my $metaUrl = Slim::Networking::SqueezeNetwork->url(
			"/api/napster/v1/playback/getBulkMetadata"
		);
		
		my $http = Slim::Networking::SqueezeNetwork->new(
			\&_gotBulkMetadata,
			\&_gotBulkMetadataError,
			{
				client  => $client,
				timeout => 60,
			},
		);

		$http->post(
			$metaUrl,
			'Content-Type' => 'application/x-www-form-urlencoded',
			'trackIds=' . join( ',', @need ),
		);
	}
	
	#$log->debug( "Returning metadata for: $url" . ($meta ? '' : ': default') );
	
	return $meta || {
		bitrate   => '128k CBR',
		type      => 'WMA (Napster)',
		icon      => $icon,
		cover     => $icon,
	};
}

sub _gotBulkMetadata {
	my $http   = shift;
	my $client = $http->params->{client};
	
	$client->master->pluginData( fetchingMeta => 0 );
	
	my $info = eval { from_json( $http->content ) };
	
	if ( $@ || ref $info ne 'ARRAY' ) {
		$log->error( "Error fetching track metadata: " . ( $@ || 'Invalid JSON response' ) );
		return;
	}
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( "Caching metadata for " . scalar( @{$info} ) . " tracks" );
	}
		
	# Cache metadata
	my $cache = Slim::Utils::Cache->new;
	my $icon  = Slim::Plugin::Napster::Plugin->_pluginDataFor('icon');

	for my $track ( @{$info} ) {
		next unless ref $track eq 'HASH';
		
		# cache the metadata we need for display
		my $trackId = delete $track->{id};
		
		my $meta = {
			%{$track},
			bitrate   => '128k CBR',
			type      => 'WMA (Napster)',
			info_link => 'plugins/napster/trackinfo.html',
			icon      => $icon,
		};
	
		$cache->set( 'napster_meta_' . $trackId, $meta, 86400 );
	}
	
	# Update the playlist time so the web will refresh, etc
	$client->currentPlaylistUpdateTime( Time::HiRes::time() );
	
	Slim::Control::Request::notifyFromArray( $client, [ 'newmetadata' ] );
}

sub _gotBulkMetadataError {
	my $http   = shift;
	my $client = $http->params('client');
	my $error  = $http->error;
	
	$client->master->pluginData( fetchingMeta => 0 );
	
	$log->warn("Error getting track metadata from SN: $error");
}

sub _playlistCallback {
	my $request = shift;
	my $client  = $request->client();
	my $p1      = $request->getRequest(1);
	
	return unless defined $client;
	
	# check that user is still using Rhapsody Radio
	my $song = $client->playingSong();
	
	if ( !$song || $song->currentTrackHandler ne __PACKAGE__ ) {
		# User stopped playing Napster 

		main::DEBUGLOG && $log->debug( "Stopped Napster, unsubscribing from playlistCallback" );
		Slim::Control::Request::unsubscribe( \&_playlistCallback, $client );
		
		return;
	}
	
	if ( $song->pluginData('radioTrackURL') && $p1 eq 'newsong' ) {
		# A new song has started playing.  We use this to change titles
		
		my $title = $song->pluginData('radioTitle');
		
		main::DEBUGLOG && $log->debug("Setting title for radio station to $title");
		
		Slim::Music::Info::setCurrentTitle( $song->track()->url, $title );
	}
}

sub canDirectStreamSong {
	my ( $class, $client, $song ) = @_;
	
	# We need to check with the base class (HTTP) to see if we
	# are synced or if the user has set mp3StreamingMethod
	return $class->SUPER::canDirectStream( $client, $song->streamUrl(), $class->getFormatForURL() );
}

# URL used for CLI trackinfo queries
sub trackInfoURL {
	my ( $class, $client, $url ) = @_;
	
	my $stationId;
	
	if ( $url =~ m{napster://(.+)\.nsr} ) {
		my $song = $client->currentSongForUrl($url);
		
		# Radio mode, pull track ID from lastURL
		$url = $song->pluginData('radioTrackURL');
		$stationId = $1;
	}

	my ($trackId) = $url =~ m{napster://(.+)\.wma};
	
	# SN URL to fetch track info menu
	my $trackInfoURL = Slim::Networking::SqueezeNetwork->url(
		'/api/napster/v1/opml/trackInfo?track=' . $trackId
	);
	
	if ( $stationId ) {
		#$trackInfoURL .= '&stationId=' . $stationId;
	}
	
	return $trackInfoURL;
}

# Track Info menu
sub trackInfo {
	my ( $class, $client, $track ) = @_;
	
	my $url          = $track->url;
	my $trackInfoURL = $class->trackInfoURL( $client, $url );
	
	# let XMLBrowser handle all our display
	my %params = (
		header   => 'PLUGIN_NAPSTER_GETTING_STREAM_INFO',
		modeName => 'Napster Now Playing',
		title    => Slim::Music::Info::getCurrentTitle( $client, $url ),
		url      => $trackInfoURL,
	);
	
	main::DEBUGLOG && $log->debug( "Getting track information for $url" );

	Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );
	
	$client->modeParam( 'handledTransition', 1 );
}

sub getIcon {
	my ( $class, $url ) = @_;

	return Slim::Plugin::Napster::Plugin->_pluginDataFor('icon');
}

sub getSeekData {
	my ( $class, $client, $song, $newtime ) = @_;
	
	# Determine byte offset and song length in bytes
	my $meta = $class->getMetadataFor( $client, $song->track()->url );
	
	my $duration = $meta->{duration} || return;
	
	# Don't seek past the end
	if ( $newtime >= $duration ) {
		$log->error('Attempt to seek past end of Napster track, ignoring');
		return;
	}
	
	my $bitrate = 128;
	
	return {
		sourceStreamOffset => ( ( $bitrate * 1000 ) / 8 ) * $newtime,
		timeOffset         => $newtime,
	};
}

# SN only, re-init upon reconnection
sub reinit {
	my ( $class, $client, $song ) = @_;
	
	my $url = $song->track->url();
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Re-init Napster - $url");
	
	my $cache     = Slim::Utils::Cache->new;
	my ($trackId) = $url =~ m{napster://(.+)\.wma};
	my $meta      = $cache->get( 'napster_meta_' . $trackId );
	
	if ( $meta ) {
		# We have previous data about the currently-playing song
		
		# Back to Now Playing
		Slim::Buttons::Common::pushMode( $client, 'playlist' );
	
		# Reset song duration/progress bar
		if ( $meta->{duration} ) {
			$song->duration( $meta->{duration} );
			
			# On a timer because $client->currentsongqueue does not exist yet
			Slim::Utils::Timers::setTimer(
				$client,
				Time::HiRes::time(),
				sub {
					my $client = shift;
				
					$client->streamingProgressBar( {
						url      => $url,
						duration => $meta->{duration},
					} );
				},
			);
		}
	}
	
	return 1;
}

1;
