package Slim::Plugin::WiMP::ProtocolHandler;

# Logitech Media Server Copyright 2003-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

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

# https://tidal.com/browse/track/95570766
# https://tidal.com/browse/album/95570764
# https://tidal.com/browse/playlist/5a36919b-251c-4fa7-802c-b659aef04216
my $URL_REGEX = qr{^https://(?:\w+\.)?tidal.com/browse/(track|playlist|album|artist)/([a-z\d-]+)}i;
Slim::Player::ProtocolHandlers->registerURLHandler($URL_REGEX, __PACKAGE__);

sub isRemote { 1 }

sub getFormatForURL {
	my ($class, $url) = @_;

	my ($trackId, $format) = _getStreamParams( $url );
	return $format;
}

# default buffer 3 seconds of 256kbps MP3/768kbps FLAC audio
my %bufferSecs = (
	flac => 80,
	flc => 80,
	mp3 => 32,
	mp4 => 40
);

sub bufferThreshold {
	my ($class, $client, $url) = @_;

	$url = $client->playingSong()->track()->url() unless $url =~ /\.(fla?c|mp[34])/;
	my $ext = $1;

	my ($trackId, $format) = _getStreamParams($url);
	return ($bufferSecs{$format} || $bufferSecs{$ext} || 40) * ($prefs->get('bufferSecs') || 3);
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
		bitrate => _getBitrate($format),
	} ) || return;

	if ($format eq 'flac') {
		${*$sock}{contentType} = 'audio/flac';
	}
	elsif ($format =~ /mp4|aac/) {
		${*$sock}{contentType} = 'audio/aac';
	}
	else {
		${*$sock}{contentType} = 'audio/mpeg';
	}

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

sub explodePlaylist {
	my ( $class, $client, $url, $cb ) = @_;

	if ( $url =~ $URL_REGEX || $url =~ m{^wimp://(playlist|album|):?([0-9a-z-]+)}i ) {
		Slim::Networking::SqueezeNetwork->new(
			sub {
				my $http = shift;
				my $opml = eval { from_json( $http->content ) };

				return $cb->($opml) if $opml && ref $opml && ref $opml eq 'ARRAY';

				$cb->([]);
			},
			sub {
				$cb->([])
			},
			{
				client => $client
			}
		)->get(
			Slim::Networking::SqueezeNetwork->url(
				"/api/wimp/v1/playback/getIdsForURL?url=" . uri_escape_utf8($url),
			)
		);
	}
	else {
		$cb->([]);
	}
}

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
			sprintf('/api/wimp/v1/playback/getMediaURL?trackId=%s&format=%s', $trackId, $format)
		)
	);
}

sub _gotTrack {
	my ( $client, $info, $params ) = @_;

	my $song = $params->{song};

	return if $song->pluginData('abandonSong');

	# Save the media URL for use in strm
	$song->streamUrl($info->{url});

	my ($trackId, $format) = _getStreamParams( $params->{url} );

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
		bitrate   => $format eq 'flac' ? 'PCM VBR' : ($info->{bitrate} . 'k CBR'),
		type      => lc($format) eq 'mp4' ? 'AAC' : uc($format),
		info_link => 'plugins/wimp/trackinfo.html',
		icon      => $icon,
	};

	$song->duration( $info->{duration} );

	my $cache = Slim::Utils::Cache->new;
	$cache->set( 'wimp_meta_' . $info->{id}, $meta, 86400 );
	if ($format =~ /mp4|aac|fla?c/i) {
		my $http = Slim::Networking::Async::HTTP->new;
		$http->send_request( {
			request     => HTTP::Request->new( GET => $info->{url} ),
			onStream    => $format =~ /fla?c/i ? 
						   \&Slim::Utils::Scanner::Remote::parseFlacHeader :
						   \&Slim::Utils::Scanner::Remote::parseMp4Header,
			onError     => sub {
				my ($self, $error) = @_;
				$log->warn( "could not find $format header $error" );
				$params->{successCb}->();
			},
			passthrough => [ $song->track, { cb => $params->{successCb} }, $info->{url} ],
		} );
	} else {
		$params->{successCb}->();
	}
}

sub _gotTrackError {
	my ( $error, $client, $params ) = @_;

	main::DEBUGLOG && $log->debug("Error during getTrackInfo: $error");

	return if $params->{song}->pluginData('abandonSong');

	_handleClientError( $error, $client, $params );
}

# parseHeaders is used for proxied streaming
sub parseHeaders {
	my ( $self, @headers ) = @_;

	__PACKAGE__->parseDirectHeaders( $self->client, $self->url, @headers );

	return $self->SUPER::parseHeaders( @headers );
}

sub parseDirectHeaders {
	my ( $class, $client, $url, @headers ) = @_;

	#main::DEBUGLOG && $log->is_debug && $log->debug(Data::Dump::dump(@headers));
	my ($length, $bitrate, $ct);
	foreach my $header (@headers) {
		if ( $header =~ /^Content-Length:\s*(.*)/i ) {
			$length = $1;
		}
		elsif ( $header =~ /^Content-Type:\s*(\S*)/) {
			$ct = Slim::Music::Info::mimeToType($1);
		}
	}

	$ct = 'aac' if !$ct || $ct eq 'mp4';

	if ( $ct eq 'flc' && $length && (my $song = $client->streamingSong()) ) {
		$bitrate = int($length/$song->duration*8);

		$url = $url->url if blessed $url;
		my ($trackId) = _getStreamParams( $url );

		if ($trackId) {
			my $cache = Slim::Utils::Cache->new;
			my $meta = $cache->get('wimp_meta_' . $trackId);
			if ($meta && ref $meta) {
				$meta->{bitrate} = sprintf("%.0f" . Slim::Utils::Strings::string('KBPS'), $bitrate/1000);
				$cache->set( 'wimp_meta_' . $trackId, $meta, 86400 );
			}
		}
	}

	$bitrate ||= _getBitrate($ct);

	$client->streamingSong->bitrate($bitrate);

	# ($title, $bitrate, $metaint, $redir, $contentType, $length, $body)
	return (undef, $bitrate, 0, '', $ct, $length);
}

sub _getBitrate {
	my $ct = shift || '';

	return 800_000 if $ct =~ /fla?c/;
	return 320_000 if $ct =~ /aac|mp4/;

	return 256_00;
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

# Metadata for a URL, used by CLI/JSON clients
sub getMetadataFor {
	my ( $class, $client, $url ) = @_;

	my $icon = $class->getIcon();

	return {} unless $url;

	my $cache = Slim::Utils::Cache->new;

	# If metadata is not here, fetch it so the next poll will include the data
	my ($trackId, $format) = _getStreamParams( $url );
	my $meta = $cache->get( 'wimp_meta_' . ($trackId || '') );

	if ( !($meta && $meta->{duration}) && !$client->master->pluginData('fetchingMeta') ) {

		$client->master->pluginData( fetchingMeta => 1 );

		# Go fetch metadata for all tracks on the playlist without metadata
		my %need = (
			$trackId => 1
		);

		for my $track ( @{ Slim::Player::Playlist::playList($client) } ) {
			my $trackURL = blessed($track) ? $track->url : $track;
			if ( my ($id) = _getStreamParams( $trackURL ) ) {
				my $cached = $id && $cache->get("wimp_meta_$id");
				if ( $id && !($cached && $cached->{duration}) ) {
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
	$meta->{cover} ||= $meta->{icon} ||= $icon;

	return $meta || {
		bitrate   => '320k CBR',
		type      => 'AAC',
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
			type      => $bitrate*1 > 320 ? 'FLAC' : ($bitrate*1 > 256 ? 'AAC' : 'MP3'),
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
	if ( $_[0] =~ m{wimp://(.+)\.(m4a|aac|mp3|mp4|flac)}i ) {
		return ($1, lc($2) );
	}
}

1;
