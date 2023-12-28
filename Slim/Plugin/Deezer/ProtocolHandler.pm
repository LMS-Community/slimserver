package Slim::Plugin::Deezer::ProtocolHandler;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use base qw(Slim::Player::Protocols::HTTP);

use JSON::XS::VersionOneAndTwo;
use URI::Escape qw(uri_escape_utf8);
use Scalar::Util qw(blessed);

use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $cache = Slim::Utils::Cache->new;
my $prefs = preferences('plugin.deezer');
my $serverprefs = preferences('server');
my $log   = logger('plugin.deezer');

# https://www.deezer.com/album/68905661?...
# https://www.deezer.com/track/531514321?...
# https://www.deezer.com/playlist/1012112431?...
my $URL_REGEX = qr/^https:\/\/(?:\w+\.)?deezer.com\/(track|playlist|album|artist)\/(\d+)/i;
Slim::Player::ProtocolHandlers->registerURLHandler($URL_REGEX, __PACKAGE__);

sub isRemote { 1 }

sub getFormatForURL {
	my ($class, $url) = @_;

	my ($trackId, $format) = _getStreamParams( $url );

	# This is hacky: for radio/flow we don't know the format type. Let's assume what we got last...
	return $format || $prefs->get('latestFormat') || 'mp3';
}

sub formatOverride {
	my ($class, $song) = @_;

	my $format = $class->getFormatForURL($song->track->url);
	$format =~ s/flac/flc/;
	return $format;
}

# default buffer 3 seconds of 320k audio
sub bufferThreshold {
	my ($class, $client, $url) = @_;

	$url = $client->playingSong()->track()->url() unless $url =~ /\.(flac|mp3)/;
	my $ext = $1;

	my ($trackId, $format) = _getStreamParams($url);

	$format ||= $ext;
	($format eq 'flac' ? 80 : 40) * ( $serverprefs->get('bufferSecs') || 3 )
}

sub canSeek {
	my ( $class, $client, $song ) = @_;

	return 0 if $song->track->url =~ /\.dzr/;

	1;
}

sub canSeekError { return ( 'SEEK_ERROR_TYPE_NOT_SUPPORTED', 'Deezer' ); }

# To support remote streaming (synced players), we need to subclass Protocols::HTTP
sub new {
	my $class  = shift;
	my $args   = shift;

	my $client = $args->{client};

	my $song      = $args->{song};
	my $streamUrl = $song->streamUrl() || return;
	my ($trackId, $format) = _getStreamParams( $args->{url} || '' );

	main::DEBUGLOG && $log->debug( 'Remote streaming Deezer track: ' . $streamUrl );

	my $sock = $class->SUPER::new( {
		url     => $streamUrl,
		song    => $args->{song},
		client  => $client,
		bitrate => _getBitrate($format),
	} ) || return;

	${*$sock}{contentType} = $format eq 'flac' ? 'audio/flac' : 'audio/mpeg';

	return $sock;
}

# Avoid scanning
sub scanUrl {
	my ( $class, $url, $args ) = @_;

	# can't just take $args->{song}->currentTrack as it might be a playlist
	$args->{cb}->( Slim::Schema->objectForUrl( {
		url => $url,
	} ) );
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
	$url = $url->url if blessed $url;

	# Clear previous duration, since we're using the same URL for all tracks
	if ( $url =~ /\.dzr$/ ) {
		Slim::Music::Info::setDuration( $url, 0 );
	}

	my ($length, $rangeLength, $bitrate, $ct);
	foreach my $header (@headers) {
		if ( $header =~ /^Content-Length:\s*(.*)/i ) {
			$length = $1;
		}
		elsif ( $header =~ /^Content-Type:\s*(\S*)/) {
			$ct = Slim::Music::Info::mimeToType($1);
		}
		elsif ($header =~ m%^Content-Range:\s+bytes\s+(\d+)-(\d+)/(\d+)%i) {
			$rangeLength = $3;
		}
	}

	# Content-Range: has predecence over Content-Length:
	if ($rangeLength) {
		$length = $rangeLength;
	}

	if ( $ct eq 'flc' && $length && (my $song = $client->streamingSong()) ) {
		my ($trackId) = _getStreamParams( $url );

		if ($trackId) {
			my $duration = $song->duration;

			if (!$duration && (my $info = $song->pluginData('info'))) {
				$duration = $info->{duration};
			}

			$bitrate = $duration ? int($length/$duration*8) : _getBitrate($ct);

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
	return (undef, $bitrate, 0, '', $ct, $length, undef);
}

# Don't allow looping
sub shouldLoop { 0 }

sub isRepeatingStream {
	my ( undef, $song ) = @_;

	return $song->track()->url =~ /\.dzr$/;
}

sub explodePlaylist {
	my ( $class, $client, $url, $cb ) = @_;

	if (my ($type, $id ) = $url =~ $URL_REGEX) {
		if ($type eq 'track') {
			$url = "deezer://$id.mp3";
		}
		else {
			$url = "deezer://$type:$id";
		}
	}

	if ($url =~ m{^deezer:\/\/([0-9a-z]+)\.dzl}) {
		$url = 'deezer://playlist:' . $1;
	}

	my $tracks = [];

	if ( $url =~ m{^deezer://((?:playlist|album|artist):[0-9a-z]+)}i ) {
		my $id = $1;

		Slim::Networking::SqueezeNetwork->new(
			sub {
				my $http = shift;
				my $tracks = eval { from_json( $http->content ) };
				$cb->($tracks || []);
			},
			sub {
				$cb->([])
			},
			{
				client => $client
			}
		)->get(
			Slim::Networking::SqueezeNetwork->url(
				'/api/deezer/v1/playback/getTracksForID?id=' . uri_escape_utf8($id),
			)
		);
	}
	else {
		$cb->([$url])
	}
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
	if ( $url =~ /(?<!flow)\.dzr$/ ) {
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
		main::DEBUGLOG && $log->debug("Deezer: Skip limit exceeded, disallowing skip");

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

	main::DEBUGLOG && $log->debug("Direct stream failed: [$response] $status_line\n");

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
	# must use currentTrack and not track to get the playlist item (if any)
	my $url    = $song->currentTrack()->url;

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
		sprintf("/api/deezer/v1/radio/getNextTrack?stationId=%s&format=%s", $stationId, $prefs->get('latestFormat'))
	);

	my $http = Slim::Networking::SqueezeNetwork->new(
		\&_gotNextRadioTrack,
		\&_gotNextRadioTrackError,
		{
			client => $params->{song}->master(),
			params => $params,
		},
	);

	main::DEBUGLOG && $log->debug("Getting next radio track from SqueezeNetwork: $radioURL");

	$http->get( $radioURL );
}

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

		my $error = ( $client->isPlaying(1) && $client->playingSong()->track()->url =~ /\.dzr/ )
					? 'PLUGIN_DEEZER_NO_NEXT_TRACK'
					: 'PLUGIN_DEEZER_NO_TRACK';

		$params->{errorCb}->( $error, $url );

		# Set the title after the errro callback so the current title
		# is still the radio-station name during the callback
		Slim::Music::Info::setCurrentTitle( $url, $client->string('PLUGIN_DEEZER_NO_TRACK') );

		return;
	}

	# set metadata for track, will be set on playlist newsong callback
	$url      = 'deezer://' . $track->{id} . '.' . __PACKAGE__->getFormatForURL($track->{url});
	my $title = $track->{title} . ' ' .
		$client->string('BY') . ' ' . $track->{artist_name} . ' ' .
		$client->string('FROM') . ' ' . $track->{album_name};

	$song->pluginData( radioTrackURL => $url );
	$song->pluginData( radioTitle    => $title );
	$song->pluginData( radioTrack    => $track );

	my $icon = getIcon();
	my $meta = {
		artist    => $track->{artist_name},
		album     => $track->{album_name},
		title     => $track->{title},
		duration  => $track->{duration} || 200,
		cover     => $track->{cover} || $icon,
		bitrate   => _getBitratePlaceholder($url),
		type      => _getFormatPlaceholder($url),
		info_link => 'plugins/deezer/trackinfo.html',
		icon      => $icon,
		buttons   => {
			fwd => $track->{canSkip} ? 1 : 0,
			rew => 0,
		},
	};

	# We already have the metadata for this track, so can save calling getTrack
	main::INFOLOG && $log->warn("Missing duration?" . Data::Dump::dump($track, $meta->{duration})) unless $track->{duration};

	Slim::Music::Info::setDuration( $url, $meta->{duration} );

	$cache->set( 'deezer_meta_' . $track->{id}, $meta, 86400 );

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

	# Get track URL for the next track
	my ($trackId, $format) = _getStreamParams($params->{url});

	my $error;
	if ( $song->pluginData('abandonSong') || ($error = Slim::Utils::Cache->new->get('deezer_ignore_' . $trackId)) ) {
		$log->warn('Ignoring track, as it is known to be invalid: ' . $trackId);
		_gotTrackError($error || 'Invalid track ID', $client, $params);
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
				if ( main::DEBUGLOG && $log->is_debug ) {
					$log->debug( 'getTrack ok: ' . Data::Dump::dump($info) );
				}

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
			format => $format
		},
	);

	main::DEBUGLOG && $log->is_debug && $log->debug('Getting next track playback info from SN');

	$http->get(
		Slim::Networking::SqueezeNetwork->url(
			sprintf('/api/deezer/v1/playback/getMediaURL?trackId=%s&format=%s', uri_escape_utf8($trackId), $format)
		)
	);
}

sub _gotTrack {
	my ( $client, $info, $params ) = @_;

	my $song = $params->{song};

	return if $song->pluginData('abandonSong');

	if (!$info->{url}) {
		_gotTrackError('No stream URL found', $client, $params);
		return;
	}

	$info->{bitrate} = _getBitratePlaceholder($info->{url});
	$info->{type}    = _getFormatPlaceholder($info->{url});
	my ($trackId, $format) = _getStreamParams( $info->{url} );

	# as we don't know the format for a flow/radio station, let's keep the format of the last played track to make assumptions later on...
	if ( $client->isPlaying(1) && $client->playingSong()->track()->url !~ /\.dzr/ ) {
		$prefs->set('latestFormat', __PACKAGE__->getFormatForURL($info->{url}));
	}

	# Save the media URL for use in strm
	$song->streamUrl($info->{url});

	# Save all the info
	$song->pluginData( info => $info );

	# Cache the rest of the track's metadata
	my $icon = getIcon();
	my $meta = {
		artist    => $info->{artist_name},
		album     => $info->{album_name},
		title     => $info->{title},
		cover     => $info->{cover} || $icon,
		duration  => $info->{duration} || 200,
		bitrate   => $info->{bitrate},
		type      => $info->{type},
		info_link => 'plugins/deezer/trackinfo.html',
		icon      => $icon,
	};

	# We already have the metadata for this track, so can save calling getTrack
	main::INFOLOG && $log->warn("Missing duration?" . Data::Dump::dump($info, $meta->{duration})) unless $info->{duration};

	Slim::Music::Info::setDuration( $info->{url}, $meta->{duration} );

	$cache->set( 'deezer_meta_' . $info->{id}, $meta, 86400 );

	# When doing flac, parse the header to be able to seek (IP3K)
	if ($format =~ /fla?c/i) {
		Slim::Utils::Scanner::Remote::parseRemoteHeader(
			$song->track, $info->{url}, $format, $params->{successCb},
			sub {
				my ($self, $error) = @_;
				$log->warn( "could not find $format header $error" );
				$params->{successCb}->();
			} );
	}
	else {
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
	}

	# Watch for playlist commands
	Slim::Control::Request::subscribe(
		\&_playlistCallback,
		[['playlist'], ['newsong']],
		$song->master(),
	);
}

sub _gotTrackError {
	my ( $error, $client, $params ) = @_;

	main::DEBUGLOG && $log->debug("Error during getTrackInfo: $error");

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

		main::DEBUGLOG && $log->debug( "Stopped Deezer, unsubscribing from playlistCallback" );
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

# URL used for CLI trackinfo queries
sub trackInfoURL {
	my ( $class, $client, $url ) = @_;

	my $stationId;

	if ( $url =~ m{deezer://(.+)\.dzr} ) {
		$stationId = $1;
		my $song = $client->currentSongForUrl($url);

		# Radio mode, pull track ID from lastURL
		if ( $song ) {
			$url = $song->pluginData('radioTrackURL');
		}
	}

	my ($trackId, $format) = _getStreamParams($url);

	# SN URL to fetch track info menu
	my $trackInfoURL = Slim::Networking::SqueezeNetwork->url(
		sprintf('/api/deezer/v1/opml/trackinfo?trackId=%s&format=%s', $trackId, $format)
	);

	if ( $stationId ) {
		$trackInfoURL .= '&stationId=' . $stationId;
	}

	return $trackInfoURL;
}

# Metadata for a URL, used by CLI/JSON clients
sub getMetadataFor {
	my ( $class, $client, $url ) = @_;

	return {} unless $url;

	my $icon = getIcon();
	my $song = $client->currentSongForUrl($url);

	if ( $url =~ /\.dzr$/ ) {
		if (!$song || !($url = $song->pluginData('radioTrackURL'))) {
			return {
				title     => ($url && $url =~ /flow\.dzr/) ? $client->string('PLUGIN_DEEZER_FLOW') : $client->string('PLUGIN_DEEZER_SMART_RADIO'),
				bitrate   => _getBitratePlaceholder($url),
				type      => _getFormatPlaceholder($url),
				icon      => $icon,
				cover     => $icon,
			};
		}
	}

	# need to take the real current track url for playlists
	$url = $song->currentTrack->url if $song && $song->isPlaylist && $song->currentTrack->url !~ /\.dzr$/;

	# If metadata is not here, fetch it so the next poll will include the data
	my ($trackId, $format) = _getStreamParams($url);
	my $meta = $cache->get( 'deezer_meta_' . $trackId );

	if ( !$client->master->pluginData('fetchingMeta') ) {
		$client->master->pluginData( fetchingMeta => 1 );

		# Go fetch metadata for all tracks on the playlist without metadata
		my @need;
		push @need, $trackId if $trackId && (!$meta || !$meta->{title});

		for my $track ( @{ Slim::Player::Playlist::playList($client) } ) {
			my $trackURL = blessed($track) ? $track->url : $track;

			my ($id) = _getStreamParams($trackURL);

			if ($id && $id != $trackId) {
				my $trackMeta = $cache->get("deezer_meta_$id");
				push @need, $id if !$trackMeta || !$trackMeta->{title};
			}
		}

		@need = do { my %seen; grep { !$seen{$_}++ } @need };

		if (!scalar @need) {
			$client->master->pluginData( fetchingMeta => 0 );
			return $meta;
		}

		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug( "Need to fetch metadata for: " . join( ', ', @need ) );
		}

		my $metaUrl = Slim::Networking::SqueezeNetwork->url(
			"/api/deezer/v1/playback/getBulkMetadata"
		);

		my $http = Slim::Networking::SqueezeNetwork->new(
			\&_gotBulkMetadata,
			\&_gotBulkMetadataError,
			{
				client  => $client,
				timeout => 60,
				trackIds=> \@need,
				format  => $format,
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
		bitrate   => _getBitratePlaceholder($url),
		type      => _getFormatPlaceholder($url),
		icon      => $icon,
		cover     => $icon,
	};
}

sub _gotBulkMetadata {
	my $http   = shift;
	my $client = $http->params->{client};
	my $trackIds = $http->params->{trackIds};
	my $format = $http->params->{format};

	$client->master->pluginData( fetchingMeta => 0 );

	my $info = eval { from_json( $http->content ) };

	if ( $@ || ref $info ne 'ARRAY' ) {
		$log->error( "Error fetching track metadata: " . ( $@ || 'Invalid JSON response' ) );
		_invalidateTracks($client, $trackIds);
		return;
	}

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( "Caching metadata for " . scalar( @{$info} ) . " tracks" );
	}

	my $icon = getIcon();

	my %trackIds = map { $_ => 1 } @$trackIds;

	for my $track ( @{$info} ) {
		next unless ref $track eq 'HASH';

		# cache the metadata we need for display
		my $trackId = delete $track->{id};

		if ( !$track->{cover} ) {
			$track->{cover} = $icon;
		}

		my $meta = {
			%{$track},
			bitrate   => _getBitratePlaceholder($format),
			type      => _getFormatPlaceholder($format),
			info_link => 'plugins/deezer/trackinfo.html',
			icon      => $icon,
		};

		$cache->set( 'deezer_meta_' . $trackId, $meta, 86400 );

		delete $trackIds{$trackId};
	}

	# see whether some tracks didn't get any data back
	$trackIds = [ keys %trackIds ];
	if ( scalar @$trackIds ) {
		_invalidateTracks($client, $trackIds, 'no data');
	}

	# Update the playlist time so the web will refresh, etc
	$client->currentPlaylistUpdateTime( Time::HiRes::time() );

	Slim::Control::Request::notifyFromArray( $client, [ 'newmetadata' ] );
}

sub _gotBulkMetadataError {
	my $http   = shift;
	my $client = $http->params('client');
	my $error  = $http->error;

	_invalidateTracks($client, $http->params->{trackIds});

	$client->master->pluginData( fetchingMeta => 0 );

	$log->warn("Error getting track metadata from SN: $error");
}

sub _invalidateTracks {
	my ($client, $trackIds, $banForGood) = @_;

	return unless $trackIds && ref $trackIds eq 'ARRAY';

	main::DEBUGLOG && $log->is_debug && $log->debug("Disable track(s) lack of metadata: " . join(', ', @$trackIds));

	my $icon = getIcon();

	# set default meta data for tracks without meta data
	foreach ( @$trackIds ) {
		$cache->set('deezer_meta_' . $_, {
			bitrate   => _getBitratePlaceholder(),
			type      => _getFormatPlaceholder(),
			icon      => $icon,
			cover     => $icon,
		},
		3600);

		# don't even try again for a while if we hit an invalid track ID
		$cache->set('deezer_ignore_' . $_, $banForGood, 86400 * 7) if $banForGood;
	}
}

sub getIcon {
	my ( $class, $url ) = @_;

	return Slim::Plugin::Deezer::Plugin->_pluginDataFor('icon');
}

sub _getStreamParams {
	my $url = shift;
	if ( $url =~ m{deezer://(.+)\.(mp3|flac)}i ) {
		return ($1, lc($2) );
	}
	elsif ( $url =~ /deezer\.com.*?\.(mp3|flac)/) {
		return (undef, lc($1));
	}
}

sub _getBitrate {
	my $ct = shift || '';

	return 800_000 if $ct =~ /fla?c/;
	return 320_000;
}

sub _getBitratePlaceholder {
	my $url = shift || 'mp3';
	return $url =~ /\.?\bflac\b/ ? 'PCM VBR' : '320k CBR';
}

sub _getFormatPlaceholder {
	my $url = shift || 'mp3';
	return ($url =~ /\.?\bflac\b/ ? 'FLAC' : 'MP3') . ' (Deezer)';
}

1;
