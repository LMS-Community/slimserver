package Slim::Formats::WMA;

# $Id: WMA.pm,v 1.7 2004/10/02 03:13:16 daniel Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
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

	my $wma  = Audio::WMA->new($file) || return $tags;
	
	# why this is an array, I don't know.
	if ($wma->tags()) {
		foreach my $key (keys %{$wma->tags()}) {
			$tags->{uc $key} = $wma->tags($key);
		}
	}
	
	# Correct ogginfo tags
	while (my ($old,$new) = each %tagMapping) {

		if (exists $tags->{$old}) {
			$tags->{$new} = $tags->{$old};
			delete $tags->{$old};
		}
	}

	# Add additional info
	$tags->{'SIZE'}	    = $wma->info('filesize');
	$tags->{'SECS'}	    = $wma->info('playtime_seconds');
	$tags->{'RATE'}	    = $wma->info('sample_rate');

	# WMA bitrate is reported in kbps
	$tags->{'BITRATE'}  = $wma->info('bitrate')*1000;
	$tags->{'DRM'}      = $wma->info('drm');

	$tags->{'STEREO'}   = $wma->info('channels') == 2 ? 1 : 0;
	$tags->{'CHANNELS'} = $wma->info('channels');

	return $tags;
}

1;
