package Slim::Formats::Wav;

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
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
use Slim::Utils::Misc;

# Global vars
use vars qw(
	@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION $REVISION $AUTOLOAD
);

@ISA = 'Exporter';
@EXPORT = qw(
	get_wavtag
);

# Things that can be exported explicitly
@EXPORT_OK = qw(get_wavtag);

%EXPORT_TAGS = (
	all	=> [@EXPORT, @EXPORT_OK]
);

my $bail;  # nasty global to know when we had a fatal error on a file.

# Given a file, return a hash of name value pairs,
# where each name is a tag name.
sub get_wavtag
{
	# Get the pathname to the file
	my $file = shift || "";
	$::d_wav && Slim::Utils::Misc::msg( "Reading WAV information for $file\n");

	# This hash will map the keys in the tag to their values.
	my $tag = MP3::Info::get_mp3tag($file);
	# bogus files are considered empty
	if (!defined($tag->{'SIZE'})) { $tag->{'SIZE'} = 0; }
	if (!defined($tag->{'SECS'})) { $tag->{'SECS'} = 0; }
	# Make sure the file exists.
#	return undef unless -s $file;

	$bail = undef;
	
	my $wav = new Audio::Wav;
	
	$wav->set_error_handler( \&myErrorHandler );
	
	my $read = $wav->read($file);
	if (!$bail) {
		my $nSeconds = $read->length_seconds();
		my $nLength = Slim::Utils::Prefs::get("wavmp3samplerate") * 1000 / 8 * $nSeconds;	# kbit per second to bytes per second
	
		$tag->{'SIZE'} = $nLength;
		$tag->{'SECS'} = $nSeconds;
	} else {
	}
	return $tag;
}

sub myErrorHandler {
	my( %parameters ) = @_;
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
