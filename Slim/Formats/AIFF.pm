package Slim::Formats::AIFF;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Formats);

use Audio::Scan;

use Slim::Formats::MP3;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

=head1 NAME

Slim::Formats::AIFF

=head1 SYNOPSIS

my $tags = Slim::Formats::AIFF->getTag( $filename );

=head1 DESCRIPTION

Read tags embedded in AIFF files.

=head1 METHODS

=head2 getTag( $filename )

Extract and return audio information & any embedded metadata found.

=head1 SEE ALSO

L<Slim::Formats>, L<Slim::Utils::SoundCheck>

=cut

my $log = logger('formats.audio');

my $prefs = preferences('server');

sub getTag {
	my $class = shift;
	my $file  = shift || return {};

	my $s = Audio::Scan->scan($file);
	
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
	$tags->{ENDIAN}       = 1;
	$tags->{DLNA_PROFILE} = $info->{dlna_profile} || undef;
	
	# Support AIFC little-endian files
	if ( $info->{compression_type} && $info->{compression_type} eq 'sowt' ) {
		$tags->{ENDIAN} = 0;
	}
	
	# Map ID3 tags if file has them
	if ( $info->{id3_version} ) {
		$tags->{TAGVERSION} = $info->{id3_version};
		
		Slim::Formats::MP3->doTagMapping($tags);
	}

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
	substr($buffer, $length - 3*4, 4, pack('N', $track->audio_size - $trim));
	substr($buffer, 4, 4, pack('N', unpack('N', substr($buffer, 4, 4) - $trim)));
	
	return $buffer;
}

sub parseStream {
	my ( $class, $dataref, $args ) = @_;

	$args->{_scanbuf} .= $$dataref;
	return -1 if length $args->{_scanbuf} < 32*1024;
	
	my $fh = File::Temp->new( DIR => Slim::Utils::Misc::getTempDir);
	$fh->write($args->{_scanbuf});
	$fh->seek(0, 0);
	
	my $info = Audio::Scan->scan_fh( aif => $fh )->{info};
	$fh->truncate($info->{audio_offset});
	$info->{fh} = $fh;
	
	return $info;
}

*getCoverArt = \&Slim::Formats::MP3::getCoverArt;

sub canSeek { 1 }

1;
