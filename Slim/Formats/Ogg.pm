package Slim::Formats::Ogg;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
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
use Slim::Utils::Misc;

use Ogg::Vorbis::Header::PurePerl;

my %tagMapping = (
	'TRACKNUMBER'	=> 'TRACKNUM',
);

# To turn perl's internal form into a utf-8 string.
if ($] > 5.007) {
	require Encode;
}

# Given a file, return a hash of name value pairs,
# where each name is a tag name.
sub getTag {

	my $file = shift || "";

	# This hash will map the keys in the tag to their values.
	my $tags = {};
	my $ogg  = undef;

	# some ogg files can blow up - especially if they are invalid.
	eval {
		local $^W = 0;
		$ogg = Ogg::Vorbis::Header::PurePerl->new($file);
	};

	if (!$ogg or $@) {
		$::d_formats && Slim::Utils::Misc::msg("Can't open ogg handle for $file\n");
		return $tags;
	}

	if (!$ogg->info('length')) {
		$::d_formats && Slim::Utils::Misc::msg("Length for Ogg file: $file is 0 - skipping.\n");
		return $tags;
	}

	# Tags can be stacked, in an array.
	foreach my $key ($ogg->comment_tags()) {

		if ($] > 5.007) {
			$tags->{uc($key)} = eval { Encode::decode("utf8", ($ogg->comment($key))[0], Encode::FB_QUIET()) };
		} else {
			$tags->{uc($key)} = Slim::Utils::Misc::utf8toLatin1(($ogg->comment($key))[0]);
		}
	}

	# Correct ogginfo tags
	while (my ($old,$new) = each %tagMapping) {

		if (exists $tags->{$old}) {
			$tags->{$new} = $tags->{$old};
			delete $tags->{$old};
		}

	}

	# Special handling for DATE tags
	# Parse the date down to just the year, for compatibility with other formats
	if (defined $tags->{'DATE'} && !defined $tags->{'YEAR'}) {
		($tags->{'YEAR'} = $tags->{'DATE'}) =~ s/.*(\d\d\d\d).*/$1/;
	}

	# Add additional info
	$tags->{'SIZE'}	    = -s $file;

	$tags->{'SECS'}	    = $ogg->info('length');
	$tags->{'BITRATE'}  = $ogg->info('bitrate_nominal');
	$tags->{'STEREO'}   = $ogg->info('channels') == 2 ? 1 : 0;
	$tags->{'CHANNELS'} = $ogg->info('channels');
	$tags->{'RATE'}	    = $ogg->info('rate') / 1000;

	if (defined $ogg->info('bitrate_upper') && defined $ogg->info('bitrate_lower')) {

		if ($ogg->info('bitrate_upper') != $ogg->info('bitrate_lower')) {

			$tags->{'VBR_SCALE'} = 1;
		} else {
			$tags->{'VBR_SCALE'} = 0;
		}

	} else {

		$tags->{'VBR_SCALE'} = 0;
	}
	
	# temporary for now - Ogg:: doesn't expose this yet.
	$tags->{'OFFSET'}   = $ogg->info('offset') || 0;

	return $tags;
}

1;
