package Slim::Formats::WMA;

# $Id: WMA.pm,v 1.1 2003/12/05 16:56:43 daniel Exp $

# SlimServer Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use Audio::WMA;

my %tagMapping = (
	'TRACKNUMBER'	=> 'TRACKNUM',
	'ALBUMTITLE'	=> 'ALBUM',
	'AUTHOR'	=> 'ARTIST',
	'VBR'		=> 'VBR_SCALE',
);

sub getTag {

	my $file = shift || "";

	# This hash will map the keys in the tag to their values.
	my $tags = {};

	my $wma  = Audio::WMA->new($file);

	# why this is an array, I don't know.
	foreach my $key (keys %{$wma->comment()}) {
		$tags->{uc $key} = $wma->comment($key);
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
	$tags->{'SECS'}	    = $wma->info('playtime_seconds');
	$tags->{'RATE'}	    = $wma->info('max_bitrate');
	$tags->{'BITRATE'}  = $wma->info('bitrate');

	# not supported yet - slimserver doesn't appear to use them anyways
	#$tags->{'STEREO'}   = $wma->info('channels') == 2 ? 1 : 0;
	#$tags->{'CHANNELS'} = $wma->info('channels');

	return $tags;
}

1;
