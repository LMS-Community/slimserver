package Slim::Plugin::Pandora::ProtocolHandler;

# $Id: ProtocolHandler.pm 11678 2007-03-27 14:39:22Z andy $

# Handler for pandora:// URLs

use strict;
use base qw(Slim::Player::Protocols::HTTP);

use JSON::XS::VersionOneAndTwo;

use Slim::Player::Playlist;
use Slim::Utils::Misc;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.pandora',
	'defaultLevel' => $ENV{PANDORA_DEV} ? 'DEBUG' : 'ERROR',
	'description'  => 'PLUGIN_PANDORA_MODULE_NAME',
});

# default artwork URL if an album has no art
my $defaultArtURL = 'http://www.pandora.com/images/no_album_art.jpg';

# max time player may be idle before stopping playback (8 hours)
my $MAX_IDLE_TIME = 60 * 60 * 8;

# To support remote streaming (synced players, slimp3/SB1), we need to subclass Protocols::HTTP
sub new {
	my $class  = shift;
	my $args   = shift;

	my $client = $args->{client};
	
	my $song      = $args->{'song'};
	my $streamUrl = $song->streamUrl() || return;
	
	main::DEBUGLOG && $log->debug( 'Remote streaming Pandora track: ' . $streamUrl );

	my $sock = $class->SUPER::new( {
		url     => $streamUrl,
		song    => $args->{'song'},
		client  => $client,
		bitrate => 128_000,
	} ) || return;
	
	${*$sock}{contentType} = 'audio/mpeg';

	return $sock;
}

sub scanUrl {
	my ($class, $url, $args) = @_;
	$args->{'cb'}->($args->{'song'}->currentTrack());
}

sub getFormatForURL () { 'mp3' }

# Don't allow looping if the tracks are short
sub shouldLoop () { 0 }

sub canSeek {
	my ( $class, $client, $song ) = @_;
	
	if ( my $track = $song->pluginData() ) {
		if ( delete $track->{_allowSeek} ) {
			return 1;
		}
	}
	
	return 0;
}

sub canSeekError { return ( 'SEEK_ERROR_TYPE_NOT_SUPPORTED', 'Pandora' ); }

sub isRepeatingStream { 1 }

# Source for AudioScrobbler (E = Personalised recommendation except Last.fm)
sub audioScrobblerSource () { 'E' }

# If either the previous or current track is an ad, disable transitions
sub transitionType {
	my ( $class, $client, $song, $transitionType ) = @_;
	
	# Ignore if transitionType is already 0
	return if $transitionType == 0;
	
	my $playingSong = $client->playingSong();
	
	# Ignore if we don't have 2 songs to compare
	return unless $song && $playingSong && $song ne $playingSong;
	
	if ( $song->pluginData->{ad} || $playingSong->pluginData->{ad} ) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Disabling transition because of audio ad');
		return 0;
	}

	return;
}

sub getNextTrack {
	my ($class, $song, $successCb, $errorCb) = @_;
	
	my $client = $song->master();
	my $url    = $song->track()->url;
	
	# Get next track
	my ($stationId) = $url =~ m{^pandora://([^.]+)\.mp3};
	
	# If the user was playing a different Pandora station, report a stationChange event
	my $prevStation = $client->master->pluginData('station');
	
	if ( $prevStation && $prevStation ne $stationId ) {
		my $snURL = Slim::Networking::SqueezeNetwork->url(
			  '/api/pandora/v1/playback/stationChange?stationId=' . $prevStation 
			. '&trackId=' . $client->master->pluginData('trackToken')
		);
		my $http = Slim::Networking::SqueezeNetwork->new(
			sub {},
			sub {},
			{
				client  => $client,
				timeout => 35,
			},
		);

		main::DEBUGLOG && $log->debug('Reporting station change to SqueezeNetwork');
		$http->get( $snURL );
	}

	$client->master->pluginData(station => $stationId);

	# If playing and idle time has been exceeded, stop playback
	if ( $client->isPlaying() ) {
		my $lastActivity = $client->lastActivityTime();
	
		# If synced, check slave players to see if they have newer activity time
		if ( $client->isSynced(1) ) {
			for my $c ( $client->syncGroupActiveMembers() ) {
				my $slaveActivity = $c->lastActivityTime();
				if ( $slaveActivity > $lastActivity ) {
					$lastActivity = $slaveActivity;
				}
			}
		}
	
		if ( time() - $lastActivity >= $MAX_IDLE_TIME ) {
			main::DEBUGLOG && $log->debug('Idle time reached, stopping playback');
			
			$client->playingSong()->pluginData( {
				songName => $client->string('PLUGIN_PANDORA_IDLE_STOPPING'),
			} );
			
			$errorCb->('PLUGIN_PANDORA_IDLE_STOPPING');
			return;
		}
	}
	
	# Talk to SN and get the next track to play
	my $trackURL = Slim::Networking::SqueezeNetwork->url(
		"/api/pandora/v1/playback/getNextTrack?stationId=$stationId"
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
	
	main::DEBUGLOG && $log->debug("Getting next track from SqueezeNetwork for stationid=$stationId");
	
	$http->get( $trackURL );
}

sub gotNextTrack {
	my $http   = shift;
	my $client = $http->params->{client};
	my $song   = $http->params->{'song'};	
	my $track  = eval { from_json( $http->content ) };
	
	if ( $@ || $track->{error} ) {
		# We didn't get the next track to play
		if ( $log->is_warn ) {
			$log->warn( 'Pandora error getting next track: ' . ( $@ || $track->{error} ) );
		}
		
		$client->playingSong()->pluginData( {
			songName => $track->{error} || $client->string('PLUGIN_PANDORA_NO_TRACKS'),
		} );
		
		$http->params->{'errorCallback'}->('PLUGIN_PANDORA_NO_TRACKS', $track->{error});
		return;
	}
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( 'Got Pandora track: ' . Data::Dump::dump($track) );
	}
	
	# Save metadata for this track
	$song->duration( $track->{secs} );
	$song->pluginData( $track );
	$song->streamUrl($track->{'audioUrl'});
	$client->master->pluginData('trackToken' => $track->{'trackToken'});
	
	# Bug 8781, Seek if instructed by SN
	# This happens when the skip limit is reached and the station has been stopped and restarted.
	if ( $track->{startOffset} ) {
		# Trigger the seek after the callback
		Slim::Utils::Timers::setTimer(
			undef,
			time(),
			sub {
				$client->controller()->jumpToTime( $track->{startOffset} );
				
				# Fix progress bar
				$client->streamingProgressBar( {
					url      => Slim::Player::Playlist::url($client),
					duration => $track->{secs},
				} );
			},
		);
	}

	$http->params->{'callback'}->();
}

sub gotNextTrackError {
	my $http   = shift;
	
	$http->params->{'errorCallback'}->('PLUGIN_PANDORA_ERROR', $http->error);
}

sub getSeekData {
	my ( $class, $client, $song, $newtime ) = @_;
	
	return {
		sourceStreamOffset => ( 128_000 / 8 ) * $newtime,
		timeOffset         => $newtime,
	};
}

sub parseDirectHeaders {
	my $class   = shift;
	my $client  = shift || return;
	my $url     = shift;
	my @headers = @_;
	
	my $bitrate     = 128_000;
	my $contentType = 'mp3';
	
	# Clear previous duration, since we're using the same URL for all tracks
	Slim::Music::Info::setDuration( $url, 0 );
	
	# Grab content-length for progress bar
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
	
	$client->streamingSong->bitrate($bitrate);
	$client->streamingSong->duration( $client->streamingSong->pluginData()->{secs} );
	
	# title, bitrate, metaint, redir, type, length, body
	return (undef, $bitrate, 0, undef, $contentType, $length, undef);
}

# If an audio stream fails, keep playing
sub handleDirectError {
	my ( $class, $client, $url, $response, $status_line ) = @_;
	
	main::INFOLOG && $log->info("Direct stream failed: $url [$response] $status_line");
		
	# Report the audio failure to Pandora
	my $song         = $client->streamingSong();
	my ($stationId)  = $song->track()->url =~ m{^pandora://([^.]+)\.mp3};

	my $snURL = Slim::Networking::SqueezeNetwork->url(
		  '/api/pandora/v1/opml/playback/audioError?stationId=' . $stationId 
		. '&trackId=' . $song->pluginData('trackToken')
	);
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		sub {},
		sub {},
		{
			client  => $client,
			timeout => 35,
		},
	);
	
	$http->get( $snURL );
	
	$client->controller()->playerStreamingFailed($client, 'PLUGIN_PANDORA_STREAM_FAILED');
}

# Check if player is allowed to skip, using canSkip value from SN
sub canSkip {
	my $client = shift;
	
	if ( my $track = $client->playingSong->pluginData() ) {
		return $track->{canSkip};
	}
	
	return 1;
}	

# Disallow skips after the limit is reached
sub canDoAction {
	my ( $class, $client, $url, $action ) = @_;
	
	# Bug 10488
	if ( $action eq 'rew' ) {
		# Bug 15763, if this is a special seek request due to startOffset, allow it
		if ( my $track = $client->playingSong->pluginData() ) {
			if ( $track->{startOffset} ) {
				# Set a temporary variable so canSeek can return 1, this is needed
				# to prevent general seeking in tracks with startOffset
				$track->{_allowSeek} = 1;
				
				return 1;
			}
		}
		
		return 0;
	}
	
	if ( $action eq 'stop' && !canSkip($client) ) {
		# Is skip allowed?
		main::DEBUGLOG && $log->debug("Pandora: Skip limit exceeded, disallowing skip");
		
		my $track = $client->playingSong->pluginData();
		return 0 if $track->{ad};
		
		my $line1 = $client->string('PLUGIN_PANDORA_ERROR');
		my $line2 = $client->string('PLUGIN_PANDORA_SKIPS_EXCEEDED');
		
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

sub canDirectStreamSong {
	my ( $class, $client, $song ) = @_;
	
	# We need to check with the base class (HTTP) to see if we
	# are synced or if the user has set mp3StreamingMethod
	return $class->SUPER::canDirectStream($client, $song->streamUrl(), $class->getFormatForURL());
}

# Override replaygain to always use the supplied gain value
sub trackGain {
	my ( $class, $client, $url ) = @_;
	
	my $gain = $client->streamingSong()->pluginData('trackGain') || 0;
	
	main::INFOLOG && $log->info("Using replaygain value of $gain for Pandora track");
	
	return $gain;
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
		header   => 'PLUGIN_PANDORA_GETTING_TRACK_DETAILS',
		modeName => 'Pandora Now Playing',
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

	my ($stationId) = $url =~ m{^pandora://([^.]+)\.mp3};
	
	# Get the current track
	my $trackToken;
	if ( my $currentSong = $client->currentSongForUrl($url) ) {
		if ( my $currentTrack = $currentSong->pluginData() ) {
			$trackToken = $currentTrack->{trackToken};
		}
	}		
	
	# SN URL to fetch track info menu
	my $trackInfoURL = Slim::Networking::SqueezeNetwork->url(
		  '/api/pandora/v1/opml/trackinfo?stationId=' . $stationId 
		. '&trackId=' . $trackToken
	);
	
	return $trackInfoURL;
}

# Metadata for a URL, used by CLI/JSON clients
sub getMetadataFor {
	my ( $class, $client, $url, $forceCurrent ) = @_;
	
	my $song = $forceCurrent ? $client->streamingSong() : $client->playingSong();
	return {} unless $song;
	
	my $icon = $class->getIcon();
	
	# Could be somewhere else in the playlist
	if ($song->track->url ne $url) {
		main::DEBUGLOG && $log->debug($url);
		return {
			icon    => $icon,
			cover   => $icon,
			bitrate => '128k CBR',
			type    => 'MP3 (Pandora)',
			title   => 'Pandora',
			album   => Slim::Music::Info::standardTitle( $client, $url, undef ),
		};
	}
	
	my $track = $song->pluginData();
	if ( $track && %$track ) {
		return {
			artist      => $track->{artistName},
			album       => $track->{albumName},
			title       => $track->{songName},
			cover       => $track->{albumArtUrl} || $defaultArtURL,
			icon        => $icon,
			replay_gain => $track->{trackGain},
			duration    => $track->{secs},
			bitrate     => '128k CBR',
			type        => 'MP3 (Pandora)',
			info_link   => 'plugins/pandora/trackinfo.html',
			buttons     => {
				# disable REW/Previous button
				rew => 0,
				# disable FWD when you've reached skip limit
				fwd => canSkip($client) ? 1 : 0,
				# replace repeat with Thumbs Up
				repeat  => {
					icon    => 'html/images/btn_thumbs_up.gif',
					jiveStyle => $track->{allowFeedback} ? 'thumbsUp' : 'thumbsUpDisabled',
					tooltip => $client->string('PLUGIN_PANDORA_I_LIKE'),
					command => $track->{allowFeedback} ? [ 'pandora', 'rate', 1 ] : [ 'jivedummycommand' ],
				},

				# replace shuffle with Thumbs Down
				shuffle => {
					icon    => 'html/images/btn_thumbs_down.gif',
					jiveStyle => $track->{allowFeedback} ? 'thumbsDown' : 'thumbsDownDisabled',
					tooltip => $client->string('PLUGIN_PANDORA_I_DONT_LIKE'),
					command => $track->{allowFeedback} ? [ 'pandora', 'rate', 0 ] : [ 'jivedummycommand' ],
				},
			}
		};
	}
	else {
		return {
			icon    => $icon,
			cover   => $icon,
			bitrate => '128k CBR',
			type    => 'MP3 (Pandora)',
			title   => $song->track()->title(),
		};
	}
}

sub getIcon {
	my ( $class, $url ) = @_;

	return Slim::Plugin::Pandora::Plugin->_pluginDataFor('icon');
}

1;
