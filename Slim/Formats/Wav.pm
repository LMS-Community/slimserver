package Slim::Formats::Wav;

# $Id: Wav.pm,v 1.8 2004/01/05 05:17:45 dean Exp $

# SlimServer Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

###############################################################################
# FILE: Slim::Formats::Wav.pm
#
# DESCRIPTION:
#   Extract Wav tag information and store in a hash for easy retrieval.
#   Useage of Nick Peskett's Audio::Wav
#
# NOTES:
#   This code has only been tested on Linux.
###############################################################################
use strict;

use Audio::Wav;
use MP3::Info;  # because WAV files sometimes have ID3 tags in them!
use Slim::Utils::Misc; # this will give a sub redefined error because we ues Slim::Music::Info;

my $bail;  # nasty global to know when we had a fatal error on a file.

# Given a file, return a hash of name value pairs,
# where each name is a tag name.
sub getTag {

	my $file = shift || "";

	$::d_wav && Slim::Utils::Misc::msg( "Reading WAV information for $file\n");

	# This hash will map the keys in the tag to their values.
	my $tags = MP3::Info::get_mp3tag($file);

	# bogus files are considered empty
	$tags->{'SIZE'} ||= 0;
	$tags->{'SECS'} ||= 0;

	$bail = undef;
	
	my $wav = Audio::Wav->new();
	
	$wav->set_error_handler( \&myErrorHandler );
	
	my $read = $wav->read($file);

	unless ($bail) {

		$tags->{'OFFSET'} = $read->offset();
		$tags->{'SIZE'}   = $read->length();
		$tags->{'SECS'}   = $read->length_seconds();
		
		my $wavtags = $read->get_info();
		
		if ($wavtags) { 
			$tags->{'ALBUM'} = $wavtags->{'product'};
			$tags->{'GENRE'} = $wavtags->{'genre'};
			$tags->{'ARTIST'} = $wavtags->{'artist'};
			$tags->{'TITLE'} = $wavtags->{'name'};
			$tags->{'COMMENT'} = $wavtags->{'comment'};
			$tags->{'TRACKNUM'} = $wavtags->{'track'};
		}
	}

	return $tags;
}

sub myErrorHandler {
	my %parameters = @_;

	if ( $parameters{'warning'} ) {
		# This is a non-critical warning
		$::d_wav && Slim::Utils::Misc::msg( "Warning: $parameters{'filename'}: $parameters{'message'}\n");
	} else {
		# Critical error!
		$bail = 1;
		$::d_wav && Slim::Utils::Misc::msg( "ERROR: $parameters{'filename'}: $parameters{'message'}\n");
	}
}

1;
