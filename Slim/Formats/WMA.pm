package Slim::Formats::WMA;

# $Id$

# SlimServer Copyright (c) 2001-2004 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Formats);

use Audio::WMA;

my %tagMapping = (
	'TRACKNUMBER'        => 'TRACKNUM',
	'ALBUMTITLE'         => 'ALBUM',
	'AUTHOR'             => 'ARTIST',
	'VBR'                => 'VBR_SCALE',
	'PARTOFACOMPILATION' => 'COMPILATION',
);

{
	# WMA tags are stored as UTF-16 by default.
	if ($] > 5.007) {
		Audio::WMA->setConvertTagsToUTF8(1);
	}
}

sub getTag {
	my $class = shift;
	my $file  = shift || return {};

	# This hash will map the keys in the tag to their values.
	my $tags = {};

	my $wma  = Audio::WMA->new($file) || return $tags;

	# We can have stacked tags for multple artists.
	if ($wma->tags) {
		foreach my $key (keys %{$wma->tags}) {
			$tags->{uc $key} = $wma->tags($key);
		}
	}
	
	# Map tags onto SlimServer's preferred.
	while (my ($old,$new) = each %tagMapping) {

		if (exists $tags->{$old}) {
			$tags->{$new} = $tags->{$old};
			delete $tags->{$old};
		}
	}

	# Add additional info
	$tags->{'SIZE'}	    = -s $file;
	$tags->{'SECS'}	    = $wma->info('playtime_seconds');
	$tags->{'RATE'}	    = $wma->info('sample_rate');

	# WMA bitrate is reported in bps
	$tags->{'BITRATE'}  = $wma->info('bitrate');
	
	$tags->{'DRM'}      = $wma->info('drm');

	$tags->{'CHANNELS'} = $wma->info('channels');
	$tags->{'LOSSLESS'} = $wma->info('lossless') ? 1 : 0;

	$tags->{'STEREO'} = ($tags->{'CHANNELS'} && $tags->{'CHANNELS'} == 2) ? 1 : 0;
	
	return $tags;
}

sub getCoverArt {
	my $class = shift;
	my $file  = shift || return undef;

	my $tags = $class->getTag($file);

	if (ref($tags) eq 'HASH' && defined $tags->{'PICTURE'}) {

		return $tags->{'PICTURE'}->{'DATA'};
	}

	return undef;
}

1;
