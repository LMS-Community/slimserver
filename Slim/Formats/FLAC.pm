package Slim::Formats::FLAC;

# $Id: FLAC.pm,v 1.1 2003/11/29 01:03:26 daniel Exp $

# SlimServer Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

###############################################################################
# FILE: Slim::Formats::FLAC.pm
#
# DESCRIPTION:
#   Extract FLAC tag information and store in a hash for easy retrieval.
#
###############################################################################

use strict;
use Audio::FLAC;

my %tagMapping = (
	'TRACKNUMBER'	=> 'TRACKNUM',
	'DATE'		=> 'YEAR',
	'SAMPLERATE'	=> 'RATE',
	'TRACKLENGTH'	=> 'SECS',
);

# Given a file, return a hash of name value pairs,
# where each name is a tag name.
sub get_flactag {

	my $file = shift || "";

	my $tags = Audio::FLAC::readFlacTag($file);

	# lazy? no. efficient. =)
	while (my ($old,$new) = each %tagMapping) {

		if (exists $tags->{$old}) {
			$tags->{$new} = $tags->{$old};
			delete $tags->{$old};
		}
	}

	$tags->{'SIZE'} = -s $file;

	return $tags;
}

1;
