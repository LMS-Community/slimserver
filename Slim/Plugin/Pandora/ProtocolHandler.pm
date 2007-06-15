package Slim::Plugin::Pandora::ProtocolHandler;

# $Id: ProtocolHandler.pm 11678 2007-03-27 14:39:22Z andy $

# Handler for pandora:// URLs

use strict;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.pandora',
	'defaultLevel' => $ENV{PANDORA_DEV} ? 'DEBUG' : 'WARN',
	'description'  => 'PLUGIN_PANDORA_MODULE_NAME',
});

sub getFormatForURL () { 'mp3' }

sub isAudioURL () { 1 }

# Don't allow looping if the tracks are short
sub shouldLoop () { 0 }

sub handleError {
    my ( $error, $client ) = @_;

	if ( $client ) {
		$client->unblock;
		
		Slim::Buttons::Common::pushModeLeft( $client, 'INPUT.Choice', {
			header  => '{PLUGIN_PANDORA_ERROR}',
			listRef => [ $error ],
		} );
		
		if ( $ENV{SLIM_SERVICE} ) {
		    logError( $client, $error );
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
		
		my ($stationId) = $url =~ m{^pandora://([^.]+)\.mp3};
		
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
	
	my $stationId = $params->{stationId};
	
	# Talk to SN and get the next track to play
	my $trackURL = Slim::Networking::SqueezeNetwork->url(
		"/api/pandora/playback/getNextTrack?stationId=$stationId"
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
	
	my $track = eval { JSON::Syck::Load( $http->content ) };
	
	if ( $log->is_debug ) {
		$log->debug( "Got Pandora track: " . Data::Dump::dump($track) );
	}
	
	if ( $track->{error} ) {
		# We didn't get the next track to play
		my $url = Slim::Player::Playlist::url($client);

		Slim::Music::Info::setCurrentTitle( $url, $client->string('PLUGIN_PANDORA_NO_TRACKS') );
		
		$client->update();

		Slim::Player::Source::playmode( $client, 'stop' );
	
		return;
	}
	
	# Watch for playlist commands
	Slim::Control::Request::subscribe( 
		\&playlistCallback, 
		[['playlist'], ['repeat', 'newsong']],
	);
	
	# Force repeating
	Slim::Player::Playlist::repeat( $client, 2 );
	
	# Save metadata for this track
	$client->pluginData( currentTrack => $track );
	
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
	
	# Flag that we don't want any buffering messages while loading the next track,
	$client->pluginData( showBuffering => 0 );
	
	# Get next track
	my ($stationId) = $nextURL =~ m{^pandora://([^.]+)\.mp3};
	
	getNextTrack( $client, {
		stationId => $stationId,
		callback  => $callback,
	} );
	
	return;
}

# On skip, load the next track before playback
sub onJump {
    my ( $class, $client, $nextURL, $callback ) = @_;

	# Display buffering info on loading the next track
	$client->pluginData( showBuffering => 1 );
	
	# Track skip if playmode was play
	if ( $client->playmode =~ /play/ ) {
		# XXX: check skip, track skip
	}
	
	# Get next track
	my ($stationId) = $nextURL =~ m{^pandora://([^.]+)\.mp3};
	
	getNextTrack( $client, {
		stationId => $stationId,
		callback  => $callback,
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
	
	$log->info("Direct stream failed: [$response] $status_line");
	
	$client->showBriefly( {
		line1 => $client->string('PLUGIN_PANDORA_ERROR'),
		line2 => $client->string('PLUGIN_PANDORA_STREAM_FAILED'),
	},
	{
		block  => 1,
		scroll => 1,
	} );
	
	# XXX: Stop after a certain number of errors in a row
	
	$client->execute([ 'playlist', 'play', $url ]);
}

# Disallow skips after the limit is reached
sub canDoAction {
	my ( $class, $client, $url, $action ) = @_;
	
	if ( $url =~ /^pandora/ && $action eq 'stop' ) {
		# XXX: check with SN to see if skip is allowed
		#if ( !canSkip($client) ) {
		#	return 0;
		#}
	}
	
	return 1;
}

sub canDirectStream {
	my ( $class, $client, $url ) = @_;
	
	my $track = $client->pluginData('currentTrack') || {};
	
	return $track->{audioUrl} || 0;
}

sub playlistCallback {
	my $request = shift;
	my $client  = $request->client();
	my $cmd     = $request->getRequest(0);
	my $p1      = $request->getRequest(1);
	
	return unless defined $client;
	
	# ignore if user is not using Pandora
	my $url = Slim::Player::Playlist::url($client) || return;
	
	return if $url !~ /^pandora/;
	
	$log->debug("Got playlist event: $p1");
	
	# The user has changed the repeat setting.  Pandora requires a repeat
	# setting of '2' (repeat all) to work properly, or it will cause the
	# "stops after every song" bug
	if ( $p1 eq 'repeat' ) {
		$log->debug("User changed repeat setting, forcing back to 2");
		
		Slim::Player::Playlist::repeat( $client, 2 );
		
		if ( $client->playmode =~ /playout/ ) {
			$client->playmode( 'playout-play' );
		}
	}
	elsif ( $p1 eq 'newsong' ) {
		# A new song has started playing.  We use this to change titles
		my $track = $client->pluginData('currentTrack');
		
		my $title = $track->{songName} . ' ' . $client->string('BY') . ' '
				  . $track->{artistName} . ' ' . $client->string('FROM') . ' '
				  . $track->{albumName};
		
		Slim::Music::Info::setCurrentTitle( $url, $title );
	}
}

# Override replaygain to always use the supplied gain value
sub trackGain {
	my ( $class, $client, $url ) = @_;
	
	my $currentTrack = $client->pluginData('currentTrack');
	
	my $gain = $currentTrack->{trackGain} || 0;
	
	$log->info("Using replaygain value of $gain for Pandora track");
	
	return $gain;
}

# Track Info menu
sub trackInfo {
	my ( $class, $client, $track ) = @_;
	
	my $url = $track->url;
	
	my $secs = Slim::Music::Info::getDuration($url);

	my ($stationId) = $url =~ m{^pandora://([^.]+)\.mp3};
	
	# XXX: this will break after the next track starts streaming
	my $currentTrack = $client->pluginData('currentTrack');
	
	# SN URL to fetch track info menu
	my $trackInfoURL = Slim::Networking::SqueezeNetwork->url(
		  '/api/pandora/opml/trackinfo?stationId=' . $stationId 
		. '&trackId=' . $currentTrack->{trackToken}
		. '&secs=' . $secs
	);
	
	# let XMLBrowser handle all our display
	my %params = (
		header   => 'PLUGIN_PANDORA_GETTING_TRACK_DETAILS',
		modeName => 'Pandora Now Playing',
		title    => Slim::Music::Info::getCurrentTitle( $client, $url ),
		url      => $trackInfoURL,
	);

	Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );
	
	$client->modeParam( 'handledTransition', 1 );
}

1;