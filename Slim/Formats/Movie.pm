package Slim::Formats::Movie;

# $Id$

# Squeezebox Server Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Formats);

use Audio::Scan;

use Slim::Formats::MP3;
use Slim::Utils::Log;
use Slim::Utils::SoundCheck;

my %tagMapping = (
	AART => 'ALBUMARTIST',	# bug 10724 - support aART as Album Artist
	ALB  => 'ALBUM',
	ART  => 'ARTIST',
	CMT  => 'COMMENT',
	COVR => 'ARTWORK',
	CPIL => 'COMPILATION',
	DAY  => 'YEAR',
	GNRE => 'GENRE',
	GEN  => 'GENRE',
	LYR  => 'LYRICS',
	NAM  => 'TITLE',
	SOAA => 'ALBUMARTISTSORT',
	SOAL => 'ALBUMSORT',
	SOAR => 'ARTISTSORT',
	SOCO => 'COMPOSERSORT',
	SONM => 'TITLESORT',
	TMPO => 'BPM',
	TRKN => 'TRACKNUM',
	WRT  => 'COMPOSER',
	
	'MusicBrainz Album Artist' => 'ALBUMARTIST',
	'MusicBrainz Track Id'     => 'MUSICBRAINZ_ID',
	'MusicBrainz Sortname'     => 'ARTISTSORT',
);

sub getTag {
	my $class = shift;
	my $file  = shift || return {};
	
	my $s = Audio::Scan->scan( $file );
	
	my $info = $s->{info};
	my $tags = $s->{tags};
	
	return unless $info->{song_length_ms};
	
	# map the existing tag names to the expected tag names
	$class->_doTagMapping($tags);

	$tags->{OFFSET} = 0;
	$tags->{RATE}   = $info->{samplerate};
	$tags->{SIZE}   = $info->{file_size};
	$tags->{SECS}   = $info->{song_length_ms} / 1000;
	
	if ( my $track = $info->{tracks}->[0] ) {
		# MP4 file	
		$tags->{BITRATE}    = $track->{avg_bitrate};
		$tags->{SAMPLESIZE} = $track->{bits_per_sample};
		$tags->{CHANNELS}   = $track->{channels};

		# If encoding is alac, the file is lossless.
		if ( $track->{encoding} && $track->{encoding} eq 'alac' ) {
			$tags->{LOSSLESS}     = 1;
			$tags->{VBR_SCALE}    = 1;
			$tags->{CONTENT_TYPE} = 'alc';
		}
		elsif ( $track->{encoding} && $track->{encoding} eq 'drms' ) {
			$tags->{DRM} = 1;
		}
		
		# Check for HD-AAC file, if the file has 2 tracks and AOTs of 2/37
		if ( defined $track->{audio_object_type} && (my $track2 = $info->{tracks}->[1]) ) {
			if ( $track->{audio_object_type} == 2 && $track2->{audio_object_type} == 37 ) {
				$tags->{LOSSLESS}  = 1;
				$tags->{VBR_SCALE} = 1;
				# XXX: may want to use a different content-type for HD?
			}
		}
	}
	elsif ( $info->{bitrate} ) {
		# ADTS file
		$tags->{OFFSET}   = $info->{audio_offset}; # ID3v2 tags may be present
		$tags->{BITRATE}  = $info->{bitrate};
		$tags->{CHANNELS} = $info->{channels};
		
		if ( $info->{id3_version} ) {
			$tags->{TAGVERSION} = $info->{id3_version};
		    
			Slim::Formats::MP3->doTagMapping($tags);
		}
	}

	return $tags;
}

sub getCoverArt {
	my $class = shift;
	my $file  = shift;
	
	my $s = Audio::Scan->scan_tags($file);
	
	return $s->{tags}->{COVR};
}

sub _doTagMapping {
	my ($class, $tags) = @_;

	# map the existing tag names to the expected tag names
	while ( my ($old, $new) = each %tagMapping ) {
		if ( exists $tags->{$old} ) {
			$tags->{$new} = delete $tags->{$old};
		}
	}

	# Special handling for DATE tags
	# Parse the date down to just the year, for compatibility with other formats
	if ( defined $tags->{YEAR} ) {
		$tags->{YEAR} =~ s/.*(\d\d\d\d).*/$1/;
	}
	
	# Unroll the disc info.
	if ( $tags->{DISK} ) {
		($tags->{DISC}, $tags->{DISCC}) = split /\//, delete $tags->{DISK};
	}
	
	# Look for iTunes SoundCheck data, unless we have a TXXX track gain tag
	if ( !$tags->{REPLAYGAIN_TRACK_GAIN} ) {
		if ( $tags->{ITUNNORM} ) {
			$tags->{REPLAYGAIN_TRACK_GAIN} = Slim::Utils::SoundCheck::normStringTodB( delete $tags->{ITUNNORM} );
		}
	}
	
	# Flag if we have embedded cover art
	$tags->{HAS_COVER} = 1 if $tags->{COVR};
}

sub getInitialAudioBlock {
	my ($class, $fh) = @_;
	
	my $sourcelog = logger('player.source');
	
	open my $localFh, '<&=', $fh;
	
	seek $localFh, 0, 0;
	
	my $s = Audio::Scan->scan_fh( mp4 => $localFh );
	
	main::DEBUGLOG && $sourcelog->is_debug && $sourcelog->debug( 'Reading initial audio block: length ' . $s->{info}->{audio_offset} );
	
	seek $localFh, 0, 0;
	read $localFh, my $buffer, $s->{info}->{audio_offset};
	
	close $localFh;
	
	# XXX: need to construct a new mdat atom for the seeked data
	
	return $buffer;
}

sub findFrameBoundaries {
	my ($class, $fh, $offset, $time) = @_;

	if (!defined $fh || !defined $time) {
		return 0;
	}
	
	return Audio::Scan->find_frame_fh( mp4 => $fh, int($time * 1000) );
}

# XXX support while transcoding?
sub canSeek { 0 }

1;
