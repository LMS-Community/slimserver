package Slim::Player::Protocols::HTTP;


# Logitech Media Server Copyright 2001-2020 Logitech, Vidur Apparao.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Formats::RemoteStream);

use IO::Socket qw(:crlf);
use Scalar::Util qw(blessed);
use List::Util qw(min);

use Slim::Formats::RemoteMetadata;
use Slim::Music::Info;
use Slim::Utils::Errno;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Scanner::Remote;
use Slim::Utils::Unicode;

use constant MAXCHUNKSIZE => 32768;

use constant MAX_ERRORS	=> 5;

use constant DISCONNECTED => 0;
use constant IDLE         => 1;
use constant READY        => 2;
use constant CONNECTING   => 3;
use constant CONNECTED    => 4;

use constant PERSISTENT   => 1;
use constant BUFFERED     => 2;

my $log       = logger('player.streaming.remote');
my $directlog = logger('player.streaming.direct');
my $sourcelog = logger('player.source');

my $prefs = preferences('server');
my $cache;

sub new {
	my $class = shift;
	my $args  = shift;

	if (!$args->{'song'}) {

		logWarning("No song passed!");

		# XXX: MusicIP abuses this as a non-async HTTP client, can't return undef
		# return undef;
	}

	my $self = $class->SUPER::new($args) or do {
		$log->error("Couldn't create socket binding to $main::localStreamAddr - $!");
		return undef;
	};

	${*$self}{'client'}  = $args->{'client'};
	${*$self}{'url'}     = $args->{'url'};
	${*$self}{'_class'}  = $class;

	return $self;
}

sub close {
	my $self = shift;

	# call parent's ONLY when new() was made by this class, otherwise
	# let subclass take care of socket's close (multiple inheritance)
	$self->SUPER::close(@_) if ${*$self}{'_class'};
	return unless my $enhanced = delete ${*$self}{'_enhanced'};

	if ($enhanced->{'fh'}) {
		# close read buffer file and remove handler
		Slim::Networking::Select::removeRead($self);
		$enhanced->{'rfh'}->close;
	} elsif ($enhanced->{'status'} && $enhanced->{'status'} > IDLE) {
		# disconnect persistent session (if any)
		$enhanced->{'session'}->disconnect;
	}
}

sub response {
	my $self = shift;
	my ($args, $request, @headers) = @_;

	# re-parse the request string as it might have been overloaded by subclasses
	my $request_object = HTTP::Request->parse($request);
	my ($first) = $self->contentRange =~ /(\d+)-/;

	# do we have the range we requested
	if ($request_object->header('Range') =~ /^bytes=(\d+)-/ && $first != $1) {
		${*$self}{'_skip'} = $1;
		$first = $1;
		$log->info("range request not served, skipping $1 bytes");
	}

	# HTTP headers have now been acquired in a blocking way
	my $enhance = $self->canEnhanceHTTP($args->{'client'}, $args->{'url'});
	return unless $enhance;

	if ($enhance == PERSISTENT || !$self->contentLength) {
		my $uri = $request_object->uri;

		# re-set full uri if it is not absolute (e.g. not proxied)
		if ($uri !~ /^https?/) {
			my ($proto, $host, $port) = $args->{'url'} =~ m|(.+)://(?:[^\@]*\@)?([^:/]+):*(\d*)|;
			$request_object->uri("$proto://$host" . ($port ? ":$port" : '') . $uri);
		}

		my $length = $self->contentLength;

		${*$self}{'_enhanced'} = {
			'session' => Slim::Networking::Async::HTTP->new,
			'request' => $request_object,
			'errors'  => 0,
			'max'     => $self->contentLength ? MAX_ERRORS : 1,
			'status'  => IDLE,
			'first'   => $first // 0,
			'length'  => $length,
			'reader'  => \&readPersistentChunk,
		};

		main::INFOLOG && $log->is_info && $log->info("Using Persistent service for $args->{'url'}");
	} else {
		# enable fast download of body to a file from which we'll read further data
		# but the switch of socket handler can only be done within _sysread otherwise
		# we will timeout when there is a pipeline with a callback
		${*$self}{'_enhanced'} = {
			'fh'      => File::Temp->new( DIR => Slim::Utils::Misc::getTempDir, SUFFIX => '.buf' ),
			'reader'  => \&readBufferedChunk,
		};
		open ${*$self}{'_enhanced'}->{'rfh'}, '<', ${*$self}{'_enhanced'}->{'fh'}->filename;
		binmode(${*$self}{'_enhanced'}->{'rfh'});

		main::INFOLOG && $log->info("Using Buffered service for $args->{'url'}");
	}
}

sub request {
	my $self = shift;
	my $args  = shift;
	my $song = $args->{'song'};
	my $track = $song->currentTrack;
	my $processor = $track->processors($song->wantFormat);

	# no other guidance, define AudioBlock if needed so that audio_offset is skipped in requestString
	if (!$processor || $song->stripHeader) {
		$song->initialAudioBlock('');
		return $self->SUPER::request($args);
	}

	# obtain initial audio block if missing and adjust seekdata then
	if (!defined $song->initialAudioBlock && Slim::Formats->loadTagFormatForType($track->content_type)) {
		my $formatClass = Slim::Formats->classForFormat($track->content_type);
		my $seekdata = $song->seekdata || {};
		open (my $fh, '<', $track->initial_block_fn) if $track->initial_block_fn;
		binmode $fh if $fh;

		if ($formatClass->can('findFrameBoundaries')) {
			my $offset = $formatClass->findFrameBoundaries($fh, $seekdata->{sourceStreamOffset} || 0, $seekdata->{timeOffset} || 0);
			$seekdata->{sourceStreamOffset} = $offset if $offset;
		}

		if ($formatClass->can('getInitialAudioBlock')) {
			$song->initialAudioBlock($formatClass->getInitialAudioBlock($fh, $track, $seekdata->{timeOffset} || 0));
		}

		$song->initialAudioBlock('') unless defined $song->initialAudioBlock;

		$fh->close if $fh;
		main::DEBUGLOG && $log->debug("building new header");
	}

	# all set for opening the HTTP object, but only handle the one non-redirected call
	$self = $self->SUPER::request($args);
	return $self if !$self || exists ${*$self}{'initialAudioBlockRef'};

	# setup audio pre-process if required
	my $blockRef = \($song->initialAudioBlock);
	${*$self}{'audio_process'} = $processor->{'init'}->($blockRef) if $processor->{'init'};

	# set initial block to be sent
	${*$self}{'initialAudioBlockRef'} = $blockRef;
	${*$self}{'initialAudioBlockRemaining'} = length $$blockRef;

	# dynamic headers need to be re-calculated every time
	$song->initialAudioBlock(undef) if $processor->{'initial_block_type'} != Slim::Schema::RemoteTrack::INITIAL_BLOCK_ONCE;

	main::DEBUGLOG && $log->debug("streaming $args->{url} with header of ", length $$blockRef, " from ",
								  $song->seekdata ? $song->seekdata->{sourceStreamOffset} || 0 : $track->audio_offset,
								  $processor->{'init'} ? 'with a processor' : '');

	return $self;
}

sub isRemote { 1 }

sub readMetaData {
	my $self = shift;
	my $client = ${*$self}{'client'};

	my $metadataSize = 0;
	my $byteRead = 0;

	# some streaming servers might align their chunks on metadata which means that
	# we might wait a long while for the 1st byte. We don't want about busy loop, so
	# exit if we don't have one. But once we have it, rest shall follow shortly

	if (!readChunk($self, $metadataSize, 1)) {
		$log->debug("Metadata byte not read, trying again: $!");
		return undef;
	}

	$metadataSize = ord($metadataSize) * 16;

	if ($metadataSize > 0) {
		main::DEBUGLOG && $log->debug("Metadata size: $metadataSize");

		my $metadata;
		my $metadatapart;

		do {
			$metadatapart = '';
			$byteRead = readChunk($self, $metadatapart, $metadataSize);

			if ($!) {

				if ($! ne "Unknown error" && $! != EWOULDBLOCK && $! != EINTR) {
					$log->error("Metadata bytes not read! $!");
					return -1;
				}
				else {
					$log->debug("Metadata bytes not read, trying again: $!");
				}
			}

			$byteRead = 0 if (!defined($byteRead));
			$metadataSize -= $byteRead;
			$metadata .= $metadatapart;

		} while ($metadataSize > 0);

		main::INFOLOG && $log->info("Metadata: $metadata");

		${*$self}{'title'} = __PACKAGE__->parseMetadata($client, $self->url, $metadata);
	}

	return 1;
}

sub getFormatForURL {
	my $classOrSelf = shift;
	my $url = shift;

	return Slim::Music::Info::typeFromSuffix($url);
}

sub currentTrackHandler {
	my ($class, $self, $track) = @_;

	# re-evaluate as we might have been upgraded to HTTPS
	return $class ne __PACKAGE__ ? $class : Slim::Player::ProtocolHandlers->handlerForURL($track->url);
}

sub parseMetadata {
	my ( $class, $client, undef, $metadata ) = @_;

	my $url = Slim::Player::Playlist::url(
		$client, Slim::Player::Source::streamingSongIndex($client)
	);

	$cache ||= Slim::Utils::Cache->new();

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

		# Bug 15896, a stream had CRLF in the metadata (no conflict with utf-8)
		$comments =~ s/\s*[\r\n]+\s*/; /g;

		my $meta = { cover => $cache->get("remote_image_$url") };
		while ( $comments ) {
			my $length = unpack 'n', substr( $comments, 0, 2, '' );
			my $value  = substr $comments, 0, $length, '';

			main::DEBUGLOG && $directlog->is_debug && $directlog->debug("Ogg comment: $value");

			# Look for artist/title/album
			if ( $value =~ /ARTIST=(.+)/i ) {
				$meta->{artist} = Slim::Utils::Unicode::utf8decode_guess($1);
			}
			elsif ( $value =~ /ALBUM=(.+)/i ) {
				$meta->{album} = Slim::Utils::Unicode::utf8decode_guess($1);
			}
			elsif ( $value =~ /TITLE=(.+)/i ) {
				$meta->{title} = Slim::Utils::Unicode::utf8decode_guess($1);
			}
		}

		if (!$meta->{artist}) {
			my @dashes = $meta->{title} =~ /( - )/g;
			($meta->{artist}, $meta->{title}) = split /\s+-\s+/, $meta->{title} if scalar @dashes == 1;
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

sub canEnhanceHTTP {
	return $prefs->get('useEnhancedHTTP');
}

sub canDirectStream {
	my ($class, $client, $url, $inType) = @_;

	# when persistent is used, we won't direct stream to enable retries
	return 0 if $class->canEnhanceHTTP($client, $url);

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

# TODO: what happens if this method is overloaded in a sub-class that does not call its parents method
sub canDirectStreamSong {
	my ( $class, $client, $song ) = @_;

	# can't go direct if we are synced or proxy is set by user
	my $direct = $class->canDirectStream( $client, $song->streamUrl, $class->getFormatForURL );
	return 0 unless $direct;

	my $processor = $song->currentTrack->processors($song->wantFormat);

	# no header or stripHeader flag has precedence
	return $direct if $song->stripHeader || !$processor;

	# with dynamic header 2, always go direct otherwise only when not seeking
	if ($processor->{'initial_block_type'} != Slim::Schema::RemoteTrack::INITIAL_BLOCK_ONSEEK || $song->seekdata) {
		main::INFOLOG && $directlog->info("Need to add header, cannot stream direct");
		return 0;
	}

	return $direct;
}

sub readChunk {
	my $self  = $_[0];
	my $enhanced = ${*$self}{'_enhanced'} || return $self->_sysread($_[1], $_[2], $_[3]);
	return $enhanced->{'reader'}->($enhanced, $self, $_[1], $_[2], $_[3]);
}

sub readPersistentChunk {
	my $enhanced = shift;
	my $self  = $_[0];

	# read directly from socket if primary connection is still active
	if ($enhanced->{'status'} == IDLE) {
		my $readLength = $self->_sysread($_[1], $_[2], $_[3]);
		$enhanced->{'first'} += $readLength;

		# return sysread's result UNLESS we reach eof before expected length
		return $readLength unless defined($readLength) && !$readLength && $enhanced->{'first'} < $self->contentLength;
	}

	# all received using persistent connection
	return 0 if $enhanced->{'status'} == DISCONNECTED;

	# if we are not streaming, need to (re)start a session
	if ( $enhanced->{'status'} <= READY ) {
		my $request = $enhanced->{'request'};
		my $last = $enhanced->{'length'} - 1 if $enhanced->{'length'};

		$request->header( 'Range', "bytes=$enhanced->{'first'}-$last");
		$enhanced->{'status'} = CONNECTING;
		$enhanced->{'lastSeen'} = undef;

		$log->warn("Persistent streaming from $enhanced->{'first'} up to ", $self->contentLength, " for ${*$self}{'url'}");

		$enhanced->{'session'}->send_request( {
			request   => $request,
			onHeaders => sub {
				my $headers = shift->response->headers;
				$enhanced->{'length'} = $1 if $headers->header('Content-Range') =~ /^bytes\s+\d+-\d+\/(\d+)/i;
				$enhanced->{'length'} ||= $headers->header('Content-Length') if $headers->header('Content-Length');
				$enhanced->{'status'} = CONNECTED;
				$enhanced->{'errors'} = 0;
			},
			onError  => sub {
				$enhanced->{'session'}->disconnect;
				$enhanced->{'status'} = READY;
				$enhanced->{'errors'}++;
				$log->error("cannot open session for ${*$self}{'url'} $_[1] ");
			},
		} );
	}

	# the child socket is non-blocking so we can safely call read_entity_body which calls sysread
	# if buffer is empty. This is normally a callback used when select() indicates pending bytes
	my $bytes = $enhanced->{'session'}->socket->read_entity_body($_[1], $_[2]) if $enhanced->{'status'} == CONNECTED;

	# note that we use EINTR with empty buffer because EWOULDBLOCK allows Source::_readNextChunk
	# to do an addRead on $self and would not work as primary socket is closed
	if ( $bytes && $bytes != -1 ) {
		$enhanced->{'first'} += $bytes;
		$enhanced->{'lastSeen'} = time();
		return $bytes;
	} elsif ( $bytes == -1 || (!defined $bytes && $enhanced->{'errors'} < $enhanced->{'max'} &&
							  ($enhanced->{'status'} != CONNECTED || $! == EINTR || $! == EWOULDBLOCK) &&
							  (!defined $enhanced->{'lastSeen'} || time() - $enhanced->{'lastSeen'} < 5)) ) {
		$! = EINTR;
		main::DEBUGLOG && $log->is_debug && $log->debug("need to wait for ${*$self}{'url'}");
		return undef;
	} elsif ( $enhanced->{'first'} == $enhanced->{'length'} || $enhanced->{'errors'} >= $enhanced->{'max'} ) {
		$enhanced->{'session'}->disconnect;
		$enhanced->{'status'} = DISCONNECTED;
		main::INFOLOG && $log->is_info && $log->info("end of ${*$self}{'url'} s:", time() - $enhanced->{'lastSeen'}, " e:$enhanced->{'errors'}");
		return 0;
	} else {
		$log->warn("unexpected connection close at $enhanced->{'first'}/$enhanced->{'length'} for ${*$self}{'url'}\n\tsince:",
		           time() - $enhanced->{'lastSeen'}, "\n\terror:", ($! != EINTR && $! != EWOULDBLOCK) ? $! : "N/A");
		$enhanced->{'session'}->disconnect;
		$enhanced->{'status'} = READY;
		$enhanced->{'errors'}++;
		$! = EINTR;
		return undef;
	}
}

sub readBufferedChunk {
	my $enhanced = shift;
	my $self  = $_[0];

	# first, try to read from buffer file
	my $readLength = $enhanced->{'rfh'}->read($_[1], $_[2], $_[3]);
	return $readLength if $readLength;

	# assume that close() will be called for cleanup
	return 0 if $enhanced->{'done'};

	# empty file but not done yet, try to read directly
	$readLength = $self->_sysread($_[1], $_[2], $_[3]);

	# if we now have data pending, likely we have been removed from the reading loop
	# so we have to re-insert ourselves (no need to store fresh data in buffer)
	if ($readLength) {
		Slim::Networking::Select::addRead($self, \&saveStream);
		return $readLength;
	}

	# use EINTR because EWOULDBLOCK (although faster) may overwrite our addRead()
	$! = EINTR;
	return undef;
}

# handler for pending data in Buffered mode
sub saveStream {
	my $self = shift;
	my $enhanced = ${*$self}{'_enhanced'};

	my $bytes = $self->_sysread(my $data, 32768);
	return unless defined $bytes;

	if ($bytes) {
		# need to bypass Perl's buffered IO and make sure read eof is reset
		syswrite($enhanced->{'fh'}, $data);
		$enhanced->{'rfh'}->seek(0, 1);
	} else {
		Slim::Networking::Select::removeRead($self);
		$enhanced->{'done'} = 1;
	}
}

# we need that call structure to make sure that SUPER calls the
# object's parent, not the package's parent
# see http://modernperlbooks.com/mt/2009/09/when-super-isnt.html
sub _sysread {
	my $self = $_[0];
	return CORE::sysread($_[0], $_[1], $_[2], $_[3]) unless ${*$self}{'_skip'};

	# skip what we need until done or EOF
	my $bytes = CORE::sysread($_[0], my $scratch, min(${*$self}{'_skip'}, 32768));
	return $bytes if defined $bytes && !$bytes;

	# pretend we don't have received anything until we've skipped all
	${*$self}{'_skip'} -= $bytes if $bytes;
	main::INFOLOG && $log->info("Done skipping bytes") unless ${*$self}{'_skip'};

	# we should use EINTR (see S::P::Source) but this is too slow when skipping - will fix in 9.0
	$_[1]= '';
	$! = EWOULDBLOCK;
	return undef;
}

sub sysread {
	my $self = $_[0];
	my $chunkSize = $_[2];

	# make sure we start with an empty return buffer ...
	$_[1] = '';

	# stitch header if any
	if (my $length = ${*$self}{'initialAudioBlockRemaining'}) {

		my $chunkLength = $length;
		my $chunkref;

		main::DEBUGLOG && $log->debug("getting initial audio block of size $length");

		if ($length > $chunkSize || $length < length(${${*$self}{'initialAudioBlockRef'}})) {
			$chunkLength = $length > $chunkSize ? $chunkSize : $length;
			my $chunk = substr(${${*$self}{'initialAudioBlockRef'}}, -$length, $chunkLength);
			$chunkref = \$chunk;
			${*$self}{'initialAudioBlockRemaining'} = ($length - $chunkLength);
		}
		else {
			${*$self}{'initialAudioBlockRemaining'} = 0;
			$chunkref = ${*$self}{'initialAudioBlockRef'};
		}

		$_[1] = $$chunkref;
		return $chunkLength;
	}

	my $metaInterval = ${*$self}{'metaInterval'};
	my $metaPointer  = ${*$self}{'metaPointer'};

	# handle instream metadata for shoutcast/icecast
	if ($metaInterval) {

		if ($metaPointer == $metaInterval) {
			# don't do anything if we can't read yet
			$self->readMetaData() || return undef;

			$metaPointer = ${*$self}{'metaPointer'} = 0;
		}
		elsif ($metaPointer > $metaInterval) {
			main::DEBUGLOG && $log->debug("The shoutcast metadata overshot the interval.");
		}

		if ($metaPointer + $chunkSize > $metaInterval) {
			$chunkSize = $metaInterval - $metaPointer;
			#$log->debug("Reduced chunksize to $chunkSize for metadata");
		}
	}

	my $readLength;

	# do not read if we are building-up too much processed audio
	if (${*$self}{'audio_bytes'} > $chunkSize) {
		${*$self}{'audio_bytes'} = ${*$self}{'audio_process'}->($_[1], $chunkSize);
	}
	else {
		$readLength = readChunk($self, $_[1], $chunkSize, length($_[1] || ''));
		${*$self}{'audio_bytes'} = ${*$self}{'audio_process'}->($_[1], $chunkSize) if ${*$self}{'audio_process'};
	}

	# update metadata pointer only from *actual* sysread
	${*$self}{'metaPointer'} += $readLength if  ${*$self}{'metaInterval'};

	# when not-empty, choose return buffer length over sysread()
	return length $_[1] if length $_[1];

	# we are still processing but have nothing yet to return
	if ($readLength) {
		$readLength = undef;
		$! = EINTR;
	}

	return $readLength;
}

sub parseDirectHeaders {
	my ( $self, $client, $url, @headers ) = @_;

	my $isDebug = main::DEBUGLOG && $directlog->is_debug;
	my $oggType;

	# May get a track object
	if ( blessed($url) ) {
		# FIXME: this does not belong here, we'd better fix the mimetotype below
		($oggType) = $url->content_type =~ /(ogf|ogg|ops)/;
		$url = $url->url;
	}

	my $song = ${*$self}{'song'} if blessed $self;

	if (!$song && $client->controller()->songStreamController()) {
		$song = $client->controller()->songStreamController()->song();
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
			if ($song && !$song->bitrate) {
				$bitrate = $1;
				$bitrate *= 1000 if $bitrate < 8000;
			}
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

		elsif ($header =~ /^Content-Range:\s+bytes\s+(\d+)-\d+\/(\d+)/i) {
			$startOffset = $1;
			$rangeLength = $2;
		}
	}

	# Content-Range: has predecence over Content-Length:
	if ($rangeLength) {
		$length = $rangeLength;
	}

	if ($song && $length) {
		my $seekdata = $song->seekdata();

		if ($startOffset && $seekdata && $seekdata->{restartOffset}
			&& $seekdata->{sourceStreamOffset} && $startOffset > $seekdata->{sourceStreamOffset})
		{
			$startOffset = $seekdata->{sourceStreamOffset};
		}
		else {
			$startOffset -= $song->currentTrack->audio_offset;
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

	return ($title, $bitrate, $metaint, $redir, $oggType || $contentType, $length, $body);
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

	# we should not parse anything before we have reached target
	return if ${*$self}{'redirect'} = $redir;

	if ($contentType) {
		if (($contentType =~ /text/i) && !($contentType =~ /text\/xml/i)) {
			# webservers often lie about playlists.  This will
			# make it guess from the suffix.  (unless text/xml)
			$contentType = '';
		}

		${*$self}{'contentType'} = $contentType;

		Slim::Music::Info::setContentType( $url, $contentType );
	}

	${*$self}{'contentLength'} = $length if $length;
	${*$self}{'song'}->isLive($length ? 0 : 1) if !$redir;

	# capture this here as our parseDirectHeader might be overloaded
	my ($range) = grep /^Content-Range:/i, @_;
	(${*$self}{'contentRange'}) = $range =~ /^Content-Range:\s*bytes\s*(.*)/i;

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
	}
	elsif ( !$self->bitrate ) {
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

	my ($server, $port, $path, $user, $password, $proxied) = Slim::Utils::Misc::crackURL($url);

	# Use full path for proxy servers
	$path = $proxied if $proxied;

	my $type = $post ? 'POST' : 'GET';

	# Although the port can be part of the Host: header, some hosts (such
	# as online.wsj.com don't like it, and will infinitely redirect.
	# According to the spec, http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html
	# The port is optional if it's standard 80/443, so follow that rule.
	my $host = (($url =~ /^http:/ && $port == 80) || ($url =~ /^https:/ && $port == 443)) ? $server : "$server:$port";

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

	# Always add Range to exclude trailing metadata or garbage (aif/mp4...)
	if ($client) {
		my $song = $client->streamingSong;
		my $track = $song->currentTrack;
		$client->songBytes(0);

		my $first = $seekdata->{restartOffset} || int( $seekdata->{sourceStreamOffset} );
		$first ||= $track->audio_offset if $song->stripHeader || defined $song->initialAudioBlock;
		$request .= $CRLF . 'Range: bytes=' . ($first || 0) . '-';
		$request .= $track->audio_offset + $track->audio_size - 1 if $track->audio_size;

		if ($first) {

			if (defined $seekdata->{timeOffset}) {
				# Fix progress bar
				$client->playingSong()->startOffset($seekdata->{timeOffset});
				$client->master()->remoteStreamStartTime( Time::HiRes::time() - $seekdata->{timeOffset} );
			}

			$client->songBytes( $first - ($song->stripHeader ? $track->audio_offset : 0) );
		}
	}

	# Send additional information if we're POSTing
	if ($post) {

		$request .= $CRLF . "Content-Type: application/x-www-form-urlencoded";
		$request .= $CRLF . sprintf("Content-Length: %d", length($post));
		$request .= $CRLF . $CRLF . $post . $CRLF;

	}
	else {
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

sub audioScrobblerSource {
	my ( $class, $client, $url ) = @_;

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
	# use HTTP protocol handler. Check for container and track
	my $song = $client->playingSong();
	my $current = ($song->track->url eq $url || $song->currentTrack->url eq $url) if $song;

	if ( $current ) {
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
			($artist, $title) = split /\s+-\s+/, $currentTitle;
		}

		else {
			$title = $currentTitle;
		}
	}

	# Remember playlist URL
	my $playlistURL = $url;

	# Check for radio or OPML feeds URLs with cached covers
	$cache ||= Slim::Utils::Cache->new();
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

	# make sure that protocol handler is what the $song wanted, not just the $url-based one
	my $handler = $current ? $song->currentTrackHandler : Slim::Player::ProtocolHandlers->handlerForURL($url);

	if ( $handler && $handler !~ /^(?:$class|Slim::Player::Protocols::MMS|Slim::Player::Protocols::HTTPS?)$/ && $handler->can('getMetadataFor') ) {
		return $handler->getMetadataFor( $client, $url );
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

	my $offset = int (( ( $bitrate * 1000 ) / 8 ) * $newtime);
	$offset -= $offset % ($song->currentTrack->block_alignment || 1);

	# this might be re-calculated by request() if direct streaming is disabled
	return {
		sourceStreamOffset   => $offset + $song->currentTrack->audio_offset,
		timeOffset           => $newtime,
	};
}

sub getSeekDataByPosition {
	my ($class, $client, $song, $bytesReceived) = @_;

	my $seekdata = $song->seekdata() || {};

	my $position = int($seekdata->{'sourceStreamOffset'}) || 0;
	$position ||= $song->currentTrack->audio_offset if defined $song->initialAudioBlock;

	return {%$seekdata, restartOffset => $position + $bytesReceived - $song->initialAudioBlock};
}

1;

__END__
