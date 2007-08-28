package Slim::Plugin::RhapsodyDirect::ProtocolHandler;

# $Id: ProtocolHandler.pm 11678 2007-03-27 14:39:22Z andy $

# Rhapsody Direct handler for rhapd:// URLs.

use strict;
use warnings;

use HTML::Entities qw(encode_entities);
use JSON::XS qw(from_json);
use MIME::Base64 qw(decode_base64);

use Slim::Plugin::RhapsodyDirect::RPDS;
use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Misc;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.rhapsodydirect',
	'defaultLevel' => $ENV{RHAPSODY_DEV} ? 'DEBUG' : 'WARN',
	'description'  => 'PLUGIN_RHAPSODY_DIRECT_MODULE_NAME',
});

sub getFormatForURL { 'wma' }

sub isAudioURL { 1 }

sub handleError {
    return Slim::Plugin::RhapsodyDirect::Plugin::handleError(@_);
}

sub parseDirectHeaders {
	my ( $class, $client, $url, @headers ) = @_;
	
	my $length;

	foreach my $header (@headers) {

		$log->debug("RhapsodyDirect header: $header");

		if ($header =~ /^Content-Length:\s*(.*)/i) {
			$length = $1;
			last;
		}
	}

	# ($title, $bitrate, $metaint, $redir, $contentType, $length, $body)
	return (undef, 128000, 0, '', 'wma', $length, undef);
}

# Don't allow looping if the tracks are short
sub shouldLoop { 0 }

sub canDoAction {
	my ( $class, $client, $url, $action ) = @_;
	
	# Don't allow pause on radio
	if ( $action eq 'pause' && $url =~ /\.rdr$/ ) {
		return 0;
	}
	
	return 1;
}

# Whether or not to display buffering info while a track is loading
sub showBuffering {
	my ( $class, $client, $url ) = @_;
	
	my $showBuffering = $client->pluginData('showBuffering');
	
	return ( defined $showBuffering ) ? $showBuffering : 1;
}

# If an audio stream fails, keep playing
sub handleDirectError {
	my ( $class, $client, $url, $response, $status_line ) = @_;
	
	$log->debug("Direct stream failed: [$response] $status_line\n");
	
	my $line1 = $client->string('PLUGIN_RHAPSODY_DIRECT_ERROR');
	my $line2 = $client->string('PLUGIN_RHAPSODY_DIRECT_STREAM_FAILED');
	
	$client->showBriefly( {
		line1 => $line1,
		line2 => $line2,
	},
	{
		block  => 1,
		scroll => 1,
	} );
	
	if ( $ENV{SLIM_SERVICE} ) {
		SDI::Service::EventLog::logEvent(
			$client->id, 'rhapsody_error', "$response - $status_line"
		);
	}
	
	# If it was a radio track, play again, we'll get a new track
	if ( $url =~ /\.rdr$/ ) {
		$log->debug('Radio track failed, restarting');
		$client->execute([ 'playlist', 'play', $url ]);
	}
	else {
		# Otherwise, skip
		my $nextsong = Slim::Player::Source::nextsong($client);
		if ( $client->playmode !~ /stop/ && defined $nextsong ) {
			$log->debug("Skipping to next track ($nextsong)");
			$client->execute([ 'playlist', 'jump', $nextsong ]);
		}
	}
}

# Perform processing during play/add, before actual playback begins
sub onCommand {
	my ( $class, $client, $cmd, $url, $callback ) = @_;
	
	$log->debug("RhapsodyDirect: Handling command '$cmd'");
	
	# Only handle 'play'
	if ( $cmd ne 'play' ) {
		return $callback->();
	}
	
	# XXX: When hitting play while currently listening to another Rhapsody track,
	# no logging is performed
	
	# Clear any previous outstanding rpds queries
	cancel_rpds($client);
	
	# Always get a new playback session
	$log->debug("Requesting new playback session...");
	
	# Update the 'Connecting...' text
	$client->suppressStatus(1);
	displayStatus( $client, $url, 'PLUGIN_RHAPSODY_DIRECT_GETTING_TRACK_INFO', 30 );
	
	# Clear old radio data if any
	$client->pluginData( radioTrack => 0 );
	
	# Display buffering info on loading the next track
	$client->pluginData( showBuffering => 1 );
	
	# Get login info from SN if we don't already have it
	my $account = $client->pluginData('account');
	
	if ( !$account ) {
		my $accountURL = Slim::Networking::SqueezeNetwork->url( '/api/rhapsody/account' );
		
		my $http = Slim::Networking::SqueezeNetwork->new(
			\&gotAccount,
			\&gotAccountError,
			{
				client => $client,
				cb     => sub {
					$class->onCommand( $client, $cmd, $url, $callback );
				},
				ecb    => sub {
					my $error = shift;
					$error = $client->string('PLUGIN_RHAPSODY_DIRECT_ERROR_ACCOUNT') . ": $error";
					handleError( $error, $client );
				},
			},
		);
		
		$log->debug("Getting Rhapsody account from SqueezeNetwork");
		
		$http->get( $accountURL );
		
		return;
	}
	
	my $packet = pack 'cC/a*C/a*C/a*C/a*', 
		2,
		encode_entities( $account->{username}->[0] ),
		$account->{cobrandId}, 
		encode_entities( decode_base64( $account->{password}->[0] ) ), 
		$account->{clientType};
	
	rpds( $client, {
		data        => $packet,
		callback    => \&gotPlaybackSession,
		onError     => \&handleError,
		passthrough => [ $url, $callback ],
	} );
}

sub gotAccount {
	my $http  = shift;
	my $params = $http->params;
	my $client = $params->{client};
	
	my $account = eval { from_json( $http->content ) };
	
	if ( ref $account eq 'HASH' ) {
		$client->pluginData( account => $account );
		
		if ( $log->is_debug ) {
			$log->debug("Got Rhapsody account info from SN: " . Data::Dump::dump($account) );
		}
		
		$params->{cb}->();
	}
	else {
		$params->{ecb}->($@);
	}
}

sub gotAccountError {
	my $http   = shift;
	my $params = $http->params;
	
	$params->{ecb}->( $http->error );
}
	
sub gotPlaybackSession {
	my ( $client, $data, $url, $callback ) = @_;
	
	# For radio mode, first get the next track ID
	if ( my ($stationId) = $url =~ m{rhapd://(.+)\.rdr} ) {
		
		# Check if we've got the next track URL
		if ( my $radioTrack = $client->pluginData('radioTrack') ) {
			$url = $radioTrack;
			
			$log->debug("Radio mode: Next track is $url");
		}
		else {
			# Get the next track and call us back
			$log->debug('Radio mode: Getting next track...');
		
			getNextRadioTrack( $client, {
				stationId   => $stationId,
				callback    => \&gotPlaybackSession,
				passthrough => [ $client, $data, $url, $callback ],
			} );
			return;
		}
	}

	$log->debug("New playback session started");
	
	my ($trackId) = $url =~ /(Tra\.[^.]+)/;
	
	# Get metadata for normal tracks
	getTrackMetadata( $client, {
		trackId     => $trackId,
		callback    => \&gotTrackMetadata,
		passthrough => [ $client ],
	} );
	
	# Get the track URL via the player
	rpds( $client, {
		data        => pack( 'cC/a*', 3, $trackId ),
		callback    => \&gotTrackInfo,
		onError     => \&gotTrackError,
		passthrough => [ $url, $callback ],
	} );
}

# Handle normal advances to the next track
sub onDecoderUnderrun {
	my ( $class, $client, $nextURL, $callback ) = @_;

	# Flag that we don't want any buffering messages while loading the next track
	$client->pluginData( showBuffering => 0 );

	# Clear radio data if any, so we always get a new radio track
	$client->pluginData( radioTrack => 0 );

	# For decoder underrun, we log the full play time of the song
	my $playtime = Slim::Player::Source::playingSongDuration($client);
	
	if ( $playtime > 0 ) {
		$log->debug("End of track, logging usage info ($playtime seconds)...");
	
		# There are different log methods for normal vs. radio play
		my $data;
	
		my $url = Slim::Player::Playlist::url($client);
		if ( my ($stationId) = $url =~ m{rhapd://(.+)\.rdr} ) {
			# logMeteringInfoForStationTrackPlay
			$data = pack( 'cC/a*C/a*', 5, $playtime, $stationId );
		}
		else {
			# logMeteringInfo
			$data = pack( 'cC/a*', 4, $playtime );
		}
	
		rpds( $client, {
			data        => $data,
			timeout     => 5, # Sometimes log requests fail, so we want to only wait a short time
			callback    => \&getNextTrackInfo,
			onError     => sub {
				# We don't really care if the logging call fails,
				# so allow onError to work like the normal callback
				getNextTrackInfo( $client, undef, $nextURL, $callback );
			},
			passthrough => [ $nextURL, $callback ],
		} );
	}
	else {
		getNextTrackInfo( $client, undef, $nextURL, $callback );
	}
}

# On skip, load the next track before playback
sub onJump {
    my ( $class, $client, $nextURL, $callback ) = @_;

	if ( $log->is_debug ) {
		$log->debug( 'Handling command "jump", playmode: ' . $client->playmode );
	}
	
	if ( $ENV{SLIM_SERVICE} ) {
		SDI::Service::EventLog::logEvent(
			$client->id, 'rhapsody_jump', "-> $nextURL",
		);
	}
	
	# Clear any previous outstanding rpds queries
	cancel_rpds($client);

	# Clear radio data if any, so we always get a new radio track
	$client->pluginData( radioTrack => 0 );
	
	# Update the 'Connecting...' text
	$client->suppressStatus(1);
	displayStatus( $client, $nextURL, 'PLUGIN_RHAPSODY_DIRECT_GETTING_TRACK_INFO', 30 );
	
	# Display buffering info on loading the next track
	$client->pluginData( showBuffering => 1 );
	
	# For a skip use only the amount of time we've played the song
	my $songtime = Slim::Player::Source::songTime($client);

	if ( $client->playmode =~ /play/ && $songtime > 0 ) {

		# logMeteringInfo, param is playtime in seconds
		
		$log->debug("Track skip, logging usage info ($songtime seconds)...");
		
		# There are different log methods for normal vs. radio play
		my $data;

		my $url = Slim::Player::Playlist::url($client);
		if ( my ($stationId) = $url =~ m{rhapd://(.+)\.rdr} ) {
			# logMeteringInfoForStationTrackPlay
			$data = pack( 'cC/a*C/a*', 5, $songtime, $stationId );
		}
		else {
			# logMeteringInfo
			$data = pack( 'cC/a*', 4, $songtime );
		}
		
		rpds( $client, {
			data        => $data,
			timeout     => 5, # Sometimes log requests fail, so we want to only wait a short time
			callback    => \&getNextTrackInfo,
			onError     => sub {
				# We don't really care if the logging call fails,
				# so allow onError to work like the normal callback
				getNextTrackInfo( $client, undef, $nextURL, $callback );
			},
			passthrough => [ $nextURL, $callback ],
		} );
	}
	else {
		getNextTrackInfo( $client, undef, $nextURL, $callback );
	}
}

sub getNextTrackInfo {
    my ( $client, undef, $nextURL, $callback ) = @_;

	# Radio mode, get next track ID
	if ( my ($stationId) = $nextURL =~ m{rhapd://(.+)\.rdr} ) {
		# Check if we've got the next track URL
		if ( my $radioTrack = $client->pluginData('radioTrack') ) {
			$nextURL = $radioTrack;

			$log->debug("Radio mode: Next track is $nextURL");
		}
		else {
			# Get the next track and call us back
			$log->debug("Radio mode: Getting info about next track ($nextURL)...");

			getNextRadioTrack( $client, {
				stationId   => $stationId,
				callback    => \&getNextTrackInfo,
				passthrough => [ $client, undef, $nextURL, $callback ],
			} );
			return;
		}
	}
	
	# Get track URL for the next track
	my ($trackId) = $nextURL =~ /(Tra\.[^.]+)/;
	
	# Get metadata for normal tracks
	getTrackMetadata( $client, {
		trackId     => $trackId,
		callback    => \&gotTrackMetadata,
		passthrough => [ $client ],
	} );
	
	rpds( $client, {
		data        => pack( 'cC/a*', 3, $trackId ),
		callback    => \&gotTrackInfo,
		onError     => \&gotTrackError,
		passthrough => [ $nextURL, $callback ],
	} );
}

# On an underrun, restart radio or skip to next track
sub onUnderrun {
	my ( $class, $client, $url, $callback ) = @_;
	
	if ( $log->is_debug ) {
		$log->debug( 'Underrun, stopping, playmode: ' . $client->playmode );
	}
	
	if ( $ENV{SLIM_SERVICE} ) {
		SDI::Service::EventLog::logEvent(
			$client->id, 'rhapsody_underrun'
		);
	}
	
	# If it was a radio track, play again, we'll get a new track
	if ( $url =~ /\.rdr$/ ) {
		$log->debug('Radio track failed, trying to restart');
		
		# Clear radio data if any, so we always get a new radio track
		$client->pluginData( radioTrack => 0 );
		
		$client->execute([ 'playlist', 'play', $url ]);
	}
	else {
		# Skip to the next track if possible
		
		my $nextsong = Slim::Player::Source::nextsong($client);
		if ( $client->playmode !~ /stop/ && defined $nextsong ) {
			# This is on a timer so the underrun callback will stop the player first
			Slim::Utils::Timers::setTimer(
				$client,
				Time::HiRes::time(),
				sub {
					my $client = shift;
					$log->debug("Skipping to next track ($nextsong)");
					$client->execute([ 'playlist', 'jump', $nextsong ]);
				},
			);
		}
	}
	
	$callback->();
}

sub getTrackMetadata {
	my ( $client, $params ) = @_;
	
	my $trackId = $params->{trackId};
	
	my $trackURL = Slim::Networking::SqueezeNetwork->url(
		"/api/rhapsody/opml/metadata/getTrack?trackId=$trackId&json=1"
	);
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&gotTrackMetadata,
		\&gotTrackMetadataError,
		{
			client => $client,
			params => $params,
		},
	);
	
	$log->debug("Getting track metadata for $trackId from SqueezeNetwork");
	
	$http->get( $trackURL );
}

sub gotTrackMetadata {
	my $http   = shift;
	my $client = $http->params->{client};
	my $params = $http->params->{params};
	
	my $track = eval { from_json( $http->content ) };
	if ( $@ ) {
		$log->warn("Error getting track metadata from SN: $@");
		$client->pluginData( currentTrack => 0 );
		return;
	}
	
	if ( $log->is_debug ) {
		$log->debug( 'Got track metadata: ' . Data::Dump::dump($track) );
	}
	
	$client->pluginData( currentTrack => $track );
}

sub gotTrackMetadataError {
	my $http   = shift;
	my $client = $http->params('client');
	my $error  = $http->error;
	
	$log->warn("Error getting track metadata from SN: $error");
	
	$client->pluginData( currentTrack => 0 );
}

sub getNextRadioTrack {
	my ( $client, $params ) = @_;
	
	my $stationId = $params->{stationId};
	
	# Talk to SN and get the next track to play
	my $radioURL = Slim::Networking::SqueezeNetwork->url(
		"/api/rhapsody/radio/getNextTrack?stationId=$stationId"
	);
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&gotNextRadioTrack,
		\&gotNextRadioTrackError,
		{
			client => $client,
			params => $params,
		},
	);
	
	$log->debug("Getting next radio track from SqueezeNetwork");
	
	$http->get( $radioURL );
}

sub gotNextRadioTrack {
	my $http   = shift;
	my $client = $http->params->{client};
	my $params = $http->params->{params};
	
	my $track = eval { from_json( $http->content ) };
	
	if ( $track->{error} ) {
		# We didn't get the next track to play
		
		my $url = Slim::Player::Playlist::url($client);
		if ( $url && $url =~ /\.rdr/ ) {
			# User was already playing, display 'unable to get track' error
			Slim::Music::Info::setCurrentTitle( $url, $client->string('PLUGIN_RHAPSODY_DIRECT_NO_NEXT_TRACK') );
		
			$client->update();

			Slim::Player::Source::playmode( $client, 'stop' );
		}
		else {
			# User was just starting a radio station
			$client->showBriefly( {
				line1 => string( $client, 'PLUGIN_RHAPSODY_DIRECT_ERROR' ),
				line2 => string( $client, 'PLUGIN_RHAPSODY_DIRECT_NO_TRACK' ),
			},
			{
				scroll => 1,
			} );
		}
		
		return;
	}
	
	# Watch for playlist commands in radio mode
	Slim::Control::Request::subscribe( 
		\&playlistCallback, 
		[['playlist'], ['repeat', 'newsong']],
	);
	
	# Force repeating for Rhapsody radio
	Slim::Player::Playlist::repeat( $client, 2 );
	
	# set metadata for track, will be set on playlist newsong callback
	my $url   = 'rhapd://' . $track->{trackId} . '.wma';
	my $title = $track->{name} . ' ' . 
			$client->string('BY') . ' ' . $track->{displayArtistName} . ' ' . 
			$client->string('FROM') . ' ' . $track->{displayAlbumName};
	
	$client->pluginData( radioTrack => $url );
	$client->pluginData( radioTitle => $title );
	$client->pluginData( currentTrack => $track );
	
	my $cb = $params->{callback};
	my $pt = $params->{passthrough} || [];
	$cb->( @{$pt} );
}

sub gotNextRadioTrackError {
	my $http   = shift;
	my $client = $http->params('client');
	
	handleError( $http->error, $client );
}

sub playlistCallback {
	my $request = shift;
	my $client  = $request->client();
	my $p1      = $request->getRequest(1);
	
	return unless defined $client;
	
	# check that user is still using Rhapsody Radio
	my $url = Slim::Player::Playlist::url($client);
	
	if ( !$url || $url !~ /\.rdr$/ ) {
		# stop listening for playback events
		Slim::Control::Request::unsubscribe( \&playlistCallback );
		return;
	}
	
	# The user has changed the repeat setting.  Radio requires a repeat
	# setting of '2' (repeat all) to work properly
	if ( $p1 eq 'repeat' ) {

		$log->debug("Radio mode, user changed repeat setting, forcing back to 2");
		
		Slim::Player::Playlist::repeat( $client, 2 );
		
		if ( $client->playmode =~ /playout/ ) {
			$client->playmode( 'playout-play' );
		}
	}
	elsif ( $p1 eq 'newsong' ) {
		# A new song has started playing.  We use this to change titles
		
		my $title = $client->pluginData('radioTitle');
		
		$log->debug("Setting title for radio station to $title");
		
		Slim::Music::Info::setCurrentTitle( $url, $title );
	}
}

sub gotTrackInfo {
	my ( $client, $mediaUrl, $url, $callback ) = @_;
	
	(undef, $mediaUrl) = unpack 'cn/a*', $mediaUrl;
	
	my ($trackId) = $url =~ /(Tra\.[^.]+)/;
	
	# Save the media URL for use in strm
	$client->pluginData( mediaUrl => $mediaUrl );
	
	if ( $ENV{SLIM_SERVICE} ) {
		# On SN, serialize some track info for display on the website
		Plugins::RhapsodyDirect::Plugin::serializeTrackInfo( $client, $url );
	}
	
	# Allow status updates again
	$client->suppressStatus(0);
	
	# Clear radio error counter
	$client->pluginData( radioError => 0 );
	
	# Async resolve the hostname so gethostbyname in Player::Squeezebox::stream doesn't block
	# When done, callback to Scanner, which will continue on to playback
	# This is a callback to Source::decoderUnderrun if we are loading the next track

	my $dns = Slim::Networking::Async->new;
	$dns->open( {
		Host        => URI->new($mediaUrl)->host,
		Timeout     => 3, # Default timeout of 10 is too long, 
		                  # by the time it fails player will underrun and stop
		onDNS       => $callback,
		onError     => $callback, # even if it errors, keep going
		passthrough => [],
	} );
	
	# Watch for stop commands for logging purposes
	Slim::Control::Request::subscribe( 
		\&stopCallback, 
		[['stop', 'playlist']],
	);
	
	# For debugging, grab extended status info for players at the start of each Rhapsody track
	if ( $ENV{SLIM_SERVICE} ) {
		$client->extendedStatus();
	}
}

sub gotTrackError {
	my ( $error, $client ) = @_;
	
	$log->debug("Error during getTrackInfo: $error");
	
	if ( $ENV{SLIM_SERVICE} ) {
		SDI::Service::EventLog::logEvent(
			$client->id, 'rhapsody_track_error', $error
		);
	}
	
	my $url = Slim::Player::Playlist::url($client);
	
	if ( $url =~ /\.rdr$/ ) {
		# In radio mode, try to restart one time		
		# If we've already tried and get another error,
		# give up so we don't loop forever
		
		if ( $client->pluginData('radioError') ) {
			$client->execute([ 'stop' ]);
			handleError( $error, $client );
		}
		else {
			$client->pluginData( radioError => 1 );
			$client->execute([ 'playlist', 'play', $url ]);
		}
		
		return;
	}
	
	# Normal playlist mode: Skip forward 1 unless we are at the end of the playlist
	if ( Slim::Player::Source::noMoreValidTracks($client) ) {
		# Stop and display error when there are no more tracks to try
		$client->execute([ 'stop' ]);
		handleError( $error, $client );
	}
	else {
		Slim::Player::Source::jumpto( $client, '+1' );
	}
}

sub canDirectStream {
	my ( $class, $client, $url ) = @_;
	
	# Might be a radio station
	if ( my ($stationId) = $url =~ m{rhapd://(.+)\.rdr} ) {
		if ( my $radioTrack = $client->pluginData('radioTrack') ) {
			$url = $radioTrack;
		}
	}
	
	# Return the RAD URL here
	my ($trackId) = $url =~ /(Tra\.[^.]+)/;
	
	# Needed so stopCallback can have the URL after a 'playlist clear'
	$client->pluginData( lastURL => $url );
	
	my $mediaUrl = $client->pluginData('mediaUrl');

	return $mediaUrl || 0;
}

sub stopCallback {
	my $request = shift;
	my $client  = $request->client();
	my $p0      = $request->getRequest(0);
	my $p1      = $request->getRequest(1);
	
	return unless defined $client;
	
	# Handle 'stop' and 'playlist clear'
	if ( $p0 eq 'stop' || ( $p1 && $p1 eq 'clear' ) ) {

		# Check that the user is still playing Rhapsody
		my $url = Slim::Player::Playlist::url($client) || $client->pluginData('lastURL');

		if ( !$url || $url !~ /^rhapd/ ) {
			# stop listening for stop events
			Slim::Control::Request::unsubscribe( \&stopCallback );
			return;
		}
		
		if ( $ENV{SLIM_SERVICE} ) {
			SDI::Service::EventLog::logEvent(
				$client->id, 'rhapsody_stop'
			);
		}

		my $songtime = Slim::Player::Source::songTime($client);
		
		if ( $songtime > 0 ) {	
			$log->debug("Player stopped, logging usage info ($songtime seconds)...");
	
			# There are different log methods for normal vs. radio play
			my $data;

			if ( my ($stationId) = $url =~ m{rhapd://(.+)\.rdr} ) {
				# logMeteringInfoForStationTrackPlay
				$data = pack( 'cC/a*C/a*', 5, $songtime, $stationId );
			}
			else {
				# logMeteringInfo
				$data = pack( 'cC/a*', 4, $songtime );
			}
			
			# Call endPlaybackSession when stopping
			rpds( $client, {
				data        => $data,
				callback    => \&endPlaybackSession,
				onError     => sub {
					# We don't really care if the logging call fails,
					# so allow onError to work like the normal callback
					endPlaybackSession( $client );
				},
				passthrough => [],
			} );
		}
	}
}

sub endPlaybackSession {
	my $client = shift;
	
	rpds( $client, {
		data        => pack( 'c', 6 ),
		callback    => sub {},
		onError     => sub {}, # doesn't matter if this one fails
		passthrough => [],
	} );
}

sub displayStatus {
	my ( $client, $url, $string, $time ) = @_;
	
	my $line1 = $client->string('NOW_PLAYING') . ' (' . $client->string($string) . ')';
	my $line2 = Slim::Music::Info::title($url) || $url;
	
	if ( $client->linesPerScreen() == 1 ) {
		$line2 = $client->string($string);
	}

	$client->showBriefly( $line1, $line2, $time );
}

# Track Info menu
sub trackInfo {
	my ( $class, $client, $track ) = @_;
	
	my ($url, $trackId);
	
	if ( $track->url =~ /\.rdr$/ ) {
		# Radio mode, pull track ID from lastURL
		$url = $client->pluginData('lastURL');
	}
	else {
		$url = $track->url;
	}

	($trackId) = $url =~ m{rhapd://(.+)\.wma};
	
	$log->debug( "Getting track information for $trackId" );
	
	# SN URL to fetch track info menu
	my $trackInfoURL = Slim::Networking::SqueezeNetwork->url(
		'/api/rhapsody/opml/metadata/getTrack?trackId=' . $trackId
	);
	
	if ( $track->url =~ m{rhapd://(.+)\.rdr} ) {
		$trackInfoURL .= '&stationId=' . $1;
	}
	
	# let XMLBrowser handle all our display
	my %params = (
		header   => 'PLUGIN_RHAPSODY_DIRECT_GETTING_TRACK_DETAILS',
		modeName => 'Rhapsody Now Playing',
		title    => Slim::Music::Info::getCurrentTitle( $client, $url ),
		url      => $trackInfoURL,
	);

	Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );
	
	$client->modeParam( 'handledTransition', 1 );
}

# Metadata hashref used by CLI/JSON clients
sub getCurrentMeta {
	my ( $class, $client, $url ) = @_;
	
	my $track = $client->pluginData('currentTrack') || return;
	
	return {
		artist => $track->{displayArtistName},
		album  => $track->{displayAlbumName},
		title  => $track->{name},
		cover  => $track->{cover} || $track->{albumMetadata}->{albumArt162x162Url},
	};
}

# SN only, re-init upon reconnection
sub reinit {
	my ( $class, $client, $playlist, $currentSong ) = @_;
	
	$log->debug('Re-init Rhapsody');
	
	SDI::Service::EventLog::logEvent(
		$client->id, 'rhapsody_reconnect'
	);
	
	# If in radio mode, re-add only the single item
	if ( scalar @{$playlist} == 1 && $playlist->[0] =~ /\.rdr$/ ) {
		$client->execute([ 'playlist', 'add', $playlist->[0] ]);
	}
	else {	
		# Re-add all playlist items
		$client->execute([ 'playlist', 'addtracks', 'listref', $playlist ]);
	}
	
	# Make sure we are subscribed to stop/playlist commands
	# Watch for stop commands for logging purposes
	Slim::Control::Request::subscribe( 
		\&stopCallback, 
		[['stop', 'playlist']],
	);
	
	# Reset song duration/progress bar
	my $currentURL = $playlist->[ $currentSong ];
	
	if ( my $length = $client->pluginData('length') ) {			
		# On a timer because $client->currentsongqueue does not exist yet
		Slim::Utils::Timers::setTimer(
			$client,
			Time::HiRes::time(),
			sub {
				my $client = shift;
				
				$client->streamingProgressBar( {
					url     => $currentURL,
					length  => $length,
					bitrate => 128000,
				} );
				
				# If it's a radio station, reset the title
				if ( my ($stationId) = $currentURL =~ m{rhapd://(.+)\.rdr} ) {
					my $title = $client->pluginData('radioTitle');

					$log->debug("Resetting title for radio station to $title");

					Slim::Music::Info::setCurrentTitle( $currentURL, $title );
				}
				
				# Back to Now Playing
				# This is within the timer because otherwise it will run before
				# addtracks adds all the tracks, and not jump to the correct playing item
				Slim::Buttons::Common::pushMode( $client, 'playlist' );
			},
		);
	}
}

1;