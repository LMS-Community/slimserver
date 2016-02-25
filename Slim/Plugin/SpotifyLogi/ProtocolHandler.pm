package Slim::Plugin::SpotifyLogi::ProtocolHandler;

# $Id$

use strict;
use base qw(Slim::Player::Protocols::SqueezePlayDirect);

use JSON::XS::VersionOneAndTwo;
use MIME::Base64 qw(decode_base64);
use Scalar::Util qw(blessed);
use URI::Escape qw(uri_escape);

use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Cache;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $log = Slim::Utils::Log->addLogCategory( {
	'category'     => 'plugin.spotifylogi',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_SPOTIFYLOGI_MODULE_NAME',
} );

my $prefs = preferences('server');

sub canSeek { 1 }

# Source for AudioScrobbler
sub audioScrobblerSource {
	# P = Chosen by the user
	return 'P';
}

# Suppress some messages during initial connection, at Spotify's request
sub suppressPlayersMessage {
	my ( $class, $client, $song, $string ) = @_;
	
	if ( $string eq 'GETTING_STREAM_INFO' || $string eq 'CONNECTING_FOR' || $string eq 'BUFFERING' ) {
		return 1;
	}
	
	return;
}

sub getNextTrack {
	my ( $class, $song, $successCb, $errorCb ) = @_;
	
	my ($trackId) = $song->track()->url =~ m{spotify:/*(.+)};
	
	my $client = $song->master();
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		sub {
			my $http = shift;
			my $info = eval { from_json( $http->content ) };
			if ( $@ || $info->{error} ) {
				if ( main::DEBUGLOG && $log->is_debug ) {
					$log->debug( 'getPlaybackInfo failed: ' . ( $@ || $info->{error} ) );
				}
				
				$errorCb->( $@ || $info->{error} );
			}
			else {
				if ( main::DEBUGLOG && $log->is_debug ) {
					$log->debug( 'getPlaybackInfo ok: ' . Data::Dump::dump($info) );
				}

				$song->pluginData( info => $info );

				$successCb->();
			}
		},
		sub {
			my $http  = shift;

			if ( main::DEBUGLOG && $log->is_debug ) {
				$log->debug( 'getPlaybackInfo failed: ' . $http->error );
			}
			
			$errorCb->( $http->error );
		},
		{
			client => $song->master(),
		},
	);
	
	main::DEBUGLOG && $log->is_debug && $log->debug('Getting playback info from SN');

	$http->get(
		Slim::Networking::SqueezeNetwork->url(
			'/api/spotify/v1/playback/getPlaybackInfo?trackId=' . uri_escape($trackId),
		)
	);
}

sub canDirectStream {
	my ( $class, $client, $url ) = @_;

	my ($handler) = $url =~ m{^spotify:/*(.+?)};

	if ($handler && $client->can('spDirectHandlers') && $client->spDirectHandlers =~ /spotify/) {
		# Rewrite URL if it came from Triode's plugin
		$url =~ s{^spotify:track}{spotify://track};
		
		return $url;
	}
}

sub onStream {
	my ( $class, $client, $song ) = @_;
	
	# send spds packet with auth info
	my $info  = $song->pluginData('info');
	my $auth  = $info->{auth};
	my $prefs = $info->{prefs};
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( 
			$client->id . ' Sending playback information (username ' . $auth->{username} . ', bitrate pref ' . $prefs->{bitrate} . ')'
		);
	}

	my $data = pack(
		'cC/a*C/a*C/a*c',
		1,
		$auth->{username},
		decode_base64( $auth->{password} ),
		decode_base64( $auth->{iv} ),
		$prefs->{bitrate} == 320 ? 1 : 0,
	);
	
	$client->sendFrame( spds => \$data );
}

sub getMetadataFor {
	my ( $class, $client, $url, undef, $song ) = @_;
	
	my $icon = Slim::Networking::SqueezeNetwork->url('/static/images/icons/spotify/album.png');
	$song ||= $client->currentSongForUrl($url);
	
	# Rewrite URL if it came from Triode's plugin
	$url =~ s{^spotify:track}{spotify://track};

	if ( $song ||= $client->currentSongForUrl($url) ) {
		if ( my $info = $song->pluginData('info') ) {		
			return {
				artist    => $info->{artist},
				album     => $info->{album},
				title     => $info->{title},
				duration  => $info->{duration},
				cover     => $info->{cover},
				icon      => $icon,
				bitrate   => $info->{prefs}->{bitrate} . 'k VBR',
				info_link => 'plugins/spotifylogi/trackinfo.html',
				type      => 'Ogg Vorbis (Spotify)',
			} if $info->{title} && $info->{duration};
		}
	}
	
	# Try to pull metadata from cache
	my $cache = Slim::Utils::Cache->new;
	
	# If metadata is not here, fetch it so the next poll will include the data
	my ($trackURI) = $url =~ m{spotify:/*(.+)};
	my $meta       = $cache->get( 'spotify_meta_' . $trackURI );
	
	if ( !$meta && !$client->master->pluginData('fetchingMeta') ) {
		# Go fetch metadata for all tracks on the playlist without metadata
		my @need;
		
		for my $track ( @{ Slim::Player::Playlist::playList($client) } ) {
			my $trackURL = blessed($track) ? $track->url : $track;
			if ( $trackURL =~ m{spotify:/*(.+)} ) {
				my $id = $1;
				if ( !$cache->get("spotify_meta_$id") ) {
					push @need, $id;
				}
			}
		}
		
		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug( "Need to fetch metadata for: " . join( ', ', @need ) );
		}
		
		$client->master->pluginData( fetchingMeta => 1 );
		
		my $metaUrl = Slim::Networking::SqueezeNetwork->url(
			"/api/spotify/v1/playback/getBulkMetadata"
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
	
	if ( $song ) {
		if ( $meta->{duration} && !($song->duration && $song->duration > 0) ) {
			$song->duration($meta->{duration});
		}
		
		$song->pluginData( info => $meta );
	}
	
	return $meta || {
		bitrate   => '320k VBR',
		type      => 'Ogg Vorbis (Spotify)',
		icon      => $icon,
		cover     => $icon,
		info_link => 'plugins/spotifylogi/trackinfo.html',
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
	my $icon  = Slim::Networking::SqueezeNetwork->url('/static/images/icons/spotify/album.png');

	for my $track ( @{$info} ) {
		next unless ref $track eq 'HASH';
		
		# cache the metadata we need for display
		my $trackId = delete $track->{trackId};
		
		my $meta = {
			%{$track},
			bitrate   => '320k VBR',
			type      => 'Ogg Vorbis (Spotify)',
			info_link => 'plugins/spotifylogi/trackinfo.html',
			icon      => $icon,
		};
	
		$cache->set( 'spotify_meta_' . $trackId, $meta, 86400 );
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

# URL used for CLI trackinfo queries
sub trackInfoURL {
	my ( $class, $client, $url ) = @_;
	
	my ($trackId) = $url =~ m{spotify:/*(.+)};
	
	# SN URL to fetch track info menu
	my $trackInfoURL = Slim::Networking::SqueezeNetwork->url(
		'/api/spotify/v1/opml/track?uri=spotify:' . $trackId
	);
	
	return $trackInfoURL;
}

sub getIcon {
	my ( $class, $url ) = @_;

	return Slim::Plugin::SpotifyLogi::Plugin->_pluginDataFor('icon');
}

# SN only, re-init upon reconnection
sub reinit { if ( main::SLIM_SERVICE ) {
	my ( $class, $client, $song ) = @_;
	
	# Reset song duration/progress bar
	my $currentURL = $song->streamUrl();
	
	main::DEBUGLOG && $log->debug("Re-init Spotify - $currentURL");
	
	return 1;
} }

1;
