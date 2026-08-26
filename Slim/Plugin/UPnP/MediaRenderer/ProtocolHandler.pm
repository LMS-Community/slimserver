package Slim::Plugin::UPnP::MediaRenderer::ProtocolHandler;

# Logitech Media Server Copyright 2003-2024 Logitech.
# Lyrion Music Server Copyright 2024-2026 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Player::Protocols::HTTP);

use Slim::Utils::Cache;
use Slim::Utils::Errno;
use Slim::Utils::Log;
use Slim::Utils::Misc;

use Slim::Plugin::UPnP::MediaRenderer::AVTransport ();

use constant MAX_RAW_READ => 32768;

my $log = logger('plugin.upnp');

sub isRemote { 1 }

# Always proxy through the server so the outgoing connection to the source uses
# the same IP address that was published for this player via UPnP, and so we can
# use the HTTP/1.1 + chunked transfer-encoding capable persistent connection.
sub canDirectStream { 0 }

sub _normalizeRequestToHttp11 {
	my ( $class, $request ) = @_;
	$request =~ s/^(\S+ \S+) HTTP\/1\.0\r\n/$1 HTTP\/1.1\r\n/;
	return $request;
}

# The server's own outgoing connection to the DLNA source (see canDirectStream
# above) is built and sent by this class, never handed to player firmware, so
# upgrading it to HTTP/1.1 requires no firmware support. HTTP/1.1 is required
# to allow the source to reply with "Transfer-Encoding: chunked" (chunked
# responses are undefined in HTTP/1.0).
sub requestString {
	my $class = shift;
	my $request = $class->SUPER::requestString(@_);
	return $class->_normalizeRequestToHttp11($request);
}

# This primary connection is always read as a raw byte stream by
# Slim::Player::Protocols::HTTP (see readPersistentChunk), with no knowledge of
# HTTP chunked Transfer-Encoding. If the source replied with chunked encoding
# (detected below), transparently strip the chunk framing here before the
# bytes reach the audio decoder.
#
# Slim::Player::Protocols::HTTP::response() re-parses $request into the
# HTTP::Request object it keeps for the persistent/proxied connection, so its
# protocol is picked up straight from the request line. Rewrite that line to
# HTTP/1.1 here (same substitution as requestString() above) instead of
# patching the base class, keeping the HTTP/1.1 upgrade local to this plugin.
sub response {
	my $self = shift;
	my ($args, $request, @headers) = @_;

	$request = $self->_normalizeRequestToHttp11($request);

	if ( grep { /^Transfer-Encoding\s*:\s*chunked/i } @headers ) {
		${*$self}{'_dechunk'} = { raw => '', out => '', pending => undef, eof => 0 };
		main::INFOLOG && $log->info('Response is chunked, decoding Transfer-Encoding on the fly');
	}

	return $self->SUPER::response($args, $request, @headers);
}

sub _sysread {
	my $self    = $_[0];
	my $dechunk = ${*$self}{'_dechunk'} || return $self->SUPER::_sysread($_[1], $_[2], $_[3]);

	my $wantLen = $_[2];
	my $offset  = $_[3] || 0;

	if ( !length $dechunk->{'out'} && !$dechunk->{'eof'} ) {
		my $raw = $self->SUPER::_sysread( my $buf, MAX_RAW_READ, 0 );

		# propagate "no data yet" (EWOULDBLOCK/EINTR) and real read errors as-is
		if ( !$raw ) {
			# A closed socket ($raw defined as 0) or a hard read error (undef $raw
			# with an errno other than "try again") before we ever saw the chunk
			# stream's own 0-size terminator below means the source dropped the
			# connection rather than ending the stream gracefully. Undo the
			# isLive(0) set by parseHeaders() so StreamingController::_RetryOrNext()
			# reconnects, same as it would for any other isLive stream that got cut off.
			if ( ( defined($raw) || ( $! != EWOULDBLOCK && $! != EINTR ) ) && ( my $song = ${*$self}{'song'} ) ) {
				$song->isLive(1);
			}
			return $raw;
		}

		$dechunk->{'raw'} .= $buf;

		# extract as many complete chunks as are currently buffered
		while (1) {
			if ( !defined $dechunk->{'pending'} ) {
				last unless $dechunk->{'raw'} =~ s/^([0-9A-Fa-f]+)[^\r\n]*\r\n//;
				my $size = hex($1);

				if ( !$size ) {
					$dechunk->{'eof'} = 1;
					last;
				}

				$dechunk->{'pending'} = $size;
			}

			last if length( $dechunk->{'raw'} ) < $dechunk->{'pending'} + 2;

			$dechunk->{'out'} .= substr( $dechunk->{'raw'}, 0, $dechunk->{'pending'}, '' );
			substr( $dechunk->{'raw'}, 0, 2, '' ); # discard the CRLF following each chunk's data
			$dechunk->{'pending'} = undef;
		}
	}

	if ( length $dechunk->{'out'} ) {
		$_[1] = '' unless defined $_[1];
		substr( $_[1], $offset ) = substr( $dechunk->{'out'}, 0, $wantLen, '' );
		return length($_[1]) - $offset;
	}

	return 0 if $dechunk->{'eof'};

	# no complete chunk decoded yet, ask caller to retry shortly
	$_[1] = '' unless $offset;
	$! = EWOULDBLOCK;
	return undef;
}

sub getFormatForURL {
	my $class = shift;
	my $url = shift;

	my $meta = Slim::Plugin::UPnP::MediaRenderer::AVTransport->trackMetaFor($url);
	if ( $meta && $meta->{res}->{mime} ) {
		if ( my $type = Slim::Music::Info::mimeToType( $meta->{res}->{mime} ) ) {
			return $type;
		}
	}

	# if typeFromSuffix can't find a result it returns the mp3 default.
	return Slim::Music::Info::typeFromSuffix($url, 'mp3');
}

# XXX use DLNA.ORG_OP value, and/or MIME type
sub canSeek { 1 } # We'll assume Range requests are supported by all servers,
                  # and this is also needed for pause to work properly

sub canSeekError { return ( 'SEEK_ERROR_TYPE_NOT_SUPPORTED', 'UPnP/DLNA' ); }

# To support remote streaming (synced players), we need to subclass Protocols::HTTP
sub new {
	my $class  = shift;
	my $args   = shift;

	my $client    = $args->{client};
	my $song      = $args->{song};
	my $streamUrl = $song->streamUrl() || return;

	main::DEBUGLOG && $log->is_debug && $log->debug( 'Remote streaming UPnP track: ' . $streamUrl );

	my $sock = $class->SUPER::new( {
		url     => $streamUrl,
		song    => $args->{song},
		client  => $client,
		bitrate => $song->bitrate() || 128_000,
	} ) || return;

	my $meta = Slim::Plugin::UPnP::MediaRenderer::AVTransport->trackMetaFor( $song->currentTrack->url );
	${*$sock}{contentType} = ( $meta && $meta->{res}->{mime} ) || 'audio/mpeg';

	return $sock;
}

# Avoid scanning
sub scanUrl {
	my ($class, $url, $args) = @_;

	# $url is a synthetic per-playlist-entry id (see AVTransport::_newTrackId),
	# looked up via AVTransport's client-independent registry rather than
	# $args->{client}'s pluginData: in a sync group, this is called with the
	# sync-group's master client, which may not be the client this UPnP
	# session's state was stored on.
	my $meta = Slim::Plugin::UPnP::MediaRenderer::AVTransport->trackMetaFor($url);

	if ( ref($meta) eq 'HASH' && ( my $uri = $meta->{res}->{uri} ) ) {
		$args->{song}->streamUrl($uri);
	}

	$args->{cb}->($args->{song}->currentTrack());
}

sub audioScrobblerSource { 'P' }

# Slim::Player::Protocols::HTTP::parseHeaders() sets isLive(1) whenever no
# Content-Length is known, which is also the case for chunked-encoded streams.
#
# StreamingController::_RetryOrNext() treats isLive tracks as infinite radio
# and, once played for more than 10s, tries to reconnect to the same URI.
# DLNA/UPnP tracks are finite, discrete tracks despite lacking a known length,
# so we override parseHeaders() to set isLive(0) for them instead.
#
# Only chunked responses get this treatment: they're the only ones where
# _sysread() can tell a graceful stream end (its own EOF chunk) apart from a
# genuine connection abort, and re-arms isLive(1) itself when it sees the
# latter, so a real disconnect still triggers a reconnect.
# For any other response (fixed Content-Length, or no chunking), leave
# isLive exactly as the base class set it.
sub parseHeaders {
        my $self = shift;
        my $ret  = $self->SUPER::parseHeaders(@_);

        if ( grep { /^Transfer-Encoding\s*:\s*chunked/i } @_ ) {
                if ( my $song = ${*$self}{'song'} ) {
                        $song->isLive(0);
                }
        }

        return $ret;
}

# XXX parseDirectHeaders, needed?

# XXX seek data, using res@size, res@duration instead of bitrate

sub isRepeatingStream {
	my (undef, $song) = @_;

	return 0; # XXX playlists, REPEAT_ONE, REPEAT_ALL, SHUFFLE
}

# XXX getNextTrack (playlists, next track)

sub getMetadataFor {
	my ( $class, $client, $url ) = @_;

	# This returns metadata for any tracks added to the playlist via the plugin.
	# $url is a synthetic per-playlist-entry id (see AVTransport::_newTrackId),
	# looked up via AVTransport's client-independent registry rather than
	# $client's pluginData: in a sync group, this is called with the sync-group's
	# master client, which may not be the client this UPnP session's state was
	# stored on.
	my $meta = Slim::Plugin::UPnP::MediaRenderer::AVTransport->trackMetaFor($url) || {};
	my $res  = $meta->{res} || {};

	# support Icy Metadata updates
	my $title = Slim::Music::Info::getCurrentTitle( $client, $url ) || $meta->{title};

	main::DEBUGLOG && $log->is_debug && $log->debug( 'Metadata returned for  ' . $title );
	return {
		artist   => $meta->{artist},
		album    => $meta->{album},
		title    => $title,
		cover    => $meta->{cover} || '', # XXX default
		icon     => '', # XXX default icon
		duration => $res->{secs} || 0,
		bitrate  => $res->{bitrate} ? ($res->{bitrate} / 1000) . 'kbps' : 0,
		type     => $res->{mime} . ' (UPnP/DLNA)',
	};
}


1;
