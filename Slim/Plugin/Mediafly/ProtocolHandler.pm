package Slim::Plugin::Mediafly::ProtocolHandler;

# $Id$

# Handler for mediafly:// URLs

use strict;
use base qw(Slim::Player::Protocols::HTTP);

use JSON::XS::VersionOneAndTwo;
use URI::Escape qw(uri_escape_utf8);

use Slim::Player::Playlist;
use Slim::Utils::Misc;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.mediafly',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_MEDIAFLY_MODULE_NAME',
} );

# To support remote streaming (synced players, slimp3/SB1), we need to subclass Protocols::HTTP
sub new {
	my $class  = shift;
	my $args   = shift;

	my $client = $args->{client};
	
	my $song      = $args->{song};
	my $streamUrl = $song->streamUrl() || return;
	my $track     = $song->pluginData();
	
	main::DEBUGLOG && $log->is_debug && $log->debug( 'Remote streaming Mediafly track: ' . $streamUrl );

	my $sock = $class->SUPER::new( {
		url     => $streamUrl,
		song    => $song,
		client  => $client,
		bitrate => $track ? $track->{bitrate} * 1000 : 128_000,
	} ) || return;
	
	${*$sock}{contentType} = 'audio/mpeg';

	return $sock;
}

sub scanUrl {
	my ($class, $url, $args) = @_;
	$args->{cb}->( $args->{song}->currentTrack() );
}

# Mediafly only gives us MP3 files
sub getFormatForURL () { 'mp3' }

# Don't allow looping if the tracks are short
sub shouldLoop () { 0 }

sub canSeek {
	my ( $class, $client, $song ) = @_;
	
	if ( my $track = $song->pluginData() ) {
		return $track->{canSeek};
	}
	
	return 0;
}

# XXX: correct seek error
sub canSeekError { return ( 'SEEK_ERROR_TYPE_NOT_SUPPORTED', 'Mediafly' ); }

sub isRepeatingStream {
	my ( $class, $song ) = @_;
	
	# Channels repeat, individual episodes do not
	return $song->track()->url =~ m{^mediafly://channel};
}

sub getNextTrack {
	my ($class, $song, $successCb, $errorCb) = @_;
	
	my $client = $song->master();
	my $url    = $song->currentTrack()->url;
	
	# Get next track
	my ($slug) = $url =~ m{^mediafly://([^\?]+)};
	
	# If first track is specified in the URL, use that once
	my ($first) = $url =~ m{\?first=(.+)};
	
	# If we were playing previously, pass the previous slug
	my $firstslug = '';
	my $prevslug = '';
	
	my $playedFirst = $client->master->pluginData('playedFirst') || '';
	
	if ( $first && $playedFirst ne $first ) {
		$firstslug = $first;
	}
	elsif ( my $track = $song->pluginData() ) {
		$prevslug = $track->{slug} || $client->master->pluginData('previousSlug');
	}
	
	# Talk to SN and get the next track to play
	my $trackURL = Slim::Networking::SqueezeNetwork->url(
		"/api/mediafly/v1/playback/getNextTrack?slug=$slug&prevslug=$prevslug&firstslug=$firstslug"
	);
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&gotNextTrack,
		\&gotNextTrackError,
		{
			client        => $client,
			song          => $song,
			playedFirst   => $first,
			callback      => $successCb,
			errorCallback => $errorCb,
			timeout       => 35,
		},
	);
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Getting next track from SqueezeNetwork for $slug");
	
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
			$log->warn( 'Mediafly error getting next track: ' . ( $@ || $track->{error} ) );
		}
		
		if ( $client->playingSong() ) {
			$client->playingSong()->pluginData( {
				songName => $@ || $track->{error},
			} );
		}
		
		$http->params->{'errorCallback'}->( 'PLUGIN_MEDIAFLY_NO_INFO', $track->{error} );
		return;
	}
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( 'Got Mediafly track: ' . Data::Dump::dump($track) );
	}
	
	# If this was a redirect request, change channels
	if ( my $redir = $track->{redirect} ) {
		main::DEBUGLOG && $log->is_debug && $log->debug( 'Redirecting to ' . $redir->{url} );
		
		$http->params->{errorCallback}->('PLUGIN_MEDIAFLY_CHANGING_CHANNELS');
		
		$client->execute( [ 'playlist', 'play', $redir->{url}, $redir->{name} ] );
		return;
	}
	
	# Save metadata for this track
	$song->pluginData( $track );
	$client->master->pluginData( playedFirst => $http->params->{playedFirst} );
	$client->master->pluginData( previousSlug => $track->{slug} );
	$song->streamUrl($track->{url});

	$http->params->{callback}->();
}

sub gotNextTrackError {
	my $http = shift;
	
	$http->params->{errorCallback}->( 'PLUGIN_MEDIAFLY_ERROR', $http->error );
}

sub parseDirectHeaders {
	my $class   = shift;
	my $client  = shift || return;
	my $url     = shift;
	my @headers = @_;
	
	my $song  = $client->streamingSong();
	my $track = $song->pluginData(); 
	
	my $bitrate     = $track->{bitrate} * 1000;
	my $contentType = 'mp3';
	
	my $length;
	my $rangelength;
	
	# Clear previous duration, since we're using the same URL for all tracks
	if ( $url =~ /\.rdr$/ ) {
		Slim::Music::Info::setDuration( $url, 0 );
	}

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
	
	$client->streamingSong->bitrate($bitrate);
	$client->streamingSong->duration($track->{secs});
	
	# Start a timer to post experience every 30 seconds
	Slim::Utils::Timers::killTimers( $client, \&postExperience );
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time() + 30,
		\&postExperience,
		$track->{slug},
	);
	
	# title, bitrate, metaint, redir, type, length, body
	return (undef, $bitrate, 0, undef, $contentType, $length, undef);
}

# If an audio stream fails, keep playing
sub handleDirectError {
	my ( $class, $client, $url, $response, $status_line ) = @_;
	
	main::INFOLOG && $log->info("Direct stream failed: $url [$response] $status_line");
	
	$client->controller()->playerStreamingFailed( $client, 'PLUGIN_MEDIAFLY_STREAM_FAILED' );
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
		header   => 'PLUGIN_MEDIAFLY_GETTING_TRACK_DETAILS',
		modeName => 'Mediafly Now Playing',
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
	my $currentTrack = $client->currentSongForUrl($url)->pluginData();
	
	my $episode     = $currentTrack->{slug};
	my $channelSlug = $currentTrack->{channelSlug};
	my $channelName = $currentTrack->{channel};
	
	# SN URL to fetch track info menu
	my $trackInfoURL = Slim::Networking::SqueezeNetwork->url(
		  '/api/mediafly/v1/opml/trackinfo?episode=' . $episode
		. '&channelSlug=' . $channelSlug 
		. '&channelName=' . uri_escape_utf8($channelName)
	);
	
	return $trackInfoURL;
}

# Metadata for a URL, used by CLI/JSON clients
sub getMetadataFor {
	my ( $class, $client, $url, $forceCurrent ) = @_;
	
	my $song = $forceCurrent ? $client->streamingSong() : $client->playingSong();
	return {} unless $song;
	
	# In episode mode, other tracks on the playlist don't return metadata
	if ( $song->currentTrack()->url ne $url ) {
		return {};
	}
	
	my $icon = $class->getIcon();
	
	if ( my $track = $song->pluginData() ) {
		
		my $date = '';
		($date) = $track->{published} =~ m/^(\d{4}-\d{2}-\d{2})/ if $track->{published};
		
		# bug 15499 - wipe track object's title, it's initially set by Slim::Control::Queries::_songData only
		$song->track->title('') if $song->track->title();

		return {
			artist      => $track->{show}->[0]->{title} || $track->{showTitle},
			title       => $track->{title},
			album       => $date,
			cover       => $track->{imageUrl},
			icon        => $icon,
			duration    => $track->{secs},
			bitrate     => ( $track->{bitrate} ) ? $track->{bitrate} . 'k' : undef,
			type        => 'Mediafly',
			info_link   => 'plugins/mediafly/trackinfo.html',
			buttons       => {
				fwd => 1,
				rew => 1,
			},
		};
	}
	else {
		return {
			icon  => $icon,
			cover => $icon,
			type  => 'Mediafly',
		};
	}
}

sub getIcon {
	my ( $class, $url ) = @_;

	return Slim::Plugin::Mediafly::Plugin->_pluginDataFor('icon');
}

# XXX: this is called more than just when we stop
sub onStop {
	my ($class, $song) = @_;
	
	main::DEBUGLOG && $log->is_debug && $log->debug("onStop, posting experience");
	
	postExperience( $song->master(), $song->pluginData()->{slug} );
}

sub onPlayout {
	my ($class, $song) = @_;
	
	main::DEBUGLOG && $log->is_debug && $log->debug("onPlayout, posting experience");
	
	postExperience( $song->master(), $song->pluginData()->{slug}, 1 );
}

sub postExperience {
	my ( $client, $slug, $end ) = @_;
	
	my $song  = $client->playingSong() || return;
	my $track = $song->pluginData();
	
	# Make sure we haven't changed tracks
	if ( !$track || !$slug || $track->{slug} ne $slug ) {
		main::DEBUGLOG && $log->is_debug && $log->debug( "Not posting experience for $slug, no longer playing" );
		return;
	}
	
	my $time = Slim::Player::Source::songTime( $song->master() );
	
	$time = int($time);
	
	my $length = $track->{secs};
	
	# If at end, set time == length
	if ( $end ) {
		$time = $length;
	}
	
	# Make sure time is not 0, that means we've stopped
	return if $time == 0;
	
	my $logURL = Slim::Networking::SqueezeNetwork->url(
		"/api/mediafly/v1/playback/postExperience?slug=$slug&position=$time&length=$length"
	);

	my $http = Slim::Networking::SqueezeNetwork->new(
		sub {
			if ( main::DEBUGLOG && $log->is_debug ) {
				my $http = shift;
				$log->debug( "Post experience returned: " . $http->content );
			}
		},
		sub {
			if ( main::DEBUGLOG && $log->is_debug ) {
				my $http = shift;
				$log->debug( "Post experience returned error: " . $http->error );
			}
		},
		{
			client => $song->master(),
		},
	);

	main::DEBUGLOG && $log->debug("Posting experience: $time/$length seconds for $slug");

	$http->get( $logURL );
	
	# Post again in 30 seconds unless we're done
	if ( !$end ) {
		main::DEBUGLOG && $log->is_debug && $log->debug( "Will post experience for $slug again in 30 seconds" );
		
		Slim::Utils::Timers::killTimers( $client, \&postExperience );
		Slim::Utils::Timers::setTimer(
			$client,
			Time::HiRes::time() + 30,
			\&postExperience,
			$slug,
		);
	}
}

# SN only
# Re-init Mediafly when a player reconnects
sub reinit {
	my ( $class, $client, $song ) = @_;

	my $url = $song->currentTrack->url();
	
	main::DEBUGLOG && $log->debug("Re-init Mediafly - $url");

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
	else {
		# No data, just restart the current station
		main::DEBUGLOG && $log->debug("No data about playing track, restarting station");

		$client->execute( [ 'playlist', 'play', $url ] );
	}
	
	return 1;
}

1;
