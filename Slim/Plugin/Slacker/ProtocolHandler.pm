package Slim::Plugin::Slacker::ProtocolHandler;

# $Id$

use strict;
use base qw(Slim::Player::Protocols::HTTP);

use Slim::Music::Info;
use Slim::Utils::Misc;
use Slim::Utils::Timers;

use JSON::XS::VersionOneAndTwo;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.slacker',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_SLACKER_MODULE_NAME',
} );

my $fav_on   = main::SLIM_SERVICE ? 'static/images/playerControl/slacker_fav_on_button.png' : 'html/images/btn_slacker_fav_on.gif'; 
my $fav_off  = main::SLIM_SERVICE ? 'static/images/playerControl/slacker_fav_button.png' : 'html/images/btn_slacker_fav.gif'; 

# XXX: Port to new streaming

# To support remote streaming (synced players, slimp3/SB1), we need to subclass Protocols::HTTP
sub new {
	my $class  = shift;
	my $args   = shift;

	my $client = $args->{client};
	
	my $track  = $client->master->pluginData('currentTrack') || {};
	
	main::DEBUGLOG && $log->debug( 'Remote streaming Slacker track: ' . $track->{URL} );

	return unless $track->{URL};

	my $sock = $class->SUPER::new( {
		url     => $track->{URL},
		song    => $args->{'song'},
		client  => $client,
		bitrate => $class->getBitrateFromTrackInfo($track) * 1000,
	} ) || return;
	
	${*$sock}{contentType} = 'audio/mpeg';

	# XXX: Time counter is not right, it starts from 0:00 as soon as next track 
	# begins streaming (slimp3/SB1 only)
	
	return $sock;
}

sub getFormatForURL () { 'mp3' }

sub getBitrateFromTrackInfo {
	my ($class, $track) = @_;

	if ( $track && ref $track && $track->{format} && $track->{format} =~ /_(\d{2,3})$/ ) {
		return $1;
	}	

	return 128;
}

# Don't allow looping if the tracks are short
sub shouldLoop () { 0 }

sub canSeek { 0 }

sub canSeekError { return ( 'SEEK_ERROR_TYPE_NOT_SUPPORTED', 'Slacker' ); }

# Source for AudioScrobbler ( E = Personalised recommendation except Last.fm)
sub audioScrobblerSource () { 'E' }

# Some ad content is small, use a small buffer threshold
sub bufferThreshold { 20 }

sub isRemote { 1 }

# If either the previous or current track is an ad, disable transitions
sub transitionType {
	my ( $class, $client, $song, $transitionType ) = @_;
	
	# Ignore if transitionType is already 0
	return if $transitionType == 0;
	
	my $current = $client->master->pluginData('currentTrack');
	my $prev    = $client->master->pluginData('prevTrack');
	
	return unless $current && $prev;
	
	if ( $current->{ad} || $prev->{ad} ) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Disabling transition because of audio ad');
		return 0;
	}

	return;
}

sub handleError {
    my ( $error, $client ) = @_;

	if ( $client ) {
		$client->unblock;
		
		Slim::Buttons::Common::pushModeLeft( $client, 'INPUT.Choice', {
			header  => '{PLUGIN_SLACKER_ERROR}',
			listRef => [ $error ],
		} );
		
		if ( main::SLIM_SERVICE ) {
			SDI::Service::EventLog->log(
				$client, 'slacker_error', $error,
			);
		}
	}
}

sub scanUrl {
	my ($class, $url, $args) = @_;
	$args->{'cb'}->($args->{'song'}->currentTrack());
}

sub _getNextTrack {
	my ( $client, $params ) = @_;
	
	my $url   = Slim::Player::Playlist::url($client);
	my $sid   = $params->{stationId};
	my $mode  = $params->{mode};
	my $track = $client->master->pluginData('currentTrack');
	
	my $last    = '';
	my $len     = $track ? $track->{tlen} : '';
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
	
	main::DEBUGLOG && $log->is_debug && $log->debug( $client->id . " Getting next track from SqueezeNetwork");
	
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
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( "Got Slacker track: " . Data::Dump::dump($track) );
	}
	
	if ( $track->{error} ) {
		# We didn't get the next track to play		
		my $title;
		
		if ( $track->{error} =~ /444/ ) {
			# Session bumped
			$title = $client->string('PLUGIN_SLACKER_SESSION_BUMPED');
			
			$client->master->pluginData( prevTrack    => 0 );
			$client->master->pluginData( currentTrack => 0 );
		}
		elsif ( $track->{error} =~ /Skip limits exceeded/ ) {
			$title = $client->string('PLUGIN_SLACKER_SKIPS_EXCEEDED_STATION');
		}
		else {
			$title = $client->string('PLUGIN_SLACKER_NO_TRACKS') . ' (' . $track->{error} . ')';
		}
		
		if ( $client->isPlaying() ) {
			Slim::Player::Source::playmode( $client, 'stop' );
		}
		
		$client->master->pluginData( prevTrack => {
			title => $title,
		} );

		my $line1 = $client->string('PLUGIN_SLACKER_ERROR');
		my $line2 = $title;
		
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
		} );
	
		return;
	}
	
	# Save existing repeat setting
	my $repeat = Slim::Player::Playlist::repeat($client);
	if ( $repeat != 2 ) {
		main::DEBUGLOG && $log->debug( "Saving existing repeat value: $repeat" );
		$client->master->pluginData( oldRepeat => $repeat );
	}
	
	# Watch for playlist commands
	Slim::Control::Request::subscribe( 
		\&playlistCallback, 
		[['playlist'], ['repeat', 'newsong']],
		$client,
	);
	
	# Watch for stop commands
	Slim::Control::Request::subscribe( 
		\&stopCallback, 
		[['stop', 'playlist']],
		$client,
	);
	
	# Force repeating
	$client->execute(["playlist", "repeat", 2]);
	
	# Save the previous track's metadata, in case the user wants track info
	# after the next track begins buffering
	$client->master->pluginData( prevTrack => $client->master->pluginData('currentTrack') );
	
	# Save metadata for this track
	$client->master->pluginData( currentTrack => $track );
	
	my $cb = $params->{callback};
	$cb->();
}

sub gotNextTrackError {
	my $http   = shift;
	my $client = $http->params('client');
	
	handleError( $http->error, $client );
}

# Handle normal advances to the next track
sub onDecoderUnderrun {
	my ( $class, $client, $nextURL, $callback ) = @_;
	
	# Special handling needed when synced
	if ( $client->isSynced() ) {
		if ( !Slim::Player::Sync::isMaster($client) ) {
			# Only the master needs to fetch next track info
			main::DEBUGLOG && $log->debug('Letting sync master fetch next Slacker track');
			return;
		}
	}
	
	# Get next track
	my ($stationId) = $nextURL =~ m{^slacker://([^.]+)\.mp3};
	
	_getNextTrack( $client, {
		stationId => $stationId,
		callback  => $callback,
		mode      => 'end',
	} );
	
	return;
}

# On skip, load the next track before playback
sub onJump {
    my ( $class, $client, $nextURL, $seekdata, $callback ) = @_;
	
	# If synced and we already fetched a track in onDecoderUnderrun,
	# just callback, don't fetch another track.  Checks prevTrack to
	# make sure there is actually a track ready to be played.
	if ( $client->isSynced() && $client->master->pluginData('prevTrack') ) {
		main::DEBUGLOG && $log->debug( 'onJump while synced, but already got the next track to play' );
		$callback->();
		return;
	}
	
	# Get next track
	my ($stationId) = $nextURL =~ m{^slacker://([^.]+)\.mp3};
	
	my $mode = ( $client->isPlaying() ) ? 'skip' : '';
	
	_getNextTrack( $client, {
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
	
	# title, bitrate, metaint, redir, type, length, body
	return (undef, $bitrate, 0, undef, $contentType, $length, undef);
}

# If an audio stream fails, keep playing
sub handleDirectError {
	my ( $class, $client, $url, $response, $status_line ) = @_;
	
	main::INFOLOG && $log->info("Direct stream failed: [$response] $status_line");
	
	my $line1 = $client->string('PLUGIN_SLACKER_ERROR');
	my $line2 = $client->string('PLUGIN_SLACKER_STREAM_FAILED');
	
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
	
	# XXX: Stop after a certain number of errors in a row
	
	$client->execute([ 'playlist', 'play', $url ]);
}

# Check if player is allowed to skip, 
sub canSkip {
	my $client = shift;
	
	if ( my $track = $client->master->pluginData('currentTrack') ) {
		return $track->{skip} eq 'yes';
	}
	
	return 1;
}

sub canRew {
	my ( $class, $url ) = @_;
	
	return $url =~ m{^slacker://(?:pid|songid|tid)/([^.]+)\.mp3} ? 1 : 0;
}

# Disallow skips after the limit is reached
sub canDoAction {
	my ( $class, $client, $url, $action ) = @_;
	
	if ( $action eq 'stop' && !canSkip($client) ) {
		# Is skip allowed?
		main::DEBUGLOG && $log->debug("Slacker: Skip limit exceeded, disallowing skip");
		
		my $line1 = $client->string('PLUGIN_SLACKER_ERROR');
		my $line2 = $client->string('PLUGIN_SLACKER_SKIPS_EXCEEDED');

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
	
	if ( $action eq 'rew' ) {
		return $class->canRew($url);
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
	
	my $track = $client->master->pluginData('currentTrack') || {};
	
	# Needed so stopCallback can have the URL after a 'playlist clear'
	$client->master->pluginData( lastURL => $url );
	
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
		$client->master->pluginData( prevTrack    => 0 );
		$client->master->pluginData( currentTrack => 0 );
		
		# User stopped playing Slacker, reset old repeat setting if any
		my $repeat = $client->master->pluginData('oldRepeat');
		if ( defined $repeat ) {
			main::DEBUGLOG && $log->debug( "Stopped Slacker, restoring old repeat setting: $repeat" );
			$client->execute(["playlist", "repeat", $repeat]);
		}
		
		main::DEBUGLOG && $log->debug( "Stopped Slacker, unsubscribing from playlistCallback" );
		Slim::Control::Request::unsubscribe( \&playlistCallback, $client );
		
		return;
	}
	
	main::DEBUGLOG && $log->debug("Got playlist event: $p1");
	
	# The user has changed the repeat setting.  Pandora requires a repeat
	# setting of '2' (repeat all) to work properly, or it will cause the
	# "stops after every song" bug
	if ( $p1 eq 'repeat' ) {
		if ( $request->getParam('_newvalue') != 2 ) {
			main::DEBUGLOG && $log->debug("User changed repeat setting, forcing back to 2");
		
			$client->execute(["playlist", "repeat", 2]);
		}
	}
	elsif ( $p1 eq 'newsong' ) {
		# Remove the previous track metadata
		$client->master->pluginData( prevTrack => 0 );
		
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
	
	my $track = $client->master->pluginData('currentTrack') || return;
	
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
		my $url = Slim::Player::Playlist::url($client) || $client->master->pluginData('lastURL');

		if ( !$url || $url !~ /^slacker/ ) {
			# stop listening for stop events
			Slim::Control::Request::unsubscribe( \&stopCallback, $client );
			return;
		}
		
		main::DEBUGLOG && $log->debug("Player stopped, reporting stop to SqueezeNetwork");
		
		if ( my $track = $client->master->pluginData('currentTrack') ) {
			my ($sid)   = $url =~ m{^slacker://([^.]+)\.mp3};
			my $len     = $track->{tlen};
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
		
		# Clear track data
		$client->master->pluginData( prevTrack    => 0 );
		$client->master->pluginData( currentTrack => 0 );
	}
}

# Override replaygain to always use the supplied gain value
sub trackGain {
	my ( $class, $client, $url ) = @_;
	
	my $currentTrack = $client->master->pluginData('currentTrack');
	
	my $gain = $currentTrack->{audiogain} || 0;
	
	main::INFOLOG && $log->info("Using replaygain value of $gain for Slacker track");
	
	return $gain;
}

# Track Info menu
sub trackInfo {
	my ( $class, $client, $track ) = @_;
	
	my $url = $track->url;

	my ($stationId) = $url =~ m{^slacker://([^.]+)\.mp3};
	
	# Get the current track
	my $currentTrack = $client->master->pluginData('prevTrack') || $client->master->pluginData('currentTrack') || {};
	
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
	my $currentTrack = $client->master->pluginData('prevTrack') || $client->master->pluginData('currentTrack') || {};
	
	# SN URL to fetch track info menu
	my $trackInfoURL = Slim::Networking::SqueezeNetwork->url(
		  '/api/slacker/v1/opml/trackinfo?stationId=' . $stationId 
		. '&trackId=' . $currentTrack->{tid}
	);
	
	return $trackInfoURL;
}

# Re-init Slacker when a player reconnects
sub reinit { if ( main::SLIM_SERVICE ) {
	my ( $class, $client, $song ) = @_;
	
	my $url = $song->currentTrack->url();
	
	main::DEBUGLOG && $log->debug("Re-init Slacker - $url");
	
	if ( my $track = $client->master->pluginData('currentTrack') ) {
		# We have previous data about the currently-playing song
		
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
		if ( $track->{tlen} ) {			
			# On a timer because $client->currentsongqueue does not exist yet
			Slim::Utils::Timers::setTimer(
				$client,
				Time::HiRes::time(),
				sub {
					my $client = shift;
					
					$client->streamingProgressBar( {
						url      => $url,
						duration => $track->{tlen},
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
} }

# Metadata for a URL, used by CLI/JSON clients
sub getMetadataFor {
	my ( $class, $client, $url, $forceCurrent ) = @_;

	my $track;
	
	# forceCurrent means the caller wants only the current song
	# This is used by Audioscrobbler
	if ( $forceCurrent ) {
		$track = $client->master->pluginData('currentTrack');
	}
	else {	
		$track = $client->master->pluginData('prevTrack') || $client->master->pluginData('currentTrack');
	}
	
	my $icon = $class->getIcon();

	if ( $track ) {
		# Fav icon changes if the user has already rated it up
		my $fav_icon = $track->{trate} ? $fav_on : $fav_off;
		my $fav_tip  = $track->{trate} ? 'PLUGIN_SLACKER_UNMARK_FAVORITE' : 'PLUGIN_SLACKER_FAVORITE_TRACK';
		my $fav_cmd  = $track->{trate} ? 'U' : 'F';
	
		return {
			artist      => $track->{artist},
			album       => $track->{album},
			title       => $track->{title},
			duration    => $track->{tlen},
			replay_gain => $track->{audiogain},
			# Note Slacker offers 5 image sizes: 75, 272, 383, 700, 1400
			cover       => $track->{cover} || 'http://images.slacker.com/covers/1400/' . $track->{albumid},
			icon        => $icon,
			bitrate     => $class->getBitrateFromTrackInfo($track) . 'k CBR',
			type        => 'MP3 (Slacker)',
			info_link   => 'plugins/slacker/trackinfo.html',
			buttons     => {
				# disable REW/Previous button
				rew => $class->canRew($url) || 0,
				# disable FWD when you've reached skip limit
				fwd => canSkip($client) ? 1 : 0,

				# replace repeat with Mark as Fav
				repeat  => {
					icon    => $fav_icon,
					jiveStyle => 'love',
					tooltip => Slim::Utils::Strings::string($fav_tip),
					command => [ 'slacker', 'rate', $fav_cmd ],
				},

				# replace shuffle with Ban Track
				shuffle => {
					icon    => main::SLIM_SERVICE ? 'static/images/playerControl/ban_button.png' : 'html/images/btn_slacker_ban.gif',
					jiveStyle => 'hate',
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

sub getIcon {
	my ( $class, $url ) = @_;

	return Slim::Plugin::Slacker::Plugin->_pluginDataFor('icon');
}

1;
