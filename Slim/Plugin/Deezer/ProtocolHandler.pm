package Slim::Plugin::Deezer::ProtocolHandler;

# $Id$

use strict;
use base qw(Slim::Player::Protocols::HTTP);

use JSON::XS::VersionOneAndTwo;
use URI::Escape qw(uri_escape_utf8);

use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $prefs = preferences('server');
my $log   = logger('plugin.deezer');

sub isRemote { 1 }

sub getFormatForURL { 'mp3' }

# default buffer 3 seconds of 128k audio
sub bufferThreshold { 16 * ( $prefs->get('bufferSecs') || 3 ) }

sub canSeek { 0 }

sub canSeekError { return ( 'SEEK_ERROR_TYPE_NOT_SUPPORTED', 'Deezer' ); }

# To support remote streaming (synced players), we need to subclass Protocols::HTTP
sub new {
	my $class  = shift;
	my $args   = shift;

	my $client = $args->{client};
	
	my $song      = $args->{song};
	my $streamUrl = $song->{streamUrl} || return;
	
	$log->debug( 'Remote streaming Deezer track: ' . $streamUrl );

	my $sock = $class->SUPER::new( {
		url     => $streamUrl,
		song    => $args->{song},
		client  => $client,
		bitrate => 128_000,
	} ) || return;
	
	${*$sock}{contentType} = 'audio/mpeg';

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

	if ( $url =~ /\.dzr$/ ) {
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
	if ( $url =~ /\.dzr$/ ) {
		Slim::Music::Info::setDuration( $url, 0 );
	}

	foreach my $header (@headers) {

		$log->debug("Deezer header: $header");

		if ( $header =~ /^Content-Length:\s*(.*)/i ) {
			$length = $1;
			last;
		}
	}
	
	# Save length for reinit
	$client->pluginData( length => $length );
	
	my $bitrate = 128_000;

	$client->streamingSong->{bitrate} = $bitrate;

	# ($title, $bitrate, $metaint, $redir, $contentType, $length, $body)
	return (undef, $bitrate, 0, '', 'mp3', $length, undef);
}

# Don't allow looping
sub shouldLoop { 0 }

sub isRepeatingStream {
	my ( undef, $song ) = @_;
	
	return $song->{track}->url =~ /\.dzr$/;
}

# Check if player is allowed to skip, using canSkip value from SN
sub canSkip {
	my $client = shift;
	
	if ( my $info = $client->playingSong->pluginData('info') ) {
		return $info->{canSkip};
	}
	
	return 1;
}

# Disallow skips in radio mode.
# Disallow smart radio after the limit is reached
sub canDoAction {
	my ( $class, $client, $url, $action ) = @_;
	
	# Don't allow pause or rew on radio
	if ( $url =~ /\.dzr$/ ) {
		if ( $action eq 'pause' || $action eq 'rew' ) {
			return 0;
		}
	}
	
	if ( $action eq 'stop' && !canSkip($client) ) {
		# Is skip allowed?
		
		# Radio tracks do not allow skipping at all
		if ( $url =~ m{^deezer://\d+\.dzr$} ) {
			return 0;
		}
		
		# Smart Radio tracks have a skip limit
		$log->debug("Deezer: Skip limit exceeded, disallowing skip");
		
		my $line1 = $client->string('PLUGIN_DEEZER_ERROR');
		my $line2 = $client->string('PLUGIN_DEEZER_SKIPS_EXCEEDED');
		
		$client->showBriefly( {
			line1 => $line1,
			line2 => $line2,
			jive  => {
				type => 'popupplay',
				text => [ $line1, $line2 ],
			},
		},
		{
			block  => 1,
			scroll => 1,
		} );
				
		return 0;
	}
	
	return 1;
}

sub handleDirectError {
	my ( $class, $client, $url, $response, $status_line ) = @_;
	
	$log->debug("Direct stream failed: [$response] $status_line\n");
	
	$client->controller()->playerStreamingFailed($client, 'PLUGIN_DEEZER_STREAM_FAILED');
}

sub _handleClientError {
	my ( $error, $client, $params ) = @_;
	
	my $song = $params->{song};
	
	return if $song->pluginData('abandonSong');
	
	# Tell other clients to give up
	$song->pluginData( abandonSong => 1 );
	
	$params->{errorCb}->($error);
}

sub getNextTrack {
	my ( $class, $song, $successCb, $errorCb ) = @_;
	
	my $client = $song->master();
	my $url    = $song->{track}->url;
	
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
}

sub _getNextRadioTrack {
	my $params = shift;
		
	my ($stationId) = $params->{url} =~ m{deezer://(.+)\.dzr};
	
	# Talk to SN and get the next track to play
	my $radioURL = Slim::Networking::SqueezeNetwork->url(
		"/api/deezer/v1/radio/getNextTrack?stationId=$stationId"
	);
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&_gotNextRadioTrack,
		\&_gotNextRadioTrackError,
		{
			client => $params->{song}->master(),
			params => $params,
		},
	);
	
	$log->debug("Getting next radio track from SqueezeNetwork");
	
	$http->get( $radioURL );
}

sub _gotNextRadioTrack {
	my $http   = shift;
	my $client = $http->params->{client};
	my $params = $http->params->{params};
	my $song   = $params->{song};
	my $url    = $song->{track}->url;
	
	my $track = eval { from_json( $http->content ) };
	
	if ( $log->is_debug ) {
		$log->debug( 'Got next radio track: ' . Data::Dump::dump($track) );
	}
	
	if ( $track->{error} ) {
		# We didn't get the next track to play
		
		my $error = ( $client->isPlaying(1) && $client->playingSong()->{track}->url =~ /\.dzr/ )
					? 'PLUGIN_DEEZER_NO_NEXT_TRACK'
					: 'PLUGIN_DEEZER_NO_TRACK';
		
		$params->{errorCb}->( $error, $url );

		# Set the title after the errro callback so the current title
		# is still the radio-station name during the callback
		Slim::Music::Info::setCurrentTitle( $url, $client->string('PLUGIN_DEEZER_NO_TRACK') );
			
		return;
	}
	
	# set metadata for track, will be set on playlist newsong callback
	$url      = 'deezer://' . $track->{id} . '.mp3';
	my $title = $track->{title} . ' ' . 
		$client->string('BY') . ' ' . $track->{artist_name} . ' ' . 
		$client->string('FROM') . ' ' . $track->{album_name};
	
	$song->pluginData( radioTrackURL => $url );
	$song->pluginData( radioTitle    => $title );
	$song->pluginData( radioTrack    => $track );
	
	$params->{url} = $url;
	
	_gotTrack( $client, $track, $params );
}

sub _gotNextRadioTrackError {
	my $http   = shift;
	my $client = $http->params('client');
	
	_handleClientError( $http->error, $client, $http->params->{params} );
}

sub _getTrack {
	my $params = shift;
	
	my $song   = $params->{song};
	my $client = $song->master();
	
	return if $song->pluginData('abandonSong');
	
	# Get track URL for the next track
	my ($trackId) = $params->{url} =~ m{deezer://(.+)\.mp3};
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		sub {
			my $http = shift;
			my $info = eval { from_json( $http->content ) };
			if ( $@ || $info->{error} ) {
				if ( $log->is_debug ) {
					$log->debug( 'getTrack failed: ' . ( $@ || $info->{error} ) );
				}
				
				_gotTrackError( $@ || $info->{error}, $client, $params );
			}
			else {
				if ( $log->is_debug ) {
					$log->debug( 'getTrack ok: ' . Data::Dump::dump($info) );
				}
				
				_gotTrack( $client, $info, $params );
			}
		},
		sub {
			my $http  = shift;
			
			if ( $log->is_debug ) {
				$log->debug( 'getTrack failed: ' . $http->error );
			}
			
			_gotTrackError( $http->error, $client, $params );
		},
		{
			client => $client,
		},
	);
	
	$log->is_debug && $log->debug('Getting next track playback info from SN');
	
	$http->get(
		Slim::Networking::SqueezeNetwork->url(
			'/api/deezer/v1/playback/getMediaURL?trackId=' . uri_escape_utf8($trackId)
		)
	);
}

sub _gotTrack {
	my ( $client, $info, $params ) = @_;
	
    my $song = $params->{song};
    
    return if $song->pluginData('abandonSong');
	
	# Save the media URL for use in strm
	$song->{streamUrl} = $info->{url};

	# Save all the info
	$song->pluginData( info => $info );
	
	# Async resolve the hostname so gethostbyname in Player::Squeezebox::stream doesn't block
	# When done, callback will continue on to playback
	my $dns = Slim::Networking::Async->new;
	$dns->open( {
		Host        => URI->new( $info->{url} )->host,
		Timeout     => 3, # Default timeout of 10 is too long, 
		                  # by the time it fails player will underrun and stop
		onDNS       => $params->{successCb},
		onError     => $params->{successCb}, # even if it errors, keep going
		passthrough => [],
	} );
	
	# Watch for playlist commands
	Slim::Control::Request::subscribe( 
		\&_playlistCallback, 
		[['playlist'], ['newsong']],
		$song->master(),
	);
}

sub _gotTrackError {
	my ( $error, $client, $params ) = @_;
	
	$log->debug("Error during getTrackInfo: $error");

	return if $params->{song}->pluginData('abandonSong');

	_handleClientError( $error, $client, $params );
}

sub _playlistCallback {
	my $request = shift;
	my $client  = $request->client();
	my $p1      = $request->getRequest(1);
	
	return unless defined $client;
	
	# check that user is still using Deezer Radio
	my $song = $client->playingSong();
	
	if ( !$song || $song->currentTrackHandler ne __PACKAGE__ ) {
		# User stopped playing Deezer 

		$log->debug( "Stopped Deezer, unsubscribing from playlistCallback" );
		Slim::Control::Request::unsubscribe( \&_playlistCallback, $client );
		
		return;
	}
	
	if ( $song->pluginData('radioTrackURL') && $p1 eq 'newsong' ) {
		# A new song has started playing.  We use this to change titles
		
		my $title = $song->pluginData('radioTitle');
		
		$log->debug("Setting title for radio station to $title");
		
		Slim::Music::Info::setCurrentTitle( $song->{track}->url, $title );
	}
}

sub canDirectStreamSong {
	my ( $class, $client, $song ) = @_;
	
	# We need to check with the base class (HTTP) to see if we
	# are synced or if the user has set mp3StreamingMethod
	return $class->SUPER::canDirectStream( $client, $song->{streamUrl}, $class->getFormatForURL() );
}

# URL used for CLI trackinfo queries
sub trackInfoURL {
	my ( $class, $client, $url ) = @_;
	
	my $stationId;
	
	if ( $url =~ m{deezer://(.+)\.dzr} ) {
		my $song = $client->currentSongForUrl($url);
		
		# Radio mode, pull track ID from lastURL
		$url = $song->pluginData('radioTrackURL');
		$stationId = $1;
	}

	my ($trackId) = $url =~ m{deezer://(.+)\.mp3};
	
	# SN URL to fetch track info menu
	my $trackInfoURL = Slim::Networking::SqueezeNetwork->url(
		'/api/deezer/v1/opml/trackinfo?trackId=' . $trackId
	);
	
	if ( $stationId ) {
		$trackInfoURL .= '&stationId=' . $stationId;
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
		header   => 'PLUGIN_DEEZER_GETTING_TRACK_DETAILS',
		modeName => 'Deezer Now Playing',
		title    => Slim::Music::Info::getCurrentTitle( $client, $url ),
		url      => $trackInfoURL,
	);
	
	$log->debug( "Getting track information for $url" );

	Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );
	
	$client->modeParam( 'handledTransition', 1 );
}

sub getMetadataFor {
	my ( $class, $client, $url, $forceCurrent ) = @_;
	
	my $song = $forceCurrent ? $client->streamingSong() : $client->playingSong();
	return unless $song;
	
	my $icon = $class->getIcon();
	
	if ( my $track = $song->pluginData('info') ) {
		my $buttons = {};
		
		if ( !$track->{canSkip} ) {
			# XXX: not supported
			$buttons->{fwd} = 0;
		}
		
		if ( $url =~ /\.dzr/ ) {
			$buttons->{rew} = 0;
		}
		
		return {
			artist      => $track->{artist_name},
			album       => $track->{album_name},
			title       => $track->{title},
			cover       => $track->{cover},
			icon        => $icon,
			#duration    => $track->{secs},
			bitrate     => '128k CBR',
			type        => 'MP3 (Deezer)',
			info_link   => 'plugins/deezer/trackinfo.html',
			buttons     => $buttons,
		};
	}
	else {
		return {
			icon    => $icon,
			cover   => $icon,
			bitrate => '128k CBR',
			type    => 'MP3 (Deezer)',
		};
	}
}

sub getIcon {
	my ( $class, $url ) = @_;

	return Slim::Plugin::Deezer::Plugin->_pluginDataFor('icon');
}

# SN only, re-init upon reconnection
sub reinit {
	my ( $class, $client, $song ) = @_;
	
	# Reset song duration/progress bar
	my $currentURL = $song->{streamUrl};
	
	$log->debug("Re-init Deezer - $currentURL");
	
	if ( my $length = $client->pluginData('length') ) {			
		# On a timer because $client->currentsongqueue does not exist yet
		Slim::Utils::Timers::setTimer(
			$client,
			Time::HiRes::time(),
			sub {
				my $client = shift;
				
				$client->streamingProgressBar( {
					url     => $currentURL,
					length  => $length,
					bitrate => 128_000,
				} );
				
				# Back to Now Playing
				# This is within the timer because otherwise it will run before
				# addtracks adds all the tracks, and not jump to the correct playing item
				Slim::Buttons::Common::pushMode( $client, 'playlist' );
			},
		);
	}
	
	return 1;
}

1;