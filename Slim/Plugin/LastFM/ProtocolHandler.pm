package Slim::Plugin::LastFM::ProtocolHandler;

# $Id$

# Handler for lastfm:// URLs

use strict;
use base qw(Slim::Player::Protocols::HTTP);

use JSON::XS qw(from_json);
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
	my $track  = $song->{'pluginData'} || {};
	
	$log->debug( 'Remote streaming Last.fm track: ' . $track->{location} );

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

sub canSeek { 0 }

sub isRepeatingStream {
	return 1;
}

# Source for AudioScrobbler (L = Last.fm)
# Must append trackauth value as well
sub audioScrobblerSource {
	my ( $class, $client, $url ) = @_;
	
	my $track = $client->streamingSong()->{'pluginData'};
	
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
	
	$log->debug("Getting next track from SqueezeNetwork ($trackURL)");
	
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

	if ( $log->is_debug ) {
		$log->debug( 'Got Last.fm track: ' . Data::Dump::dump($track) );
	}
	
	# Watch for playlist commands
	Slim::Control::Request::subscribe( 
		\&playlistCallback, 
		[['playlist'], ['newsong']],
		$client,
	);
	
	# Save metadata for this track
	$params->{'song'}->{'pluginData'} = $track;
	
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
	
	$client->streamingSong->{'duration'} = $length * 8 / $bitrate;
	
	# title, bitrate, metaint, redir, type, length, body
	return (undef, $bitrate, 0, undef, $contentType, $length, undef);
}

# If an audio stream fails, keep playing
sub handleDirectError {
	my ( $class, $client, $url, $response, $status_line ) = @_;
	
	$log->info("Direct stream failed: [$response] $status_line");
	
	$client->controller()->playerStreamingFailed($client, 'PLUGIN_LFM_ERROR', $client->string('PLUGIN_LFM_STREAM_FAILED'));
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
		$log->debug("Last.fm: Skip limit exceeded, disallowing skip");

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
	elsif ( $action eq 'pause' ) {
		# Pausing not allowed, stop instead
		return 0;
	}
	
	return 1;
}

sub canDirectStreamSong {
	my ( $class, $client, $song ) = @_;
	
	my $track = $song->{'pluginData'} || {};
	
	# We need to check with the base class (HTTP) to see if we
	# are synced or if the user has set mp3StreamingMethod
	return $class->SUPER::canDirectStream( $client, $track->{location}, $class->getFormatForURL());
}

sub playlistCallback {
	my $request = shift;
	my $client  = $request->client();
	my $cmd     = $request->getRequest(0);
	my $p1      = $request->getRequest(1);
	
	return unless defined $client;
	
	my $song = $client->playingSong() || return;
	my $url  = $song->currentTrack()->url;
			
	if ($url !~ /^lfm/) {
		$log->debug( "Stopped Last.fm, unsubscribing from playlistCallback" );
		Slim::Control::Request::unsubscribe( \&playlistCallback, $client );
		
		return;
	}
	
	if ( $p1 eq 'newsong' ) {
		
		# A new song has started playing.  We use this to change titles
		my $track = $client->playingSong()->{'pluginData'};
		
		my $title 
			= $track->{title} . ' ' . $client->string('BY') . ' '
			. $track->{creator};
		
		# Some Last.fm tracks don't have albums
		if ( $track->{album} ) {
			$title .= ' ' . $client->string('FROM') . ' ' . $track->{album};
		}
		
		setCurrentTitle( $client, $url, $title );
	}
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
	my $currentTrack = $client->currentSongForUrl($url)->{'pluginData'};
	
	# SN URL to fetch track info menu
	my $trackInfoURL = Slim::Networking::SqueezeNetwork->url(
		  '/api/lastfm/v1/opml/trackinfo?station=' . uri_escape_utf8($station)
		. '&trackId=' . $currentTrack->{identifier}
		. '&account=' . uri_escape_utf8($account)
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
	
	return {
		artist      => $track->{creator},
		album       => $track->{album},
		title       => $track->{title},
		cover       => $track->{image} || $icon,
		icon        => $icon,
		duration    => $track->{secs},
		bitrate     => '128k CBR',
		type        => 'MP3 (' . $client->string('PLUGIN_LFM_MODULE_NAME') . ')',
		info_link   => 'plugins/lastfm/trackinfo.html',
		buttons     => {
			# disable REW/Previous button
			rew => 0,

			# replace repeat with Love
			repeat  => {
				icon    => 'html/images/btn_lastfm_love.gif',
				tooltip => $client->string('PLUGIN_LFM_LOVE'),
				command => [ 'lfm', 'rate', 'L' ],
			},

			# replace shuffle with Ban
			shuffle => {
				icon    => 'html/images/btn_lastfm_ban.gif',
				tooltip => $client->string('PLUGIN_LFM_BAN'),
				command => [ 'lfm', 'rate', 'B' ],
			},
		}
	};
}

sub getIcon {
	my ( $class, $url ) = @_;

	return Slim::Plugin::LastFM::Plugin->_pluginDataFor('icon');
}

# SN only
# Re-init Last.fm when a player reconnects
sub reinit {
	my ( $class, $client, $playlist ) = @_;
	
	my $url = $playlist->[0];
	
	if ( my $track = $client->streamingSong()->{'pluginData'} ) {
		# We have previous data about the currently-playing song
		
		$log->debug("Re-init Last.fm");
		
		# Re-add playlist item
		$client->execute( [ 'playlist', 'add', $url ] );
	
		# Reset track title
		my $title = $track->{title}   . ' ' . $client->string('BY')   . ' '
				  . $track->{creator} . ' ' . $client->string('FROM') . ' '
				  . $track->{album};
				
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
