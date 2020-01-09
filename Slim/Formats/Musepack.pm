package Slim::Formats::Musepack;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

###############################################################################
# FILE: Slim::Formats::Musepack.pm
#
# DESCRIPTION:
#   Extract APE tag information from a Musepack file and store in a hash for 
#   easy retrieval.
#
###############################################################################

use strict;
use base qw(Slim::Formats);

use Audio::Scan;
use Slim::Formats::APE;

# Given a file, return a hash of name value pairs,
# where each name is a tag name.
sub getTag {
	my $class = shift;
	my $file  = shift || return {};
	
	my $s = Audio::Scan->scan($file);

	my $info = $s->{info};
	my $tags = $s->{tags};

	# Check for the presence of the info block here
	return unless $info->{song_length_ms};
	
	# Add info
	$tags->{SIZE}     = $info->{file_size};
	$tags->{BITRATE}  = $info->{bitrate};
	$tags->{SECS}     = $info->{song_length_ms} / 1000;
	$tags->{RATE}     = $info->{samplerate};
	$tags->{CHANNELS} = $info->{channels};
	
	Slim::Formats::APE->doTagMapping($tags);

	return $tags;
}

*getCoverArt = \&Slim::Formats::APE::getCoverArt;

1;
