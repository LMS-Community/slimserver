package Slim::Player::Protocols::MMS;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech, Vidur Apparao.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Player::Pipeline);

use Audio::WMA;
use File::Spec::Functions qw(:ALL);
use IO::Socket qw(:DEFAULT :crlf);

use Slim::Formats::Playlists;
use Slim::Player::Source;
use Slim::Player::TranscodingHelper;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

my $log = logger('player.streaming.direct');

use constant DEFAULT_TYPE => 'wma';

# Use the same random GUID for all connections
our $guid;

=head2 new ( $class, $args )

Create a new instance of the MMS protocol handler, only for transcoding using wmadec or
another command-line tool.

=cut

sub new {
	my $class = shift;
	my $args  = shift;

	my $url    = $args->{'url'};
	my $client = $args->{'client'};

	# Set the content type to 'wma' to get the convert command
	my ($command, $type, $format) = Slim::Player::TranscodingHelper::getConvertCommand($client, $url, DEFAULT_TYPE);

	unless (defined($command) && $command ne '-') {

		logger('player.streaming.remote')->error("Error: Couldn't find conversion command for wma!");

		# XXX - errorOpening should not be in Source!
		Slim::Player::Source::errorOpening($client, $client->string('WMA_NO_CONVERT_CMD'));

		return undef;
	}

	my $maxRate = 0;
	my $quality = 1;

	if (defined($client)) {
		$maxRate = Slim::Utils::Prefs::maxRate($client);
		$quality = $prefs->client($client)->get('lameQuality');
	}

	$command = Slim::Player::TranscodingHelper::tokenizeConvertCommand($command, $type, $url, $url, 0, $maxRate, 1, $quality);

	my $self = $class->SUPER::new(undef, $command);

	${*$self}{'contentType'} = $format;

	return $self;
}

sub contentType {
	my $self = shift;

	return ${*$self}{'contentType'};
}

# Whether or not to display buffering info while a track is loading
sub showBuffering {
	my ( $class, $client, $url ) = @_;
	
	return $client->showBuffering;
}

sub randomGUID {

	return $guid if $guid;
	
	$guid = '';

	for my $digit (0...31) {

        	if ($digit==8 || $digit == 12 || $digit == 16 || $digit == 20) {

			$guid .= '-';
		}
		
		$guid .= sprintf('%x', int(rand(16)));
	}

	return $guid;
}

sub canDirectStream {
	my ($classOrSelf, $client, $url) = @_;

	# Bug 3181 & Others. Check the available types - if the user has
	# disabled built-in WMA, return false. This is required for streams
	# that are MMS only, or for WMA codecs we don't support in firmware.
	my ($command, $type, $format) = Slim::Player::TranscodingHelper::getConvertCommand($client, $url, DEFAULT_TYPE);

	if (defined $command && $command eq '-') {
		return $url;
	}

	return 0;
}

# Most WM streaming stations also stream via HTTP. The requestString class
# method is invoked by the direct streaming code to obtain a request string
# to send to a WM streaming server. We construct a HTTP request string and
# cross our fingers. 
sub requestString {
	my $classOrSelf = shift;
	my $client      = shift;
	my $url         = shift;

	my ($server, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($url);

	# Use full path for proxy servers
	my $proxy = $prefs->get('webproxy');
	if ( $proxy && $server !~ /(?:localhost|127.0.0.1)/ ) {
		$path = "http://$server:$port$path";
	}

	my $host = $port == 80 ? $server : "$server:$port";

	my @headers = (
		"GET $path HTTP/1.0",
		"Accept: */*",
		"User-Agent: NSPlayer/4.1.0.3856",
		"Host: $host",
		"Pragma: xClientGUID={" . randomGUID() . "}",
	);
	
	my $streamNum = $client->scanData->{streamNum} || 1;
	my $metadata  = $client->scanData->{metadata};
	my $seekdata  = $client->scanData->{seekdata}  || {};
	
	# Handle our metadata
	if ( $metadata ) {
		setMetadata( $client, $url, $metadata, $streamNum );
	}
	
	my $newtime = $seekdata->{newtime};
	
	my $context    = $newtime ? 4 : 2;
	my $streamtime = $newtime ? $newtime * 1000 : 0;

	push @headers, (
		"Pragma: no-cache,rate=1.0000000,stream-offset=0:0,max-duration=0",
		"Pragma: stream-time=$streamtime",
		"Pragma: request-context=$context",
		"Pragma: xPlayStrm=1",
		"Pragma: stream-switch-count=1",
		"Pragma: stream-switch-entry=ffff:" . $streamNum . ":0 ",
	);
	
	# Fix progress bar if seeking
	if ( $newtime ) {
		$client->masterOrSelf->currentsongqueue()->[-1]->{startOffset} = $newtime;
		$client->masterOrSelf->remoteStreamStartTime( Time::HiRes::time() - $newtime );
		
		# Remove seek data
		delete $client->scanData->{seekdata};
	}

	# make the request
	return join($CRLF, @headers, $CRLF);
}

sub getFormatForURL {
	my ($classOrSelf, $url) = @_;

	return DEFAULT_TYPE;
}

sub parseDirectHeaders {
	my ( $class, $client, $url, @headers ) = @_;
	
	my ($title, $bitrate, $metaint, $redir, $contentType, $length, $body);
	
	foreach my $header (@headers) {
	
		logger('player.streaming.direct')->debug("header-ds: $header");

		if ($header =~ /^Location:\s*(.*)/i) {
			$redir = $1;
		}
		
		elsif ($header =~ /^Content-Type:\s*(.*)/i) {
			$contentType = $1;
		}
		
		elsif ($header =~ /^Content-Length:\s*(.*)/i) {
			$length = $1;
		}
		
		# mp3tunes metadata, this is a bit of hack but creating
		# an mp3tunes protocol handler is overkill
		elsif ( $url =~ /mp3tunes\.com/ && $header =~ /^X-Locker-Info:\s*(.+)/i ) {
			Slim::Plugin::MP3tunes::Plugin->setLockerInfo( $client, $url, $1 );
		}
	}

	$contentType = Slim::Music::Info::mimeToType($contentType);
	
	return ($title, $bitrate, $metaint, $redir, $contentType, $length, $body);
}

sub parseMetadata {
	my ( $client, $url, $metadata ) = @_;
	
	my $wma       = Audio::WMA->parseObject( $metadata );
	my $streamNum = $client->scanData->{streamNum} || 1;

	setMetadata( $client, $url, $wma, $streamNum );
	
	return;
}

sub setMetadata {
	my ( $client, $url, $wma, $streamNumber ) = @_;
	
	# Bitrate method 1: from parseDirectBody, we have the whole WMA object
	if ( $streamNumber && ref $wma->stream ) {

		for my $stream ( @{ $wma->stream } ) {

			if ( $stream->{'streamNumber'} == $streamNumber ) {

				if ( my $bitrate = $stream->{'bitrate'} ) {

					my $kbps = int( $bitrate / 1000 );
					my $vbr  = $wma->tags('vbr') || undef;

					Slim::Music::Info::setBitrate( $url, $kbps * 1000, $vbr );

					$log->info("Setting bitrate to $kbps from WMA metadata");
				}

				last;
			}
		}
	}
	elsif ( ref $wma->{'BITRATES'} ) {

		# method 2: from parseMetadata
		my $bitrates = $wma->{'BITRATES'};
		my $bitrate  = 0;

		for my $stream ( keys %{ $bitrates } ) {

			if ( $stream == $streamNumber ) {

				$bitrate = $bitrates->{$stream};
			}
		}

		my $kbps = int( $bitrate / 1000 );
		my $vbr  = $wma->tags('vbr') || undef;

		Slim::Music::Info::setBitrate( $url, $kbps * 1000, $vbr );

		$log->info("Setting bitrate to $kbps from WMA bitrate properties object");
	}
	
	# Set duration and progress bar if available and this is not a broadcast stream
	if ( $wma->info('playtime_seconds') ) {

		if ( my $secs = int( $wma->info('playtime_seconds') ) ) {

			if ( $wma->info('flags') && $wma->info('flags')->{'broadcast'} != 1 ) {

				if ( $secs > 0 ) {
					
					$client->streamingProgressBar( {
						'url'      => $url,
						'duration' => $secs,
					} );
				}
			}
		}
	}
	
	# Set title if available
	if ( my $title = $wma->tags('title') ) {
		
		# Ignore title metadata for Rhapsody tracks
		if ( $url !~ /^rhap/ ) {

			Slim::Music::Info::setCurrentTitle($url, $title);

			for my $everybuddy ( $client, Slim::Player::Sync::syncedWith($client)) {
				$everybuddy->update();
			}
		
			$log->info("Setting title to '$title' from WMA metadata");
		}
	}
}

# Handle normal advances to the next track
sub onDecoderUnderrun {
	my ( $class, $client, $nextURL, $callback ) = @_;
	
	# Flag that we don't want any buffering messages while loading the next track,
	$client->showBuffering( 0 );
	
	$log->debug( 'Scanning next HTTP track before playback' );
	
	Slim::Player::Protocols::HTTP->scanHTTPTrack( $client, $nextURL, $callback );
}

# On skip, load the next track before playback
sub onJump {
	my ( $class, $client, $nextURL, $callback ) = @_;
	
	# If seeking, we can avoid scanning	
	if ( $client->scanData->{seekdata} ) {
		# XXX: we could set showBuffering to 0 but on slow
		# streams there would be no feedback
		
		$callback->();
		return;
	}

	# Display buffering info on loading the next track
	$client->showBuffering( 1 );
	
	$log->debug( 'Scanning next HTTP track before playback' );
	
	Slim::Player::Protocols::HTTP->scanHTTPTrack( $client, $nextURL, $callback );
}

sub canSeek {
	my ( $class, $client, $url ) = @_;
	
	$client = $client->masterOrSelf;
	
	# Remote stream must be seekable
	if ( my $headers = $client->scanData->{headers} ) {
		if ( $headers->content_type eq 'application/vnd.ms.wms-hdr.asfv1' ) {
			# Stream is from a Windows Media server and we can seek if seekable flag is true
			if ( $client->scanData->{metadata}->info('flags')->{seekable} ) {
				return 1;
			}
		}
	}
	
	return 0;
}

sub canSeekError {
	my ( $class, $client, $url ) = @_;
	
	$client = $client->masterOrSelf;
	
	if ( my $metadata = $client->scanData->{metadata} ) {
		if ( $metadata->info('flags')->{broadcast} ) {
			return 'SEEK_ERROR_LIVE';
		}
	}
	
	return 'SEEK_ERROR_MMS';
}

sub getSeekData {
	my ( $class, $client, $url, $newtime ) = @_;
	
	$client = $client->masterOrSelf;
	
	# Determine byte offset and song length in bytes
	my $data = {};
	
	if ( my $metadata = $client->scanData->{metadata} ) {
		my $bitrate = Slim::Music::Info::getBitrate( $url ) || return;
		my $seconds = $metadata->info('playtime_seconds')   || return;
		
		$bitrate /= 1000;
		
		$log->debug( "Trying to seek $newtime seconds into $bitrate kbps stream of $seconds length" );
		
		$data->{newoffset}         = ( ( $bitrate * 1024 ) / 8 ) * $newtime;
		$data->{songLengthInBytes} = ( ( $bitrate * 1024 ) / 8 ) * $seconds;
	}
	
	return $data;
}

sub setSeekData {
	my ( $class, $client, $url, $newtime, $newoffset ) = @_;
	
	my @clients;
	
	if ( Slim::Player::Sync::isSynced($client) ) {
		# if synced, save seek data for all players
		my $master = Slim::Player::Sync::masterOrSelf($client);
		push @clients, $master, @{ $master->slaves };
	}
	else {
		push @clients, $client;
	}
	
	for my $client ( @clients ) {
		# Save the new seek point
		$client->scanData->{seekdata} = {
			newtime   => $newtime,
			newoffset => $newoffset,
		};
	}
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
