package Slim::Plugin::WiMP::ProtocolHandler;

# $Id: ProtocolHandler.pm 30836 2010-05-28 20:13:33Z agrundman $

use strict;
use base qw(Slim::Player::Protocols::HTTP);

use JSON::XS::VersionOneAndTwo;
use URI::Escape qw(uri_escape_utf8);
use Scalar::Util qw(blessed);

use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

my $prefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory( {
	'category'     => 'plugin.tidal',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_WIMP_MODULE_NAME',
} );

sub isRemote { 1 }

sub getFormatForURL {
	my ($class, $url) = @_;
	
	my ($trackId, $format) = _getStreamParams( $url );
	return $format;
}

# default buffer 3 seconds of 256kbps MP3/768kbps FLAC audio
sub bufferThreshold {
	my ($class, $client, $url) = @_;

	$url = $client->playingSong()->track()->url() unless $url =~ /\.(?:fla?c|mp3)$/;
	
	my ($trackId, $format) = _getStreamParams( $url );
	return ($format eq 'flac' ? 80 : 32) * ($prefs->get('bufferSecs') || 3); 
}

sub canSeek { 1 }

# To support remote streaming (synced players), we need to subclass Protocols::HTTP
sub new {
	my $class  = shift;
	my $args   = shift;

	my $client = $args->{client};
	
	my $song      = $args->{song};
	my $streamUrl = $song->streamUrl() || return;
	my ($trackId, $format) = _getStreamParams( $args->{url} || '' );
	
	main::DEBUGLOG && $log->debug( 'Remote streaming TIDAL track: ' . $streamUrl );

	my $sock = $class->SUPER::new( {
		url     => $streamUrl,
		song    => $args->{song},
		client  => $client,
		bitrate => $format eq 'flac' ? 800_000 : 256_000,
	} ) || return;
	
	${*$sock}{contentType} = $format eq 'flac' ? 'audio/flac' : 'audio/mpeg';

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

	# P = Chosen by the user
	return 'P';
}

# Don't allow looping
sub shouldLoop { 0 }

# Check if player is allowed to skip, using canSkip value from SN
sub canSkip { 1 }

sub handleDirectError {
	my ( $class, $client, $url, $response, $status_line ) = @_;
	
	main::DEBUGLOG && $log->debug("Direct stream failed: [$response] $status_line\n");
	
	$client->controller()->playerStreamingFailed($client, 'PLUGIN_WIMP_STREAM_FAILED');
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
	
	my $url = $song->track()->url;
	
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
	my $params = shift;
	
	my $song   = $params->{song};
	my $client = $song->master();
	
	return if $song->pluginData('abandonSong');
	
	# Get track URL for the next track
	my ($trackId, $format) = _getStreamParams( $params->{url} );
	
	if (!$trackId) {
		_gotTrackError( $client->string('PLUGIN_WIMP_INVALID_TRACK_ID'), $client, $params );
		return;
	}
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		sub {
			my $http = shift;
			my $info = eval { from_json( $http->content ) };
			if ( $@ || $info->{error} ) {
				if ( main::DEBUGLOG && $log->is_debug ) {
					$log->debug( 'getTrack failed: ' . ( $@ || $info->{error} ) );
				}
				
				_gotTrackError( $@ || $info->{error}, $client, $params );
			}
			else {
				#if ( main::DEBUGLOG && $log->is_debug ) {
				#	$log->debug( 'getTrack ok: ' . Data::Dump::dump($info) );
				#}
				
				_gotTrack( $client, $info, $params );
			}
		},
		sub {
			my $http  = shift;
			
			if ( main::DEBUGLOG && $log->is_debug ) {
				$log->debug( 'getTrack failed: ' . $http->error );
			}
			
			_gotTrackError( $http->error, $client, $params );
		},
		{
			client => $client,
		},
	);
	
	main::DEBUGLOG && $log->is_debug && $log->debug('Getting next track playback info from SN for ' . $params->{url});
	
	$http->get(
		Slim::Networking::SqueezeNetwork->url(
			'/api/wimp/v1/playback/getMediaURL?trackId=' . $trackId
		)
	);
}

sub _gotTrack {
	my ( $client, $info, $params ) = @_;
	
    my $song = $params->{song};
    
    return if $song->pluginData('abandonSong');
	
	# Save the media URL for use in strm
	$song->streamUrl($info->{url});

	# Save all the info
	$song->pluginData( info => $info );
	
	# Cache the rest of the track's metadata
	my $icon = Slim::Plugin::WiMP::Plugin->_pluginDataFor('icon');
	my $meta = {
		artist    => $info->{artist},
		album     => $info->{album},
		title     => $info->{title},
		cover     => $info->{cover} || $icon,
		duration  => $info->{duration},
		bitrate   => $params->{url} =~ /\.flac/ ? 'PCM VBR' : ($info->{bitrate} . 'k CBR'),
		type      => $params->{url} =~ /\.flac/ ? 'FLAC' : 'MP3',
		info_link => 'plugins/wimp/trackinfo.html',
		icon      => $icon,
	};
	
	$song->duration( $info->{duration} );
	
	my $cache = Slim::Utils::Cache->new;
	$cache->set( 'wimp_meta_' . $info->{id}, $meta, 86400 );

	$params->{successCb}->();
	
	# trigger playback statistics update
	if ( $info->{duration} > 2) {
		# we're asked to report back if a track has been played halfway through
		my $params = {
			duration => $info->{duration} / 2,
			url      => $params->{url},
		};
	}
}

sub _gotTrackError {
	my ( $error, $client, $params ) = @_;
	
	main::DEBUGLOG && $log->debug("Error during getTrackInfo: $error");

	return if $params->{song}->pluginData('abandonSong');

	_handleClientError( $error, $client, $params );
}

sub canDirectStreamSong {
	my ( $class, $client, $song ) = @_;
	
	# We need to check with the base class (HTTP) to see if we
	# are synced or if the user has set mp3StreamingMethod
	return $class->SUPER::canDirectStream( $client, $song->streamUrl(), $class->getFormatForURL($song->track->url()) );
}

# parseHeaders is used for proxied streaming
sub parseHeaders {
	my ( $self, @headers ) = @_;
	
	__PACKAGE__->parseDirectHeaders( $self->client, $self->url, @headers );
	
	return $self->SUPER::parseHeaders( @headers );
}

sub parseDirectHeaders {
	my ( $class, $client, $url, @headers ) = @_;

	# XXX - parse bitrate
	#main::DEBUGLOG && $log->is_debug && $log->debug(Data::Dump::dump(@headers));
	
	my $isFlac  = grep m{Content.*audio/(?:x-|)flac}i, @headers;
	my $bitrate = $isFlac ? 800_000 : 256_000;

	$client->streamingSong->bitrate($bitrate);

	# ($title, $bitrate, $metaint, $redir, $contentType, $length, $body)
	return (undef, $bitrate, 0, '', $isFlac ? 'flc' : 'mp3');
}

# URL used for CLI trackinfo queries
sub trackInfoURL {
	my ( $class, $client, $url ) = @_;

	my ($trackId) = _getStreamParams( $url );
	
	# SN URL to fetch track info menu
	my $trackInfoURL = Slim::Networking::SqueezeNetwork->url(
		'/api/wimp/v1/opml/trackinfo?trackId=' . $trackId
	);
	
	return $trackInfoURL;
}

# Track Info menu
=pod XXX - legacy track info menu from before Slim::Menu::TrackInfo times?
sub trackInfo {
	my ( $class, $client, $track ) = @_;
	
	my $url          = $track->url;
	my $trackInfoURL = $class->trackInfoURL( $client, $url );
	
	# let XMLBrowser handle all our display
	my %params = (
		header   => 'PLUGIN_WIMP_GETTING_TRACK_DETAILS',
		modeName => 'WiMP Now Playing',
		title    => Slim::Music::Info::getCurrentTitle( $client, $url ),
		url      => $trackInfoURL,
	);
	
	main::DEBUGLOG && $log->debug( "Getting track information for $url" );

	Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );
	
	$client->modeParam( 'handledTransition', 1 );
}
=cut

# Metadata for a URL, used by CLI/JSON clients
sub getMetadataFor {
	my ( $class, $client, $url ) = @_;
	
	my $icon = $class->getIcon();
	
	return {} unless $url;
	
	my $cache = Slim::Utils::Cache->new;
	
	# If metadata is not here, fetch it so the next poll will include the data
	my ($trackId, $format) = _getStreamParams( $url );
	my $meta = $cache->get( 'wimp_meta_' . ($trackId || '') );
	
	if ( !$meta && !$client->master->pluginData('fetchingMeta') ) {

		$client->master->pluginData( fetchingMeta => 1 );

		# Go fetch metadata for all tracks on the playlist without metadata
		my %need = (
			$trackId => 1
		);
		
		for my $track ( @{ Slim::Player::Playlist::playList($client) } ) {
			my $trackURL = blessed($track) ? $track->url : $track;
			if ( my ($id) = _getStreamParams( $trackURL ) ) {
				if ( $id && !$cache->get("wimp_meta_$id") ) {
					$need{$id}++;
				}
			}
		}
		
		if (keys %need) {
			if ( main::DEBUGLOG && $log->is_debug ) {
				$log->debug( "Need to fetch metadata for: " . join( ', ', keys %need ) );
			}
			
			my $metaUrl = Slim::Networking::SqueezeNetwork->url(
				"/api/wimp/v1/playback/getBulkMetadata"
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
				'trackIds=' . join( ',', keys %need ),
			);
		}
		else {
			$client->master->pluginData( fetchingMeta => 0 );
		}
	}
	
	#$log->debug( "Returning metadata for: $url" . ($meta ? '' : ': default') );
	
	return $meta || {
		bitrate   => '256k CBR',
		type      => 'MP3',
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
	my $icon  = Slim::Plugin::WiMP::Plugin->_pluginDataFor('icon');

	for my $track ( @{$info} ) {
		next unless ref $track eq 'HASH';
		
		# cache the metadata we need for display
		my $trackId = delete $track->{id};
		
		if ( !$track->{cover} ) {
			$track->{cover} = $icon;
		}

		my $bitrate = delete($track->{bitrate});
		
		my $meta = {
			%{$track},
			bitrate   => $bitrate*1 > 320 ? 'PCM VBR ' : ($bitrate . 'k CBR'),
			type      => $bitrate*1 > 320 ? 'FLAC' : 'MP3',
			info_link => 'plugins/wimp/trackinfo.html',
			icon      => $icon,
		};

		# if bitrate is not set, we have invalid data - only cache for a few minutes
		# if we didn't cache at all, we'd keep on hammering our servers
		$cache->set( 'wimp_meta_' . $trackId, $meta, $bitrate ? 86400 : 500 );
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

sub getIcon {
	my ( $class, $url ) = @_;

	return Slim::Plugin::WiMP::Plugin->_pluginDataFor('icon');
}

sub _getStreamParams {
	if ( $_[0] =~ m{wimp://(.+)\.(m4a|aac|mp3|flac)}i ) {
		return ($1, lc($2) );
	}
}

1;
