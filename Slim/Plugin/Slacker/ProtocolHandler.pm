package Slim::Plugin::Slacker::ProtocolHandler;

# $Id$

use strict;
use base qw(Slim::Player::Protocols::HTTP);

use Slim::Music::Info;
use Slim::Utils::Misc;
use Slim::Utils::Timers;

use JSON::XS qw(from_json);

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.slacker',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_SLACKER_MODULE_NAME',
} );

# To support remote streaming (synced players, slimp3/SB1), we need to subclass Protocols::HTTP
# XXX: needs testing in SqueezeCenter
sub new {
	my $class  = shift;
	my $args   = shift;

	my $client = $args->{client};
	my $url    = $args->{url};
	
	my $track  = $client->pluginData('currentTrack') || {};
	
	$log->debug( 'Remote streaming Slacker track: ' . $track->{URL} );

	return unless $track->{URL};

	my $sock = $class->SUPER::new( {
		url     => $track->{URL},
		client  => $client,
		bitrate => 128_000,
	} ) || return;
	
	${*$sock}{contentType} = 'audio/mpeg';

	# XXX: Time counter is not right, it starts from 0:00 as soon as next track 
	# begins streaming (slimp3/SB1 only)
	
	return $sock;
}

sub getFormatForURL () { 'mp3' }

sub isAudioURL () { 1 }

# Don't allow looping if the tracks are short
sub shouldLoop () { 0 }

# Source for AudioScrobbler ( E = Personalised recommendation except Last.fm)
sub audioScrobblerSource () { 'E' }

sub handleError {
    my ( $error, $client ) = @_;

	if ( $client ) {
		$client->unblock;
		
		Slim::Buttons::Common::pushModeLeft( $client, 'INPUT.Choice', {
			header  => '{PLUGIN_SLACKER_ERROR}',
			listRef => [ $error ],
		} );
		
		if ( $ENV{SLIM_SERVICE} ) {
		    #logError( $client, $error );
		}
	}
}

# Whether or not to display buffering info while a track is loading
sub showBuffering {
	my ( $class, $client, $url ) = @_;
	
	my $showBuffering = $client->pluginData('showBuffering');
	
	return ( defined $showBuffering ) ? $showBuffering : 1;
}

# Perform processing during play/add, before actual playback begins
sub onCommand {
	my ( $class, $client, $cmd, $url, $callback ) = @_;
	
	# Only handle 'play'
	if ( $cmd eq 'play' ) {
		# Display buffering info on loading the next track
		$client->pluginData( showBuffering => 1 );
		
		my ($stationId) = $url =~ m{^slacker://([^.]+)\.mp3};
		
		getNextTrack( $client, {
			stationId => $stationId,
			callback  => $callback,
		} );
		
		return;
	}
	
	return $callback->();
}

sub getNextTrack {
	my ( $client, $params ) = @_;
	
	my $url   = Slim::Player::Playlist::url($client);
	my $sid   = $params->{stationId};
	my $mode  = $params->{mode};
	my $track = $client->pluginData('currentTrack');
	
	my $last    = '';
	my $len     = $track ? $track->{len} : '';
	my $end     = $mode || '';
	my $elapsed = $track ? $track->{elapsed} : '';
	
	my $device  = $client->deviceid . '.' . $client->revision;
	
	if ( $mode eq 'end' ) {
		# normal track advance, mark elapsed == len
		$elapsed = $len;
	}
	
	# Talk to SN and get the next track to play
	my $trackURL = Slim::Networking::SqueezeNetwork->url(
		"/api/slacker/v1/playback/getNextTrack?device=$device&sid=$sid&len=$len&end=$end&elapsed=$elapsed"
	);
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&gotNextTrack,
		\&gotNextTrackError,
		{
			client => $client,
			params => $params,
		},
	);
	
	$log->debug("Getting next track from SqueezeNetwork");
	
	$http->get( $trackURL );
}

sub gotNextTrack {
	my $http   = shift;
	my $client = $http->params->{client};
	my $params = $http->params->{params};
	
	my $url = Slim::Player::Playlist::url($client);
	
	my $track = eval { from_json( $http->content ) };
	
	if ( !$track ) {
		$track = {
			error => $@,
		};
	}
	
	# Add station ID to track info
	$track->{sid} = $params->{stationId};
	
	if ( $log->is_debug ) {
		$log->debug( "Got Slacker track: " . Data::Dump::dump($track) );
	}
	
	if ( $track->{error} ) {
		# We didn't get the next track to play		
		my $title;
		
		if ( $track->{error} =~ /444/ ) {
			# Session bumped
			$title = $client->string('PLUGIN_SLACKER_SESSION_BUMPED');
			
			$client->pluginData( prevTrack    => 0 );
			$client->pluginData( currentTrack => 0 );
		}
		elsif ( $track->{error} =~ /Skip limits exceeded/ ) {
			$title = $client->string('PLUGIN_SLACKER_SKIPS_EXCEEDED_STATION');
		}
		else {
			$title = $client->string('PLUGIN_SLACKER_NO_TRACKS') . ' (' . $track->{error} . ')';
		}
		
		if ( $client->playmode =~ /play/ ) {
			setCurrentTitle( $client, $url, $title );
		
			$client->update();

			Slim::Player::Source::playmode( $client, 'stop' );
		}
		else {
			$client->showBriefly( {
				line1 => $client->string('PLUGIN_SLACKER_ERROR'),
				line2 => $title,
			},
			{
				scroll => 1,
			} );
		}
	
		return;
	}
	
	# Save existing repeat setting
	my $repeat = Slim::Player::Playlist::repeat($client);
	if ( $repeat != 2 ) {
		$log->debug( "Saving existing repeat value: $repeat" );
		$client->pluginData( oldRepeat => $repeat );
	}
	
	# Watch for playlist commands
	Slim::Control::Request::subscribe( 
		\&playlistCallback, 
		[['playlist'], ['repeat', 'newsong']],
	);
	
	# Watch for stop commands
	Slim::Control::Request::subscribe( 
		\&stopCallback, 
		[['stop', 'playlist']],
	);
	
	# Force repeating
	$client->execute(["playlist", "repeat", 2]);
	
	# Save the previous track's metadata, in case the user wants track info
	# after the next track begins buffering
	$client->pluginData( prevTrack => $client->pluginData('currentTrack') );
	
	# Save metadata for this track
	$client->pluginData( currentTrack => $track );
	
	my $cb = $params->{callback};
	$cb->();
}

sub gotNextTrackError {
	my $http   = shift;
	my $client = $http->params('client');
	
	handleError( $http->error, $client );
	
	# Make sure we re-enable readNextChunkOk
	#$client->readNextChunkOk(1);
}

# Handle normal advances to the next track
sub onDecoderUnderrun {
	my ( $class, $client, $nextURL, $callback ) = @_;
	
	# Special handling needed when synced
	if ( Slim::Player::Sync::isSynced($client) ) {
		if ( !Slim::Player::Sync::isMaster($client) ) {
			# Only the master needs to fetch next track info
			$log->debug('Letting sync master fetch next Slacker track');
			return;
		}
	}
	
	# Flag that we don't want any buffering messages while loading the next track,
	$client->pluginData( showBuffering => 0 );
	
	# Get next track
	my ($stationId) = $nextURL =~ m{^slacker://([^.]+)\.mp3};
	
	getNextTrack( $client, {
		stationId => $stationId,
		callback  => $callback,
		mode      => 'end',
	} );
	
	return;
}

# On skip, load the next track before playback
sub onJump {
    my ( $class, $client, $nextURL, $callback ) = @_;

	# Display buffering info on loading the next track
	# unless we shouldn't (when banning tracks)
	if ( $client->pluginData('banMode') ) {
		$client->pluginData( showBuffering => 0 );
		$client->pluginData( banMode => 0 );
	}
	else {
		$client->pluginData( showBuffering => 1 );
	}
	
	# If synced and we already fetched a track in onDecoderUnderrun,
	# just callback, don't fetch another track.  Checks prevTrack to
	# make sure there is actually a track ready to be played.
	if ( Slim::Player::Sync::isSynced($client) && $client->pluginData('prevTrack') ) {
		$log->debug( 'onJump while synced, but already got the next track to play' );
		$callback->();
		return;
	}
	
	# Get next track
	my ($stationId) = $nextURL =~ m{^slacker://([^.]+)\.mp3};
	
	my $mode = ( $client->playmode =~ /play/ ) ? 'skip' : '';
	
	getNextTrack( $client, {
		stationId => $stationId,
		callback  => $callback,
		mode      => $mode,
	} );
	
	return;
}

sub parseDirectHeaders {
	my $class   = shift;
	my $client  = shift || return;
	my $url     = shift;
	my @headers = @_;
	
	my $bitrate     = 128000;
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
	
	# Remember the length of this track
	$client->pluginData( length => $length );
	
	if ( my $track = $client->pluginData('currentTrack') ) {
		$track->{len} = int( ( $length * 8 ) / $bitrate );
	}
	
	# title, bitrate, metaint, redir, type, length, body
	return (undef, $bitrate, 0, undef, $contentType, $length, undef);
}

# If an audio stream fails, keep playing
sub handleDirectError {
	my ( $class, $client, $url, $response, $status_line ) = @_;
	
	$log->info("Direct stream failed: [$response] $status_line");
	
	$client->showBriefly( {
		line1 => $client->string('PLUGIN_SLACKER_ERROR'),
		line2 => $client->string('PLUGIN_SLACKER_STREAM_FAILED'),
	},
	{
		block  => 1,
		scroll => 1,
	} );
	
	# XXX: Stop after a certain number of errors in a row
	
	$client->execute([ 'playlist', 'play', $url ]);
}

# Check if player is allowed to skip, 
sub canSkip {
	my $client = shift;
	
	if ( my $track = $client->pluginData('currentTrack') ) {
		return $track->{skip} eq 'yes';
	}
	
	return 1;
}

# Disallow skips after the limit is reached
sub canDoAction {
	my ( $class, $client, $url, $action ) = @_;
	
	if ( $action eq 'stop' && !canSkip($client) ) {
		# Is skip allowed?
		$log->debug("Slacker: Skip limit exceeded, disallowing skip");

		$client->showBriefly( {
			line1 => $client->string('PLUGIN_SLACKER_MODULE_NAME'),
			line2 => $client->string('PLUGIN_SLACKER_SKIPS_EXCEEDED'),
		},
		{
			block  => 1,
			scroll => 1,
		} );
				
		return 0;
	}
	
	return 1;
}

sub canDirectStream {
	my ( $class, $client, $url ) = @_;
	
	# We need to check with the base class (HTTP) to see if we
	# are synced or if the user has set mp3StreamingMethod
	my $base = $class->SUPER::canDirectStream( $client, $url );
	if ( !$base ) {
		return 0;
	}
	
	my $track = $client->pluginData('currentTrack') || {};
	
	# Needed so stopCallback can have the URL after a 'playlist clear'
	$client->pluginData( lastURL => $url );
	
	return $track->{URL} || 0;
}

sub playlistCallback {
	my $request = shift;
	my $client  = $request->client();
	my $cmd     = $request->getRequest(0);
	my $p1      = $request->getRequest(1);
	
	return unless defined $client;
	
	# ignore if user is not using Pandora
	my $url = Slim::Player::Playlist::url($client);
	
	if ( !$url || $url !~ /^slacker/ ) {
		# No longer playing Slacker, clear plugin data
		$client->pluginData( prevTrack    => 0 );
		$client->pluginData( currentTrack => 0 );
		
		# User stopped playing Slacker, reset old repeat setting if any
		my $repeat = $client->pluginData('oldRepeat');
		if ( defined $repeat ) {
			$log->debug( "Stopped Slacker, restoring old repeat setting: $repeat" );
			$client->execute(["playlist", "repeat", $repeat]);
		}
		
		$log->debug( "Stopped Slacker, unsubscribing from playlistCallback" );
		Slim::Control::Request::unsubscribe( \&playlistCallback );
		
		return;
	}
	
	$log->debug("Got playlist event: $p1");
	
	# The user has changed the repeat setting.  Pandora requires a repeat
	# setting of '2' (repeat all) to work properly, or it will cause the
	# "stops after every song" bug
	if ( $p1 eq 'repeat' ) {
		if ( $request->getParam('_newvalue') != 2 ) {
			$log->debug("User changed repeat setting, forcing back to 2");
		
			$client->execute(["playlist", "repeat", 2]);
		
			if ( $client->playmode =~ /playout/ ) {
				$client->playmode( 'playout-play' );
			}
		}
	}
	elsif ( $p1 eq 'newsong' ) {
		# A new song has started playing.  We use this to change titles
		if ( my $track = $client->pluginData('currentTrack') ) {		
			my $title = $track->{title}  . ' ' . $client->string('BY')   . ' '
					  . $track->{artist} . ' ' . $client->string('FROM') . ' '
					  . $track->{album};
		
			setCurrentTitle( $client, $url, $title );
		}
		
		# Remove the previous track metadata
		$client->pluginData( prevTrack => 0 );
		
		# Start a timer to track elapsed time.  Can't find a better way to do this
		# because we can't read songTime when starting a new station or in stopCallback
		Slim::Utils::Timers::killTimers( $client, \&trackElapsed );
		Slim::Utils::Timers::setTimer(
			$client,
			Time::HiRes::time() + 1,
			\&trackElapsed,
		);
	}
}

sub trackElapsed {
	my $client = shift || return;
	
	my $track = $client->pluginData('currentTrack') || return;
	
	if ( my $songtime = Slim::Player::Source::songTime($client) ) {
		$track->{elapsed} = $songtime;
	}
	
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time() + 1,
		\&trackElapsed,
	);
}

sub stopCallback {
	my $request = shift;
	my $client  = $request->client();
	my $p0      = $request->getRequest(0);
	my $p1      = $request->getRequest(1);
	
	return unless defined $client;
	
	# Handle 'stop' and 'playlist clear'
	if ( $p0 eq 'stop' || ( $p1 && $p1 eq 'clear' ) ) {

		# Check that the user is still playing Slacker
		my $url = Slim::Player::Playlist::url($client) || $client->pluginData('lastURL');

		if ( !$url || $url !~ /^slacker/ ) {
			# stop listening for stop events
			Slim::Control::Request::unsubscribe( \&stopCallback );
			return;
		}
		
		$log->debug("Player stopped, reporting stop to SqueezeNetwork");
		
		if ( my $track = $client->pluginData('currentTrack') ) {
			my ($sid)   = $url =~ m{^slacker://([^.]+)\.mp3};
			my $len     = $track->{len};
			my $elapsed = $track->{elapsed};
		
			my $stopURL = Slim::Networking::SqueezeNetwork->url(
				"/api/slacker/v1/playback/stop?sid=$sid&len=$len&elapsed=$elapsed"
			);

			my $http = Slim::Networking::SqueezeNetwork->new(
				sub {},
				sub {},
				{
					client => $client,
				},
			);

			$http->get( $stopURL );
		}
		
		# Reset title to station title
		my $title = Slim::Music::Info::title($url);
		setCurrentTitle( $client, $url, $title );
		
		# Clear track data
		$client->pluginData( prevTrack    => 0 );
		$client->pluginData( currentTrack => 0 );
	}
}

# Track Info menu
sub trackInfo {
	my ( $class, $client, $track ) = @_;
	
	my $url = $track->url;

	my ($stationId) = $url =~ m{^slacker://([^.]+)\.mp3};
	
	# Get the current track
	my $currentTrack = $client->pluginData('prevTrack') || $client->pluginData('currentTrack') || {};
	
	# SN URL to fetch track info menu
	my $trackInfoURL = Slim::Networking::SqueezeNetwork->url(
		  '/api/slacker/v1/opml/trackinfo?stationId=' . $stationId 
		. '&trackId=' . $currentTrack->{tid}
	);
	
	# let XMLBrowser handle all our display
	my %params = (
		header   => 'PLUGIN_SLACKER_GETTING_TRACK_DETAILS',
		modeName => 'Slacker Now Playing',
		title    => Slim::Music::Info::getCurrentTitle( $client, $url ),
		url      => $trackInfoURL,
		timeout  => 35,
		remember => 0, # Don't remember where user was browsing
	);

	Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );
	
	$client->modeParam( 'handledTransition', 1 );
}

# URL used for CLI trackinfo queries
sub trackInfoURL {
	my ( $class, $client, $url ) = @_;

	my ($stationId) = $url =~ m{^slacker://([^.]+)\.mp3};
	
	# Get the current track
	my $currentTrack = $client->pluginData('prevTrack') || $client->pluginData('currentTrack') || {};
	
	# SN URL to fetch track info menu
	my $trackInfoURL = Slim::Networking::SqueezeNetwork->url(
		  '/api/slacker/v1/opml/trackinfo?stationId=' . $stationId 
		. '&trackId=' . $currentTrack->{tid}
	);
	
	return $trackInfoURL;
}

# Re-init Slacker when a player reconnects
sub reinit {
	my ( $class, $client, $playlist ) = @_;
	
	my $url = $playlist->[0];
	
	if ( my $track = $client->pluginData('currentTrack') ) {
		# We have previous data about the currently-playing song
		
		$log->debug("Re-init Slacker");
		
		# Re-add playlist item
		$client->execute( [ 'playlist', 'add', $url ] );
	
		# Reset track title
		my $title = $track->{title}  . ' ' . $client->string('BY')   . ' '
				  . $track->{artist} . ' ' . $client->string('FROM') . ' '
				  . $track->{album};
				
		setCurrentTitle( $client, $url, $title );
		
		# Restart elapsed second timer
		Slim::Utils::Timers::killTimers( $client, \&trackElapsed );
		Slim::Utils::Timers::setTimer(
			$client,
			Time::HiRes::time() + 1,
			\&trackElapsed,
		);
		
		# Back to Now Playing
		Slim::Buttons::Common::pushMode( $client, 'playlist' );
		
		# Reset song duration/progress bar
		if ( my $length = $client->pluginData('length') ) {			
			# On a timer because $client->currentsongqueue does not exist yet
			Slim::Utils::Timers::setTimer(
				$client,
				Time::HiRes::time(),
				sub {
					my $client = shift;
					
					$client->streamingProgressBar( {
						url     => $url,
						length  => $length,
						bitrate => 128000,
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

sub setCurrentTitle {
	my ( $client, $url, $title ) = @_;
	
	# We can't use the normal getCurrentTitle method because it would cause multiple
	# players playing the same station to get the same titles
	$client->pluginData( currentTitle => $title );
	
	# Call the normal setCurrentTitle method anyway, so it triggers callbacks to
	# update the display
	Slim::Music::Info::setCurrentTitle( $url, $title );
}

sub getCurrentTitle {
	my ( $class, $client, $url ) = @_;
	
	return $client->pluginData('currentTitle');
}

# Metadata for a URL, used by CLI/JSON clients
sub getMetadataFor {
	my ( $class, $client, $url, $forceCurrent ) = @_;

	my $track;
	
	# forceCurrent means the caller wants only the current song
	# This is used by Audioscrobbler
	if ( $forceCurrent ) {
		$track = $client->pluginData('currentTrack');
	}
	else {	
		$track = $client->pluginData('prevTrack') || $client->pluginData('currentTrack');
	}
	
	my $icon = Slim::Plugin::Slacker::Plugin->_pluginDataFor('icon');

	if ( $track ) {
		# Fav icon changes if the user has already rated it up
		# XXX: Need icons
		my $fav_icon = $track->{trate} ? 'html/images/btn_slacker_fav_on.gif' : 'html/images/btn_slacker_fav.gif';
		my $fav_tip  = $track->{trate} ? 'PLUGIN_SLACKER_UNMARK_FAVORITE' : 'PLUGIN_SLACKER_FAVORITE_TRACK';
		my $fav_cmd  = $track->{trate} ? 'U' : 'F';
	
		return {
			artist      => $track->{artist},
			album       => $track->{album},
			title       => $track->{title},
			# Note Slacker offers 5 image sizes: 75, 272, 383, 700, 1400
			cover       => 'http://images.slacker.com/covers/272/' . $track->{albumid},
			icon        => $icon,
			bitrate     => '128k CBR',
			type        => 'MP3 (Slacker)',
			info_link   => 'plugins/slacker/trackinfo.html',
			buttons     => {
				# disable REW/Previous button
				rew => 0,

				# replace repeat with Mark as Fav
				repeat  => {
					icon    => $fav_icon,
					tooltip => Slim::Utils::Strings::string($fav_tip),
					command => [ 'slacker', 'rate', $fav_cmd ],
				},

				# replace shuffle with Ban Track
				shuffle => {
					icon    => 'html/images/btn_slacker_ban.gif',
					tooltip => Slim::Utils::Strings::string('PLUGIN_SLACKER_BAN_TRACK'),
					command => [ 'slacker', 'rate', 'B' ],
				},
			}
		};
	}
	else {
		return {
			icon    => $icon,
			cover   => $icon,
			bitrate => '128k CBR',
			type    => 'MP3 (Slacker)',
		};
	}
}

1;
