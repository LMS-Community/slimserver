package Slim::Formats::Movie;

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
	
	# skip files with video tracks
	for my $track ( @{ $info->{tracks} } ) {
		return if exists $track->{width};
	}
	
	# map the existing tag names to the expected tag names
	$class->_doTagMapping($tags);

	$tags->{OFFSET}       = 0;
	$tags->{RATE}         = $info->{samplerate};
	$tags->{SIZE}         = $info->{file_size};
	$tags->{SECS}         = $info->{song_length_ms} / 1000;
	$tags->{BITRATE}      = $info->{avg_bitrate};
	$tags->{DLNA_PROFILE} = $info->{dlna_profile} || undef;
	
	if ( my $track = $info->{tracks}->[0] ) {
		# MP4 file
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
				$tags->{LOSSLESS}     = 1;
				$tags->{VBR_SCALE}    = 1;
				$tags->{SAMPLESIZE}   = $track2->{bits_per_sample};
				$tags->{CONTENT_TYPE} = 'sls';
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
	
	# Enable artwork in Audio::Scan
	local $ENV{AUDIO_SCAN_NO_ARTWORK} = 0;
	
	my $s = Audio::Scan->scan_tags($file);
	
	return $s->{tags}->{COVR};
}

sub _doTagMapping {
	my ($class, $tags) = @_;

	# map the existing tag names to the expected tag names
	while ( my ($old, $new) = each %tagMapping ) {
		foreach ($old, uc($old)) {
			if ( exists $tags->{$_} ) {
				$tags->{$new} = delete $tags->{$_};
				last;
			}
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
	if ( $tags->{ARTWORK} ) {
		if ( $ENV{AUDIO_SCAN_NO_ARTWORK} ) {
			# In 'no artwork' mode, ARTWORK is the length
			$tags->{COVER_LENGTH} = $tags->{ARTWORK};
		}
		else {
			$tags->{COVER_LENGTH} = length( $tags->{ARTWORK} );
		}
	}
}

sub getInitialAudioBlock {
	my ($class, $fh, $track, $time) = @_;
	
	my $sourcelog = logger('player.source');
	
	# When playing the start of a virtual cue sheet track, findFrameBoundaries will not have been called
	if ( !exists ${*$fh}{_mp4_seek_header} && $track->url =~ /#([^-]+)-([^-]+)$/ ) {
		$class->findFrameBoundaries( $fh, undef, $1 );
	}
	
	main::INFOLOG && $sourcelog->is_info && $sourcelog->info(
	    'Reading initial audio block: length ' . length( ${ ${*$fh}{_mp4_seek_header} } )
	);
	
	return ${ delete ${*$fh}{_mp4_seek_header} };
}

sub findFrameBoundaries {
	my ($class, $fh, $offset, $time) = @_;

	if (!defined $fh || !defined $time) {
		return 0;
	}
	
	my $info = Audio::Scan->find_frame_fh_return_info( mp4 => $fh, int($time * 1000) );
	
	# Since getInitialAudioBlock will be called right away, stash the new seek header so
	# we don't have to scan again
	${*$fh}{_mp4_seek_header} = \($info->{seek_header});
	
	return $info->{seek_offset};
}

sub canSeek { 1 }

1;
