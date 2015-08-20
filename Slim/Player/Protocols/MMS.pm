package Slim::Player::Protocols::MMS;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech, Vidur Apparao.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Formats::RemoteStream);

use IO::Socket qw(:crlf);

use Slim::Formats::Playlists;
use Slim::Formats::RemoteMetadata;
use Slim::Player::Source;
use Slim::Player::Song;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

my $log = logger('player.streaming.direct');

use constant DEFAULT_TYPE        => 'wma';
use constant META_STATUS_PARTIAL => 1;
use constant META_STATUS_FINAL   => 2;

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
	
	my $self = $class->open($args);

	if (defined($self)) {
		${*$self}{'client'}  = $args->{'client'};
		${*$self}{'url'}     = $args->{'url'};
	}

	return $self;
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
	
	# When synced, we don't direct stream so that the server can proxy a single
	# stream for all players
	if ( $client->isSynced(1) ) {

		if ( main::INFOLOG && $log->is_info ) {
			$log->info(sprintf(
				"[%s] Not direct streaming because player is synced", $client->id
			));
		}

		return 0;
	}

	# Strip noscan info from URL
	$url =~ s/#slim:.+$//;

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
	
	main::DEBUGLOG && $log->debug($url);

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
		"User-Agent: NSPlayer/8.0.0.3802",
		"Host: $host",
		"Pragma: xClientGUID={" . randomGUID() . "}",
	);
	
	my $song = $client->streamingSong();
	my $streamNum = 1;
	my $metadata;
	my $scanData;
	
	if ($song && ($scanData = $song->scanData()) && ($scanData = $scanData->{$url})) {
		main::INFOLOG && $log->info("Getting scanData from song");
		$streamNum = $scanData->{'streamNum'} if defined $scanData->{'streamNum'};
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
	if ( $song->wmaMetadataStream() ) {
		$streamCount    = 2;
		$metadataStream = 'ffff:' . $song->wmaMetadataStream() . ':0 ';
	}

	push @headers, (
		"Pragma: no-cache,rate=1.0000000,stream-offset=0:0,max-duration=0",
		"Pragma: stream-time=$streamtime",
		"Pragma: request-context=$context",
		"Pragma: LinkBW=2147483647, AccelBW=1048576, AccelDuration=21000",
		"Pragma: Speed=5.000",
		"Pragma: xPlayStrm=1",
		"Pragma: stream-switch-count=$streamCount",
		"Pragma: stream-switch-entry=ffff:" . $streamNum . ":0 " . $metadataStream,
	);
	
	# Fix progress bar if seeking
	if ( $newtime ) {
		$client->playingSong()->startOffset($newtime);
		$client->master()->remoteStreamStartTime( Time::HiRes::time() - $newtime );
	}

	# make the request
	my $request = join($CRLF, @headers, $CRLF);
	main::DEBUGLOG && $log->debug($request);
	return $request;
}

sub getFormatForURL {
	my ($classOrSelf, $url) = @_;

	return DEFAULT_TYPE;
}

sub parseHeaders {
	my $self    = shift;
	
	my ($title, $bitrate, $metaint, $redir, $contentType, $length, $body) = $self->parseDirectHeaders($self->client, $self->url, @_);

	${*$self}{'contentType'} = $contentType if $contentType;
	${*$self}{'redirect'} = $redir;

	${*$self}{'contentLength'} = $length if $length;
	${*$self}{'song'}->isLive($length ? 0 : 1) if !$redir;
	# XXX maybe should (also) check $song->scanData()->{$url}->{metadata}->{info}->{broadcast} here.

	return;
}

sub getMMSStreamingParameters {
	my ($class, $song, $url) = @_;
	
	my ($chunked, $audioStream, $metadataStream) = (1, 1, $song->wmaMetadataStream());
	
	# Bugs 5631, 7762
	# Check WMA metadata to see if this remote stream is being served from a
	# Windows Media server or a normal HTTP server.  WM servers will use MMS chunking
	# and need a pcmsamplesize value of 1, whereas HTTP servers need pcmsamplesize of 0.
	if ( my $scanData = $song->scanData() ) {
		if ( my $streamScanData = $scanData->{$url} ) {
			if ( my $meta = $streamScanData->{metadata} ) {
				if ( !$meta->{info}->{broadcast} ) {
					if ( $streamScanData->{headers}->content_type ne 'application/vnd.ms.wms-hdr.asfv1' ) {
						# The server didn't return the expected ASF header content-type,
						# so we assume it's not a Windows Media server
						$chunked = 0;
					}
				}
			}
			
			$audioStream = $streamScanData->{'streamNum'} if defined $streamScanData->{'streamNum'};
		}
	}
	
	main::DEBUGLOG && $log->is_debug && $log->debug("chunked=$chunked, audio=$audioStream, metadata=", (defined $metadataStream ? $metadataStream : 'undef'));
	
	return ($chunked, $audioStream, $metadataStream);
}

# WMA GUIDs we want to have the player send back to us
my @WMA_ASF_COMMAND_MEDIA_OBJECT_GUID = (0x59, 0xda, 0xcf, 0xc0, 0x59, 0xe6, 0x11, 0xd0, 0xa3, 0xac, 0x00, 0xa0, 0xc9, 0x03, 0x48, 0xf6);

sub metadataGuids {
	my $client = shift;
	
	my @guids = ();
	
	if ($client == $client->master()) {
		push @guids, @WMA_ASF_COMMAND_MEDIA_OBJECT_GUID;
	}
	
	return @guids;
}

# This is a horrible hack to handle metadata
sub handlesStreamHeaders {
	my ($class, $client) = @_;
	
	my $controller = $client->controller()->songStreamController();
	
	# let the normal direct-streaming code in Slim::Player::Squeezebox2 handle things
	return 0 if $controller->isDirect();
	
	# tell player to continue and send us metadata
	$client->sendContCommand(0, 0, metadataGuids($client));
	
	return 1;
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
		# Strip first 16 bytes of metadata (GUID)
		substr $metadata, 0, 16, '';
		
		# Next 8 bytes is the length field.  First byte is used to
		# indicate if this is a partial or final packet
		my $status = unpack 'C', substr( $metadata, 0, 8, '' );
		
		my $md = $song->wmaMetaData() || '';
		
		# Buffer partial packets
		if ( $status == META_STATUS_PARTIAL ) {
			$md .= $metadata;
			$song->wmaMetaData($md);
			main::DEBUGLOG && $log->is_debug && $log->debug( "ASF_Command_Media: Buffered partial packet, len " . length($metadata) );
			return;
		}
		elsif ( $status == META_STATUS_FINAL ) {		
			# Prepend previous chunks, if any
			$metadata = $md . $metadata;
			$song->wmaMetaData(undef);
		
			# Strip first byte if it is a length byte
			my $len = unpack 'C', $metadata;
			if ( $len == length($metadata) - 1 ) {
				substr $metadata, 0, 1, '';
			}
			
			# WMA Metadata is UTF-16LE
			$metadata = eval { Encode::decode( 'UTF-16LE', $metadata ) };
			if ( $@ ) {
				main::DEBUGLOG && $log->is_debug && $log->debug( "Decoding of WMA metadata failed: $@" );
				return;
			}
		
			main::DEBUGLOG && $log->is_debug && $log->debug( "ASF_Command_Media: $metadata" );
		
			# See if there is a parser for this stream
			my $url = Slim::Player::Playlist::url($client);
			my $parser = Slim::Formats::RemoteMetadata->getParserFor( $url );
			if ( $parser ) {
				if ( main::DEBUGLOG && $log->is_debug ) {
					$log->debug( 'Trying metadata parser ' . Slim::Utils::PerlRunTime::realNameForCodeRef($parser) );
				}
				
				my $handled = eval { $parser->( $client, $url, $metadata ) };
				if ( $@ ) {
					my $name = main::DEBUGLOG ? Slim::Utils::PerlRunTime::realNameForCodeRef($parser) : 'unk';
					$log->error( "Metadata parser $name failed: $@" );
				}
				return if $handled;
			}
		
			# See if the metadata matches a common format used by the SAM broadcaster
			# http://www.spacialaudio.com
			# URI-escaped query string terminated by a null
			# This format is used by RadioIO's WMA streams and some other providers
		
			if ( !$song->pluginData('wmaHasData') && $metadata =~ /CAPTION\0([^\0]+)/i ) {
				# use CAPTION formatted metadata unless we also have query-string metadata
				my $cb = sub {
					$song->pluginData( wmaMeta => {
						title => $1,
					} );
					Slim::Music::Info::setCurrentTitle($url, $1, $client);
				};
				
				# Delay metadata according to buffer size if we already have metadata
				if ( $song->pluginData('wmaMeta') ) {
					Slim::Music::Info::setDelayedCallback( $client, $cb, 'output-only' );
				}
				else {
					$cb->();
				}
			
				main::DEBUGLOG && $log->is_debug && $log->debug('Parsed WMA metadata from CAPTION string');
			}
			elsif ( $metadata =~ /(artist=[^\0]+)/i ) {
				require URI::QueryParam;
				my $uri  = URI->new( '?' . $1 );
				my $meta = $uri->query_form_hash;
				
				# Make sure query params are lowercase
				for my $k ( keys %{$meta} ) {
					if ( $k ne lc($k) ) {
						$meta->{ lc($k) } = delete $meta->{$k};
					}
				}				
				
				main::DEBUGLOG && $log->is_debug && $log->debug('Parsed WMA metadata from artist-style query string');
			
				my $cb = sub {
					$song->pluginData( wmaMeta => $meta );
					$song->pluginData( wmaHasData => 1 );
					Slim::Music::Info::setCurrentTitle($url, $meta->{title}, $client) if $meta->{title};
				};
				
				# Delay metadata according to buffer size if we already have metadata
				if ( $song->pluginData('wmaHasData') ) {
					Slim::Music::Info::setDelayedCallback( $client, $cb, 'output-only' );
				}
				else {
					$cb->();
				}
			}
			
			# type=SONG format used by KFOG
			elsif ( $metadata =~ /(type=SONG[^\0]+)/ ) {
				require URI::QueryParam;
				my $uri  = URI->new( '?' . $1 );
				my $meta = $uri->query_form_hash;
				
				main::DEBUGLOG && $log->is_debug && $log->debug('Parsed WMA metadata from type=SONG query string');
				
				$meta->{artist} = delete $meta->{currentArtist};
				$meta->{title}  = delete $meta->{currentSong};
				
				my $cb = sub {
					$song->pluginData( wmaMeta => $meta );
					$song->pluginData( wmaHasData => 1 );
					Slim::Music::Info::setCurrentTitle($url, $meta->{title}, $client) if $meta->{title};
				};
				
				# Delay metadata according to buffer size if we already have metadata
				if ( $song->pluginData('wmaHasData') ) {
					Slim::Music::Info::setDelayedCallback( $client, $cb, 'output-only' );
				}
				else {
					$cb->();
				}
			}
		}
		
		# If there is no parser, we ignore ASF_Command_Media
		return;
	}
	
	return;
}

sub setMetadata {
	my ( $client, $url, $wma, $streamNumber ) = @_;
	
	# Bitrate method 1: from parseDirectBody, we have the whole WMA object
	if ( $streamNumber && ref $wma->{info}->{streams} ) {

		for my $stream ( @{ $wma->{info}->{streams} } ) {

			if ( $stream->{stream_number} == $streamNumber ) {

				if ( my $bitrate = $stream->{bitrate} ) {

					my $kbps = int( $bitrate / 1000 );
					my $vbr  = $wma->{tags}->{IsVBR} || undef;

					Slim::Music::Info::setBitrate( $url, $kbps * 1000, $vbr );

					main::INFOLOG && $log->info("Setting bitrate to $kbps from WMA metadata");
				}

				last;
			}
		}
	}
	
	# Set duration and progress bar if available and this is not a broadcast stream
	if ( my $ms = $wma->{info}->{song_length_ms} ) {
		$client->streamingProgressBar( {
			url      => $url,
			duration => int($ms / 1000),
		} );
		
		if ( my $song = $client->streamingSong() ) {
			$song->duration($ms / 1000);
		}
	}
	
	# Set title if available
	if ( my $title = $wma->{tags}->{Title} ) {
		
		# Ignore title metadata for Rhapsody tracks
		if ( $url !~ /^rhap/ ) {

			Slim::Music::Info::setCurrentTitle($url, $title);

			for my $everybuddy ( $client->syncGroupActiveMembers()) {
				$everybuddy->update();
			}
		
			main::INFOLOG && $log->info("Setting title to '$title' from WMA metadata");
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
	if ( ($scanData = $song->scanData())
		&& ($scanData = $scanData->{$song->currentTrack()->url})
		&& ($headers = $scanData->{headers}) )
	{
		if ( $headers->content_type eq 'application/vnd.ms.wms-hdr.asfv1' ) {
			if ( $scanData->{metadata} && $scanData->{metadata}->{info}->{seekable} ) {
				# Stream is from a Windows Media server and we can seek if seekable flag is true
				return 1;
			}
		}
	}
	
	return 0;
}

sub canSeekError {
	my ( $class, $client, $song ) = @_;
	
	my ($metadata, $scanData);
	if ( ($scanData = $song->scanData())
		&& ($scanData = $scanData->{$song->currentTrack()->url})
		&& ($metadata = $scanData->{metadata}) )
	{
		if ( $metadata->{info}->{broadcast} ) {
			return 'SEEK_ERROR_LIVE';
		}
	}
	
	return 'SEEK_ERROR_MMS';
}

sub getSeekData {
	my ( $class, $client, $song, $newtime ) = @_;
		
	# Determine byte offset and song length in bytes

	my ($metadata, $scanData);
	if ( ($scanData = $song->scanData())
		&& ($scanData = $scanData->{$song->currentTrack()->url})
		&& ($metadata = $scanData->{metadata}) )
	{
		my $bitrate = $song->bitrate() || return;
		
		$bitrate /= 1000;
		
		main::DEBUGLOG && $log->debug( "Trying to seek $newtime seconds into $bitrate kbps stream" );

		return {
			sourceStreamOffset   => ( ( $bitrate * 1000 ) / 8 ) * $newtime,
			timeOffset           => $newtime,
		};		
	}
	
	return undef;
}

sub getMetadataFor {
	my $class = shift;
	
	Slim::Player::Protocols::HTTP->getMetadataFor( @_ );
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
