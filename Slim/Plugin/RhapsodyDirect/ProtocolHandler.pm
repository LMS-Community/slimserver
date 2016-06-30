package Slim::Plugin::RhapsodyDirect::ProtocolHandler;

# Rhapsody Direct / Napster handler for rhapd:// URLs.

use strict;
use base qw(Slim::Player::Protocols::HTTP);

use HTML::Entities qw(encode_entities);
use JSON::XS::VersionOneAndTwo;
use MIME::Base64 qw(decode_base64);
use Scalar::Util qw(blessed);
use URI::Escape qw(uri_escape_utf8);

use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Cache;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.rhapsodydirect',
	'defaultLevel' => $ENV{RHAPSODY_DEV} ? 'DEBUG' : 'ERROR',
	'description'  => 'PLUGIN_RHAPSODY_DIRECT_MODULE_NAME',
});

my $prefs = preferences('server');

sub isRemote { 1 }

sub getFormatForURL { 'mp4' }

sub formatOverride { 'aac' }

# default buffer 3 seconds of 192k audio
sub bufferThreshold { 24 * ( $prefs->get('bufferSecs') || 3 ) }

sub canSeek {}

sub canSeekError { return ( 'SEEK_ERROR_TYPE_NOT_SUPPORTED', 'Napster Radio' ); }

# To support remote streaming (synced players), we need to subclass Protocols::HTTP
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
		bitrate => $streamUrl =~ /\.mp3$/ ? 128_000 : 320_000,
	} ) || return;
	
	${*$sock}{contentType} = 'audio/mp4';

	return $sock;
}

# Avoid scanning
sub scanUrl {
	my ($class, $url, $args) = @_;
	$args->{cb}->($args->{song}->currentTrack());
}

# Source for AudioScrobbler
sub audioScrobblerSource {
	my ( $class, $client, $url ) = @_;

	if ( $url =~ /\.rdr$/ ) {
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
	my $rangelength;
	
	# Clear previous duration, since we're using the same URL for all tracks
	if ( $url =~ /\.rdr$/ ) {
		Slim::Music::Info::setDuration( $url, 0 );
	}

	foreach my $header (@headers) {

		main::DEBUGLOG && $log->debug("Napster header: $header");

		if ( $header =~ /^Content-Length:\s*(.*)/i ) {
			$length = $1;
		}
		elsif ( $header =~ m{^Content-Range: .+/(.*)}i ) {
			$rangelength = $1;
		}
	}
	
	if ( $rangelength ) {
		$length = $rangelength;
	}
	
	# Save length for reinit and seeking
	$client->master->pluginData( length => $length );
	
	my $bitrate = $client->streamingSong()->streamUrl() =~ /\.mp3$/ ? 128_000 : 320_000;

	$client->streamingSong->bitrate($bitrate);

	# ($title, $bitrate, $metaint, $redir, $contentType, $length, $body)
	return (undef, $bitrate, 0, '', 'aac', $length, undef);
}

# Don't allow looping
sub shouldLoop { 0 }

sub isRepeatingStream {
	my (undef, $song) = @_;
	
	return $song->track()->url =~ /\.rdr$/;
}

sub canDoAction {
	my ( $class, $client, $url, $action ) = @_;
	
	# Don't allow pause or rew on radio
	if ( $url =~ /\.rdr$/ ) {
		if ( $action eq 'pause' || $action eq 'rew' ) {
			return 0;
		}
	}
	
	return 1;
}

sub handleDirectError {
	my ( $class, $client, $url, $response, $status_line ) = @_;
	
	main::DEBUGLOG && $log->debug("Direct stream failed: [$response] $status_line\n");
	
	$client->controller()->playerStreamingFailed($client, 'PLUGIN_RHAPSODY_DIRECT_STREAM_FAILED');
}

sub _handleClientError {
	my ($error, $client, $params) = @_;
	
	my $song    = $params->{'song'};
	
	return if $song->pluginData('abandonSong');
	
	# Tell other clients to give up
	$song->pluginData(abandonSong => 1);
	
	$params->{'errorCb'}->($error);
}

sub getNextTrack {
	my ($class, $song, $successCb, $errorCb) = @_;
	
	my $client = $song->master();
	my $url    = $song->track()->url;
	
	$song->pluginData( radioTrackURL => undef );
	$song->pluginData( radioTitle    => undef );
	$song->pluginData( radioTrack    => undef );
	$song->pluginData( abandonSong   => 0 );
	
	# XXX - need to verify this
	foreach ($client->syncGroupActiveMembers()) {
		if (!$_->canDecodeRhapsody()) {
			$errorCb->('PLUGIN_RHAPSODY_DIRECT_PLAYER_REQUIRED',
				sprintf('%s (%s)', $_->name(), $_->model()));
			return;
		}
	}
	
	my $params = {
		song      => $song,
		url       => $url,
		successCb => $successCb,
		errorCb   => $errorCb,
	};
	
	# 0. If playing Rhapsody, log track-played (handled via onDecode callback)
	
	# 1. If this is a radio-station then get next track info
	if ($class->isRepeatingStream($song)) {
		_getNextRadioTrack($params);
	} else {
		_getTrack($params);
	}
	
	# 2. For each player in sync-group:
	# 2.1 Get mediaURL

}

# 1. If this is a radio-station then get next track info
sub _getNextRadioTrack {
	my ($params) = @_;
		
	my ($stationId) = $params->{'url'} =~ m{rhapd://(.+)\.rdr};
	
	# Talk to SN and get the next track to play
	my $radioURL = Slim::Networking::SqueezeNetwork->url(
		"/api/rhapsody/v1/radio/getNextTrack?stationId=$stationId"
	);
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&_gotNextRadioTrack,
		\&_gotNextRadioTrackError,
		{
			client => $params->{'song'}->master(),
			params => $params,
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
	my $song   = $params->{'song'};
	my $url    = $song->track()->url;
	
	my $track = eval { from_json( $http->content ) };
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( 'Got next radio track: ' . Data::Dump::dump($track) );
	}
	
	if ( $track->{error} ) {
		# We didn't get the next track to play
		
		my $error = ( $client->isPlaying(1) && $client->playingSong()->track()->url =~ /\.rdr/ )
					? 'PLUGIN_RHAPSODY_DIRECT_NO_NEXT_TRACK'
					: 'PLUGIN_RHAPSODY_DIRECT_NO_TRACK';
		
		$params->{'errorCb'}->($error, $url);

		# Set the title after the errro callback so the current title
		# is still the radio-station name during the callback
		Slim::Music::Info::setCurrentTitle( $url, $client->string('PLUGIN_RHAPSODY_DIRECT_NO_TRACK') );
			
		return;
	}
	
	# set metadata for track, will be set on playlist newsong callback
	$url      = 'rhapd://' . $track->{trackId} . '.m4a';
	my $title = $track->{name} . ' ' . 
			$client->string('BY') . ' ' . $track->{displayArtistName} . ' ' . 
			$client->string('FROM') . ' ' . $track->{displayAlbumName};
	
	$song->pluginData( radioTrackURL => $url );
	$song->pluginData( radioTitle    => $title );
	$song->pluginData( radioTrack    => $track );
	
	# We already have the metadata for this track, so can save calling getTrack
	my $meta = {
		artist    => $track->{displayArtistName},
		album     => $track->{displayAlbumName},
		title     => $track->{name},
		cover     => $track->{cover},
		duration  => $track->{playbackSeconds},
		bitrate   => '320k CBR',
		type      => 'M4A (Napster)',
		info_link => 'plugins/rhapsodydirect/trackinfo.html',
		icon      => Slim::Plugin::RhapsodyDirect::Plugin->_pluginDataFor('icon'),
		buttons   => {
			# disable REW/Previous button in radio mode
			rew => 0,
		},
	};
	
	my $cache = Slim::Utils::Cache->new;
	$cache->set( 'rhapsody_meta_' . $track->{trackId}, $meta, 86400 );
	
	$params->{'url'} = $url;
	_getTrack($params);
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

	my $song = $params->{'song'};
	
	return if $song->pluginData('abandonSong');

	# Get track URL for the next track
	my ($trackId) = $params->{'url'} =~ m{rhapd://(.+)\.m4a};
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		sub {
			my $http = shift;
			my $info = eval { from_json( $http->content ) };
			if ( $@ || $info->{error} ) {
				if ( main::DEBUGLOG && $log->is_debug ) {
					$log->debug( 'getTrackInfo failed: ' . ( $@ || $info->{error} ) );
				}
				
				_gotTrackError( $@ || $info->{error}, $client, $params );
			}
			else {
				if ( main::DEBUGLOG && $log->is_debug ) {
					$log->debug( 'getTrackInfo ok: ' . Data::Dump::dump($info) );
				}
				
				$song->pluginData( playbackSessionId => $info->{account}->{playbackSessionId} );
				
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
			'/api/rhapsody/v1/playback/getMediaURL?trackId=' . uri_escape_utf8($trackId)
		)
	);
}

# 2.1a Get mediaURL 
sub _gotTrackInfo {
	my ( $client, $info, $params ) = @_;
	
    my $song = $params->{'song'};
    
    return if $song->pluginData('abandonSong');
    
	# Save the media URL for use in strm
	$song->streamUrl($info->{mediaUrl});

	# Save all the info so we can use it for sending the playback session info
	$song->pluginData( info => $info );
	
	# Async resolve the hostname so gethostbyname in Player::Squeezebox::stream doesn't block
	# When done, callback will continue on to playback
	my $dns = Slim::Networking::Async->new;
	$dns->open( {
		Host        => URI->new( $info->{mediaUrl} )->host,
		Timeout     => 3, # Default timeout of 10 is too long, 
		                  # by the time it fails player will underrun and stop
		onDNS       => $params->{'successCb'},
		onError     => $params->{'successCb'}, # even if it errors, keep going
		passthrough => [],
	} );
	
	# Watch for playlist commands
	Slim::Control::Request::subscribe( 
		\&_playlistCallback, 
		[['playlist'], ['newsong']],
		$song->master(),
	);
}

# 2.1b Get mediaURL 
sub _gotTrackError {
	my ( $error, $client, $params ) = @_;
	
	main::DEBUGLOG && $log->debug("Error during getTrackInfo: $error");

	return if $params->{'song'}->pluginData('abandonSong');

	_handleClientError( $error, $client, $params );
}
	
# Metadata for a URL, used by CLI/JSON clients
sub getMetadataFor {
	my ( $class, $client, $url ) = @_;
	
	my $icon = $class->getIcon();
	
	if ( $url =~ /\.rdr$/ ) {
		my $song = $client->currentSongForUrl($url);
		if (!$song || !($url = $song->pluginData('radioTrackURL'))) {
			return {
				bitrate   => '320k CBR',
				type      => 'M4A (Napster)',
				icon      => $icon,
				cover     => $icon,
			};
		}
	}
	
	return {} unless $url;
	
	my $cache = Slim::Utils::Cache->new;
	
	# If metadata is not here, fetch it so the next poll will include the data
	my ($trackId) = $url =~ m{rhapd://(.+)\.m4a};
	my $meta      = $cache->get( 'rhapsody_meta_' . $trackId );
	
	if ( $trackId && !$meta && !$client->master->pluginData('fetchingMeta') ) {

		$client->master->pluginData( fetchingMeta => 1 );
		
		# Go fetch metadata for all tracks on the playlist without metadata
		my @need = ($trackId);
		
		for my $track ( @{ Slim::Player::Playlist::playList($client) } ) {
			my $trackURL = blessed($track) ? $track->url : $track;
			if ( $trackURL =~ m{rhapd://(.+)\.m4a} ) {
				my $id = $1;
				if ( !$cache->get("rhapsody_meta_$id") ) {
					push @need, $id;
				}
			}
		}
		
		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug( "Need to fetch metadata for: " . join( ', ', @need ) );
		}
		
		my $metaUrl = Slim::Networking::SqueezeNetwork->url(
			"/api/rhapsody/v1/playback/getBulkMetadata"
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
		) if scalar @need;
	}
	
	#$log->debug( "Returning metadata for: $url" . ($meta ? '' : ': default') );
	
	return $meta || {
		bitrate   => '320k CBR',
		type      => 'M4A (Napster)',
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
	my $icon  = Slim::Plugin::RhapsodyDirect::Plugin->_pluginDataFor('icon');

	for my $track ( @{$info} ) {
		next unless ref $track eq 'HASH';
		
		# cache the metadata we need for display
		my $trackId = delete $track->{trackId};
		
		my $meta = {
			%{$track},
			bitrate   => '320k CBR',
			type      => 'M4A (Napster)',
			info_link => 'plugins/rhapsodydirect/trackinfo.html',
			icon      => $icon,
		};
	
		$cache->set( 'rhapsody_meta_' . $trackId, $meta, 86400 );
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
		# User stopped playing Rhapsody, 

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
	return $class->SUPER::canDirectStream($client, $song->streamUrl(), $class->getFormatForURL());
}

# URL used for CLI trackinfo queries
sub trackInfoURL {
	my ( $class, $client, $url ) = @_;
	
	my $stationId;
	
	if ( $url =~ m{rhapd://(.+)\.rdr} ) {
		my $song = $client->currentSongForUrl($url);
		
		# Radio mode, pull track ID from lastURL
		$url = $song->pluginData('radioTrackURL');
		$stationId = $1;
	}

	my ($trackId) = $url =~ m{rhapd://(.+)\.m4a};
	
	# SN URL to fetch track info menu
	my $trackInfoURL = Slim::Networking::SqueezeNetwork->url(
		'/api/rhapsody/v1/opml/metadata/getTrack?trackId=' . $trackId
	);
	
	if ( $stationId ) {
		$trackInfoURL .= '&stationId=' . $stationId;
	}
	
	return $trackInfoURL;
}

sub getIcon {
	my ( $class, $url ) = @_;

	return Slim::Plugin::RhapsodyDirect::Plugin->_pluginDataFor('icon');
}

# XXX: this is called more than just when we stop
sub onStop {
	my ($class, $song) = @_;
	
	main::DEBUGLOG && $log->is_debug && $log->debug("onStop, logging playback");
	
	_doLog(Slim::Player::Source::songTime($song->master()), $song);
}

sub onPlayout {
	my ($class, $song) = @_;
	
	main::DEBUGLOG && $log->is_debug && $log->debug("onPlayout, logging playback");
	
	_doLog($song->duration(), $song);
}

sub _doLog {
	my ($time, $song) = @_;
	
	$time = int($time);
	
	# There are different log methods for normal vs. radio play
	my $stationId;
	my $trackId;

	if ( ($stationId) = $song->track()->url =~ m{rhapd://(.+)\.rdr} ) {
		# logMeteringInfoForStationTrackPlay
		$song = $song->master()->currentSongForUrl( $song->track()->url );
		
		my $url = $song->pluginData('radioTrackURL');
		
		($trackId) = $url =~ m{rhapd://(.+)\.m4a};		
	}
	else {
		# logMeteringInfo
		$stationId = '';
		($trackId) = $song->track()->url =~ m{rhapd://(.+)\.m4a};
	}
	
	my $logURL = Slim::Networking::SqueezeNetwork->url(
		"/api/rhapsody/v1/playback/log?stationId=$stationId&trackId=$trackId&playtime=$time"
	);
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		sub {
			if ( main::DEBUGLOG && $log->is_debug ) {
				my $http = shift;
				$log->debug( "Logging returned: " . $http->content );
			}
		},
		sub {
			if ( main::DEBUGLOG && $log->is_debug ) {
				my $http = shift;
				$log->debug( "Logging returned error: " . $http->error );
			}
		},
		{
			client => $song->master(),
		},
	);
	
	main::DEBUGLOG && $log->debug("Logging track playback: $time seconds, trackId: $trackId, stationId: $stationId");
	
	$http->get( $logURL );
}


1;
