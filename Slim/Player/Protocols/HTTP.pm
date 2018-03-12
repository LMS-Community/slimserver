package Slim::Player::Protocols::HTTP;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech, Vidur Apparao.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.  

use strict;
use base qw(Slim::Formats::RemoteStream);

use IO::Socket qw(:crlf);
use Scalar::Util qw(blessed);

use Slim::Formats::RemoteMetadata;
use Slim::Music::Info;
use Slim::Utils::Errno;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Scanner::Remote;
use Slim::Utils::Unicode;

use constant MAXCHUNKSIZE => 32768;

my $log       = logger('player.streaming.remote');
my $directlog = logger('player.streaming.direct');
my $sourcelog = logger('player.source');

my $prefs = preferences('server');


sub new {
	my $class = shift;
	my $args  = shift;

	if (!$args->{'song'}) {

		logWarning("No song passed!");
		
		# XXX: MusicIP abuses this as a non-async HTTP client, can't return undef
		# return undef;
	}

	my $self = $class->open($args);

	if (defined($self)) {
		${*$self}{'client'}  = $args->{'client'};
		${*$self}{'url'}     = $args->{'url'};
	}

	return $self;
}

sub isRemote { 1 }

sub readMetaData {
	my $self = shift;
	my $client = ${*$self}{'client'};

	my $metadataSize = 0;
	my $byteRead = 0;

	while ($byteRead == 0) {

		$byteRead = $self->SUPER::sysread($metadataSize, 1);

		if ($!) {

			if ($! ne "Unknown error" && $! != EWOULDBLOCK) {

			 	#$log->warn("Warning: Metadata byte not read! $!");
			 	return;

			 } else {

				#$log->debug("Metadata byte not read, trying again: $!");  
			 }
		}

		$byteRead = defined $byteRead ? $byteRead : 0;
	}
	
	$metadataSize = ord($metadataSize) * 16;
	
	if ($metadataSize > 0) {
		main::DEBUGLOG && $log->debug("Metadata size: $metadataSize");
		
		my $metadata;
		my $metadatapart;
		
		do {
			$metadatapart = '';
			$byteRead = $self->SUPER::sysread($metadatapart, $metadataSize);

			if ($!) {
				if ($! ne "Unknown error" && $! != EWOULDBLOCK) {

					#$log->info("Metadata bytes not read! $!");
					return;

				} else {

					#$log->info("Metadata bytes not read, trying again: $!");
				}
			}

			$byteRead = 0 if (!defined($byteRead));
			$metadataSize -= $byteRead;	
			$metadata .= $metadatapart;	

		} while ($metadataSize > 0);			

		main::INFOLOG && $log->info("Metadata: $metadata");

		${*$self}{'title'} = __PACKAGE__->parseMetadata($client, $self->url, $metadata);
	}
}

sub getFormatForURL {
	my $classOrSelf = shift;
	my $url = shift;

	return Slim::Music::Info::typeFromSuffix($url);
}

sub parseMetadata {
	my ( $class, $client, undef, $metadata ) = @_;

	my $url = Slim::Player::Playlist::url(
		$client, Slim::Player::Source::streamingSongIndex($client)
	);
	
	# See if there is a parser for this stream
	my $parser = Slim::Formats::RemoteMetadata->getParserFor( $url );
	if ( $parser ) {
		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug( 'Trying metadata parser ' . Slim::Utils::PerlRunTime::realNameForCodeRef($parser) );
		}
		
		my $handled = eval { $parser->( $client, $url, $metadata ) };
		if ( $@ ) {
			my $name = main::DEBUGLOG ? Slim::Utils::PerlRunTime::realNameForCodeRef($parser) : 'unk';
			logger('formats.metadata')->error( "Metadata parser $name failed: $@" );
		}
		return if $handled;
	}
	
	# Assume Icy metadata as first guess
	# BUG 15896 - treat as single line, as some stations add cr/lf to the song title field
	if ($metadata =~ (/StreamTitle=\'(.*?)\'(;|$)/s)) {
	
		main::DEBUGLOG && $log->is_debug && $log->debug("Icy metadata received: $metadata");

		my $newTitle = Slim::Utils::Unicode::utf8decode_guess($1);
		
		# Some stations provide TuneIn enhanced metadata (TPID, itunesTrackID, etc.) in the title - remove it
		if ( $newTitle =~ /(.*?)- text="(.*?)"/ ) {
			$newTitle = "$1 - $2";
		}

		# Bug 15896, a stream had CRLF in the metadata
		$newTitle =~ s/\s*[\r\n]+\s*//g;

		# capitalize titles that are all lowercase
		# XXX: Why do we do this?  Shouldn't we let metadata display as-is?
		if (lc($newTitle) eq $newTitle) {
			$newTitle =~ s/ (
					  (^\w)    #at the beginning of the line
					  |        # or
					  (\s\w)   #preceded by whitespace
					  |        # or
					  (-\w)   #preceded by dash
					  )
				/\U$1/xg;
		}
		
		# Check for an image URL in the metadata.
		my $artworkUrl;
		if ( $metadata =~ /StreamUrl=\'([^']+)\'/i ) {
			$artworkUrl = $1;
			if ( $artworkUrl !~ /\.(?:jpe?g|gif|png)$/i ) {
				$artworkUrl = undef;
			}
		}
		
		my $cb = sub {
			Slim::Music::Info::setCurrentTitle($url, $newTitle, $client);
			
			if ($artworkUrl) {
				my $cache = Slim::Utils::Cache->new();
				$cache->set( "remote_image_$url", $artworkUrl, 3600 );
				
				if ( my $song = $client->playingSong() ) {
					$song->pluginData( httpCover => $artworkUrl );
				}
				
				main::DEBUGLOG && $directlog->debug("Updating stream artwork to $artworkUrl");
			};
		};
		
		# Delay metadata according to buffer size if we already have metadata
		if ( $client->metaTitle() ) {
			Slim::Music::Info::setDelayedCallback( $client, $cb );
		}
		else {
			$cb->();
		}
	}
	
	# Check for Ogg metadata, which is formatted as a series of
	# 2-byte length/string pairs.
	elsif ( $metadata =~ /^Ogg(.+)/s ) {
		my $comments = $1;
		my $meta = {};
		while ( $comments ) {
			my $length = unpack 'n', substr( $comments, 0, 2, '' );
			my $value  = substr $comments, 0, $length, '';
			
			main::DEBUGLOG && $directlog->is_debug && $directlog->debug("Ogg comment: $value");
			
			# Bug 15896, a stream had CRLF in the metadata
			$metadata =~ s/\s*[\r\n]+\s*/; /g;

			# Look for artist/title/album
			if ( $value =~ /ARTIST=(.+)/i ) {
				$meta->{artist} = $1;
			}
			elsif ( $value =~ /ALBUM=(.+)/i ) {
				$meta->{album} = $1;
			}
			elsif ( $value =~ /TITLE=(.+)/i ) {
				$meta->{title} = $1;
			}
		}
		
		# Re-use wmaMeta field
		my $song = $client->controller()->songStreamController()->song();
		
		my $cb = sub {
			$song->pluginData( wmaMeta => $meta );
			Slim::Music::Info::setCurrentTitle($url, $meta->{title}, $client) if $meta->{title};
		};
		
		# Delay metadata according to buffer size if we already have metadata
		if ( $song->pluginData('wmaMeta') ) {
			Slim::Music::Info::setDelayedCallback( $client, $cb, 'output-only' );
		}
		else {
			$cb->();
		}
		
		return;
	}

	return undef;
}

sub canDirectStream {
	my ($classOrSelf, $client, $url, $inType) = @_;
	
	# When synced, we don't direct stream so that the server can proxy a single
	# stream for all players
	if ( $client->isSynced(1) ) {

		if ( main::INFOLOG && $directlog->is_info ) {
			$directlog->info(sprintf(
				"[%s] Not direct streaming because player is synced", $client->id
			));
		}

		return 0;
	}

	# Allow user pref to select the method for streaming
	if ( my $method = $prefs->client($client)->get('mp3StreamingMethod') ) {
		if ( $method == 1 ) {
			main::DEBUGLOG && $directlog->debug("Not direct streaming because of mp3StreamingMethod pref");
			return 0;
		}
	}
	
	# Strip noscan info from URL
	$url =~ s/#slim:.+$//;

	return $url;
}

sub sysread {
	my $self = $_[0];
	my $chunkSize = $_[2];

	my $metaInterval = ${*$self}{'metaInterval'};
	my $metaPointer  = ${*$self}{'metaPointer'};

	if ($metaInterval && ($metaPointer + $chunkSize) > $metaInterval) {

		$chunkSize = $metaInterval - $metaPointer;

		# This is very verbose...
		#$log->debug("Reduced chunksize to $chunkSize for metadata");
	}

	my $readLength = CORE::sysread($self, $_[1], $chunkSize, length($_[1] || ''));

	if ($metaInterval && $readLength) {

		$metaPointer += $readLength;
		${*$self}{'metaPointer'} = $metaPointer;

		# handle instream metadata for shoutcast/icecast
		if ($metaPointer == $metaInterval) {

			$self->readMetaData();

			${*$self}{'metaPointer'} = 0;

		} elsif ($metaPointer > $metaInterval) {

			main::DEBUGLOG && $log->debug("The shoutcast metadata overshot the interval.");
		}	
	}

	return $readLength;
}

sub parseDirectHeaders {
	my ( $self, $client, $url, @headers ) = @_;
	
	my $isDebug = main::DEBUGLOG && $directlog->is_debug;
	
	# May get a track object
	if ( blessed($url) ) {
		$url = $url->url;
	}
	
	my ($title, $bitrate, $metaint, $redir, $contentType, $length, $body);
	my ($rangeLength, $startOffset);
	
	foreach my $header (@headers) {
	
		# Tidy up header to make no stray nulls or \n have been left by caller.
		$header =~ s/[\0]*$//;
		$header =~ s/\r/\n/g;
		$header =~ s/\n\n/\n/g;

		$isDebug && $directlog->debug("header-ds: $header");

		if ($header =~ /^(?:ic[ey]-name|x-audiocast-name):\s*(.+)/i) {
			
			$title = Slim::Utils::Unicode::utf8decode_guess($1);
		}
		
		elsif ($header =~ /^(?:icy-br|x-audiocast-bitrate):\s*(.+)/i) {
			$bitrate = $1;
			$bitrate *= 1000 if $bitrate < 1000;
		}
	
		elsif ($header =~ /^icy-metaint:\s*(.+)/i) {
			$metaint = $1;
		}
	
		elsif ($header =~ /^Location:\s*(.*)/i) {
			$redir = $1;
		}
		
		elsif ($header =~ /^Content-Type:\s*([^;\n]*)/i) {
			$contentType = $1;
		}
		
		elsif ($header =~ /^Content-Length:\s*(.*)/i) {
			$length = $1;
		}
		
		elsif ($header =~ m%^Content-Range:\s+bytes\s+(\d+)-(\d+)/(\d+)%i) {
			$rangeLength = $3;
			$startOffset = $1;
		}
		
		# mp3tunes metadata, this is a bit of hack but creating
		# an mp3tunes protocol handler is overkill
		elsif ( $url =~ /mp3tunes\.com/ && $header =~ /^X-Locker-Info:\s*(.+)/i ) {
			Slim::Plugin::MP3tunes::Plugin->setLockerInfo( $client, $url, $1 );
		}
	}
	
	# Content-Range: has predecence over Content-Length:
	if ($rangeLength) {
		$length = $rangeLength;
	}
	
	my $song = ${*self}{'song'} if blessed $self;
	
	if (!$song && $client->controller()->songStreamController()) {
		$song = $client->controller()->songStreamController()->song();
	}
	
	if ($song && $length) {
		my $seekdata = $song->seekdata();
		
		if ($startOffset && $seekdata && $seekdata->{restartOffset}
			&& $seekdata->{sourceStreamOffset} && $startOffset > $seekdata->{sourceStreamOffset})
		{
			$startOffset = $seekdata->{sourceStreamOffset};
		}

		my $streamLength = $length;
		$streamLength -= $startOffset if $startOffset;
		$song->streamLength($streamLength);
		
		# However we got here, we want to know that we did not start at the beginning, if possible
		if ($startOffset) {
			
			
			# Assume saved duration is more accurate that by calculating from length and bitrate
			my $duration = Slim::Music::Info::getDuration($url);
			$duration ||= $length * 8 / $bitrate if $bitrate;
			
			if ($duration) {
				main::INFOLOG && $directlog->info("Setting startOffest based on Content-Range to ", $duration * ($startOffset/$length));
				$song->startOffset($duration * ($startOffset/$length));
			}
		}
	}

	$contentType = Slim::Music::Info::mimeToType($contentType);
	
	if ( !$contentType ) {
		# Bugs 7225, 7423
		# Default contentType to mp3 as some servers don't send the type
		# or send an invalid type we don't include in types.conf
		$contentType = 'mp3';
	}
		
	return ($title, $bitrate, $metaint, $redir, $contentType, $length, $body);
}

=head2 parseHeaders( @headers )

Parse the response headers from an HTTP request, and set instance variables
based on items in the response, eg: bitrate, content type.

Updates the client's streamingProgressBar with the correct duration.

=cut

# XXX Still a lot of duplication here with Squeezebox2::directHeaders()

sub parseHeaders {
	my $self    = shift;
	my $url     = $self->url;
	my $client  = $self->client;
	
	my ($title, $bitrate, $metaint, $redir, $contentType, $length, $body) = $self->parseDirectHeaders($client, $url, @_);

	if ($contentType) {
		if (($contentType =~ /text/i) && !($contentType =~ /text\/xml/i)) {
			# webservers often lie about playlists.  This will
			# make it guess from the suffix.  (unless text/xml)
			$contentType = '';
		}
			
		${*$self}{'contentType'} = $contentType;

		Slim::Music::Info::setContentType( $url, $contentType );
	}
	
	${*$self}{'redirect'} = $redir;
	
	${*$self}{'contentLength'} = $length if $length;
	${*$self}{'song'}->isLive($length ? 0 : 1) if !$redir;

	# Always prefer the title returned in the headers of a radio station
	if ( $title ) {
		main::INFOLOG && $log->is_info && $log->info( "Setting new title for $url, $title" );
		Slim::Music::Info::setCurrentTitle( $url, $title );
		
		# Bug 7979, Only update the database title if this item doesn't already have a title
		my $curTitle = Slim::Music::Info::title($url);
		if ( !$curTitle || $curTitle =~ /^(?:http|mms)/ ) {
			Slim::Music::Info::setTitle( $url, $title );
		}
	}

	if ($bitrate) {
		main::INFOLOG && $log->is_info &&
				$log->info(sprintf("Bitrate for %s set to %d",
					$self->infoUrl,
					$bitrate,
				));
		
		${*$self}{'bitrate'} = $bitrate;
		Slim::Music::Info::setBitrate( $self->infoUrl, $bitrate );
	} elsif ( !$self->bitrate ) {
		# Bitrate may have been set in Scanner by reading the mp3 stream
		$bitrate = ${*$self}{'bitrate'} = Slim::Music::Info::getBitrate( $url );
	}
	
	
	if ($metaint) {
		${*$self}{'metaInterval'} = $metaint;
		${*$self}{'metaPointer'}  = 0;
	}
	
	# See if we have an existing track object with duration info for this stream.
	if ( my $secs = Slim::Music::Info::getDuration( $url ) ) {
		
		# Display progress bar
		$client->streamingProgressBar( {
			'url'      => $url,
			'duration' => $secs,
		} );
	}
	else {
	
		if ( $bitrate && $bitrate > 0 && defined $self->contentLength && $self->contentLength > 0 ) {
			# if we know the bitrate and length of a stream, display a progress bar
			if ( $bitrate < 1000 ) {
				${*$self}{'bitrate'} *= 1000;
			}
			$client->streamingProgressBar( {
				'url'     => $url,
				'bitrate' => $self->bitrate,
				'length'  => $self->contentLength,
			} );
		}
	}
		
	# Bug 6482, refresh the cached Track object in the client playlist from the database
	# so it picks up any changed data such as title, bitrate, etc
	Slim::Player::Playlist::refreshTrack( $client, $url );

	return;
}

=head2 requestString( $client, $url, [ $post, [ $seekdata ] ] )

Generate a HTTP request string suitable for sending to a HTTP server.

=cut

sub requestString {
	my $self   = shift;
	my $client = shift;
	my $url    = shift;
	my $post   = shift;
	my $seekdata = shift;

	my ($server, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($url);
 
	# Use full path for proxy servers
	my $proxy = $prefs->get('webproxy');
	
	if ( $proxy && $server !~ /(?:localhost|127.0.0.1)/ ) {
		$path = "http://$server:$port$path";
	}

	my $type = $post ? 'POST' : 'GET';

	# Although the port can be part of the Host: header, some hosts (such
	# as online.wsj.com don't like it, and will infinitely redirect.
	# According to the spec, http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html
	# The port is optional if it's 80, so follow that rule.
	my $host = $port == 80 ? $server : "$server:$port";
	
	# Special case, for the fallback-alarm, disable Icy Metadata, or our own
	# server will try and send it
	my $want_icy = 1;
	if ( $path =~ m{/slim-backup-alarm.mp3$} ) {
		$want_icy = 0;
	}

	# make the request
	my $request = join($CRLF, (
		"$type $path HTTP/1.0",
		"Accept: */*",
		"Cache-Control: no-cache",
		"User-Agent: " . Slim::Utils::Misc::userAgentString(),
		"Icy-MetaData: $want_icy",
		"Connection: close",
		"Host: $host",
	));
	
	if (defined($user) && defined($password)) {
		$request .= $CRLF . "Authorization: Basic " . MIME::Base64::encode_base64($user . ":" . $password,'');
	}
	
	$client->songBytes(0) if $client;

	# If seeking, add Range header
	if ($client && $seekdata) {
		$request .= $CRLF . 'Range: bytes=' . int( ($seekdata->{sourceStreamOffset} || 0) + ($seekdata->{restartOffset} || 0) ) . '-';
		
		if (defined $seekdata->{timeOffset}) {
			# Fix progress bar
			$client->playingSong()->startOffset($seekdata->{timeOffset});
			$client->master()->remoteStreamStartTime( Time::HiRes::time() - $seekdata->{timeOffset} );
		}

		$client->songBytes(int( $seekdata->{sourceStreamOffset} ));
	}

	# Send additional information if we're POSTing
	if ($post) {

		$request .= $CRLF . "Content-Type: application/x-www-form-urlencoded";
		$request .= $CRLF . sprintf("Content-Length: %d", length($post));
		$request .= $CRLF . $CRLF . $post . $CRLF;

	} else {
		$request .= $CRLF . $CRLF;
	}
	
	# Bug 5858, add cookies to the request
	my $request_object = HTTP::Request->parse($request);
	$request_object->uri($url);
	Slim::Networking::Async::HTTP::cookie_jar->add_cookie_header( $request_object );
	$request_object->uri($path);
		
	# Bug 9709, strip long cookies from the request
	$request_object->headers->scan( sub {
		if ( $_[0] eq 'Cookie' ) {
			if ( length($_[1]) > 512 ) {
				$request_object->headers->remove_header('Cookie');
			}
		}
	} );
	
	$request = $request_object->as_string( $CRLF );				

	return $request;
}

sub scanUrl {
	my ( $class, $url, $args ) = @_;
	
	Slim::Utils::Scanner::Remote->scanURL($url, $args);
}

# Allow mp3tunes tracks to be scrobbled
sub audioScrobblerSource {
	my ( $class, $client, $url ) = @_;
	
	if ( $url =~ /mp3tunes\.com/ ) {
		# Scrobble mp3tunes as 'chosen by user' content
		return 'P';
	}
	 
	# R (radio source)
	return 'R';
}

sub getMetadataFor {
	my ( $class, $client, $url, $forceCurrent ) = @_;
	
	# Check for an alternate metadata provider for this URL
	my $provider = Slim::Formats::RemoteMetadata->getProviderFor($url);
	if ( $provider ) {
		my $metadata = eval { $provider->( $client, $url ) };
		if ( $@ ) {
			my $name = main::DEBUGLOG ? Slim::Utils::PerlRunTime::realNameForCodeRef($provider) : 'unk';
			$log->error( "Metadata provider $name failed: $@" );
		}
		elsif ( scalar keys %{$metadata} ) {
			return $metadata;
		}
	}
	
	# Check for parsed WMA metadata, this is here because WMA may
	# use HTTP protocol handler
	if ( my $song = $client->playingSong() ) {
		if ( my $meta = $song->pluginData('wmaMeta') ) {
			my $data = {};
			if ( $meta->{artist} ) {
				$data->{artist} = $meta->{artist};
			}
			if ( $meta->{album} ) {
				$data->{album} = $meta->{album};
			}
			if ( $meta->{title} ) {
				$data->{title} = $meta->{title};
			}
			if ( $meta->{cover} ) {
				$data->{cover} = $meta->{cover};
			}
	
			if ( scalar keys %{$data} ) {
				return $data;
			}
		}
	}
	
	my ($artist, $title);
	# Radio tracks, return artist and title if the metadata looks like Artist - Title
	if ( my $currentTitle = Slim::Music::Info::getCurrentTitle( $client, $url ) ) {
		my @dashes = $currentTitle =~ /( - )/g;
		if ( scalar @dashes == 1 ) {
			($artist, $title) = split / - /, $currentTitle;
		}

		else {
			$title = $currentTitle;
		}
	}
	
	# Remember playlist URL
	my $playlistURL = $url;
	
	# Check for radio URLs with cached covers
	my $cache = Slim::Utils::Cache->new();
	my $cover = $cache->get( "remote_image_$url" );
	
	# Item may be a playlist, so get the real URL playing
	if ( Slim::Music::Info::isPlaylist($url) ) {
		if (my $cur = $client->currentTrackForUrl($url)) {
			$url = $cur->url;
		}
	}
	
	# Remote streams may include ID3 tags with embedded artwork
	# Example: http://downloads.bbc.co.uk/podcasts/radio4/excessbag/excessbag_20080426-1217.mp3
	my $track = Slim::Schema->objectForUrl( {
		url => $url,
	} );
	
	return {} unless $track;
	
	if ( $track->cover ) {
		# XXX should remote tracks use coverid?
		$cover = '/music/' . $track->id . '/cover.jpg';
	}
	
	$artist ||= $track->artistName;
	
	if ( $url =~ /archive\.org/ || $url =~ m|mysqueezebox\.com.+/lma/| ) {
		if ( Slim::Utils::PluginManager->isEnabled('Slim::Plugin::LMA::Plugin') ) {
			my $icon = Slim::Plugin::LMA::Plugin->_pluginDataFor('icon');
			return {
				title    => $title,
				cover    => $cover || $icon,
				icon     => $icon,
				type     => 'Live Music Archive',
			};
		}
	}
	else {	

		if ( (my $handler = Slim::Player::ProtocolHandlers->handlerForURL($url)) !~ /^(?:$class|Slim::Player::Protocols::MMS|Slim::Player::Protocols::HTTPS?)$/ )  {
			if ( $handler && $handler->can('getMetadataFor') ) {
				return $handler->getMetadataFor( $client, $url );
			}
		}	

		my $type = uc( $track->content_type || '' ) . ' ' . Slim::Utils::Strings::cstring($client, 'RADIO');
		
		my $icon = $class->getIcon($url, 'no fallback artwork') || $class->getIcon($playlistURL);
		
		return {
			artist   => $artist,
			title    => $title,
			type     => $type,
			bitrate  => $track->prettyBitRate,
			duration => $track->secs,
			icon     => $icon,
			cover    => $cover || $icon,
		};
	}
	
	return {};
}

sub getIcon {
	my ( $class, $url, $noFallback ) = @_;

	my $handler;

	if ( ($handler = Slim::Player::ProtocolHandlers->iconHandlerForURL($url)) && ref $handler eq 'CODE' ) {
		return &{$handler};
	}

	return $noFallback ? '' : 'html/images/radio.png';
}

sub canSeek {
	my ( $class, $client, $song ) = @_;
	
	$client = $client->master();
	
	# Can only seek if bitrate and duration are known
	my $bitrate = $song->bitrate();
	my $seconds = $song->duration();
	
	if ( !$bitrate || !$seconds ) {
		#$log->debug( "bitrate: $bitrate, duration: $seconds" );
		#$log->debug( "Unknown bitrate or duration, seek disabled" );
		return 0;
	}
		
	return 1;
}

sub canSeekError {
	my ( $class, $client, $song ) = @_;
	
	my $url = $song->currentTrack()->url;
	
	my $ct = Slim::Music::Info::contentType($url);
	
	if ( $ct ne 'mp3' ) {
		return ( 'SEEK_ERROR_TYPE_NOT_SUPPORTED', $ct );
	} 
	
	if ( !$song->bitrate() ) {
		main::INFOLOG && $log->info("bitrate unknown for: " . $url);
		return 'SEEK_ERROR_MP3_UNKNOWN_BITRATE';
	}
	elsif ( !$song->duration() ) {
		return 'SEEK_ERROR_MP3_UNKNOWN_DURATION';
	}
	
	return 'SEEK_ERROR_MP3';
}

sub getSeekData {
	my ( $class, $client, $song, $newtime ) = @_;
	
	# Determine byte offset and song length in bytes
	my $bitrate = $song->bitrate() || return;
		
	$bitrate /= 1000;
		
	main::INFOLOG && $log->info( "Trying to seek $newtime seconds into $bitrate kbps" );
	
	return {
		sourceStreamOffset   => ( ( $bitrate * 1000 ) / 8 ) * $newtime,
		timeOffset           => $newtime,
	};
}

sub getSeekDataByPosition {
	my ($class, $client, $song, $bytesReceived) = @_;
	
	my $seekdata = $song->seekdata() || {};
	
	return {%$seekdata, restartOffset => $bytesReceived};
}

1;

__END__
