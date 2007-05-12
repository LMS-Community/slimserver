package Slim::Formats::Musepack;

# $tagsd: Musepack.pm,v 1.0 2004/01/27 00:00:00 daniel Exp $

# SlimServer Copyright (c) 2001-2007 Logitech.
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

use Audio::APETags;
use Audio::Musepack;

my %tagMapping = (
	'TRACK'	     => 'TRACKNUM',
	'DATE'       => 'YEAR',
	'DISCNUMBER' => 'DISC',
);

# Given a file, return a hash of name value pairs,
# where each name is a tag name.
sub getTag {
	my $class = shift;
	my $file  = shift || return {};

	my $mpc = Audio::Musepack->new($file);

	my $tags = $mpc->tags() || {};

	# Check for the presence of the info block here
	if (!defined $mpc->{'bitRate'}) {
		return {};
	}

	# There should be a TITLE tag if the APE tags are to be trusted
	if (defined $tags->{'TITLE'}) {

		# map the existing tag names to the expected tag names
		while (my ($old,$new) = each %tagMapping) {
			if (exists $tags->{$old}) {
				$tags->{$new} = $tags->{$old};
				delete $tags->{$old};
			}
		}

	} else {

		if (exists $mpc->{'ID3V2Tag'} && Slim::Formats->loadTagFormatForType('mp3')) {

			# Get the ID3V2 tag on there, sucka
			$tags = MP3::Info::get_mp3tag($file, 2);
		}
	}

	# add more information to these tags
	# these are not tags, but calculated values from the streaminfo
	$tags->{'SIZE'}    = $mpc->{'fileSize'};
	$tags->{'SECS'}    = $mpc->{'trackTotalLengthSeconds'};
#	$tags->{'OFFSET'}  = $mpc->{'startAudioData'};
	$tags->{'BITRATE'} = $mpc->{'bitRate'};

	# Add the stuff that's stored in the Streaminfo Block
	my $mpcInfo = $mpc->info();
	$tags->{'RATE'}     = $mpcInfo->{'sampleFreq'};
	$tags->{'CHANNELS'} = $mpcInfo->{'channels'};

	# stolen from MP3::Info
	$tags->{'MM'}	    = int $tags->{'SECS'} / 60;
	$tags->{'SS'}	    = int $tags->{'SECS'} % 60;
	$tags->{'MS'}	    = (($tags->{'SECS'} - ($tags->{'MM'} * 60) - $tags->{'SS'}) * 1000);
	$tags->{'TIME'}	    = sprintf "%.2d:%.2d", @{$tags}{'MM', 'SS'};

	return $tags;
}

1;
