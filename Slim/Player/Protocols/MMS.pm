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
use Slim::Formats::RemoteMetadata;
use Slim::Player::Source;
use Slim::Player::Song;
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

sub isRemote { 1 }

=head2 new ( $class, $args )

Create a new instance of the MMS protocol handler, only for transcoding using wmadec or
another command-line tool.

=cut

sub new {
	my $class = shift;
	my $args  = shift;

	my $url        = $args->{'url'};
	my $client     = $args->{'client'};
	my $transcoder = $args->{'transcoder'};

	my $command    = $transcoder->{'command'};

	# Sanity check
	unless (defined($command) && $command ne '-') {
		logger('player.streaming.remote')->error("Error: Couldn't find conversion command");
		# XXX - errorOpening should not be in Source!
		Slim::Player::Source::errorOpening($client, $client->string('WMA_NO_CONVERT_CMD'));
		return undef;
	}

	my $quality = $prefs->client($client)->get('lameQuality');
		
	$command = Slim::Player::TranscodingHelper::tokenizeConvertCommand2(
		$transcoder, $url, $url, 1, $quality
	);
	
	$log->info("Tokenized command $command");

	my $self = $class->SUPER::new(undef, $command);

	${*$self}{'contentType'} = $transcoder->{'streamformat'};

	return $self;
}

sub canHandleTranscode {
	my ($self, $song) = @_;
	
	return 1;
}

sub getStreamBitrate {
	my ($self, $maxRate) = @_;
	
	return Slim::Player::Song::guessBitrateFromFormat(${*$self}{'contentType'}, $maxRate);
}

sub contentType {
	my $self = shift;

	return ${*$self}{'contentType'};
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
	my ($classOrSelf, $client, $url, $inType) = @_;
	
	if ( main::SLIM_SERVICE ) {
		# Strip noscan info from URL
		$url =~ s/#slim:.+$//;
	}

	return $url;
}

# Most WM streaming stations also stream via HTTP. The requestString class
# method is invoked by the direct streaming code to obtain a request string
# to send to a WM streaming server. We construct a HTTP request string and
# cross our fingers. 
sub requestString {
	my $classOrSelf = shift;
	my $client      = shift;
	my $url         = shift;
	my $post		= shift; # not used
	my $seekdata    = shift || {};

	my ($server, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($url);

	# Use full path for proxy servers
	my $proxy;
	
	if ( main::SLIM_SERVICE ) {
		$proxy = $prefs->client($client)->get('webproxy');
	}
	else {
		$proxy = $prefs->get('webproxy');
	}
	
	if ( $proxy && $server !~ /(?:localhost|127.0.0.1)/ ) {
		$path = "http://$server:$port$path";
	}

	my $host = $port == 80 ? $server : "$server:$port";

	my @headers = (
		"GET $path HTTP/1.0",
		"Accept: */*",
		"User-Agent: NSPlayer/8.0.0.3802",
		"Host: $host",
		"Pragma: xClientGUID={" . randomGUID() . "}",
	);
	
	my $song = $client->streamingSong();
	my $streamNum = 1;
	my $metadata;
	my $scanData;
	
	if ($song && ($scanData = $song->{'scanData'}) && ($scanData = $scanData->{$url})) {
		$log->info("Getting scanData from song");
		$streamNum = $scanData->{'streamNum'};
		$metadata  = $scanData->{'metadata'};
	}
	
	# Handle our metadata
	if ( $metadata ) {
		setMetadata( $client, $url, $metadata, $streamNum );
	}
	
	my $newtime = $seekdata->{timeOffset};
	
	my $context    = $newtime ? 4 : 2;
	my $streamtime = $newtime ? $newtime * 1000 : 0;
	
	# Does the song include a metadata stream (Sirius)?
	my $streamCount    = 1;
	my $metadataStream = '';
	if ( $song->{wmaMetadataStream} ) {
		$streamCount    = 2;
		$metadataStream = 'ffff:' . $song->{wmaMetadataStream} . ':0 ';
	}

	push @headers, (
		"Pragma: no-cache,rate=1.0000000,stream-offset=0:0,max-duration=0",
		"Pragma: stream-time=$streamtime",
		"Pragma: request-context=$context",
		"Pragma: LinkBW=2147483647, AccelBW=1048576, AccelDuration=18000",
		"Pragma: Speed=5.000",
		"Pragma: xPlayStrm=1",
		"Pragma: stream-switch-count=$streamCount",
		"Pragma: stream-switch-entry=ffff:" . $streamNum . ":0 " . $metadataStream,
	);
	
	# Fix progress bar if seeking
	if ( $newtime ) {
		$client->master()->currentsongqueue()->[-1]->{startOffset} = $newtime;
		$client->master()->remoteStreamStartTime( Time::HiRes::time() - $newtime );
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
	
	my $isDebug = $log->is_debug;
	
	my ($title, $bitrate, $metaint, $redir, $contentType, $length, $body);
	
	foreach my $header (@headers) {
	
		$isDebug && $log->debug("header-ds: $header");

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
	my ( $class, $client, $song, $metadata ) = @_;
	
	my $guid;
	map { $guid .= $_ } unpack( 'H*', substr $metadata, 0, 16 );
	
	if ( $guid eq '59dacfc059e611d0a3ac00a0c90348f6' ) {
		$log->is_debug && $log->debug( "ASF_Command_Media: $metadata" );
		
		# See if there is a parser for this stream
		my $parser = Slim::Formats::RemoteMetadata->getParserFor( $song->{streamUrl} );
		if ( $parser ) {
			eval { $parser->( $client, $song->{streamUrl}, $metadata ) };
			if ( $@ ) {
				my $name = Slim::Utils::PerlRunTime::realNameForCodeRef($parser);
				$log->error( "Metadata parser $name failed: $@" );
			}
		}
		
		# If there is no parser, we ignore ASF_Command_Media
		return;
	}
	
	my $wma       = Audio::WMA->parseObject( $metadata );
	my $streamNum = $song->{'scanData'}->{$song->{'streamUrl'}}->{'streamNum'} || 1;

	setMetadata( $client, $song->{'streamUrl'}, $wma, $streamNum );
	
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

		if ( my $secs = $wma->info('playtime_seconds') ) {

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

			for my $everybuddy ( $client->syncGroupActiveMembers()) {
				$everybuddy->update();
			}
		
			$log->info("Setting title to '$title' from WMA metadata");
		}
	}
}


sub scanUrl {
	my ( $class, $url, $args ) = @_;
	Slim::Player::Protocols::HTTP->scanUrl($url, $args);
}

sub canSeek {
	my ( $class, $client, $song ) = @_;
	
	$client = $client->master();
	
	# Remote stream must be seekable
	my ($headers, $scanData);
	if ( ($scanData = $song->{'scanData'})
		&& ($scanData = $scanData->{$song->currentTrack()->url})
		&& ($headers = $scanData->{headers}) )
	{
		if ( $headers->content_type eq 'application/vnd.ms.wms-hdr.asfv1' ) {
			# Stream is from a Windows Media server and we can seek if seekable flag is true
			if ( $scanData->{metadata}->info('flags')->{seekable} ) {
				return 1;
			}
		}
	}
	
	return 0;
}

sub canSeekError {
	my ( $class, $client, $song ) = @_;
	
	my ($metadata, $scanData);
	if ( ($scanData = $song->{'scanData'})
		&& ($scanData = $scanData->{$song->currentTrack()->url})
		&& ($metadata = $scanData->{metadata}) )
	{
		if ( $metadata->info('flags')->{broadcast} ) {
			return 'SEEK_ERROR_LIVE';
		}
	}
	
	return 'SEEK_ERROR_MMS';
}

sub getSeekData {
	my ( $class, $client, $song, $newtime ) = @_;
		
	# Determine byte offset and song length in bytes

	my ($metadata, $scanData);
	if ( ($scanData = $song->{'scanData'})
		&& ($scanData = $scanData->{$song->currentTrack()->url})
		&& ($metadata = $scanData->{metadata}) )
	{
		my $bitrate = $song->bitrate() || return;
		
		$bitrate /= 1000;
		
		$log->debug( "Trying to seek $newtime seconds into $bitrate kbps stream" );

		return {
			sourceStreamOffset   => ( ( $bitrate * 1024 ) / 8 ) * $newtime,
			timeOffset           => $newtime,
		};		
	}
	
	return undef;
}

sub getMetadataFor {
	my $class = shift;
	
	Slim::Player::Protocols::HTTP->getMetadataFor( @_ );
}

# reinit is used on SN to maintain seamless playback when bumped to another instance
sub reinit {
	my $class = shift;
	
	# Same as HTTP::reinit
	Slim::Player::Protocols::HTTP->reinit( @_ );
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
