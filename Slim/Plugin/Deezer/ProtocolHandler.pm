package Slim::Plugin::Deezer::ProtocolHandler;

# Logitech Media Server Copyright 2001-2016 Logitech.
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
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $prefs = preferences('server');
my $log   = logger('plugin.deezer');

sub isRemote { 1 }

sub getFormatForURL { 'mp3' }

# default buffer 3 seconds of 320k audio
sub bufferThreshold { 40 * ( $prefs->get('bufferSecs') || 3 ) }

sub canSeek { 0 }

sub canSeekError { return ( 'SEEK_ERROR_TYPE_NOT_SUPPORTED', 'Deezer' ); }

# To support remote streaming (synced players), we need to subclass Protocols::HTTP
sub new {
	my $class  = shift;
	my $args   = shift;

	my $client = $args->{client};
	
	my $song      = $args->{song};
	my $streamUrl = $song->streamUrl() || return;
	
	main::DEBUGLOG && $log->debug( 'Remote streaming Deezer track: ' . $streamUrl );

	my $sock = $class->SUPER::new( {
		url     => $streamUrl,
		song    => $args->{song},
		client  => $client,
		bitrate => 320_000,
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
	
	my $bitrate = 320_000;

	$client->streamingSong->bitrate($bitrate);

	# ($title, $bitrate, $metaint, $redir, $contentType, $length, $body)
	return (undef, $bitrate, 0, '', 'mp3', $length, undef);
}

# Don't allow looping
sub shouldLoop { 0 }

sub isRepeatingStream {
	my ( undef, $song ) = @_;
	
	return $song->track()->url =~ /\.dzr$/;
}

sub explodePlaylist {
	my ( $class, $client, $url, $cb ) = @_;
	
	my $tracks = [];

	if ( $url =~ m{^deezer://((?:playlist|album):[0-9a-z]+)}i ) {
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
	
	main::DEBUGLOG && $log->debug("Getting next radio track from SqueezeNetwork");
	
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
	$url      = 'deezer://' . $track->{id} . '.mp3';
	my $title = $track->{title} . ' ' . 
		$client->string('BY') . ' ' . $track->{artist_name} . ' ' . 
		$client->string('FROM') . ' ' . $track->{album_name};
	
	$song->pluginData( radioTrackURL => $url );
	$song->pluginData( radioTitle    => $title );
	$song->pluginData( radioTrack    => $track );
	
	# We already have the metadata for this track, so can save calling getTrack
	my $icon = Slim::Plugin::Deezer::Plugin->_pluginDataFor('icon');
	my $meta = {
		artist    => $track->{artist_name},
		album     => $track->{album_name},
		title     => $track->{title},
		duration  => $track->{duration} || 200,
		cover     => $track->{cover} || $icon,
		bitrate   => '320k CBR',
		type      => 'MP3 (Deezer)',
		info_link => 'plugins/deezer/trackinfo.html',
		icon      => $icon,
		buttons   => {
			fwd => $track->{canSkip} ? 1 : 0,
			rew => 0,
		},
	};
	
	$song->duration( $meta->{duration} );
	
	my $cache = Slim::Utils::Cache->new;
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
	my ($trackId) = $params->{url} =~ m{deezer://(.+)\.mp3};
	
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
		},
	);
	
	main::DEBUGLOG && $log->is_debug && $log->debug('Getting next track playback info from SN');
	
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
	
	if (!$info->{url}) {
		_gotTrackError('No stream URL found', $client, $params);
		return;
	}
	
	# Save the media URL for use in strm
	$song->streamUrl($info->{url});

	# Save all the info
	$song->pluginData( info => $info );
	
	# Cache the rest of the track's metadata
	my $icon = Slim::Plugin::Deezer::Plugin->_pluginDataFor('icon');
	my $meta = {
		artist    => $info->{artist_name},
		album     => $info->{album_name},
		title     => $info->{title},
		cover     => $info->{cover} || $icon,
		duration  => $info->{duration} || 200,
		bitrate   => '320k CBR',
		type      => 'MP3 (Deezer)',
		info_link => 'plugins/deezer/trackinfo.html',
		icon      => $icon,
	};
	
	$song->duration( $meta->{duration} );
	
	my $cache = Slim::Utils::Cache->new;
	$cache->set( 'deezer_meta_' . $info->{id}, $meta, 86400 );
	
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
	
	if ( $url =~ m{deezer://(.+)\.dzr} ) {
		$stationId = $1;
		my $song = $client->currentSongForUrl($url);
		
		# Radio mode, pull track ID from lastURL
		if ( $song ) {
			$url = $song->pluginData('radioTrackURL');
		}
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
=pod XXX - legacy track info menu from before Slim::Menu::TrackInfo times?
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
	
	main::DEBUGLOG && $log->debug( "Getting track information for $url" );

	Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );
	
	$client->modeParam( 'handledTransition', 1 );
}
=cut

# Metadata for a URL, used by CLI/JSON clients
sub getMetadataFor {
	my ( $class, $client, $url ) = @_;
	
	my $icon = $class->getIcon();
	
	if ( $url =~ /\.dzr$/ ) {
		my $song = $client->currentSongForUrl($url);
		if (!$song || !($url = $song->pluginData('radioTrackURL'))) {
			return {
				title     => ($url && $url =~ /flow\.dzr/) ? $client->string('PLUGIN_DEEZER_FLOW') : $client->string('PLUGIN_DEEZER_SMART_RADIO'),
				bitrate   => '320k CBR',
				type      => 'MP3 (Deezer)',
				icon      => $icon,
				cover     => $icon,
			};
		}
	}
	
	return {} unless $url;
	
	my $cache = Slim::Utils::Cache->new;
	
	# If metadata is not here, fetch it so the next poll will include the data
	my ($trackId) = $url =~ m{deezer://(.+)\.mp3};
	my $meta      = $cache->get( 'deezer_meta_' . $trackId );
	
	if ( !$meta && !$client->master->pluginData('fetchingMeta') ) {

		$client->master->pluginData( fetchingMeta => 1 );
		
		# Go fetch metadata for all tracks on the playlist without metadata
		my @need = ($trackId);
		
		for my $track ( @{ Slim::Player::Playlist::playList($client) } ) {
			my $trackURL = blessed($track) ? $track->url : $track;
			if ( $trackURL =~ m{deezer://(.+)\.mp3} ) {
				my $id = $1;
				if ( !$cache->get("deezer_meta_$id") ) {
					push @need, $id;
				}
			}
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
		bitrate   => '320k CBR',
		type      => 'MP3 (Deezer)',
		icon      => $icon,
		cover     => $icon,
	};
}

sub _gotBulkMetadata {
	my $http   = shift;
	my $client = $http->params->{client};
	my $trackIds = $http->params->{trackIds};
	
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
	
	# Cache metadata
	my $cache = Slim::Utils::Cache->new;
	my $icon  = Slim::Plugin::Deezer::Plugin->_pluginDataFor('icon');
	
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
			bitrate   => '320k CBR',
			type      => 'MP3 (Deezer)',
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

	my $cache = Slim::Utils::Cache->new;
	my $icon  = Slim::Plugin::Deezer::Plugin->_pluginDataFor('icon');

	# set default meta data for tracks without meta data
	foreach ( @$trackIds ) {
		$cache->set('deezer_meta_' . $_, {
			bitrate   => '320k CBR',
			type      => 'MP3 (Deezer)',
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

1;
