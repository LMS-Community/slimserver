package Slim::Formats::Movie;

# $Id: Movie.pm,v 1.7 2004/01/26 05:44:14 dean Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

###############################################################################
# FILE: Slim::Formats::Movie.pm
#
# DESCRIPTION:
#   Extract Movie user data information and store in a hash for easy retrieval.
#
###############################################################################

use strict;
use QuickTime::Movie;

my %tagMapping = (
	'TRACKNUMBER'	=> 'TRACKNUM',
	'DATE'			=> 'YEAR',
	'SAMPLERATE'	=> 'RATE',
	'TRACKLENGTH'	=> 'SECS',
);

# Given a file, return a hash of name value pairs,
# where each name is a tag name.
sub getTag {

	my $file = shift || "";

	my $tags = QuickTime::Movie::readUserData($file);

	# lazy? no. efficient. =)
	if (ref $tags eq "HASH") {
	   while (my ($old,$new) = each %tagMapping) {
	      if (exists $tags->{$old}) {
		 $tags->{$new} = $tags->{$old};
		 delete $tags->{$old};
	      }
	   }
	} else {
	   $tags = {};
	}

	$tags->{'SIZE'} = -s $file;
	$tags->{'SECS'}   = ($tags->{'SIZE'}) * 8 / 128000;
	$tags->{'OFFSET'} = 0;

	return $tags;
}

1;
