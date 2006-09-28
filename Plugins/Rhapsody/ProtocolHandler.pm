package Plugins::Rhapsody::ProtocolHandler;

use strict;
use base  qw(Slim::Player::Protocols::HTTP);

use File::Slurp qw(read_file);
use IO::Socket qw(:DEFAULT :crlf);

use Slim::Formats::Playlists::M3U;
use Slim::Utils::IPDetect;
use Slim::Utils::Misc;

my %radioTracks = ();

sub new {
	my $class  = shift;
	my $args   = shift;

	my $url    = $args->{'url'};
	my $client = $args->{'client'};

	$args->{'infoUrl'} = $url;

	$url =~ s/^rhap/http/;
	$args->{'url'} = $url;

	return $class->SUPER::new($args);
}

sub canDirectStream {
	my $self = shift;
	my $client = shift;
	my $url = shift;
	
	$url = _verifyPort( $url );
	
	if ( $url =~ /\.rhr$/ ) {
		# Watch for playlist commands for radio mode
		Slim::Control::Request::subscribe( 
			\&playlistCallback, 
			[['playlist'], ['repeat', 'newsong']],
		);
		return $url;
	}
	
	# Direct stream supported for audio files but not playlists
	return $url if $url =~ /\.wma$/;

	return;
}

sub getFormatForURL {
	my $classOrSelf = shift;
	my $url = shift;

	return 'wma';
}

sub isAudioURL {
	my ( $class, $url ) = @_;
	
	# Consider Rhapsody audio and radio URLs as audio so they won't be scanned
	if ( $url =~ /^rhap.+(?:wma|rhr)$/ ) {
		return 1;
	}
	
	return;
}

sub isUnsupported {
	my ( $class, $model ) = @_;
	
	if ( $model =~ /^(?:slimp3|squeezebox|softsqueeze)$/ ) {
		return 'PLUGIN_RHAPSODY_UNSUPPORTED';
	}
	
	return;
}

sub requestString {
	my $classOrSelf = shift;
	my $client = shift;
	my $url = shift;
	my $post = shift;
	my $direct = shift;

	# Radio rhr (actually m3u) files must be reloaded for each
	# track. If we followed the regular path for playlist loading, the
	# originally radio URL would be replaced with that of the current
	# song and on the next iteration of the repeat loop, we'd play the
	# same song again. Instead, we save the single track within the
	# rhr file in the %radioTracks hash and return the radio URL as
	# the result of rhr parsing (i.e. as if the rhr file referred to
	# itself. The next time a request comes in for the rhr file, we
	# actually send a request string for the saved song. Once that
	# song has been played, we go back to returning a request string
	# for the rhr file itself.
	if ($url =~ /\.rhr$/) {
		
		# Force repeating for Rhapsody radio files.
		Slim::Player::Playlist::repeat($client, 2);
		
		my $rhapURL = $url;
		$rhapURL =~ s/^http/rhap/;
		
		if ( my $trackURL = $radioTracks{ $client->id }->{$rhapURL} ) {
			
			# direct stream the audio file
			$url = $trackURL;
			
			if ( $client->master ) {
				$::d_plugins && msgf("Rhapsody: [%s] Radio mode, synced slave got playlist track from master: %s\n",
					$client->id,
					$url,
				);
			}
		}
		else {
			# If synced, only the master should request the playlist rhr file
			if ( $client->master ) {
				$::d_plugins && msgf("Rhapsody: [%s] Radio mode, synced slave not requesting playlist\n",
					$client->id,
				);
				
				# XXX: This will cause a 'can't connect' error on the slave(s), but will (hopefully)
				# connect on repeat when the master gets a playlist track.  Sometimes Rhapsody will
				# return a 403 error when a slave tries to request a radio track.
				return;
			}
		}
	}

	my ($host, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($url);

	my $mode = "SessionStart";
	# If we got here without any user interaction (the current play
	# "session" hasn't eneded) we send a SessionContinue.
	if ( $client && $client->lastSong() =~ /(?:wma|rhr)$/ ) {
		$mode = "SessionContinue";
	}
	
	# Use full path for proxy servers
	my $proxy = Slim::Utils::Prefs::get('webproxy');
	if ( $proxy ) {
		$path = "http://$host:$port$path";
	}

	my @headers = (
		"GET $path HTTP/1.0",
		"Accept: */*",
		"User-Agent: " . Slim::Utils::Misc::userAgentString(),
		"Host: $host",
		"X-Rhapsody-Device-Id: urn:rhapsody-real-com:device-id-1-0:slimdevices_1:" . (defined($client) ? $client->macaddress() : 'slimserver'),
		"X-Rhapsody-Request-Mode: $mode",
	);

	my $request;
	if ($direct) {
		# If direct streaming, 1 additional header will be added by the player
		$request = join($CRLF, @headers) . $CRLF;
	}
	else {
		# If not direct streaming, we need to add that header ourselves
		push @headers, 'X-Rhapsody-Request-Token: ' . time;
		$request = join($CRLF, @headers) . $CRLF . $CRLF;
	}
	
	return $request;
}

sub handleDirectError {
	my $self = shift;
	my $client = shift;
	my $url = shift;
	my $response = shift;
	my $status_line = shift;

	# Rhapsody errors:
	# 401 - Unauthorized
	# 404 - File not found
	# 409 - Conflict (Busy, i.e. more than 3 players trying to play)
	# 412 - Stale (timed out)
	# 500 - Server error
	
	my $responses = {
		401 => 'PLUGIN_RHAPSODY_ERROR_UNAUTH',
		403 => 'PLUGIN_RHAPSODY_ERROR_FORBIDDEN',       # undocumented, but happens sometimes
		404 => 'PLUGIN_RHAPSODY_ERROR_FILE_NOT_FOUND',
		409 => 'PLUGIN_RHAPSODY_ERROR_BUSY',
		412 => 'PLUGIN_RHAPSODY_ERROR_STALE',
		500 => 'PLUGIN_RHAPSODY_ERROR_INTERNAL',
	};
	
	if ( my $error = $responses->{$response} ) {	
		# Bug 2226, stop after the current song ends
		my $elapsed  = $client->songElapsedSeconds;
		
		# Generally we'll run into these errors only as the next track begins to buffer
		# Therefore, the current track's duration moves into the -1 song queue slot
		my $tracklen = 
			( $client->currentsongqueue->[-1] ) 
			? $client->currentsongqueue->[-1]->{'duration'}
			: $client->currentsongqueue->[0]->{'duration'};
			
		my $stopIn = $tracklen - $elapsed;
		my $stopAt = time + ( $stopIn || 0 );
		
		$::d_plugins && msgf("Rhapsody: [%s] Got error %s, stopping player after current song (in %d seconds).\n",
			$client->id,
			$error,
			$stopIn || 0,
		);

		Slim::Utils::Timers::setTimer( $client, $stopAt, sub {
			my $client = shift;
			$client->execute(["stop"]);
			$client->showBriefly( $client->string($error), undef, 3, undef );
		} );
	}
	else {
		$client->failedDirectStream($status_line);
	}
}

sub parseDirectHeaders {
	my $self = shift;
	my $client = shift;
	my $url = shift;
	my @headers = @_;

	my ($contentType, $mimeType, $length, $body, $encType, $encParams);

	foreach my $header (@headers) {

		$::d_directstream && msg("Rhapsody header: " . $header . "\n");

		if ($header =~ /^Content-Type:\s*(.*)/i) {
			$mimeType = $1;
		}

		if ($header =~ /^Content-Length:\s*(.*)/i) {
			$length = $1;
		}

		if ($header =~ /^Content-Encoding:\s*(.*)/i) {
			$encType = $1;
		}
		
		if ($header =~ /^X-Rhapsody-Encoding-Parameters:\s*(.*)/i) {
			$encParams = $1;
		}
	}

	if ($mimeType eq "audio/x-rhap-radio") {
		$contentType = 'm3u';
	}
	elsif ($mimeType eq "audio/x-ms-wma") {
		$contentType = 'wma';
	}
	else {
		$contentType = Slim::Music::Info::mimeToType($mimeType) || 'wma';
	}

	if ($encType) {
		my $frame = pack('nn', length($encType), length($encParams));
		$frame .= $encType . $encParams;

		$client->sendFrame('rhap', \$frame);
	}
	
	# clear duration information for this URL if we're playing radio
	if ( $url =~ /rhr$/ ) {
		Slim::Music::Info::setDuration( $url, 0 );
	}

	return (undef, undef, 0, '', $contentType, $length, $body);
}

# parseDirectBody reads rhr radio playlist files
# They need to be directly handled by the player because we dynamically change
# the direct stream URL in order to play the audio file.
sub parseDirectBody {
	my $classOrSelf = shift;
	my $client      = shift;
	my $url         = shift;
	
	# Read in the temporary file since we need to modify it
	my $body = read_file( $client->directBody );
	
	# Note: Rhapsody never sends back audio body data for security purposes,
	# so this only needs to worry about processing playlists
	
	# If synced, we only want the master to read the playlist
	return ($url) if $client->master;

	if ($url =~ /\.rhr$/) {
		# For radio playlists, don't lop off too much, just the
		# extra angle brackets.
		$body =~ s/#EXTINF\:(.*?),<(.*?)> - <(.*?)> - <(.*?)>/#EXTINF\:$1,$2 - $3 - $4/g;
	}
	
	my $io = IO::String->new($body);
	my @tracks = Slim::Formats::Playlists::M3U->read($io, undef, $url);

	# For rhr files, we save off the contained track and return the
	# URL of the rhr file itself. This way we don't lose the original
	# URL and we can go back to it after the song has played out.
	if ( $url =~ /\.rhr$/ && scalar @tracks ) {
		my $trackURL = ( ref $tracks[0] ) ? $tracks[0]->url : $tracks[0];
		
		# For sync, loop through all synced clients and set trackURL for each
		for my $everybuddy ( $client, Slim::Player::Sync::syncedWith($client) ) {
			$radioTracks{ $everybuddy->id }->{$url} = $trackURL;
		}

		# change the format of this URL back to wma so $client->stream doesn't think it's m3u
		Slim::Music::Info::setContentType( $url, 'wma' );
		
		return ($url);
	}

	return @tracks;
}

sub playlistCallback {
	my $request = shift;
	my $client  = $request->client();
	my $p1      = $request->getRequest(1);
	
	return unless defined $client;
	
	# check that user is still using Rhapsody Radio
	my $url = Slim::Player::Playlist::url($client);
	
	if ( !$url || $url !~ /\.rhr$/ ) {
		# stop listening for playback eventss
		Slim::Control::Request::unsubscribe( \&playlistCallback );
		return;
	}
	
	# The user has changed the repeat setting.  Radio requires a repeat
	# setting of '2' (repeat all) to work properly
	if ( $p1 eq 'repeat' ) {
		$::d_plugins && msg("Rhapsody: Radio mode, user changed repeat setting, forcing back to 2\n");
		
		Slim::Player::Playlist::repeat( $client, 2 );
		
		if ( $client->playmode =~ /playout/ ) {
			$client->playmode( 'playout-play' );
		}
	}
	elsif ( $p1 eq 'newsong' ) {
		# A new song has started playing.  We use this to change titles
		my $trackURL = delete $radioTracks{ $client->id }->{$url};
		my $title    = Slim::Music::Info::standardTitle( $client, $trackURL );
		
		Slim::Music::Info::setCurrentTitle( $url, $title );
	}
}

sub canDoAction {
	my $self = shift;
	my $client = shift;
	my $url = shift;
	my $action = shift;

	if ( $url =~ /\.rhr/ && ( $action eq 'pause' || $action eq 'rew' ) ) {
			
		if ( $action eq 'pause' ) {
			# clear the current track's duration, so unpause will set a new title
			if ( $client->currentsongqueue->[0] ) {
				delete $client->currentsongqueue->[0]->{'duration'};
			}
		}
		
		return 0;
	}

	return 1;
}

# Make sure our port number is correct, in case the user restarted Rhapsody
sub _verifyPort {
	my $url = shift;
	
	my ($host, $port) = $url =~ m|//([0-9.]+):(\d+)|;	
	my $realPort = Plugins::Rhapsody::Plugin::getPortForHost($host);
	
	# if we don't see this host in the list of connected servers, don't modify the URL
	if ( !$realPort ) {
		return $url;
	}
	
	# If Rhapsody is running on the same PC as SlimServer, UPnP may report in as 127.0.0.1
	# but we need the real IP address for SBs to connect to
	if ( $host =~ /(?:127.0.0.1|localhost)/ ) {
		my $realIP = Slim::Utils::IPDetect::IP();
		$url       =~ s/$host/$realIP/;
	}
	
	if ( $port != $realPort ) {
		$url =~ s/$port/$realPort/;
	}

	return $url;
}

1;


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
