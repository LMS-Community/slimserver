package Slim::Formats::DSD;

# Copyright (C) 2013 Kimmo 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Formats);

use Audio::Scan;
use Slim::Formats::MP3;
use Slim::Utils::Log;

sub getTag {
	my $class = shift;
	my $file  = shift || return {};
	
	my $s = Audio::Scan->scan( $file );
	
	my $info = $s->{info};
	my $tags = $s->{tags};
	
	return unless $info->{song_length_ms};

	# size is the number of bytes to stream = header + all of audio block
	$tags->{SIZE}	    = $info->{audio_offset} + $info->{audio_size};

	$tags->{SECS}	    = $info->{song_length_ms} / 1000;
	$tags->{RATE}	    = $info->{samplerate};
	$tags->{CHANNELS}   = $info->{channels};
	$tags->{SAMPLESIZE} = 1;
	$tags->{LOSSLESS}   = 1;

	if ( $info->{tag_diar_artist} ) { 
		$tags->{ARTIST} = $info->{tag_diar_artist}; 
	}
	if ( $info->{tag_diti_title} ) {
		$tags->{TITLE} = $info->{tag_diti_title};
	} 
	
	if ( $info->{id3_version} ) {
		$tags->{TAGVERSION} = $info->{id3_version};
		Slim::Formats::MP3->doTagMapping($tags);
	}
	
	return $tags;
}

*getCoverArt = \&Slim::Formats::MP3::getCoverArt;

sub canSeek { 1 }

1;
