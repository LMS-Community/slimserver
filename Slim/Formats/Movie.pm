package Slim::Formats::Movie;

# $Id: Movie.pm,v 1.13 2004/06/07 23:11:59 dean Exp $

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
	'©nam'	=> 'TITLE',
	'©ART'	=> 'ARTIST',
	'©alb'	=> 'ALBUM',
	'©gen'	=> 'GENRE',
	'©day'	=> 'YEAR',
);

my %binaryTags = (
	'trkn'	=> 'TRACKNUM',
	'disk'	=> 'DISC',
	'cpil'	=> 'COMPILATION',
	'covr'	=> 'PIC'
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
			 $tags->{$new} = Slim::Utils::Misc::utf8toLatin1($tags->{$old});
			 delete $tags->{$old};
	      }
	   }
	   while (my ($old,$new) = each %binaryTags) {
	      if (exists $tags->{$old}) {
			 $tags->{$new} = $tags->{$old};
			 delete $tags->{$old};
	      }
	   }
	} else {
	   $tags = {};
	}

	$tags->{'SIZE'} = -s $file;
	if ($tags->{'TIMESCALE'}) {
		$tags->{'SECS'} = $tags->{'DURATION'} / $tags->{'TIMESCALE'};
		$tags->{'BITRATE'} = $tags->{'SIZE'} * 8 / $tags->{'SECS'};
	}
	$tags->{'OFFSET'} = 0;
	
	# clean up binary tags
	$tags->{'COVER'} = 1 if ($tags->{'COVER'});
	$tags->{'TRACKNUM'} = unpack('N', $tags->{'TRACKNUM'}) if $tags->{'TRACKNUM'};
	($tags->{'DISC'}, $tags->{'DISCC'}) = unpack('Nn', $tags->{'DISC'}) if $tags->{'DISC'};	
	$tags->{'COMPILATION'} = unpack('N', $tags->{'COMPILATION'}) if $tags->{'COMPILATION'};	

	return $tags;
}

sub getCoverArt {
	my $file = shift;
	my $tags = QuickTime::Movie::readUserData($file);

	my $coverart;
	
	$coverart = $tags->{'covr'};
	
	return $coverart;
}



1;
