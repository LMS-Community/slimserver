package Slim::Formats::AAC;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Formats::AAC

=head1 SYNOPSIS

my $tags = Slim::Formats::AAC->getTag( $filename );

=head1 DESCRIPTION

Read tags & metadata embedded in AAC files.

=head1 METHODS

=cut

use strict;
use base qw(Slim::Formats);

use Audio::Scan;

use Fcntl qw(:seek SEEK_SET);

use Slim::Utils::Log;
use Slim::Utils::Misc;

my $log        = logger('formats.audio');

=head2 getTag( $filename )

Extract and return audio information & any embedded metadata found.

=cut

sub getTag {
	my $class = shift;
	my $file  = shift;

	if (!$file) {
		$log->error("No file was passed!");
		return {};
	}

	open my $fh, '<', $file or do {
        warn "Could not open $file for reading: $!\n";
        return;
    };

	my $s = $class->getAudioScan($fh);
	my $tags = $s->{tags};
	my $info = $s->{info};
	close $fh;

	return unless $info->{song_length_ms};

	# map the existing tag names to the expected tag names
	$class->doTagMapping($tags);

	# Map info into tags
	$tags->{TAGVERSION}   = $info->{id3_version};
	$tags->{OFFSET}       = $info->{audio_offset};
	$tags->{SIZE}         = $info->{audio_size};
	$tags->{SECS}         = $info->{song_length_ms} / 1000;
	$tags->{BITRATE}      = $info->{bitrate};
	$tags->{STEREO}       = $info->{stereo};
	$tags->{CHANNELS}     = $info->{stereo} ? 2 : 1;
	$tags->{RATE}         = $info->{samplerate};
	$tags->{DLNA_PROFILE} = $info->{dlna_profile} || undef;

	# when scanning we brokenly align by bytes.
	# XXX: needed?
	$tags->{BLOCKALIGN} = 1;

	return $tags;
}

=head2 findFrameBoundaries( $fh, $offset, $time )

Locate AAC frame boundaries when seeking through a file.

=cut

sub findFrameBoundaries {
	my ( $class, $fh, $offset, $time ) = @_;

	if ( !defined $fh || (!defined $offset && !defined $time) ) {
		return 0;
	}

	my $s = Audio::Scan->scan_fh( aac => $fh );

	if ( defined $time ) {
		$offset = int($s->{info}->{bitrate} * $time / 8) + $s->{info}->{audio_offset};
	}
	else {
		$offset = abs($offset);
	}

	seek($fh, $offset, SEEK_SET);

	# an ADTS frame is 8191 maximum, so we'll capture one for sure
	read($fh, my $buffer, 16384);

=comment
------------------------------------------------------------------------------------
|                		ADTS Fixed Header (7 or 9 bytes)                           |
------------------------------------------------------------------------------------
|    Sync word    |    MPEG version     |    Layer    |  Protection  |   Profile   |
|    (12 bits)    |       (1 bit)       |   (2 bits)  |    (1 bit)   |   (2 bits)  |
------------------------------------------------------------------------------------
|   Profile  |   Sampling frequency index  |  Private bit  | Channel configuration |
|  (2 bits)  |       (4 bits)              |   (1 bit)     |       (1 bit)         |
------------------------------------------------------------------------------------
| Channel config | Original | Home    | Copyright | Copyright start | Frame length |
| (2 bits)       | (1 bit)  | (1 bit) |  (1 bit)  |   (1 bit)       |   (2 bits)   |
------------------------------------------------------------------------------------
|	                       Frame length                         |     Fullness     |
|                            (11 bits)                          |     (5 bits)     |
------------------------------------------------------------------------------------
|                    Fullness                      |     AAC frames in ADTS - 1    |
|                     (6 bits)                     |             (2 bits)          |
------------------------------------------------------------------------------------
|                                 CRC - optional                                   |
|                                    (16 bits)                                     |
------------------------------------------------------------------------------------
=cut

	# iterate in buffer till we find an ADTS frame
	for (my $pos = 0; ($pos = index($buffer, "\xFF\xF1", $pos)) >= 0; $pos += 2) {
		my $length = (unpack('N', substr($buffer, $pos + 3, 4)) >> 13) & 0x1fff;
		return $offset + $pos if substr($buffer, $pos + $length, 2) eq "\xFF\xF1";
	}

	# nothing found
	return -1;
}

=head2 getAudioScan( $fh )

populate tags and info in a hash to be parsed by scanBitrate

=cut

sub getAudioScan {
	my ($class, $fh) = @_;

	# get aac info (Audio::Scan does not scan for id3 in aac
	seek $fh, 0, 0;
	my $s = Audio::Scan->scan_fh( aac => $fh);

	# re-use mp3 to get id3 tags only
	seek $fh, 0, 0;
	my $tags = Audio::Scan->scan_fh( mp3 => $fh, { filter => Audio::Scan->FILTER_TAGS_ONLY } );
	$s->{tags} = $tags->{tags} || {};

	return $s;
}

# for now steal doTagMapping and getCoverArt from mp3 (id3 if any)
*doTagMapping = \&Slim::Formats::MP3::doTagMapping;
*getCoverArt = \&Slim::Formats::MP3::getCoverArt;

# no need of getInitialAudioBlock

sub canSeek { 1 }

1;
