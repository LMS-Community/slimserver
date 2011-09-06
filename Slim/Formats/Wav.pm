package Slim::Formats::Wav;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Formats);

use Audio::Scan;

use Slim::Formats::MP3;
use Slim::Utils::Log;

my %tagMapping = (
	IART => 'ARTIST',
	ICMT => 'COMMENT',
	ICRD => 'YEAR',
	IGNR => 'GENRE',
	INAM => 'TITLE',
	IPRD => 'ALBUM',
	TRCK => 'TRACKNUM',
	ITRK => 'TRACKNUM',
);

sub getTag {
	my $class = shift;
	my $file  = shift || return {};
	
	my $s = Audio::Scan->scan( $file );
	
	my $info = $s->{info};
	my $tags = $s->{tags};
	
	return unless $info->{song_length_ms};
	
	# Add file info
	$tags->{OFFSET}       = $info->{audio_offset};
	$tags->{SIZE}         = $info->{audio_size};
	$tags->{SECS}         = $info->{song_length_ms} / 1000;
	$tags->{RATE}         = $info->{samplerate};
	$tags->{BITRATE}      = $info->{bitrate};
	$tags->{CHANNELS}     = $info->{channels};
	$tags->{SAMPLESIZE}   = $info->{bits_per_sample};
	$tags->{BLOCKALIGN}   = $info->{block_align};
	$tags->{ENDIAN}       = 0;
	$tags->{DLNA_PROFILE} = $info->{dlna_profile} || undef;
	
	# Map ID3 tags if file has them
	if ( $info->{id3_version} ) {
		$tags->{TAGVERSION} = $info->{id3_version};
	}
	
	$class->doTagMapping($tags);

	return $tags;
}

sub getInitialAudioBlock {
	my ($class, $fh, $track) = @_;
	
	# bug 10026: do not provide header when streaming as PCM
	if (${*$fh}{'streamFormat'} eq 'pcm') {
		return '';
	}
	
	my $length = $track->audio_offset() || return undef;
	
	open(my $localFh, '<&=', $fh);
	
	seek($localFh, 0, 0);
	main::DEBUGLOG && logger('player.source')->debug("Reading initial audio block: length $length");
	read ($localFh, my $buffer, $length);
	seek($localFh, 0, 0);
	close($localFh);
	
	return $buffer;
}

sub doTagMapping {
	my ( $class, $tags ) = @_;
	
	while ( my ($old, $new) = each %tagMapping ) {
		if ( exists $tags->{$old} ) {
			$tags->{$new} = delete $tags->{$old};
		}
	}
	
	# Map ID3 tags if any
	if ( $tags->{TAGVERSION} ) {
		Slim::Formats::MP3->doTagMapping($tags);
	}
}

*getCoverArt = \&Slim::Formats::MP3::getCoverArt;

sub canSeek { 1 }

1;
