package Slim::Plugin::MOG::ProtocolHandler;

# $Id: ProtocolHandler.pm 31715 2011-08-16 13:14:29Z shameed $

use strict;
use base qw(Slim::Player::Protocols::HTTP);

use JSON::XS::VersionOneAndTwo;
use Scalar::Util qw(blessed);
use URI::Escape qw(uri_escape_utf8);

use Slim::Networking::SqueezeNetwork;
use Slim::Music::Info;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Timers;
use Slim::Utils::Prefs;


my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.mog',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_MOG_MODULE_NAME',
} );

my $prefs = preferences('server');
my $log   = logger('plugin.mog');

my $value = 0;

sub getFormatForURL { 'mp3' }

sub isRepeatingStream { 0 }

sub isRemote { 1 }

sub canSeek { return 1; }

sub canSeekError { return ( 'SEEK_ERROR_TYPE_NOT_SUPPORTED', 'MOG' ); }

# XXX: Port to new streaming

# To support remote streaming (synced players), we need to subclass Protocols::HTTP
sub new {
	my $class  = shift;
	my $args   = shift;

	my $client = $args->{client};
	
	my $song      = $args->{song};
	my $streamUrl = $song->streamUrl() || return;
	my $track     = $song->pluginData('info') || {};
	
	main::DEBUGLOG && $log->debug( 'Remote streaming MOG track: ' . $streamUrl );

	my $sock = $class->SUPER::new( {
		url     => $streamUrl,
		song    => $args->{song},
		client  => $client,
		bitrate => ($track->{bitrate} || 320) * 1000,
	} ) || return;
	
	${*$sock}{contentType} = 'audio/mpeg';

	return $sock;
}

# Avoid scanning
sub scanUrl {
	my ( $class, $url, $args ) = @_;
	
	$args->{cb}->( $args->{song}->currentTrack() );
}

sub audioScrobblerSource {
	my ( $class, $client, $url ) = @_;

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
	
	my $song  = $client->streamingSong();
	my $track = $song->pluginData('info');
	
	my $duration = $track->{duration};
	
	my $length;
	my $rangelength;

	foreach my $header (@headers) {
		if ( $header =~ /^Content-Length:\s*(.*)/i ) {
			$length = $1;
		}
		elsif ( $header =~ m{^Content-Range: .+/(.*)}i ) {
			$rangelength = $1;
			last;
		}
	}
	
	if ( $rangelength ) {
		$length = $rangelength;
	}
	
	my $bitrate = $track->{bitrate} * 1000;
	
	$song->bitrate($bitrate);
	$song->duration($duration);

	# ($title, $bitrate, $metaint, $redir, $contentType, $length, $body)
	return (undef, $bitrate, 0, '', 'mp3', $length, undef);
}

# Don't allow looping
sub shouldLoop { 0 }

sub getNextTrack {
	my ( $class, $song, $successCb, $errorCb ) = @_;
	
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
		_getTrack($params);

}

sub _getTrack {
	my $params  = shift;
	
	my $song    = $params->{song};
	my @players = $song->master()->syncGroupActiveMembers();
	
	# Fetch the track info
	_getTrackInfo( $song->master(), undef, $params );
}

sub _getTrackInfo {
	my ( $client, undef, $params ) = @_;
	my $song   = $params->{song};
	
	return if $song->pluginData('abandonSong');
	
	# Get track URL for the next track
	my ($trackId) = $params->{url} =~ m{mog://(.+)\.mp3};
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		sub {
			my $http = shift;
			my $info = eval { from_json( $http->content ) };
			if ( $@ || $info->{error} || !$info->{url} ) {
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
				
				_gotTrack( $client, $info, $params );
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
			'/api/mog/v1/playback/playStream?trackid=' . uri_escape_utf8($trackId)
		)
	);
}

sub _gotTrack {
	my ( $client, $info, $params ) = @_;
	
	my $song = $params->{song};

	return if $song->pluginData('abandonSong');
	
	# Save the media URL for use in strm
	$song->streamUrl($info->{url});
	
	# Cache the rest of the track's metadata
	my $meta = {
		artist    => $info->{artist},
		album     => $info->{album},
		title     => $info->{title},
		cover     => $info->{cover},
		duration  => $info->{duration},
		genre     => $info->{genre},
		year      => $info->{year},
		bitrate   => ($info->{bitrate} || 320). 'k CBR',
		type      => 'MP3 (MOG)',
		info_link => 'plugins/mog/trackinfo.html',
	};
	
	$song->pluginData( info => $info );
	$song->duration( $info->{duration} );

	my $cache = Slim::Utils::Cache->new;

	$cache->set( 'mog_meta_' . $info->{id}, $meta, 86400 );

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

# Metadata for a URL, used by CLI/JSON clients
sub getMetadataFor {
	my ( $class, $client, $url ) = @_;
	
	my $icon = $class->getIcon();
	
	return {} unless $url;
	
	my $cache = Slim::Utils::Cache->new;
	
	# If metadata is not here, fetch it so the next poll will include the data
	my ($trackId) = $url =~ m{mog://(.+)\.mp3};
	my $meta      = $cache->get( 'mog_meta_' . $trackId );
	
	if ( !$meta && !$client->master->pluginData('fetchingMeta') ) {
		# Go fetch metadata for all tracks on the playlist without metadata
		my @need;
		
		for my $track ( @{ Slim::Player::Playlist::playList($client) } ) {
			my $trackURL = blessed($track) ? $track->url : $track;
			if ( $trackURL =~ m{mog://(.+)\.mp3} ) {
				my $id = $1;
				if ( !$cache->get("mog_meta_$id") ) {
					push @need, $id;
				}
			}
		}
		
		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug( "Need to fetch metadata for: " . join( ', ', @need ) );
		}
		
		$client->master->pluginData( fetchingMeta => 1 );
		
		my $metaUrl = Slim::Networking::SqueezeNetwork->url(
			"/api/mog/v1/playback/getBulkMetadata"
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
			'trackids=' . join( ',', @need ),
		);
	}
	
	#$log->debug( "Returning metadata for: $url" . ($meta ? '' : ': default') );
	
	return $meta || {
		bitrate   => '320k CBR',
		type      => 'MP3 (MOG)',
		icon      => $icon,
		cover     => $icon,
	};
}

sub _gotBulkMetadata {
	my $http   = shift;

	my $client = $http->params->{client};
	
	$client->master->pluginData( fetchingMeta => 0 );
	
	my $info = eval { from_json( $http->content ) };
	
	if ( $@ || ref $info ne 'ARRAY' || !scalar @$info ) {
		$log->error( "Error fetching track metadata: " . ( $@ || 'Invalid JSON response' ) );
		return;
	}
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( "Caching metadata for " . scalar( @{$info} ) . " tracks" );
	}
	
	# Cache metadata
	my $cache = Slim::Utils::Cache->new;
	my $icon  = Slim::Plugin::MOG::Plugin->_pluginDataFor('icon');

	for my $track ( @{$info} ) {
		next unless ref $track eq 'HASH';
		
		# cache the metadata we need for display
		my $trackId = delete $track->{id};
		
		my $meta = {
			artist    => $track->{artist},
			album     => $track->{album},
			title     => $track->{title},
			cover     => $track->{cover} || $icon,
			duration  => $track->{duration},
			genre     => $track->{genre},
			year      => $track->{year},
			bitrate   => '320k CBR', # XXX bulk API call does not know the actual bitrate, it will be replaced in _gotTrack
			type      => 'MP3 (MOG)',
			info_link => 'plugins/mog/trackinfo.html',
			icon      => $icon,
		};
	
		$cache->set( 'mog_meta_' . $trackId, $meta, 86400 );
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

sub _gotTrackError {
	my ( $error, $client, $params ) = @_;
	
	main::DEBUGLOG && $log->debug("Error during getTrackInfo: $error");

	return if $params->{song}->pluginData('abandonSong');

	_handleClientError( $error, $client, $params );
}

sub _handleClientError {
	my ( $error, $client, $params ) = @_;
	
	my $song    = $params->{song};
	
	return if $song->pluginData('abandonSong');
	
	# Tell other clients to give up
	$song->pluginData( abandonSong => 1 );
	
	$params->{errorCb}->($error);
}

sub canDirectStreamSong {
	my ( $class, $client, $song ) = @_;

	# We need to check with the base class (HTTP) to see if we
	# are synced or if the user has set mp3StreamingMethod
	return $class->SUPER::canDirectStream( $client, $song->streamUrl(), $class->getFormatForURL() );
}

sub _playlistCallback {
	my $request = shift;

	my $client  = $request->client();
	my $p1      = $request->getRequest(1);
	
	return unless defined $client;
	
	# check that user is still using MOG Radio
	my $song = $client->playingSong();
	
	if ( !$song || $song->currentTrackHandler ne __PACKAGE__ ) {
		# User stopped playing MOG 

		main::DEBUGLOG && $log->debug( "Stopped MOG, unsubscribing from playlistCallback" );
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

sub trackInfoURL {
	my ( $class, $client, $url ) = @_;
	
	my ($trackId) = $url =~ m{mog://(.+)\.mp3};
	
	# SN URL to fetch track info menu
	my $trackInfoURL = Slim::Networking::SqueezeNetwork->url(
		'/api/mog/v1/opml/trackinfo?trackid=' . $trackId
	);
	
	return $trackInfoURL;
}

# Track Info menu
sub trackInfo {
	my ( $class, $client, $track ) = @_;
	
	my $url          = $track->url;
	my $trackInfoURL = $class->trackInfoURL( $client, $url );
	
	# let XMLBrowser handle all our display
	my %params = (
		header   => 'PLUGIN_MOG_GETTING_STREAM_INFO',
		modeName => 'MOG Now Playing',
		title    => Slim::Music::Info::getCurrentTitle( $client, $url ),
		url      => $trackInfoURL,
	);
	
	main::DEBUGLOG && $log->debug( "Getting track information for $url" );

	Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );
	
	$client->modeParam( 'handledTransition', 1 );
}

sub getIcon {
	my ( $class, $url ) = @_;

	return Slim::Plugin::MOG::Plugin->_pluginDataFor('icon');
}

# SN only, re-init upon reconnection
sub reinit {
	my ( $class, $client, $song ) = @_;
	
	my $url = $song->track->url();
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Re-init MOG - $url");
	
	my $cache     = Slim::Utils::Cache->new;
	my ($trackId) = $url =~ m{mog://(.+)\.mp3};
	my $meta      = $cache->get( 'mog_meta_' . $trackId );
	
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

