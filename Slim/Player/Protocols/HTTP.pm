package Slim::Player::Protocols::HTTP;

# $Id$

# SlimServer Copyright (c) 2001-2004 Vidur Apparao, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.  

use strict;
use base qw(Slim::Formats::HTTP);

use File::Spec::Functions qw(:ALL);
use IO::String;

BEGIN {
	if ($^O =~ /Win32/) {
		*EWOULDBLOCK = sub () { 10035 };
		*EINPROGRESS = sub () { 10036 };

	} else {
		require Errno;
		import Errno qw(EWOULDBLOCK EINPROGRESS);
	}
}

use Slim::Music::Info;
use Slim::Player::TranscodingHelper;
use Slim::Utils::Misc;
use Slim::Utils::Unicode;

use constant MAXCHUNKSIZE => 32768;

sub new {
	my $class = shift;
	my $args  = shift;

	if (!$args->{'url'}) {
		msg("No url passed to Slim::Player::Protocols::HTTP->new() !\n");
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
			 	$::d_remotestream && msg("Metadata byte not read! $!\n");  
			 	return;
			 } else {
			 	# too verbose!
				#$::d_remotestream && msg("Metadata byte not read, trying again: $!\n");  
			 }
		}

		$byteRead = defined $byteRead ? $byteRead : 0;
	}
	
	$metadataSize = ord($metadataSize) * 16;
	
	# too verbose
	#$::d_remotestream && msg("metadata size: $metadataSize\n");

	if ($metadataSize > 0) {
		my $metadata;
		my $metadatapart;
		
		do {
			$metadatapart = '';
			$byteRead = $self->SUPER::sysread($metadatapart, $metadataSize);

			if ($!) {
				if ($! ne "Unknown error" && $! != EWOULDBLOCK) {
					$::d_remotestream && msg("Metadata bytes not read! $!\n");  
					return;
				} else {
					$::d_remotestream && msg("Metadata bytes not read, trying again: $!\n");  
				}			 
			}

			$byteRead = 0 if (!defined($byteRead));
			$metadataSize -= $byteRead;	
			$metadata .= $metadatapart;	

		} while ($metadataSize > 0);			

		$::d_remotestream && msg("metadata: $metadata\n");

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

		my $oldTitle = Slim::Music::Info::getCurrentTitle($client, $url) || '';

		# capitalize titles that are all lowercase
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

		if ($newTitle && ($oldTitle ne $newTitle)) {

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
			
			if ( $::d_remotestream || $::d_directstream ) {
				msg("parseMetadata: Setting title for $url to $newTitle\n");
			}
		}

		return $newTitle;
	}

	return undef;
}

sub canDirectStream {
	my ($classOrSelf, $client, $url) = @_;

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
		$::d_source && msg("reduced chunksize to $chunkSize for metadata\n");
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

			msg("Problem: the shoutcast metadata overshot the interval.\n");
		}	
	}
	
	# Use MPEG::Audio::Frame to detect the bitrate if we didn't see an icy header
	if ( !$self->bitrate && $self->contentType =~ /^(?:mp3|audio\/mpeg)$/ ) {
		my $io = IO::String->new($_[1]);
		
		$::d_remotestream && msg("Trying to read bitrate from stream\n");
		
		my ($bitrate, $vbr) = Slim::Utils::Scanner::scanBitrate($io);
		if ( $bitrate ) {
			Slim::Music::Info::setBitrate( $self->infoUrl, $bitrate, $vbr );
			${*$self}{'bitrate'} = $bitrate;
			
			if ( $self->client && $self->bitrate && $self->contentLength ) {
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
		else {
			${*$self}{'bitrate'} = 1;	# so we don't check again
		}
	}

	return $readLength;
}

sub parseDirectBody {
	my ( $class, $client, $url, $body ) = @_;
	
	$::d_directstream && msgf( "parseDirectBody: Parsing %d bytes for MP3 frames\n", length($body) );

	my $io = IO::String->new(\$body);
	
	my ($bitrate, $vbr) = Slim::Utils::Scanner::scanBitrate($io);
	if ( $bitrate ) {
		Slim::Music::Info::setBitrate( $url, $bitrate, $vbr );
	}
	
	# Must return a track object to play
	my $track = Slim::Schema->rs('Track')->objectForUrl({
		'url'      => $url,
		'readTags' => 1
	});
	
	return ($track);
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
