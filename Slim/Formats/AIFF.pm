package Slim::Formats::AIFF;

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

# Global vars
use vars qw(
	@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION $REVISION $AUTOLOAD
);

@ISA = 'Exporter';
@EXPORT = qw(
	get_aifftag
);

# Things that can be exported explicitly
@EXPORT_OK = qw(get_aifftag);

%EXPORT_TAGS = (
	all	=> [@EXPORT, @EXPORT_OK]
);

# Given a file, return a hash of name value pairs,
# where each name is a tag name.
sub get_aifftag
{
	# Get the pathname to the file
	my $file = shift || "";

	# This hash will map the keys in the tag to their values.
	my $tag = {};

	# Make sure the file exists.
#	return undef unless -s $file;


	$tag->{'SIZE'} = -s$file;
	$tag->{'SECS'} = (-s$file) / 4 / 44100;

	return $tag;
}

1;
