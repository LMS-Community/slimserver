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
	my $streamUrl = $song->{'streamUrl'} || return;
	
	$log->debug( 'Remote streaming Pandora track: ' . $streamUrl );

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

sub canSeek { 0 }

sub isRepeatingStream { 1 }

# Source for AudioScrobbler (E = Personalised recommendation except Last.fm)
sub audioScrobblerSource () { 'E' }

sub getNextTrack {
	my ($class, $song, $successCb, $errorCb) = @_;
	
	my $client = $song->master();
	my $url    = $song->currentTrack()->url;
	
	# Get next track
	my ($stationId) = $url =~ m{^pandora://([^.]+)\.mp3};
	
	# If the user was playing a different Pandora station, report a stationChange event
	my $prevStation = $client->pluginData('station');
	
	if ( $prevStation && $prevStation ne $stationId ) {
		my $snURL = Slim::Networking::SqueezeNetwork->url(
			  '/api/pandora/v1/playback/stationChange?stationId=' . $prevStation 
			. '&trackId=' . $client->pluginData('trackToken')
		);
		my $http = Slim::Networking::SqueezeNetwork->new(
			sub {},
			sub {},
			{
				client  => $client,
				timeout => 35,
			},
		);

		$log->debug('Reporting station change to SqueezeNetwork');
		$http->get( $snURL );
	}

	$client->pluginData(station => $stationId);

	# If playing and idle time has been exceeded, stop playback
	if ( $client->isPlaying() ) {
		my $lastActivity = $client->lastActivityTime();
	
		# If synced, check slave players to see if they have newer activity time
		if ( $client->isSynced() ) {
			for my $c ( $client->syncGroupActiveMembers() ) {
				my $slaveActivity = $c->lastActivityTime();
				if ( $slaveActivity > $lastActivity ) {
					$lastActivity = $slaveActivity;
				}
			}
		}
	
		if ( time() - $lastActivity >= $MAX_IDLE_TIME ) {
			$log->debug('Idle time reached, stopping playback');
			setCurrentTitle( $client, $url, $client->string('PLUGIN_PANDORA_IDLE_STOPPING') );
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
	
	$log->debug("Getting next track from SqueezeNetwork for stationid=$stationId");
	
	$http->get( $trackURL );
}

sub gotNextTrack {
	my $http   = shift;
	my $client = $http->params->{client};
	my $song   = $http->params->{'song'};	
	my $url    = $song->currentTrack()->url;
	my $track  = eval { from_json( $http->content ) };
	
	if ( $@ || $track->{error} ) {
		# We didn't get the next track to play
		if ( $log->is_warn ) {
			$log->warn( 'Pandora error getting next track: ' . ( $@ || $track->{error} ) );
		}
		
		setCurrentTitle( $client, $url, $track->{error} || $client->string('PLUGIN_PANDORA_NO_TRACKS') );
		$http->params->{'errorCallback'}->('PLUGIN_PANDORA_NO_TRACKS', $track->{error});
		return;
	}
	
	if ( $log->is_debug ) {
		$log->debug( 'Got Pandora track: ' . Data::Dump::dump($track) );
	}
	
	# Watch for playlist commands for this client only
	Slim::Control::Request::subscribe( 
		\&playlistCallback, 
		[['playlist'], ['newsong']],
		$client,
	);
	
	# Save metadata for this track
	$song->{'pluginData'} = $track;
	$song->{'streamUrl'}  = $track->{'audioUrl'};
	$client->pluginData('trackToken' => $track->{'trackToken'});
	
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

	if ( main::SLIM_SERVICE ) {
	    logError( $http->params->{'client'}, $http->error );
	}
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
	foreach my $header (@headers) {
		if ( $header =~ /^Content-Length:\s*(.*)/i ) {
			$length = $1;
			last;
		}
	}
	
	$client->streamingSong->{'bitrate'} = $bitrate;
	$client->streamingSong->{'duration'} = $length * 8 / $bitrate; 
	
	# title, bitrate, metaint, redir, type, length, body
	return (undef, $bitrate, 0, undef, $contentType, $length, undef);
}

# If an audio stream fails, keep playing
sub handleDirectError {
	my ( $class, $client, $url, $response, $status_line ) = @_;
	
	$log->info("Direct stream failed: $url [$response] $status_line");
		
	# Report the audio failure to Pandora
	my $song         = $client->streamingSong();
	my ($stationId)  = $song->currentTrack()->url =~ m{^pandora://([^.]+)\.mp3};

	my $snURL = Slim::Networking::SqueezeNetwork->url(
		  '/api/pandora/v1/opml/playback/audioError?stationId=' . $stationId 
		. '&trackId=' . $song->{'pluginData'}->{trackToken}
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
	
	if ( main::SLIM_SERVICE ) {
		SDI::Service::EventLog->log(
			$client, 'pandora_error', "[$response] $status_line",
		);
	}
	
	$client->controller()->playerStreamingFailed($client, 'PLUGIN_PANDORA_STREAM_FAILED');
}

# Check if player is allowed to skip, using canSkip value from SN
sub canSkip {
	my $client = shift;
	
	if ( my $track = $client->playingSong->{'pluginData'} ) {
		return $track->{canSkip};
	}
	
	return 1;
}	

# Disallow skips after the limit is reached
sub canDoAction {
	my ( $class, $client, $url, $action ) = @_;
	
	if ( $action eq 'stop' && !canSkip($client) ) {
		# Is skip allowed?
		$log->debug("Pandora: Skip limit exceeded, disallowing skip");
		
		my $track = $client->playingSong->{'pluginData'};
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
	return $class->SUPER::canDirectStream($client, $song->{'streamUrl'}, $class->getFormatForURL());
}

sub playlistCallback {
	my $request = shift;
	my $client  = $request->client();
	my $cmd     = $request->getRequest(0);
	my $p1      = $request->getRequest(1);
	
	return unless defined $client;
	
	my $song = $client->playingSong() || return;
	my $url  = $song->currentTrack()->url;
	
	if ( !$url || $url !~ /^pandora/ ) {
		# User stopped playing Pandora
		$log->debug( "Stopped Pandora, unsubscribing from playlistCallback" );
		Slim::Control::Request::unsubscribe( \&playlistCallback, $client );
		
		return;
	}
	
	$log->debug("Got playlist event: $p1");
	
	if ( $p1 eq 'newsong' ) {
		# A new song has started playing.  We use this to change titles
		my $track = $song->{'pluginData'};
		
		my $title 
			= $track->{songName} . ' ' . $client->string('BY') . ' '
			. $track->{artistName} . ' ' . $client->string('FROM') . ' '
			. $track->{albumName};
		
		setCurrentTitle( $client, $url, $title );		
	}
}

# Override replaygain to always use the supplied gain value
sub trackGain {
	my ( $class, $client, $url ) = @_;
	
	my $gain = $client->streamingSong()->{'pluginData'}->{trackGain} || 0;
	
	$log->info("Using replaygain value of $gain for Pandora track");
	
	return $gain;
}

# Track Info menu
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

# URL used for CLI trackinfo queries
sub trackInfoURL {
	my ( $class, $client, $url ) = @_;

	my ($stationId) = $url =~ m{^pandora://([^.]+)\.mp3};
	
	# Get the current track
	my $currentTrack = $client->currentSongForUrl($url)->{'pluginData'};
	
	# SN URL to fetch track info menu
	my $trackInfoURL = Slim::Networking::SqueezeNetwork->url(
		  '/api/pandora/v1/opml/trackinfo?stationId=' . $stationId 
		. '&trackId=' . $currentTrack->{trackToken}
	);
	
	return $trackInfoURL;
}

sub setCurrentTitle {
	my ( $client, $url, $title ) = @_;
	
	# We can't use the normal getCurrentTitle method because it would cause multiple
	# players playing the same station to get the same titles
	$client->currentSongForUrl($url)->{'currentTitle'} = $title;
	
	# Call the normal setCurrentTitle method anyway, so it triggers callbacks to
	# update the display
	Slim::Music::Info::setCurrentTitle( $url, $title );
}

sub getCurrentTitle {
	my ( $class, $client, $url ) = @_;
	
	return $client->currentSongForUrl($url)->{'currentTitle'};
}

# Metadata for a URL, used by CLI/JSON clients
sub getMetadataFor {
	my ( $class, $client, $url, $forceCurrent ) = @_;
	
	my $song = $forceCurrent ? $client->streamingSong() : $client->playingSong();
	return unless $song;
	
	my $track = $song->{'pluginData'} || return;
	
	my $icon = $class->getIcon();
	
	if ( $track ) {
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

				# replace repeat with Thumbs Up
				repeat  => {
					icon    => 'html/images/btn_thumbs_up.gif',
					tooltip => Slim::Utils::Strings::string('PLUGIN_PANDORA_I_LIKE'),
					command => [ 'pandora', 'rate', 1 ],
				},

				# replace shuffle with Thumbs Down
				shuffle => {
					icon    => 'html/images/btn_thumbs_down.gif',
					tooltip => Slim::Utils::Strings::string('PLUGIN_PANDORA_I_DONT_LIKE'),
					command => [ 'pandora', 'rate', 0 ],
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
		};
	}
}

sub getIcon {
	my ( $class, $url ) = @_;

	return Slim::Plugin::Pandora::Plugin->_pluginDataFor('icon');
}

# SN only
# Re-init Pandora when a player reconnects
sub reinit {
	my ( $class, $client, $playlist ) = @_;
	
	my $url = $playlist->[0];
	
	if ( my $track = $client->pluginData('currentTrack') ) {
		# We have previous data about the currently-playing song
		
		$log->debug("Re-init Pandora");
		
		# Re-add playlist item
		$client->execute( [ 'playlist', 'add', $url ] );
	
		# Reset track title
		my $title = $track->{songName}   . ' ' . $client->string('BY')   . ' '
				  . $track->{artistName} . ' ' . $client->string('FROM') . ' '
				  . $track->{albumName};
				
		setCurrentTitle( $client, $url, $title );
		
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
		$log->debug("No data about playing track, restarting station");

		$client->execute( [ 'playlist', 'play', $url ] );
	}
	
	return 1;
}

1;
