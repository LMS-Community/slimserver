package Slim::Formats::FLAC;

# $Id: FLAC.pm,v 1.4 2003/12/15 16:39:14 daniel Exp $

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
use MP3::Info ();

my %tagMapping = (
	'TRACKNUMBER' => 'TRACKNUM',
	'DATE'        => 'YEAR',
);

# Given a file, return a hash of name value pairs,
# where each name is a tag name.
sub getTag {

	my $file = shift || "";

	my $flac = Audio::FLAC->new($file);

	my $tags = {};

	# Check for the presence of the info block here
	if (defined $flac->{'bitRate'}) {

		my $tags = $flac->tags();

		# There should be a TITLE tag if the VORBIS tags are to be trusted
		if (defined $tags->{'TITLE'}) {

			# map the existing tag names to the expected tag names
			while (my ($old,$new) = each %tagMapping) {
				if (exists $tags->{$old}) {
					$tags->{$new} = $tags->{$old};
					delete $tags->{$old};
				}
			}

		} else {

			if (exists $flac->{'ID3V2Tag'}) {
				# Get the ID3V2 tag on there, sucka
				$tags = MP3::Info::get_mp3tag($file,2);
			}
		}

		# add more information to these tags
		# these are not tags, but calculated values from the streaminfo
		$tags->{'SIZE'}    = $flac->{'fileSize'};
		$tags->{'SECS'}    = $flac->{'trackTotalLengthSeconds'};
		$tags->{'BITRATE'} = $flac->{'bitRate'}/1000.0;

		# Add the stuff that's stored in the Streaminfo Block
		my $flacInfo = $flac->info();
		$tags->{'RATE'}     = $flacInfo->{'SAMPLERATE'};
		$tags->{'CHANNELS'} = $flacInfo->{'NUMCHANNELS'};

		return $tags;

	} else {

		return undef;
	}
}

1;
