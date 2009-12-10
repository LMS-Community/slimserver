package Slim::Plugin::Queen::ProtocolHandler;

# $Id$

# Handler for queen:// URLs

use strict;
use base qw(Slim::Player::Protocols::HTTP);

use JSON::XS::VersionOneAndTwo;
use Scalar::Util qw(blessed);
use URI::Escape qw(uri_escape_utf8);

use Slim::Player::Playlist;
use Slim::Utils::Misc;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.queen',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_QUEEN_MODULE_NAME',
} );

# To support remote streaming (synced players, slimp3/SB1), we need to subclass Protocols::HTTP
sub new {
	my $class  = shift;
	my $args   = shift;

	my $client = $args->{client};
	
	my $song      = $args->{song};
	my $streamUrl = $song->streamUrl() || return;
	my $track     = $song->pluginData();
	
	main::DEBUGLOG && $log->is_debug && $log->debug( 'Remote streaming Queen track: ' . $streamUrl );

	my $sock = $class->SUPER::new( {
		url     => $streamUrl,
		song    => $song,
		client  => $client,
		bitrate => 160_000,
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

sub canSeek { 1 }

sub getNextTrack {
	my ($class, $song, $successCb, $errorCb) = @_;
	
	my $client = $song->master();
	my $url    = $song->currentTrack()->url;
	
	# Get next track
	my ($id) = $url =~ m{^queen://([^\.]+).mp3};
	
	# Talk to SN and get the next track to play
	my $trackURL = Slim::Networking::SqueezeNetwork->url(
		"/api/queen/v1/playback/getMediaURL?trackId=$id"
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
			$log->warn( 'Queen error getting next track: ' . ( $@ || $track->{error} ) );
		}
		
		if ( $client->playingSong() ) {
			$client->playingSong()->pluginData( {
				songName => $@ || $track->{error},
			} );
		}
		
		$http->params->{'errorCallback'}->( 'PLUGIN_QUEEN_NO_INFO', $track->{error} );
		return;
	}
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( 'Got Queen track: ' . Data::Dump::dump($track) );
	}
	
	# Save metadata for this track
	$song->pluginData( $track );
	$song->streamUrl($track->{URL});
	
	# Cache metadata
	my $meta = {
		artist    => $track->{artist},
		album     => $track->{album},
		title     => $track->{title},
		cover     => $track->{cover},
		duration  => $track->{secs},
		bitrate   => '160k CBR',
		type      => 'MP3 (Queen)',
		info_link => 'plugins/queen/trackinfo.html',
		icon      => __PACKAGE__->getIcon(),
	};
	
	my $cache = Slim::Utils::Cache->new;
	$cache->set( 'queen_meta_' . $track->{id}, $meta, 86400 );

	$http->params->{callback}->();
}

sub gotNextTrackError {
	my $http = shift;
	
	$http->params->{errorCallback}->( 'PLUGIN_QUEEN_ERROR', $http->error );
}

sub parseDirectHeaders {
	my $class   = shift;
	my $client  = shift || return;
	my $url     = shift;
	my @headers = @_;
	
	my $song  = $client->streamingSong();
	my $track = $song->pluginData(); 
	
	my $bitrate     = 160_000;
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
	
	$client->streamingSong->duration($track->{secs});
	
	# title, bitrate, metaint, redir, type, length, body
	return (undef, $bitrate, 0, undef, $contentType, $length, undef);
}

# If an audio stream fails, keep playing
sub handleDirectError {
	my ( $class, $client, $url, $response, $status_line ) = @_;
	
	main::INFOLOG && $log->info("Direct stream failed: $url [$response] $status_line");
	
	$client->controller()->playerStreamingFailed( $client, 'PLUGIN_QUEEN_STREAM_FAILED' );
}

sub canDirectStreamSong {
	my ( $class, $client, $song ) = @_;
	
	# We need to check with the base class (HTTP) to see if we
	# are synced or if the user has set mp3StreamingMethod
	return $class->SUPER::canDirectStream( $client, $song->streamUrl(), $class->getFormatForURL() );
}

# Track Info menu
sub trackInfo {
	my ( $class, $client, $track ) = @_;
	
	my $url = $track->url;

	# SN URL to fetch track info menu
	my $trackInfoURL = $class->trackInfoURL( $client, $url );
	
	# let XMLBrowser handle all our display
	my %params = (
		header   => 'PLUGIN_QUEEN_GETTING_TRACK_DETAILS',
		modeName => 'Queen Now Playing',
		title    => Slim::Music::Info::getCurrentTitle( $client, $url ),
		url      => $trackInfoURL,
		remember => 0,
		timeout  => 35,
	);

	Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );
	
	$client->modeParam( 'handledTransition', 1 );
}

# URL used for CLI trackinfo queries
sub trackInfoURL {
	my ( $class, $client, $url ) = @_;
	
	# Get the current track
	my ($trackId) = $url =~ m{queen://(.+)\.mp3};
	
	# SN URL to fetch track info menu
	my $trackInfoURL = Slim::Networking::SqueezeNetwork->url(
		  '/api/queen/v1/opml/trackinfo?trackId=' . $trackId
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
	my ($trackId) = $url =~ m{queen://(.+)\.mp3};
	my $meta      = $cache->get( 'queen_meta_' . $trackId );
		
	return $meta || {
		bitrate   => '160k CBR',
		type      => 'MP3 (Queen)',
		icon      => $icon,
		cover     => Slim::Networking::SqueezeNetwork->url('/static/images/queen/01_cover.jpg'),
	};
}

sub getIcon {
	my ( $class, $url ) = @_;

	return Slim::Plugin::Queen::Plugin->_pluginDataFor('icon');
}

# SN only
# Re-init when a player reconnects
sub reinit { if ( main::SLIM_SERVICE ) {
	my ( $class, $client, $song ) = @_;

	my $url = $song->currentTrack->url();
	
	main::DEBUGLOG && $log->debug("Re-init Queen - $url");

	if ( my $track = $song->pluginData() ) {
		# We have previous data about the currently-playing song
		
		# Back to Now Playing
		Slim::Buttons::Common::pushMode( $client, 'playlist' );
		
		# Reset song duration/progress bar
		if ( $track->{secs} ) {
			# On a timer because $client->currentsongqueue does not exist yet
			Slim::Utils::Timers::setTimer(
				$client,
				Time::HiRes::time(),
				sub {
					my $client = shift;
					
					$client->streamingProgressBar( {
						url      => $url,
						duration => $track->{secs},
					} );
				},
			);
		}
	}
	
	return 1;
} }

1;
