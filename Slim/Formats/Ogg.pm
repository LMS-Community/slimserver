package Slim::Formats::Ogg;

# $Id: Ogg.pm,v 1.4 2003/11/29 01:03:26 daniel Exp $

# SlimServer Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

###############################################################################
# FILE: Slim::Formats::Ogg.pm
#
# DESCRIPTION:
#   Extract Ogg tag information and store in a hash for easy retrieval.
#
###############################################################################

use strict;

# try and use the C based version of the Vorbis::Header if it exists
# the ::PurePerl version is checked into Slim CVS, so it will always be available.
my $oggHeaderClass;

{
        eval 'use Ogg::Vorbis::Header';

        if ($@ !~ /Can't locate/) {
                $oggHeaderClass = 'Ogg::Vorbis::Header';
        } else {
                $@ = '';
        	eval 'use Ogg::Vorbis::Header::PurePerl';
                $oggHeaderClass = 'Ogg::Vorbis::Header::PurePerl';
        }
}

my %tagMapping = (
	'TRACKNUMBER'	=> 'TRACKNUM',
	'DATE'		=> 'YEAR',
);

# Given a file, return a hash of name value pairs,
# where each name is a tag name.
sub get_oggtag {

	my $file = shift || "";

	# This hash will map the keys in the tag to their values.
	my $tags = {};

	my $ogg  = $oggHeaderClass->new($file);

	# why this is an array, I don't know.
	foreach my $key ($ogg->comment_tags()) {
		$tags->{$key} = ($ogg->comment($key))[0];
	}

	# Correct ogginfo tags
	while (my ($old,$new) = each %tagMapping) {

		if (exists $tags->{$old}) {
			$tags->{$new} = $tags->{$old};
			delete $tags->{$old};
		}
	}

	# Add additional info
	$tags->{'SIZE'}	    = -s $file;

	$tags->{'SECS'}	    = $ogg->info('length');
	$tags->{'BITRATE'}  = int($ogg->info('bitrate_nominal') / 1000);
	$tags->{'STEREO'}   = $ogg->info('channels') == 2 ? 1 : 0;
	$tags->{'CHANNELS'} = $ogg->info('channels');
	$tags->{'RATE'}	    = $ogg->info('rate') / 1000;

	return $tags;
}

1;
