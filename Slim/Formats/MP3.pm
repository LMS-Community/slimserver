package Slim::Formats::MP3;

# $Id: MP3.pm,v 1.3 2003/12/27 23:48:05 daniel Exp $

# SlimServer Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use MP3::Info ();

sub getTag {

	my $file = shift || "";

	my $tags = MP3::Info::get_mp3tag($file); 
	my $info = MP3::Info::get_mp3info($file);

	# we'll always have $info, as it's machine generated.
	if ($tags && $info) {
		%$info = (%$info, %$tags);
	}

	# sometimes we don't get this back.
	$info->{'OFFSET'} += 0;

	return $info;
}

1;
