package Slim::Formats::Movie;


# Logitech Media Server Copyright 2001-2020 Logitech.
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
	CON  => 'CONDUCTOR',
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
	$tags->{LEADING_MDAT} = $info->{leading_mdat} || undef;

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

sub volatileInitialAudioBlock { 1 }

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
	
	# I'm not sure why we need a localFh here ...
	open(my $localFh, '<&=', $fh);
	$localFh->seek(0, 0);
	my $info = Audio::Scan->find_frame_fh_return_info( mp4 => $localFh, int($time * 1000) );
	$localFh->close;

	# Since getInitialAudioBlock will be called right away, stash the new seek header so
	# we don't have to scan again
	${*$fh}{_mp4_seek_header} = \($info->{seek_header});

	return $info->{seek_offset};
}

sub canSeek { 1 }

sub parseStream {
	my ( $class, $dataref, $args, $formats ) = @_;
	return -1 unless defined $$dataref;
	
	# stitch new data to existing buf and init parser if needed
	$args->{_scanbuf} .= $$dataref;
	$args->{_need} ||= 8;
	$args->{_offset} ||= 0;
	
	my $len = length($$dataref);
	my $offset = $args->{_offset};
	my $log = logger('player.streaming');
	
	while (length($args->{_scanbuf}) > $args->{_offset} + $args->{_need} + 8) {
		$args->{_atom} = substr($args->{_scanbuf}, $offset+4, 4);
		$args->{_need} = unpack('N', substr($args->{_scanbuf}, $offset, 4));
		$args->{_offset} = $args->{"_$args->{_atom}_"} = $offset;
		
		# a bit of sanity check
		if ($offset == 0 && $args->{_atom} ne 'ftyp') {
			$log->warn("no header! this is supposed to be a mp4 track");
			return 0;
		}
		
		$offset += $args->{_need};
		main::DEBUGLOG && $log->is_debug && $log->debug("atom $args->{_atom} at $args->{_offset} of size $args->{_need}");
		
		# mdat reached = audio offset & size acquired
		if ($args->{_atom} eq 'mdat') {
			$args->{_audio_size} = $args->{_need};
			last;
		}
	}
	
	return -1 unless $args->{_mdat_};

	# now make sure we have acquired a full moov atom
	if (!$args->{_moov_}) {
		# no 'moov' found but EoF
		if (!$len) {
			$log->warn("no 'moov' found before EOF => track probably not playable");
			return 0;
		}
		
		# already waiting for bottom 'moov', we need more
		return -1 if $args->{_range};
		
		# top 'moov' not found, need to seek beyond 'mdat'
		$args->{_range} = $offset;
		$args->{_scanbuf} = substr($args->{_scanbuf}, 0, $args->{_offset});
		delete $args->{_need};
		return $offset;
	} elsif ($args->{_atom} eq 'moov' && $len) {
		return -1;
	}	
	
	# finally got it, add 'moov' size it if was last atom
	$args->{_scanbuf} = substr($args->{_scanbuf}, 0, $args->{_offset} + ($args->{_atom} eq 'moov' ? $args->{_need} : 0));
	
	# put at least 16 bytes after mdat or it confuses audio::scan (and header creation)
	my $fh = File::Temp->new();
	$fh->write($args->{_scanbuf} . pack('N', $args->{_audio_size}) . 'mdat' . ' ' x 16);
	$fh->seek(0, 0);

	my $info = Audio::Scan->scan_fh( mp4 => $fh )->{info};
	$info->{fh} = $fh;
	$info->{audio_offset} = $args->{_mdat_} + 8;
	
	# MPEG-4 audio = 64,  MPEG-4 ADTS main = 102, MPEG-4 ADTS Low Complexity = 103
	# MPEG-4 ADTS Scalable Sampling Rate = 104	
	if ($info->{tracks}->[0] && $info->{tracks}->[0]->{audio_type} == 64 && (!$formats || grep(/aac/i, @{$formats}))) {
		$info->{audio_initiate} = \&setADTSProcess;
		$info->{audio_format} = 'aac';
	}	

	return $info;
}

1;
