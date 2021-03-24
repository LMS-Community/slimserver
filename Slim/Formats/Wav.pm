package Slim::Formats::Wav;


# Logitech Media Server Copyright 2001-2020 Logitech.
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

sub volatileInitialAudioBlock { 1 }

sub getInitialAudioBlock {
	my ($class, $fh, $track, $time) = @_;
	my $length = $track->audio_offset() || return undef;
	
	open(my $localFh, '<&=', $fh);
	
	seek($localFh, 0, 0);
	main::DEBUGLOG && logger('player.source')->debug("Reading initial audio block: length $length");
	read ($localFh, my $buffer, $length);
	seek($localFh, 0, 0);
	close($localFh);

	# adjust header size according to seek position
	my $trim = int($time * $track->bitrate / 8);
	$trim -= $trim % ($track->block_alignment || 1);
	substr($buffer, $length - 4, 4, pack('V', $track->audio_size - $trim));
	
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

sub parseStream {
	my ( $class, $dataref, $args ) = @_;

	$args->{_scanbuf} .= $$dataref;
	return -1 if length $args->{_scanbuf} < 128;
	
	my $fh = File::Temp->new( DIR => Slim::Utils::Misc::getTempDir);
	$fh->write($args->{_scanbuf});
	$fh->seek(0, 0);
	
	my $info = Audio::Scan->scan_fh( wav => $fh )->{info};
	$fh->truncate($info->{audio_offset});
	$info->{fh} = $fh;
	
	return $info;
}	

*getCoverArt = \&Slim::Formats::MP3::getCoverArt;

sub canSeek { 1 }

1;
