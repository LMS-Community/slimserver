package Slim::Formats::Movie;

# SlimServer Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

# Given a file, return a hash of name value pairs,
# where each name is a tag name.
sub get_movietag {

	my $file = shift || "";

	# This hash will map the keys in the tag to their values.
	my $tag = {};

	$tag->{'SIZE'}   = -s $file;
	$tag->{'SECS'}   = ($tag->{'SIZE'}) * 8 / 128000;
	$tag->{'OFFSET'} = 0;

	return $tag;
}

1;
