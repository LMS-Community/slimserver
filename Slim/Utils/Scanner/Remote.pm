package Slim::Utils::Scanner::Remote;

# $Id$
#
# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, version 2.

=head1 NAME

Slim::Utils::Scanner::Remote

=head1 SYNOPSIS

Slim::Utils::Scanner::Remote->scanURL( $url, {
	client => $client,
	cb     => sub { ... },
} );

=head1 DESCRIPTION

This class handles anything to do with obtaining information about a remote
music source, whether that is a playlist, mp3 stream, wma stream, remote mp3 file with
ID3 tags, etc.

=head1 METHODS

=cut

# TODO
# Build a submenu of TrackInfo to select alternate streams in remote playlists?
# Duplicate playlist items sometimes get into the DB, maybe when multiple nested playlists
#   refer to the same stream (Q-91.3 http://opml.radiotime.com/StationPlaylist.axd?stationId=22200)
# Ogg broken: http://opml.radiotime.com/StationPlaylist.axd?stationId=54657

use strict;

use Audio::Scan;
use File::Temp ();
use HTTP::Request;
use IO::String;
use Scalar::Util qw(blessed);

use Slim::Formats;
use Slim::Formats::Playlists;
use Slim::Networking::Async::HTTP;
use Slim::Player::Protocols::MMS;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $log = logger('scan.scanner');

use constant MAX_DEPTH => 7;

my %ogg_quality = (
	0  => 64000,
	1  => 80000,
	2  => 96000,
	3  => 112000,
	4  => 128000,
	5  => 160000,
	6  => 192000,
	7  => 224000,
	8  => 256000,
	9  => 320000,
	10 => 500000,
);

=head2 scanURL( $url, $args );

Scan a remote URL.  When finished, calls back to $args->{cb} with a success flag
and an error string if the scan failed.

=cut

sub scanURL {
	my ( $class, $url, $args ) = @_;
	
	my $client = $args->{client};
	my $cb     = $args->{cb} || sub {};
	my $pt     = $args->{pt} || [];
	
	$args->{depth} ||= 0;
	
	main::DEBUGLOG && $log->is_debug && $log->debug( "Scanning remote stream $url" );
	
	if ( !$url ) {
		return $cb->( undef, 'SCANNER_REMOTE_NO_URL_PROVIDED', @{$pt} );
	}

	if ( !Slim::Music::Info::isRemoteURL($url) ) {
		return $cb->( undef, 'SCANNER_REMOTE_INVALID_URL', @{$pt} );
	}

	# Refuse to scan too deep in a nested playlist
	if ( $args->{depth} >= MAX_DEPTH ) {
		return $cb->( undef, 'SCANNER_REMOTE_NESTED_TOO_DEEP', @{$pt} );
	}
	
	# Get/Create a track object for this URL
	my $track = Slim::Schema->updateOrCreate( {
		url => $url,
	} );
	
	# Make sure it has a title
	if ( !$track->title ) {
		$track = Slim::Music::Info::setTitle( $url, $args->{'title'} ? $args->{'title'} : $url );
	}

	# Check if the protocol handler has a custom scanning method
	# This is used to allow plugins to add scanning routines for exteral stream types
	my $handler = Slim::Player::ProtocolHandlers->handlerForURL($url);
	if ($handler && $handler->can('scanStream') ) {
		main::DEBUGLOG && $log->is_debug && $log->debug( "Scanning remote stream $url using protocol hander $handler" );
		
		# Allow protocol hander to scan the stream and then call the callback
		$handler->scanStream($url, $track, $args);

		return;
	}
	
	# In some cases, a remote protocol may always be audio and not need scanning
	# This is not used by any core code, but some plugins require it
	my $isAudio = Slim::Music::Info::isAudioURL($url);

	$url =~ s/#slim:.+$//;
	
	if ( $isAudio ) { 	 
		main::DEBUGLOG && $log->is_debug && $log->debug( "Remote stream $url known to be audio" ); 	 

		# Set this track's content type from protocol handler getFormatForURL method 	 
		my $type = Slim::Music::Info::typeFromPath($url);
		if ( $type eq 'unk' ) {
			$type = 'mp3';
		}
		
		main::DEBUGLOG && $log->is_debug && $log->debug( "Content-type of $url - $type" );
		
		$track->content_type( $type );
		$track->update;

		# Success, done scanning 	 
		return $cb->( $track, undef, @{$pt} );
	}
	
	# Bug 4522, if user has disabled native WMA decoding to get MMS support, don't scan MMS URLs
	if ( $url =~ /^mms/i ) {
		
		# XXX This test will not be good enough when we get WMA proxied streaming
		if ( main::TRANSCODING && ! Slim::Player::TranscodingHelper::isEnabled('wma-wma-*-*') ) {
			main::DEBUGLOG && $log->is_debug && $log->debug('Not scanning MMS URL because direct streaming disabled.');

			$track->content_type( 'wma' );

			return $cb->( $track, undef, @{$pt} );
		}
	}
	
	# Connect to the remote URL and figure out what it is
	my $request = HTTP::Request->new( GET => $url );
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Scanning remote URL $url");
	
	# Use WMP headers for MMS protocol URLs or ASF/ASX/WMA URLs
	if ( $url =~ /(?:^mms|\.asf|\.asx|\.wma)/i ) {
		addWMAHeaders( $request );
	}
	
	# If the URL is on SqueezeNetwork, add session headers
	if ( !main::NOMYSB && Slim::Networking::SqueezeNetwork->isSNURL($url) ) {
		my %snHeaders = Slim::Networking::SqueezeNetwork->getHeaders($client);
		while ( my ($k, $v) = each %snHeaders ) {
			$request->header( $k => $v );
		}
	
		if ( my $snCookie = Slim::Networking::SqueezeNetwork->getCookie($client) ) {
			$request->header( Cookie => $snCookie );
		}
	}
	
	my $timeout = preferences('server')->get('remotestreamtimeout');
	
	my $send = sub {
		my $http = Slim::Networking::Async::HTTP->new;
		$http->send_request( {
			request     => $request,
			onRedirect  => \&handleRedirect,
			onHeaders   => \&readRemoteHeaders,
			onError     => sub {
				my ( $http, $error ) = @_;

				logError("Can't connect to remote server to retrieve playlist for, ", $request->uri, ": $error.");
				
				$track->error( $error );

				return $cb->( undef, $error, @{$pt} );
			},
			passthrough => [ $track, $args ],
			Timeout     => $timeout,
		} );
	};
	
	if ( $args->{delay} ) {
		Slim::Utils::Timers::setTimer( undef, Time::HiRes::time() + $args->{delay}, $send );
	}
	else {
		$send->();
	}
}

=head2 addWMAHeaders( $request )

Adds Windows Media Player headers to the HTTP request to make it a valid 'Describe' request.
See Microsoft HTTP streaming spec for details:
http://msdn2.microsoft.com/en-us/library/cc251059.aspx

=cut

sub addWMAHeaders {
	my $request = shift;
	
	my $url = $request->uri->as_string;
	$url =~ s/^mms/http/;
	
	$request->uri( $url );
	
	my $h = $request->headers;
	$h->header( 'User-Agent' => 'NSPlayer/8.0.0.3802' );
	$h->header( Pragma => [
		'xClientGUID={' . Slim::Player::Protocols::MMS::randomGUID(). '}',
		'no-cache',
	] );
	$h->header( Connection => 'close' );
}

=head2 handleRedirect( $http, $track, $args )

Callback when Async::HTTP encounters a redirect.  If a server
redirects to an mms:// protocol URL we need to rewrite the link and set proper headers.

=cut

sub handleRedirect {
	my ( $request, $track, $args ) = @_;
	
	main::DEBUGLOG && $log->is_debug && $log->debug( 'Server redirected to ' . $request->uri );
	
	if ( $request->uri =~ /^mms/ ) {

		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug("Server redirected to MMS URL: " . $request->uri . ", adding WMA headers");
		}
		
		addWMAHeaders( $request );
	}
	
	# Keep track of artwork or station icon across redirects
	my $cache = Slim::Utils::Cache->new();
	if ( my $icon = $cache->get("remote_image_" . $track->url) ) {
		$cache->set("remote_image_" . $request->uri, $icon, '30 days');
	}
	
	return $request;
}

=head2 readRemoteHeaders( $http, $track, $args )

Async callback from scanURL.  The remote headers are read to determine the content-type.

=cut

sub readRemoteHeaders {
	my ( $http, $track, $args ) = @_;
	
	my $client = $args->{client};
	my $cb     = $args->{cb} || sub {};
	my $pt     = $args->{pt} || [];

	# $track is the track object for the original URL we scanned
	# $url is the final URL, may be different due to a redirect
	
	my $url = $http->request->uri->as_string;
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( "Headers for $url are " . Data::Dump::dump( $http->response->headers ) );
	}

	# Make sure the content type of the track is correct
	my $type = $http->response->content_type;

	# Content-Type may have multiple elements, i.e. audio/x-mpegurl; charset=ISO-8859-1
	if ( ref $type eq 'ARRAY' ) {
		$type = $type->[0];
	}
	
	$type = Slim::Music::Info::mimeToType($type) || $type;
	
	# Handle some special cases
	
	# Bug 3396, some m4a audio is incorrectly served as audio/mpeg.
	# In this case, prefer the file extension to the content-type
	if ( $url =~ /aac$/i && ($type eq 'mp3' || $type eq 'txt') ) {
		$type = 'aac';
	}
	elsif ( $url =~ /(?:m4a|mp4)$/i && ($type eq 'mp3' || $type eq 'txt') ) {
		$type = 'mp4';
	}

	# bug 15491 - some radio services are too lazy to correctly configure their servers
	# thus serve playlists with content-type text/html or text/plain
	elsif ( $type =~ /(?:htm|txt)/ && $url =~ /\.(asx|m3u|pls|wpl|wma)$/i ) {
		$type = $1;
	}
	
	# KWMR misconfiguration
	elsif ( $type eq 'wma' && $url =~ /\.(m3u)$/i ) {
		$type = $1;
	}
	
	# fall back to m3u for html and text
	elsif ( $type =~ /(?:htm|txt)/ ) {
		$type = 'm3u';
	}
	
	# Some Shoutcast/Icecast servers don't send content-type
	if ( !$type && $http->response->header('icy-name') ) {
		$type = 'mp3';
	}
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( "Content-type for $url detected as $type (" . $http->response->content_type . ")" );
	}
	
	# Set content-type for original URL and redirected URL
	main::DEBUGLOG && $log->is_debug && $log->debug( 'Updating content-type for ' . $track->url . " to $type" );
	$track = Slim::Music::Info::setContentType( $track->url, $type );
	
	if ( $track->url ne $url ) {
		my $update;
		
		# Don't create a duplicate object if the only difference is http:// instead of mms://
		if ( $track->url =~ m{^mms://(.+)} ) {
			if ( $url ne "http://$1" ) {
				$update = 1;
			}
		}
		else {
			$update = 1;
		}
		
		if ( $update ) {
			main::DEBUGLOG && $log->is_debug && $log->debug( "Updating redirected URL $url" );
			
			# Get/create a new entry for the redirected track
			my $redirTrack = Slim::Schema->updateOrCreate( {
				url => $url,
			} );
			
			# Copy values from original track
			$redirTrack->title( $track->title );
			$redirTrack->content_type( $track->content_type );
			$redirTrack->bitrate( $track->bitrate );
			
			$redirTrack->update;
			
			# Delete original track
			$track->delete;
			
			$track = $redirTrack;
		}
	}

	# Is this an audio stream or a playlist?
	if ( Slim::Music::Info::isSong( $track, $type ) ) {
		main::INFOLOG && $log->is_info && $log->info("This URL is an audio stream [$type]: " . $track->url);
		
		$track->content_type($type);
		
		if ( $type eq 'wma' ) {
			# WMA streams require extra processing, we must parse the Describe header info
			
			main::DEBUGLOG && $log->is_debug && $log->debug('Reading WMA header');
			
			# If URL was http but content-type is wma, change URL
			if ( $track->url =~ /^http/i ) {
				# XXX: may create duplicate track entries
				my $mmsURL = $track->url;
				$mmsURL =~ s/^http/mms/i;
				$track->url( $mmsURL );
				$track->update;
			}

			# Read the rest of the header and pass it on to parseWMAHeader
			$http->read_body( {
				readLimit   => 128 * 1024,
				onBody      => \&parseWMAHeader,
				passthrough => [ $track, $args ],
			} );
		}
		elsif ( $type eq 'aac' ) {
			# Bug 16379, AAC streams require extra processing to check for the samplerate
			
			main::DEBUGLOG && $log->is_debug && $log->debug('Reading AAC header');
			
			$http->read_body( {
				readLimit   => 4 * 1024,
				onBody      => \&parseAACHeader,
				passthrough => [ $track, $args ],
			} );
		}
		elsif ( $type eq 'ogg' ) {

			# Read the header to allow support for oggflac as it requires different decode path
			main::DEBUGLOG && $log->is_debug && $log->debug('Reading Ogg header');
			
			$http->read_body( {
				readLimit   => 64,
				onBody      => \&parseOggHeader,
				passthrough => [ $track, $args ],
			} );
		}
		else {
			# If URL was mms but content-type is not wma, change URL
			if ( $track->url =~ /^mms/i ) {
				main::DEBUGLOG && $log->is_debug && $log->debug("URL was mms:// but content-type is $type, fixing URL to http://");
				
				# XXX: may create duplicate track entries
				my $httpURL = $track->url;
				$httpURL =~ s/^mms/http/i;
				$track->url( $httpURL );
				$track->update;
			}
			
			my $bitrate;
			my $vbr = 0;
			
			# Look for Icecast info header and determine bitrate from this
			if ( my $audioinfo = $http->response->header('ice-audio-info') ) {
				($bitrate) = $audioinfo =~ /ice-(?:bitrate|quality)=([^;]+)/i;
				if ( $bitrate =~ /(\d+)/ ) {
					if ( $bitrate <= 10 ) {
						# Ogg quality, may be fractional
						my $quality = sprintf "%d", $1;
						$bitrate = $ogg_quality{$quality};
						$vbr = 1;
					
						main::DEBUGLOG && $log->is_debug && $log->debug("Found bitrate from Ogg quality header: $bitrate");
					}
					else {					
						main::DEBUGLOG && $log->is_debug && $log->debug("Found bitrate from ice-audio-info header: $bitrate");
					}
				}
			}
			
			# Look for bitrate information in header indicating it's an Icy stream
			elsif ( $bitrate = ( $http->response->header('icy-br') || $http->response->header('x-audiocast-bitrate') || 0 ) * 1000 ) {
				main::DEBUGLOG && $log->is_debug && $log->debug("Found bitrate in Icy header: $bitrate");
			}
			
			if ( $bitrate ) {
				if ( $bitrate < 1000 ) {
					$bitrate *= 1000;
				}
							
				Slim::Music::Info::setBitrate( $track, $bitrate, $vbr );
				
				if ( $track->url ne $url ) {
					Slim::Music::Info::setBitrate( $url, $bitrate, $vbr );
				}
			
				# We don't need to read any more data from this stream
				$http->disconnect;
				
				# All done
				
				# Bug 11001, if the URL uses basic authentication, it may be an Icecast
				# server that allows only 1 connection per user.  Delay this callback for a second
				# to avoid the chance of getting a 401 error when trying to stream.
				if ( $track->url =~ m{http://[^:]+:[^@]+@} ) {
					main::DEBUGLOG && $log->is_debug && $log->debug( 'Auth stream detected, waiting 1 second before streaming' );
					
					Slim::Utils::Timers::setTimer(
						undef,
						Time::HiRes::time() + 1,
						sub {
							$cb->( $track, undef, @{$pt} );
						},
					);
				}
				else {
					$cb->( $track, undef, @{$pt} );
				}
			}
			else {
				# We still need to read more info about this stream, but we can begin playing it now
				$cb->( $track, undef, @{$pt} );
				
				# Continue scanning in the background
				
				# We may be able to determine the bitrate or other tag information
				# about this remote stream/file by reading a bit of audio data
				main::DEBUGLOG && $log->is_debug && $log->debug('Reading audio data in the background to detect bitrate and/or tags');

				# read as much as is necessary to read all ID3v2 tags and determine bitrate
				$http->read_body( {
					onStream    => \&streamAudioData,
					passthrough => [ $track, $args, $url ],
				} );
			}
		}
	}
	else {
		main::DEBUGLOG && $log->is_debug && $log->debug('This URL is a playlist: ' . $track->url);
		
		# Read the rest of the playlist
		$http->read_body( {
			readLimit   => 128 * 1024,
			onBody      => \&parsePlaylist,
			passthrough => [ $track, $args ],
		} );
	}
}

sub parseWMAHeader {
	my ( $http, $track, $args ) = @_;
	
	my $client = $args->{client};
	my $cb	   = $args->{cb} || sub {};
	my $pt	   = $args->{pt} || [];
	
	# Check for WMA chunking header from a server and remove it
	my $header	  = $http->response->content;
	my $chunkType = unpack 'v', substr( $header, 0, 2 );
	if ( $chunkType == 0x4824 ) {
		substr $header, 0, 12, '';
	}
	
	# The header may be at the front of the file, if the remote
	# WMA file is not a live stream
	my $fh = File::Temp->new();
	$fh->write( $header, length($header) );
	$fh->seek(0, 0);
	
	my $wma = Audio::Scan->scan_fh( asf => $fh );
	
	if ( !$wma->{info}->{max_bitrate} ) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Unable to parse WMA header');
		
		# Delete bad item
		$track->delete;
		
		return $cb->( undef, 'ASF_UNABLE_TO_PARSE', @{$pt} );
	}
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( 'WMA header data for ' . $track->url . ': ' . Data::Dump::dump($wma) );
	}
	
	my $streamNum = 1;
	
	# Some ASF streams appear to have no stream objects (mms://ms1.capitalinteractive.co.uk/fm_high)
	# I think it's safe to just assume stream #1 in this case
	if ( ref $wma->{info}->{streams} ) {
		
		# Look through all available streams and select the one with the highest bitrate still below
		# the user's preferred max bitrate
		my $max = preferences('server')->get('maxWMArate') || 9999;
	
		my $bitrate = 0;
		my $valid	= 0;
		
		for my $stream ( @{ $wma->{info}->{streams} } ) {
			next unless defined $stream->{stream_number};
			
			my $streamBitrate = sprintf "%d", $stream->{bitrate} / 1000;
			
			# If stream is ASF_Command_Media, it may contain metadata, so let's get it
			if ( $stream->{stream_type} eq 'ASF_Command_Media' ) {
				main::DEBUGLOG && $log->is_debug && $log->debug( "Possible ASF_Command_Media metadata stream: \#$stream->{stream_number}, $streamBitrate kbps" );
				$args->{song}->wmaMetadataStream($stream->{stream_number});
				next;
			}

			# Skip non-audio streams or audio codecs we can't play
			# The firmware supports 2 codecs:
			# Windows Media Audio V7 / V8 / V9 (0x0161)
			# Windows Media Audio 9 Voice (0x000A)
			next unless $stream->{codec_id} && (
				$stream->{codec_id} == 0x0161
				||
				$stream->{codec_id} == 0x000a
			);
		
			main::DEBUGLOG && $log->is_debug && $log->debug( "Available stream: \#$stream->{stream_number}, $streamBitrate kbps" );

			if ( $stream->{bitrate} > $bitrate && $max >= $streamBitrate ) {
				$streamNum = $stream->{stream_number};
				$bitrate   = $stream->{bitrate};
			}
			
			$valid++;
		}
		
		# If we saw no valid streams, such as a stream with only MP3 codec, give up
		if ( !$valid ) {
			main::DEBUGLOG && $log->is_debug && $log->debug('WMA contains no valid audio streams');
			
			# Delete bad item
			$track->delete;
			
			return $cb->( undef, 'ASF_UNABLE_TO_PARSE', @{$pt} );
		}
	
		if ( !$bitrate && ref $wma->{info}->{streams}->[0] ) {
			# maybe we couldn't parse bitrate information, so just use the first stream
			$streamNum = $wma->{info}->{streams}->[0]->{stream_number};
		}
		
		if ( $bitrate ) {
			Slim::Music::Info::setBitrate( $track, $bitrate );
		}

		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug( sprintf( "Will play stream #%d, bitrate: %s kbps",
				$streamNum,
				$bitrate ? int( $bitrate / 1000 ) : 'unknown',
			) );
		}
	}
	
	# Set duration if available (this is not a broadcast stream)
	if ( my $ms = $wma->{info}->{song_length_ms} ) {	
		Slim::Music::Info::setDuration( $track, int($ms / 1000) );
	}
	
	# Save this metadata for the MMS protocol handler to use
	if ( my $song = $args->{song} ) {
		my $sd = $song->scanData();
		if (!defined $sd) {
			$song->scanData($sd = {});
		} 
		$sd->{$track->url} = {
			streamNum => $streamNum,
			metadata  => $wma,
			headers	  => $http->response->headers,
		};
	}
	
	# All done
	$cb->( $track, undef, @{$pt} );
}

sub parseAACHeader {
	my ( $http, $track, $args ) = @_;
	
	my $client = $args->{client};
	my $cb	   = $args->{cb} || sub {};
	my $pt	   = $args->{pt} || [];
	
	my $header = $http->response->content;
	
	my $fh = File::Temp->new();
	$fh->write( $header, length($header) );
	$fh->seek(0, 0);
	
	my $aac = Audio::Scan->scan_fh( aac => $fh );
	
	if ( my $samplerate = $aac->{info}->{samplerate} ) {
		if ( $samplerate <= 24000 ) { # XXX remove when Audio::Scan is updated to 0.84
			$samplerate *= 2;
		}
		$track->samplerate($samplerate);
		main::DEBUGLOG && $log->is_debug && $log->debug("AAC samplerate: $samplerate");
	}
	
	# All done
	$cb->( $track, undef, @{$pt} );
}

sub parseOggHeader {
	my ( $http, $track, $args ) = @_;
	
	my $client = $args->{client};
	my $cb	   = $args->{cb} || sub {};
	my $pt	   = $args->{pt} || [];

	my $header = $http->response->content;
	my $data   = substr($header, 28);

	# search for Ogg FLAC headers within the data - if so change the content type to ogf for OggFlac
	# OggFlac header defined: http://flac.sourceforge.net/ogg_mapping.html
	if (substr($data, 0, 5) eq "\x7fFLAC" && substr($data, 9,4) eq 'fLaC') {
		main::DEBUGLOG && $log->is_debug && $log->debug("Ogg stream is OggFlac - setting content type [ogf]");
		Slim::Schema->clearContentTypeCache( $track->url );
		Slim::Music::Info::setContentType( $track->url, 'ogf' );
		$track->content_type('ogf');
	}

	# All done
	$cb->( $track, undef, @{$pt} );
}

sub streamAudioData {
	my ( $http, $dataref, $track, $args, $url ) = @_;
	
	my $first;
	
	# Buffer data to a temp file, 128K of data by default
	my $fh = $args->{_scanbuf};
	if ( !$fh ) {
		$fh = File::Temp->new();
		$args->{_scanbuf} = $fh;
		$args->{_scanlen} = 128 * 1024;
		$first = 1;
		main::DEBUGLOG && $log->is_debug && $log->debug( $track->url . ' Buffering audio stream data to temp file ' . $fh->filename );
	}
	
	my $len = length($$dataref);
	$fh->write( $$dataref, $len );
	
	if ( $first ) {
		if ( $$dataref =~ /^ID3/ ) {
			# get ID3v2 tag length from bytes 7-10
			my $id3size = 0;
			my $rawsize = substr $$dataref, 6, 4;

			for my $b ( unpack 'C4', $rawsize ) {
				$id3size = ($id3size << 7) + $b;
			}
			
			$id3size += 10;
			
			# Read the full ID3v2 tag + some audio frames for bitrate
			$args->{_scanlen} = $id3size + (16 * 1024);
			
			main::DEBUGLOG && $log->is_debug && $log->debug( 'ID3v2 tag detected, will read ' . $args->{_scanlen} . ' bytes' );
		}
		
		# XXX: other tag types may need more than 128K too

		# Reset fh back to the end
		$fh->seek( 0, 2 );
	}
	
	$args->{_scanlen} -= $len;
	
	if ( $args->{_scanlen} > 0 ) {
		# Read more data
		#$log->is_debug && $log->debug( $track->url . ' Bytes left: ' . $args->{_scanlen} );
		
		return 1;
	}
	
	# Parse tags and bitrate
	my $bitrate = -1;
	my $vbr;
	
	my $cl          = $http->response->content_length;
	my $type        = $track->content_type;
	my $formatClass = Slim::Formats->classForFormat($type);
	
	if ( $formatClass && Slim::Formats->loadTagFormatForType($type) && $formatClass->can('scanBitrate') ) {
		($bitrate, $vbr) = eval { $formatClass->scanBitrate( $fh, $track->url ) };
		
		if ( $@ ) {
			$log->error("Unable to scan bitrate for " . $track->url . ": $@");
			$bitrate = 0;
		}
		
		if ( $bitrate > 0 ) {
			Slim::Music::Info::setBitrate( $track, $bitrate, $vbr );
			if ($cl) {
				Slim::Music::Info::setDuration( $track, ( $cl * 8 ) / $bitrate );
			}	
			
			# Copy bitrate to redirected URL
			if ( $track->url ne $url ) {
				Slim::Music::Info::setBitrate( $url, $bitrate );
				if ($cl) {
					Slim::Music::Info::setDuration( $url, ( $cl * 8 ) / $bitrate );
				}	
			}
		}
	}
	else {
		main::DEBUGLOG && $log->is_debug && $log->debug("Unable to parse audio data for $type file");
	}
	
	# Update filesize with Content-Length
	if ( $cl ) {
		$track->filesize( $cl );
		$track->update;
		
		# Copy size to redirected URL
		if ( $track->url ne $url ) {
			my $redir = Slim::Schema->updateOrCreate( {
				url => $url,
			} );
			$redir->filesize( $cl );
			$redir->update;
		}
	}
	
	# Delete temp file and other data
	$fh->close;
	unlink $fh->filename if -e $fh->filename;
	delete $args->{_scanbuf};
	delete $args->{_scanlen};
	
	# Disconnect
	return 0;
}

sub parsePlaylist {
	my ( $http, $playlist, $args ) = @_;
	
	my $client = $args->{client};
	my $cb     = $args->{cb} || sub {};
	my $pt     = $args->{pt} || [];
	
	my @results;
	
	my $type = $playlist->content_type;
	
	my $formatClass = Slim::Formats->classForFormat($type);

	if ( $formatClass && Slim::Formats->loadTagFormatForType($type) && $formatClass->can('read') ) {
		my $fh = IO::String->new( $http->response->content_ref );
		@results = eval { $formatClass->read( $fh, '', $playlist->url ) };
	}
	
	if ( !scalar @results || !defined $results[0]) {
		main::DEBUGLOG && $log->is_debug && $log->debug( "Unable to parse playlist for content-type $type $@" );
		
		# delete bad playlist
		$playlist->delete;
		
		return $cb->( undef, 'PLAYLIST_NO_ITEMS_FOUND', @{$pt} );
	}
	
	# Convert the track to a playlist object
	$playlist = Slim::Schema->objectForUrl( {
		url => $playlist->url,
		playlist => 1,
	} );
	
	# Link the found tracks with the playlist
	$playlist->setTracks( \@results );
	
	if ( main::INFOLOG && $log->is_info ) {
		$log->info( 'Found ' . scalar( @results ) . ' items in playlist ' . $playlist->url );
		main::DEBUGLOG && $log->debug( map { $_->url . "\n" } @results );
	}
	
	# Scan all URLs in the playlist concurrently
	my $delay   = 0;
	my $ready   = 0;
	my $scanned = 0;
	my $total   = scalar @results;
	
	for my $entry ( @results ) {
		if ( !blessed($entry) ) {
			$total--;
			next;
		}
		
		__PACKAGE__->scanURL( $entry->url, {
			client => $client,
			song   => $args->{song},
			depth  => $args->{depth} + 1,
			delay  => $delay,
			title  => (($playlist->title && $playlist->title =~ /^(?:http|mms)/i) ? undef : $playlist->title),
			cb     => sub {
				my ( $result, $error ) = @_;
				
				# Bug 10208: If resulting track is not the same as entry (due to redirect),
				# we need to adjust the playlist
				if ( blessed($result) && $result->id != $entry->id ) {
					main::DEBUGLOG && $log->is_debug && $log->debug('Scanned track changed, updating playlist');
					
					my $i = 0;
					for my $e ( @results ) {
						if ( $e->id == $entry->id ) {
							splice @results, $i, 1, $result;
							last;
						}
						$i++;
					}
					
					# Get the $playlist object again, as it may have changed
					$playlist = Slim::Schema->objectForUrl( {
						url      => $playlist->url,
						playlist => 1,
					} );
					
					$playlist->setTracks( \@results );
				}
				
				$scanned++;
				
				main::DEBUGLOG && $log->is_debug && $log->debug("Scanned $scanned/$total items in playlist");
				
				if ( !$ready ) {
					# As soon as we find an audio URL, start playing it and continue scanning the rest
					# of the playlist in the background
					if ( my $entry = $playlist->getNextEntry ) {
					
						if ( $entry->bitrate ) {
							# Copy bitrate to playlist
							Slim::Music::Info::setBitrate( $playlist->url, $entry->bitrate, $entry->vbr_scale );
						}
					
						# Copy title if the playlist is untitled or a URL
						# If entry doesn't have a title either, use the playlist URL
						if ( !$playlist->title || $playlist->title =~ /^(?:http|mms)/i ) {
							$playlist = Slim::Music::Info::setTitle( $playlist->url, $entry->title || $playlist->url );
						}
					
						main::DEBUGLOG && $log->is_debug && $log->debug('Found at least one audio URL in playlist');
						
						$ready = 1;
					
						$cb->( $playlist, undef, @{$pt} );
					}
				}
				
				if ( $scanned == $total ) {
					main::DEBUGLOG && $log->is_debug && $log->debug( 'Playlist scan of ' . $playlist->url . ' finished' );
					
					# If we scanned everything and are still not ready, fail
					if ( !$ready ) {
						main::DEBUGLOG && $log->is_debug && $log->debug( 'No audio tracks found in playlist' );
						
						# Get error of last item we tried in the playlist, or a generic error
						my $error;
						for my $track ( $playlist->tracks ) {
							if ( $track->can('error') && $track->error ) {
								$error = $track->error;
							}
						}
						
						$error ||= 'PLAYLIST_NO_ITEMS_FOUND';
						
						# Delete bad playlist
						$playlist->delete;
						
						$cb->( undef, $error, @{$pt} );
					}
				}
			},
		} );
		
		# Stagger playlist scanning by a small amount so we prefer the first item
		
		# XXX: This can be a problem if a playlist file contains 'backup' streams or files
		# we would not want to play these if any of the real streams in the playlist are valid.
		$delay += 1;
	}
}

1;

