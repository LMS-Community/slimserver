package Slim::Plugin::LastFM::ProtocolHandler;

# $Id$

# Handler for lastfm:// URLs

use strict;
use base qw(Slim::Player::Protocols::HTTP);

use JSON::XS::VersionOneAndTwo;
use URI::Escape qw(uri_escape_utf8);

use Slim::Player::Playlist;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.lfm',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_LFM_MODULE_NAME',
} );

my $prefs = preferences('plugin.audioscrobbler');

# To support remote streaming (synced players, slimp3/SB1), we need to subclass Protocols::HTTP
sub new {
	my $class  = shift;
	my $args   = shift;

	my $song   = $args->{'song'};
	my $track  = $song->pluginData() || {};
	
	main::DEBUGLOG && $log->debug( 'Remote streaming Last.fm track: ' . $track->{location} );

	return unless $track->{location};

	my $sock = $class->SUPER::new( {
		url     => $track->{location},
		client  => $args->{client},
		song    => $song,
		bitrate => 128_000,
	} ) || return;
	
	${*$sock}{contentType} = 'audio/mpeg';

	return $sock;
}

sub getFormatForURL () { 'mp3' }

sub isAudioURL () { 1 }

# Don't allow looping if the tracks are short
sub shouldLoop () { 0 }

sub usePlayerProxyStreaming { 1 } # 1 => player-proxy-streaming necessary for sync

sub canSeek { 0 }
sub getSeekDataByPosition { undef }
sub getSeekData { undef }

sub isRepeatingStream {
	return 1;
}

# Source for AudioScrobbler (L = Last.fm)
# Must append trackauth value as well
sub audioScrobblerSource {
	my ( $class, $client, $url ) = @_;
	
	my $track = $client->streamingSong()->pluginData();
	
	if ( $track ) {
		return 'L' . $track->{extension}->{trackauth};
	}
	
	return;
}

sub logError {
	my ( $client, $error ) = @_;
	
	SDI::Service::EventLog->log( 
		$client, 'lastfm_error', $error,
	);
}

sub scanUrl {
	my ($class, $url, $args) = @_;
	$args->{'cb'}->($args->{'song'}->currentTrack());
}

sub getNextTrack {
	my ($class, $song, $successCb, $errorCb) = @_;
	
	my $client = $song->master();

	# Get Scrobbling prefs
	my $enable_scrobbling;
	if ( main::SLIM_SERVICE ) {
		$enable_scrobbling = $prefs->client($client)->get('enable_scrobbling');
	}
	else {
		$enable_scrobbling = $prefs->get('enable_scrobbling');
	}
	
	my $account      = $prefs->client($client)->get('account');
	my $isScrobbling = ( $account && $enable_scrobbling ) ? 1 : 0;
	my $discovery    = $prefs->client($client)->get('discovery') || 0;
	
	my ($station) = $song->currentTrack()->url =~ m{^lfm://(.+)};
	
	# Talk to SN and get the next track to play
	my $trackURL = Slim::Networking::SqueezeNetwork->url(
		"/api/lastfm/v1/playback/getNextTrack?station=" . uri_escape_utf8($station)
		. "&isScrobbling=$isScrobbling"
		. "&discovery=$discovery"
		. "&account=" . uri_escape_utf8($account)
	);
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&_gotNextTrack,
		\&_gotNextTrackError,
		{
			client  => $client,
			params  => {
				station       => $station,
				song          => $song,
				callback      => $successCb,
				errorCallback => $errorCb,
			},
			timeout => 35,
		},
	);
	
	main::DEBUGLOG && $log->debug("Getting next track from SqueezeNetwork ($trackURL)");
	
	$http->get( $trackURL );
}

sub _gotNextTrack {
	my $http   = shift;
	my $client = $http->params->{client};
	my $params = $http->params->{params};
	
	my $track = eval { from_json( $http->content ) };
	
	if ( $@ || $track->{error} ) {
		# We didn't get the info to play		
		if ( $log->is_warn ) {
			$log->warn( 'Last.fm error getting next track: ' . ( $@ || $track->{error} ) );
		}

		my $title = $track->{error} || $client->string('PLUGIN_LFM_NO_TRACKS');
		$params->{'errorCallback'}->('PLUGIN_LFM_MODULE_NAME', $title);
		return;
	}

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( 'Got Last.fm track: ' . Data::Dump::dump($track) );
	}
	
	# Save metadata for this track
	$params->{'song'}->pluginData($track);
	
	$params->{'callback'}->();
}

sub _gotNextTrackError {
	my $http   = shift;
	
	$http->params->{'params'}->{'errorCallback'}->('PLUGIN_LFM_ERROR', $http->error);

	if ( main::SLIM_SERVICE ) {
	    logError( $http->params('client'), $http->error );
	}
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
		}
	}	
	
	$client->streamingSong->duration($length * 8 / $bitrate);
	
	# title, bitrate, metaint, redir, type, length, body
	return (undef, $bitrate, 0, undef, $contentType, $length, undef);
}

# If an audio stream fails, keep playing
sub handleDirectError {
	my ( $class, $client, $url, $response, $status_line ) = @_;
	
	main::INFOLOG && $log->info("Direct stream failed: [$response] $status_line");
	
	$client->controller()->playerStreamingFailed($client, 'PLUGIN_LFM_ERROR', $client->string('PLUGIN_LFM_STREAM_FAILED'));
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
		return 0;
	}

	if ( $action eq 'stop' && !canSkip($client) ) {
		# Is skip allowed?
		main::DEBUGLOG && $log->debug("Last.fm: Skip limit exceeded, disallowing skip");

		my $line1 = $client->string('PLUGIN_LFM_MODULE_NAME');
		my $line2 = $client->string('PLUGIN_LFM_SKIPS_EXCEEDED');

		$client->showBriefly( {
			line1 => $line1,
			line2 => $line2,
			jive  => {
				type => 'popupplay',
				text => [ $line1, $line2 ],
			},
			
		},
		{
			scroll => 1,
			block  => 1,
		} );
				
		return 0;
	}
	
	return 1;
}

sub canDirectStreamSong {
	my ( $class, $client, $song ) = @_;
	
	my $track = $song->pluginData() || {};
	
	# We need to check with the base class (HTTP) to see if we
	# are synced or if the user has set mp3StreamingMethod
	return $class->SUPER::canDirectStream( $client, $track->{location}, $class->getFormatForURL());
}

# Track Info menu
sub trackInfo {
	my ( $class, $client, $track ) = @_;
	
	my $url = $track->url;
	
	# SN URL to fetch track info menu
	my $trackInfoURL = $class->trackInfoURL( $client, $url );
	
	# let XMLBrowser handle all our display
	my %params = (
		header   => 'PLUGIN_LFM_GETTING_TRACK_DETAILS',
		modeName => 'Last.fm Now Playing',
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
	
	my ($station) = $url =~ m{^lfm://(.+)};
	
	my $account = $prefs->client($client)->get('account');
	
	# Get the current track
	my $currentTrack = $client->currentSongForUrl($url)->pluginData();
	
	# SN URL to fetch track info menu
	my $trackInfoURL = Slim::Networking::SqueezeNetwork->url(
		  '/api/lastfm/v1/opml/trackinfo?station=' . uri_escape_utf8($station)
		. '&trackId=' . $currentTrack->{identifier}
		. '&account=' . uri_escape_utf8($account)
	);
	
	return $trackInfoURL;
}

# Metadata for a URL, used by CLI/JSON clients
sub getMetadataFor {
	my ( $class, $client, $url, $forceCurrent ) = @_;
	
	my $song = $forceCurrent ? $client->streamingSong() : $client->playingSong();
	return {} unless $song;
	
	my $icon = $class->getIcon();
	my $name = $client->string('PLUGIN_LFM_MODULE_NAME');
	
	# Could be somewhere else in the playlist
	if ($song->track->url ne $url) {
		$log->error("$url: ");
		return {
			icon    => $icon,
			cover   => $icon,
			bitrate => '128k CBR',
			type    => 'MP3 (' . $name . ')',
			title   => $name,
			album   => Slim::Music::Info::standardTitle( $client, $url, undef ),
		};
	}
	
	my $track = $song->pluginData();
	if ( $track && %$track ) {
		return {
			artist      => $track->{creator},
			album       => $track->{album},
			title       => $track->{title},
			cover       => $track->{image} || $icon,
			icon        => $icon,
			duration    => $track->{secs},
			bitrate     => '128k CBR',
			type        => 'MP3 (' . $name . ')',
			info_link   => 'plugins/lastfm/trackinfo.html',
			buttons     => {
				# disable REW/Previous button
				rew => 0,
				# disable FWD when you've reached skip limit
				fwd => canSkip($client) ? 1 : 0,

				# replace repeat with Love
				repeat  => {
					icon    => main::SLIM_SERVICE ? 'static/images/playerControl/love_button.png' : 'html/images/btn_lastfm_love.gif',
					jiveStyle => 'love',
					tooltip => $client->string('PLUGIN_LFM_LOVE'),
					command => [ 'lfm', 'rate', 'L' ],
				},

				# replace shuffle with Ban
				shuffle => {
					icon    => main::SLIM_SERVICE ? 'static/images/playerControl/ban_button.png' : 'html/images/btn_lastfm_ban.gif',
					jiveStyle => 'hate',
					tooltip => $client->string('PLUGIN_LFM_BAN'),
					command => [ 'lfm', 'rate', 'B' ],
				},
			}
		};
	}
	else {
		return {
			icon    => $icon,
			cover   => $icon,
			bitrate => '128k CBR',
			type    => 'MP3 (' . $name . ')',
			title   => $song->track()->title(),
		};
	}
}

sub getIcon {
	my ( $class, $url ) = @_;

	return Slim::Plugin::LastFM::Plugin->_pluginDataFor('icon');
}

# SN only
# Re-init Last.fm when a player reconnects
sub reinit {
	my ( $class, $client, $song ) = @_;
	
	if ( my $track = $song->pluginData() ) {
		# We have previous data about the currently-playing song
		
		main::DEBUGLOG && $log->debug("Re-init Last.fm");
		
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
						url      => $song->currentTrack->url(),
						duration => $track->{secs},
					} );
				},
			);
		}
	}
	else {
		# No data, just restart the current station
		main::DEBUGLOG && $log->debug("No data about playing track, restarting station");

		$client->execute( [ 'playlist', 'play', $song->currentTrack->url() ] );
	}
	
	return 1;
}

1;
