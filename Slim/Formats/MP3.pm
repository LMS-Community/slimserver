package Slim::Formats::MP3;

# $Id: MP3.pm,v 1.5 2004/01/26 05:44:14 dean Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
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
	
	# when scanning we brokenly align by bytes.  
	# TODO: We need a frame saavy seek routine here...
	$info->{'BLOCKALIGN'} = 1;
	
	# bitrate is in bits per second, not kbits per second.
	$info->{'BITRATE'} = $info->{'BITRATE'} * 1000 if ($info->{'BITRATE'});

	return $info;
}

1;
