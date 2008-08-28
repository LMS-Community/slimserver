package Slim::Plugin::Sirius::ProtocolHandler;

# $Id$

# TODO:
# Test with transcoding
# Test synced
# Test add to favorites
# Detect player gone away, stop updates
# SN web images

use strict;
use base qw(Slim::Player::Protocols::MMS);

use Slim::Music::Info;
use Slim::Networking::Async::HTTP;
use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Misc;
use Slim::Utils::Timers;

use HTTP::Request;
use JSON::XS qw(from_json);
use URI::Escape qw(uri_escape);

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.sirius',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_SIRIUS_MODULE_NAME',
} );

sub audioScrobblerSource { 'R' }

sub getFormatForURL { 'wma' }

sub isAudioURL { 1 }

sub isRemote { 1 }

# Support transcoding
sub new {
	my $class = shift;
	my $args  = shift;

	my $client = $args->{client};
	my $url    = $client->pluginData('url');
	
	return unless $url;

	return $class->SUPER::new( {
		client => $client,
		url    => $url,
	} );
}

sub onJump {
	my ( $class, $client, $nextURL, $callback ) = @_;
	
	my ($channelId) = $nextURL =~ m{^sirius://(.+)};
	
	getChannelInfo( $client, {
		channelId => $channelId,
		callback  => $callback,
	} );
	
	# Update the 'Connecting...' text
	Slim::Utils::Timers::setTimer(
		undef,
		time(),
		sub {
			displayStatus( $client, $nextURL, 'PLUGIN_SIRIUS_GETTING_STREAM_INFO', 60 );
		},
	);

	return;
}

sub displayStatus {
	my ( $client, $url, $string, $time ) = @_;
	
	my $line1 = $client->string('NOW_PLAYING') . ' (' . $client->string($string) . ')';
	my $line2 = Slim::Music::Info::title($url) || $url;
	
	if ( $client->linesPerScreen() == 1 ) {
		$line2 = $client->string($string);
	}

	$client->showBriefly( {
		line => [ $line1, $line2 ],
	},
	{
		duration => $time,
	} );
}

sub getChannelInfo {
	my ( $client, $params ) = @_;
	
	# Talk to SN and get the channel info for this station
	my $infoURL = Slim::Networking::SqueezeNetwork->url(
		"/api/sirius/v1/playback/getChannelInfo?channelId=" . $params->{channelId}
	);
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&gotChannelInfo,
		\&gotChannelInfoError,
		{
			client  => $client,
			params  => $params,
			timeout => 60, # Sirius can be pretty slow
		},
	);
	
	$log->debug("Getting channel info from SqueezeNetwork for " . $params->{channelId} );
	
	$http->get( $infoURL );
}

sub gotChannelInfo {
	my $http   = shift;
	my $client = $http->params->{client};
	my $params = $http->params->{params};
	
	my $url = Slim::Player::Playlist::url($client);
	
	my $info = eval { from_json( $http->content ) };
	
	if ( $@ || ref $info ne 'HASH' ) {
		$info = {
			error => $@ || 'Invalid JSON reponse',
		};
	}
	
	if ( $log->is_debug ) {
		$log->debug( "Got Sirius channel info: " . Data::Dump::dump($info) );
	}
	
	if ( $info->{error} ) {
		# We didn't get the info to play		
		my $title = $client->string('PLUGIN_SIRIUS_NO_INFO') . ' (' . $info->{error} . ')';
		
		$client->showBriefly( {
			line1 => $client->string('PLUGIN_SIRIUS_ERROR'),
			line2 => $title,
		},
		{
			scroll => 1,
		} );
	
		return;
	}
	
	# Find best stream URL
	my $streamURL;
	my $activityInterval;
	my $bitrate;
	
	for my $stream ( @{ $info->{streams} } ) {
		if ( $stream->{Enabled} eq 'true' ) {
			$streamURL        = $stream->{content};
			$activityInterval = $stream->{ActivityInterval};
			$bitrate          = $stream->{Bitrate} * 1000;
			last;
		}
	}
	
	$streamURL =~ s/^http/mms/;
	
	# Save metadata for this track
	$client->pluginData( url     => $streamURL );
	$client->pluginData( bitrate => $bitrate );
	$client->pluginData( logo    => $info->{logo} );
	
	# Connect to the metadata sub-stream for this station
	connectMetadataStream( $client, $streamURL );
	
	# Start a timer to check status at the defined interval
	$log->debug( 'Polling status in ' . $info->{status}->{PollingInterval} . ' seconds' );
	Slim::Utils::Timers::killTimers( $client, \&pollStatus );
	Slim::Utils::Timers::setTimer( 
		$client,
		Time::HiRes::time() + $info->{status}->{PollingInterval},
		\&pollStatus,
		$info->{status},
	);

	# Start a timer to make sure the user remains active
	$log->debug( "Checking activity in $activityInterval seconds" );
	Slim::Utils::Timers::killTimers( $client, \&checkActivity );
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time() + $activityInterval,
		\&checkActivity,
		$activityInterval,
	);
	
	my $cb = $params->{callback};
	$cb->();
}

sub gotChannelInfoError {
	my $http   = shift;
	my $client = $http->params('client');
	
	handleError( $http->error, $client );
}

sub handleError {
    my ( $error, $client ) = @_;

	if ( $client ) {
		$client->unblock;
		
		Slim::Buttons::Common::pushModeLeft( $client, 'INPUT.Choice', {
			header  => '{PLUGIN_SIRIUS_ERROR}',
			listRef => [ $error ],
		} );
		
		if ( main::SLIM_SERVICE ) {
			SDI::Service::EventLog->log(
				$client, 'sirius_error', $error,
			);
		}
	}
}

sub canDirectStream {
	my ( $class, $client, $url ) = @_;
	
	if ( my $url = $client->pluginData('url') ) {
		return $url;
	}
	
	return 0;
}

sub parseDirectHeaders {
	my $class   = shift;
	my $client  = shift || return;
	my $url     = shift;
	my @headers = @_;
	
	my $contentType = 'wma';
	my $bitrate     = $client->pluginData('bitrate');
	
	# title, bitrate, metaint, redir, type, length, body
	return (undef, $bitrate, 0, undef, $contentType, undef, undef);
}

sub pollStatus {
	my ( $client, $status ) = @_;
	
	# Make sure we're still playing Sirius
	my $url = Slim::Player::Playlist::url($client);
	return unless $client->playmode =~ /play|pause/ && $url =~ /^sirius/;
	
	$log->debug("Polling status...");

	my $statusURL = Slim::Networking::SqueezeNetwork->url(
		"/api/sirius/v1/playback/streamStatus?content=" . uri_escape( $status->{content} )
	);
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&gotPollStatus,
		\&gotPollStatusError,
		{
			client  => $client,
			status  => $status,
			timeout => 60,
		},
	);
	
	$http->get( $statusURL );
}

sub gotPollStatus {
	my $http   = shift;
	my $client = $http->params('client');
	my $status = $http->params('status');
	
	my $info = eval { from_json( $http->content ) };
	
	if ( $@ || ref $info ne 'HASH' ) {
		$info = {
			error => $@ || 'Invalid JSON reponse',
		};
	}
	
	if ( $log->is_debug ) {
		$log->debug( "Got Sirius stream status: " . Data::Dump::dump($info) );
	}
	
	if ( $info->{error} ) {
		# We didn't get the status, try again using the previous poll interval
		$log->error( "Error getting Sirius stream status: " . $info->{error} );
		
		Slim::Utils::Timers::killTimers( $client, \&pollStatus );
		Slim::Utils::Timers::setTimer( 
			$client,
			Time::HiRes::time() + $status->{PollingInterval},
			\&pollStatus,
			$status,
		);
		return;
	}
	
	if ( $info->{Status} ne 'open' ) {
		stopStreaming( $client, 'PLUGIN_SIRIUS_STOPPING_UNAUTHORIZED' );
		return;
	}
	
	# Add the status URL, for some reason it's not included in the status response
	$info->{content} = $status->{content};
	
	$log->debug( "Sirius stream status OK, polling again in " . $info->{PollingInterval} );
	
	# Stream is OK, setup next poll
	Slim::Utils::Timers::killTimers( $client, \&pollStatus );
	Slim::Utils::Timers::setTimer( 
		$client,
		Time::HiRes::time() + $info->{PollingInterval},
		\&pollStatus,
		$info,
	);
}

sub gotPollStatusError {
	my $http   = shift;
	my $error  = $http->error;
	my $client = $http->params('client');
	my $status = $http->params('status');
	
	$log->error( "Error getting Sirius stream status: " . $error );
	
	# Retry getting status later
	Slim::Utils::Timers::killTimers( $client, \&pollStatus );
	Slim::Utils::Timers::setTimer( 
		$client,
		Time::HiRes::time() + $status->{PollingInterval},
		\&pollStatus,
		$status,
	);
}
	

sub checkActivity {
	my ( $client, $interval ) = @_;
	
	# Make sure we're still playing Sirius
	my $url = Slim::Player::Playlist::url($client);
	return unless $client->playmode =~ /play|pause/ && $url =~ /^sirius/;
	
	# Check for activity within last $interval seconds
	# If idle time has been exceeded, stop playback
	my $now          = Time::HiRes::time();
	my $lastActivity = $client->lastActivityTime();
	if ( $now - $lastActivity >= $interval ) {
		
		$log->debug("User has been inactive for at least $interval seconds, stopping");
		
		stopStreaming( $client, 'PLUGIN_SIRIUS_STOPPING_INACTIVE' );
	}
	else {
		
		if ( $log->is_debug ) {
			my $inactive  = $now - $lastActivity;
			my $nextCheck = $interval - $inactive;
			$log->debug( "User has been inactive for only $inactive seconds, next check in $nextCheck" );
		}
		
		# Check again when the user would next be inactive for $interval seconds
		Slim::Utils::Timers::setTimer(
			$client,
			Time::HiRes::time() + ( $interval - ( $now - $lastActivity ) ),
			\&checkActivity,
			$interval,
		);
	}
}

sub stopStreaming {
	my ( $client, $string ) = @_;
	
	# Change the stream title to the error message
	my $url = Slim::Player::Playlist::url($client);
	Slim::Music::Info::setCurrentTitle( $url, $client->string($string) );
	
	$client->update();
	
	# Kill all timers
	Slim::Utils::Timers::killTimers( $client, \&pollStatus );
	Slim::Utils::Timers::killTimers( $client, \&checkActivity );
	
	$client->execute( [ 'stop' ] );
}

sub connectMetadataStream {
	my ( $client, $url ) = @_;
	
	$log->debug( 'Connecting to Sirius metadata stream...' );
	
	$url =~ s/^mms/http/;
	
	# Construct the request for stream #2
	my $request = HTTP::Request->new( GET => $url );
	my $h = $request->headers;
	$h->header( Accept => '*/*' );
	$h->header( 'User-Agent' => 'NSPlayer/8.0.0.3802' );
	$h->header( Pragma => [
		'xClientGUID={' . Slim::Player::Protocols::MMS::randomGUID(). '}',
		'no-cache,rate=1.0000000,stream-time=0,stream-offset=0:0,request-context=2,max-duration=0',
		'LinkBW=2147483647, AccelBW=1048576, AccelDuration=18000',
		'Speed=5.000',
		'xPlayStrm=1',
		'stream-switch-count=1',
		'stream-switch-entry=ffff:2:0 ',
	] );
	$h->header( Connection => 'close' );
	
	# Start streaming it
	my $http = Slim::Networking::Async::HTTP->new();
	$http->send_request( {
		request     => $request,
		Timeout     => 60,
		onStream    => \&handleMetadataStream,
		onError     => sub {
			my ( $http, $error ) = @_;

			$log->error("Error on metadata stream: $error.");
		},
		passthrough => [ $client, $url ],
	} );
}

sub handleMetadataStream {
	my ( $http, $data_ref, $client, $url ) = @_;
	
	return 0 if !blessed $client;
	
	# Make sure we're still playing Sirius
	my $playlistURL = Slim::Player::Playlist::url($client);
	if ( $client->playmode !~ /play|pause/ || $playlistURL !~ /^sirius/ ) {
		$log->debug( "Player stopped or changed streams (playmode: " . $client->playmode . ", url: $playlistURL), disconnecting from metadata stream for $url" );
		return 0;
	}
	
	# Get the real URL of the playing station to compare with the metadata URL
	my $realURL = $client->pluginData('url');
	my $mmsURL  = $url;
	$mmsURL    =~ s/^http/mms/;
	
	# See if they changed Sirius stations
	if ( $realURL ne $mmsURL ) {
		$log->debug( "Playlist changed, disconnecting from metadata stream ($realURL ne $mmsURL)" );
		return 0;
	}
	
	# Format of the metadata stream is:
	# TITLE <title>|ARTIST <artist>\0
	
	# WMA text is in UTF-16, if we can't decode it, just wait for more data
	my $metadata = eval { Encode::decode('UTF-16LE', $$data_ref ) } || return 1;
	
	#$log->debug( "ASF_Command_Media: $metadata" );
	
	my ($artist, $title);
	
	if ( $metadata =~ /TITLE\s+([^|]+)/ ) {
		$title = $1;
	}
	
	if ( $metadata =~ /ARTIST\s([^\0]+)/ ) {
		$artist = $1;
	}
	
	if ( $artist || $title ) {
		if ( $artist && $artist ne $title ) {
			$title = "$artist - $title";
		}
		
		Slim::Music::Info::setDelayedTitle( $client, $playlistURL, $title );
	}
	
	# Signal we want more data
	return 1;
}

# Metadata for a URL, used by CLI/JSON clients
sub getMetadataFor {
	my ( $class, $client, $url ) = @_;

	my ($artist, $title);
	# Return artist and title if the metadata looks like Artist - Title
	if ( my $currentTitle = Slim::Music::Info::getCurrentTitle( $client, $url ) ) {
		my @dashes = $currentTitle =~ /( - )/g;
		if ( scalar @dashes == 1 ) {
			($artist, $title) = split / - /, $currentTitle;
		}

		else {
			$title = $currentTitle;
		}
	}
	
	my $bitrate = $client->pluginData('bitrate') / 1000;
	my $logo    = $class->getIcon($url, $client);
	
	return {
		artist  => $artist,
		title   => $title,
		cover   => $logo,
		bitrate => $bitrate . 'k CBR',
		type    => 'WMA (Sirius)',
	};
}

sub getIcon {
	my ( $class, $url, $client ) = @_;

	return $client->pluginData('logo') if ($client && $client->pluginData('logo'));

	return Slim::Plugin::Sirius::Plugin->_pluginDataFor('icon');
}

# SN only
sub reinit {
	my ( $class, $client, $playlist ) = @_;
	
	my $url = $playlist->[0];
	
	# XXX: To properly re-init Sirius we need to:
	# * Reconnect to WMA metadata stream, this may not
	#   work due to the timeout on the Akamai URLs
	# * Restart pollStatus timer
	# * Restart checkActivity timer
	
	$log->debug( "Reinit Sirius for $url" );
	
	# Ignore the check for playing status
	$client->ignoreCheckPlayingStatus(1);
	
	# For now, just restart the stream
	$client->execute( [ 'playlist', 'play', $url ] );
}    

1;
