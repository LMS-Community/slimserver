package Slim::Plugin::Classical::ProtocolHandler;

# $Id$

# Handler for classical:// URLs

use strict;
use base qw(Slim::Player::Protocols::HTTP);

use JSON::XS::VersionOneAndTwo;
use Scalar::Util qw(blessed);
use URI::Escape qw(uri_escape_utf8);

use Slim::Player::Playlist;
use Slim::Utils::Misc;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.classical',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_CLASSICAL_MODULE_NAME',
} );

# To support remote streaming (synced players, slimp3/SB1), we need to subclass Protocols::HTTP
sub new {
	my $class  = shift;
	my $args   = shift;

	my $client = $args->{client};
	
	my $song      = $args->{song};
	my $streamUrl = $song->streamUrl() || return;
	my $track     = $song->pluginData();
	
	main::DEBUGLOG && $log->is_debug && $log->debug( 'Remote streaming Classical track: ' . $streamUrl );

	my $sock = $class->SUPER::new( {
		url     => $streamUrl,
		song    => $song,
		client  => $client,
		bitrate => 128_000,
	} ) || return;
	
	${*$sock}{contentType} = 'audio/mpeg';

	return $sock;
}

sub scanUrl {
	my ($class, $url, $args) = @_;
	$args->{cb}->( $args->{song}->currentTrack() );
}

sub getFormatForURL { 'mp3' }

# Don't allow looping if the tracks are short
sub shouldLoop { 0 }

sub canSeek { 0 }

sub canSeekError { return ( 'SEEK_ERROR_TYPE_NOT_SUPPORTED', 'Classical.com' ); }

sub getNextTrack {
	my ($class, $song, $successCb, $errorCb) = @_;
	
	my $client = $song->master();
	my $url    = $song->currentTrack()->url;
	
	# Get next track
	my ($id) = $url =~ m{^classical://([^\.]+).mp3};
	
	# Talk to SN and get the next track to play
	my $trackURL = Slim::Networking::SqueezeNetwork->url(
		"/api/classical/v1/playback/getMediaURL?trackId=$id"
	);
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&gotNextTrack,
		\&gotNextTrackError,
		{
			client        => $client,
			song          => $song,
			callback      => $successCb,
			errorCallback => $errorCb,
			timeout       => 35,
		},
	);
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Getting track from SqueezeNetwork for $id");
	
	$http->get( $trackURL );
}

sub gotNextTrack {
	my $http   = shift;
	my $client = $http->params->{client};
	my $song   = $http->params->{song};	
	my $url    = $song->currentTrack()->url;
	my $track  = eval { from_json( $http->content ) };
	
	if ( $@ || $track->{error} ) {
		# We didn't get the next track to play
		if ( $log->is_warn ) {
			$log->warn( 'Classical error getting next track: ' . ( $@ || $track->{error} ) );
		}
		
		if ( $client->playingSong() ) {
			$client->playingSong()->pluginData( {
				songName => $@ || $track->{error},
			} );
		}
		
		$http->params->{'errorCallback'}->( 'PLUGIN_CLASSICAL_NO_INFO', $track->{error} );
		return;
	}
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( 'Got Classical track: ' . Data::Dump::dump($track) );
	}
	
	# Save metadata for this track
	$song->pluginData( $track );
	$song->streamUrl($track->{URL});
	
	# Cache metadata
	my $meta = {
		artist    => $track->{Composers},
		album     => $track->{Workname},
		title     => $track->{Name},
		cover     => $track->{Coverart},
		duration  => $track->{Length},
		bitrate   => '128k CBR',
		type      => 'MP3 (Classical.com)',
		info_link => 'plugins/classical/trackinfo.html',
		icon      => __PACKAGE__->getIcon(),
	};
	
	my $cache = Slim::Utils::Cache->new;
	$cache->set( 'classical_meta_' . $track->{id}, $meta, 86400 );

	$http->params->{callback}->();
}

sub gotNextTrackError {
	my $http = shift;
	
	$http->params->{errorCallback}->( 'PLUGIN_CLASSICAL_ERROR', $http->error );
}

sub parseDirectHeaders {
	my $class   = shift;
	my $client  = shift || return;
	my $url     = shift;
	my @headers = @_;
	
	my $song  = $client->streamingSong();
	my $track = $song->pluginData(); 
	
	my $bitrate     = 128_000;
	my $contentType = 'mp3';
	
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
	
	$client->streamingSong->duration($track->{Length});
	
	# title, bitrate, metaint, redir, type, length, body
	return (undef, $bitrate, 0, undef, $contentType, $length, undef);
}

# If an audio stream fails, keep playing
sub handleDirectError {
	my ( $class, $client, $url, $response, $status_line ) = @_;
	
	main::INFOLOG && $log->info("Direct stream failed: $url [$response] $status_line");
	
	$client->controller()->playerStreamingFailed( $client, 'PLUGIN_CLASSICAL_STREAM_FAILED' );
}

sub canDirectStreamSong {
	my ( $class, $client, $song ) = @_;
	
	# We need to check with the base class (HTTP) to see if we
	# are synced or if the user has set mp3StreamingMethod
	return $class->SUPER::canDirectStream( $client, $song->streamUrl(), $class->getFormatForURL() );
}

# Track Info menu
=pod XXX - legacy track info menu from before Slim::Menu::TrackInfo times?
sub trackInfo {
	my ( $class, $client, $track ) = @_;
	
	my $url = $track->url;

	# SN URL to fetch track info menu
	my $trackInfoURL = $class->trackInfoURL( $client, $url );
	
	# let XMLBrowser handle all our display
	my %params = (
		header   => 'PLUGIN_CLASSICAL_GETTING_TRACK_DETAILS',
		modeName => 'Classical Now Playing',
		title    => Slim::Music::Info::getCurrentTitle( $client, $url ),
		url      => $trackInfoURL,
		remember => 0,
		timeout  => 35,
	);

	Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );
	
	$client->modeParam( 'handledTransition', 1 );
}
=cut

# URL used for CLI trackinfo queries
sub trackInfoURL {
	my ( $class, $client, $url ) = @_;
	
	# Get the current track
	if (my $song = $client->currentSongForUrl($url)) {
		my $currentTrack = $song->pluginData();
	
		# SN URL to fetch track info menu
		my $trackInfoURL = Slim::Networking::SqueezeNetwork->url(
			  '/api/classical/v1/opml/trackInfo?trackId=' . $currentTrack->{id}
		);
		
		return $trackInfoURL;
	}
}

# Metadata for a URL, used by CLI/JSON clients
sub getMetadataFor {
	my ( $class, $client, $url ) = @_;
	
	my $icon = $class->getIcon();
	
	return {} unless $url;
	
	my $cache = Slim::Utils::Cache->new;
	
	# If metadata is not here, fetch it so the next poll will include the data
	my ($trackId) = $url =~ m{classical://(.+)\.mp3};
	my $meta      = $cache->get( 'classical_meta_' . $trackId );
	
	if ( !$meta && !$client->master->pluginData('fetchingMeta') ) {
		# Go fetch metadata for all tracks on the playlist without metadata
		my @need;
		
		for my $track ( @{ Slim::Player::Playlist::playList($client) } ) {
			my $trackURL = blessed($track) ? $track->url : $track;
			if ( $trackURL =~ m{classical://(.+)\.mp3} ) {
				my $id = $1;
				if ( !$cache->get("classical_meta_$id") ) {
					push @need, $id;
				}
			}
		}
		
		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug( "Need to fetch metadata for: " . join( ', ', @need ) );
		}
		
		$client->master->pluginData( fetchingMeta => 1 );
		
		my $metaUrl = Slim::Networking::SqueezeNetwork->url(
			"/api/classical/v1/playback/getBulkMetadata"
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
		type      => 'MP3 (Classical.com)',
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
	my $icon  = Slim::Plugin::Classical::Plugin->_pluginDataFor('icon');

	for my $track ( @{$info} ) {
		next unless ref $track eq 'HASH';
		
		# cache the metadata we need for display
		my $meta = {
			artist    => $track->{Composers},
			album     => $track->{Workname},
			title     => $track->{Name},
			cover     => $track->{Coverart},
			duration  => $track->{Length},
			bitrate   => '128k CBR',
			type      => 'MP3 (Classical.com)',
			info_link => 'plugins/classical/trackinfo.html',
			icon      => $icon,
		};
	
		$cache->set( 'classical_meta_' . $track->{id}, $meta, 86400 );
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

	return Slim::Plugin::Classical::Plugin->_pluginDataFor('icon');
}

1;
