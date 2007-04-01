package Slim::Player::Protocols::HTTP;

# $Id$

# SlimServer Copyright (c) 2001-2004 Vidur Apparao, Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.  

use strict;
use base qw(Slim::Formats::HTTP);

use File::Spec::Functions qw(:ALL);
use IO::String;

use Slim::Music::Info;
use Slim::Player::TranscodingHelper;
use Slim::Utils::Errno;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Unicode;

use constant MAXCHUNKSIZE => 32768;

my $log = logger('player.streaming.remote');

sub new {
	my $class = shift;
	my $args  = shift;

	if (!$args->{'url'}) {

		logWarning("No url passed!");
		return undef;
	}

	my $self = $class->open($args);

	if (defined($self)) {
		${*$self}{'url'}     = $args->{'url'};
		${*$self}{'client'}  = $args->{'client'};
	}

	return $self;
}

sub readMetaData {
	my $self = shift;
	my $client = ${*$self}{'client'};

	my $metadataSize = 0;
	my $byteRead = 0;

	while ($byteRead == 0) {

		$byteRead = $self->SUPER::sysread($metadataSize, 1);

		if ($!) {

			if ($! ne "Unknown error" && $! != EWOULDBLOCK) {

			 	$log->warn("Warning: Metadata byte not read! $!");
			 	return;

			 } else {

				$log->debug("Metadata byte not read, trying again: $!");  
			 }
		}

		$byteRead = defined $byteRead ? $byteRead : 0;
	}
	
	$metadataSize = ord($metadataSize) * 16;
	
	$log->debug("Metadata size: $metadataSize");

	if ($metadataSize > 0) {
		my $metadata;
		my $metadatapart;
		
		do {
			$metadatapart = '';
			$byteRead = $self->SUPER::sysread($metadatapart, $metadataSize);

			if ($!) {
				if ($! ne "Unknown error" && $! != EWOULDBLOCK) {

					$log->info("Metadata bytes not read! $!");
					return;

				} else {

					$log->info("Metadata bytes not read, trying again: $!");
				}
			}

			$byteRead = 0 if (!defined($byteRead));
			$metadataSize -= $byteRead;	
			$metadata .= $metadatapart;	

		} while ($metadataSize > 0);			

		$log->info("Metadata: $metadata");

		${*$self}{'title'} = parseMetadata($client, $self->url, $metadata);

		# new song, so reset counters
		$client->songBytes(0);
	}
}

sub getFormatForURL {
	my $classOrSelf = shift;
	my $url = shift;

	return Slim::Music::Info::typeFromSuffix($url);
}

sub parseMetadata {
	my $client   = shift;
	my $url      = shift;
	my $metadata = shift;

	$url = Slim::Player::Playlist::url(
		$client, Slim::Player::Source::streamingSongIndex($client)
	);

	if ($metadata =~ (/StreamTitle=\'(.*?)\'(;|$)/)) {

		my $newTitle = Slim::Utils::Unicode::utf8decode_guess($1, 'iso-8859-1');

		my $metaTitle = $client->metaTitle || '';

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

		if ($newTitle && ($metaTitle ne $newTitle)) {
			
			# Some mp3 stations can have 10-15 seconds in the buffer.
			# This will delay metadata updates according to how much is in
			# the buffer, so title updates are more in sync with the music
			my $bitrate = Slim::Music::Info::getBitrate($url) || 128000;
			my $delay   = 0;
			
			if ( $bitrate > 0 ) {
				my $decodeBuffer = $client->bufferFullness() / ( int($bitrate / 8) );
				my $outputBuffer = $client->outputBufferFullness() / (44100 * 8);
			
				$delay = $decodeBuffer + $outputBuffer;
			}
			
			# No delay on the initial metadata
			if ( !$metaTitle ) {
				$delay = 0;
			}
			
			logger('player.streaming')->info("Delaying metadata title set by $delay secs");
			
			$client->metaTitle( $newTitle );
			
			Slim::Utils::Timers::setTimer(
				$client,
				Time::HiRes::time() + $delay,
				\&setMetadataTitle,
				$url,
				$newTitle,
			);
		}

		return $metaTitle;
	}

	return undef;
}

sub setMetadataTitle {
	my ( $client, $url, $newTitle ) = @_;
	
	my $currentTitle = Slim::Music::Info::getCurrentTitle($client, $url) || '';
	return if $newTitle eq $currentTitle;
	
	Slim::Music::Info::setCurrentTitle($url, $newTitle);
	
	$client->sendParent( {
		command => 'setCurrentTitle',
		url     => $url,
		title   => $newTitle,
	} );

	for my $everybuddy ( $client, Slim::Player::Sync::syncedWith($client)) {
		$everybuddy->update();
	}
	
	# For some purposes, a change of title is a newsong...
	Slim::Control::Request::notifyFromArray($client, ['playlist', 'newsong', $newTitle]);
	
	logger('player.streaming')->info("Setting title for $url to $newTitle");
}

sub canDirectStream {
	my ($classOrSelf, $client, $url) = @_;
	
	# When synced, we don't direct stream so that the server can proxy a single
	# stream for all players
	if ( Slim::Player::Sync::isSynced($client) ) {

		logger('player.streaming')->info(sprintf(
			"[%s] Not direct streaming because player is synced", $client->id
		));

		return 0;
	}

	# Allow user pref to select the method for streaming
	if ( my $method = $client->prefGet('mp3StreamingMethod') ) {
		if ( $method == 1 ) {
			logger('player.streaming')->debug("Not direct streaming because of mp3StreamingMethod pref");
			return 0;
		}
	}

	# Check the available types - direct stream MP3, but not Ogg.
	my ($command, $type, $format) = Slim::Player::TranscodingHelper::getConvertCommand($client, $url);

	if (defined $command && $command eq '-' || $format eq 'mp3') {
		return $url;
	}

	return 0;
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

			$log->debug("The shoutcast metadata overshot the interval.");
		}	
	}
	
	# Use MPEG::Audio::Frame to detect the bitrate if we didn't see an icy header
	if ( !$self->bitrate && $self->contentType =~ /^(?:mp3|audio\/mpeg)$/ ) {

		my $io = IO::String->new($_[1]);

		$log->info("Trying to read bitrate from stream");

		my ($bitrate, $vbr) = Slim::Utils::Scanner::scanBitrate($io);

		Slim::Music::Info::setBitrate( $self->infoUrl, $bitrate, $vbr );
		${*$self}{'bitrate'} = $bitrate;
		
		if ( $self->client && $self->bitrate > 0 && $self->contentLength > 0 ) {

			# if we know the bitrate and length of a stream, display a progress bar
			if ( $self->bitrate < 1000 ) {
				${*$self}{'bitrate'} *= 1000;
			}
			
			# But don't update the progress bar if it was already set in parseHeaders
			# using previously-known duration info
			unless ( my $secs = Slim::Music::Info::getDuration( $self->url ) ) {
								
				$self->client->streamingProgressBar( {
					'url'     => $self->url,
					'bitrate' => $self->bitrate,
					'length'  => $self->contentLength,
				} );
			}
		}
	}
	
	# XXX: Add scanBitrate support for non-directstreaming Ogg and FLAC

	return $readLength;
}

sub parseDirectBody {
	my ( $class, $client, $url, $body ) = @_;

	logger('player.streaming.direct')->info("Parsing body for bitrate.");

	my $contentType = Slim::Music::Info::contentType($url);

	my ($bitrate, $vbr) = Slim::Utils::Scanner::scanBitrate( $body, $contentType, $url );

	if ( $bitrate ) {
		Slim::Music::Info::setBitrate( $url, $bitrate, $vbr );
	}

	# Must return a track object to play
	my $track = Slim::Schema->rs('Track')->objectForUrl({
		'url'      => $url,
		'readTags' => 1
	});

	return $track;
}

1;

__END__
