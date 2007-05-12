package Slim::Formats::APE;

# $Id: APE.pm 5405 2005-12-14 22:02:37Z dean $

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Formats::APE

=head1 SYNOPSIS

my $tags = Slim::Formats::APE->getTag( $filename );

=head1 DESCRIPTION

Read tags embedded in Monkey's Audio (APE) files.

=head1 METHODS

=head2 getTag( $filename )

Extract and return audio information & any embedded metadata found.

=head1 SEE ALSO

L<Slim::Formats>, L<Audio::APETags>, L<Audio::APE>, L<MP3::Info>

=cut

use strict;
use base qw(Slim::Formats);

use Audio::APETags;
use Audio::APE;
use MP3::Info ();

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

	my $mac = Audio::APE->new($file);

	my $tags = $mac->tags() || {};

	# Check for the presence of the info block here
	unless (defined $mac->{'bitRate'}) {
		return undef;
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
	}

	# add more information to these tags
	# these are not tags, but calculated values from the streaminfo
	$tags->{'SIZE'}    = $mac->{'fileSize'};
	$tags->{'BITRATE'} = $mac->{'bitRate'};
	$tags->{'SECS'} = $mac->{'duration'};
#	$tags->{'OFFSET'}  = $mac->{'startAudioData'};

	# Add the stuff that's stored in the Streaminfo Block
	#my $mpcInfo = $mac->info();
	$tags->{'RATE'}     = $mac->{'sampleRate'};
	$tags->{'CHANNELS'} = $mac->{'Channels'};

	# stolen from MP3::Info
	$tags->{'MM'}	    = int $tags->{'SECS'} / 60;
	$tags->{'SS'}	    = int $tags->{'SECS'} % 60;
	$tags->{'MS'}	    = (($tags->{'SECS'} - ($tags->{'MM'} * 60) - $tags->{'SS'}) * 1000);
	$tags->{'TIME'}	    = sprintf "%.2d:%.2d", @{$tags}{'MM', 'SS'};

	return $tags;
}

1;
