package Slim::Formats::Shorten;

# $Id: Shorten.pm,v 1.1 2003/12/10 23:02:04 dean Exp $

###############################################################################
# FILE: Slim::Formats::Shorten.pm
#
# DESCRIPTION:
#   Extract tag information from a Shorten file and store in a hash
#   for easy retrieval.  Requires the external command line "shorten"
#   decoder and uses the Audio::Wav module.
#
# NOTES:
#   This code has only been tested on Linux.
###############################################################################
use strict;

use Audio::Wav;
use MP3::Info;  # because WAV files sometimes have ID3 tags in them!
use Slim::Utils::Misc; # this will give a sub redefined error because we ues Slim::Music::Info;

my $bail;  # nasty global to know when we had a fatal error on a file.

# Given a file, return a hash of name value pairs, where each name is
# a tag name.
sub getTag {
	my $file = shift || "";

	# Extract the file and read from the pipe; redirect stderr to
	# /dev/null since we will be closing the pipe before the
	# entire file has been extracted and we don't want to see
	# shorten's error message "failed to write decompressed
	# stream".  Note that this requires a slightly modified
	# Audio/Wav.pm
	$file = "shorten -x \Q$file\E - 2>/dev/null|";

	$::d_source &&
	  Slim::Utils::Misc::msg( "Reading WAV information from $file\n");

	# This hash will map the keys in the tag to their values.
	# Don't use MP3::Info since we can't seek around the stream
	# and don't want to open it multiple times
	my $tags = {};

	# bogus files are considered empty
	$tags->{'SIZE'} ||= 0;
	$tags->{'SECS'} ||= 0;

	$bail = undef;

	my $wav = Audio::Wav->new();

	$wav->set_error_handler( \&myErrorHandler );

	my $read = $wav->read($file);

	unless ($bail) {
		$tags->{'OFFSET'} = $read->position();
		$tags->{'SIZE'}   = $read->length();
		$tags->{'SECS'}   = $read->length_seconds();
	}

	return $tags;
}

sub myErrorHandler {
	my %parameters = @_;

	if ( $parameters{'warning'} or

	     # When reading from a pipeline, the seek done in
	     # Audio::Wav::move_to will fail, but we don't really care
	     # about that
	     ($parameters{'filename'} =~ /\|$/ and
	      $parameters{'message'} =~ /^can\'t move to position/)) {
		# This is a non-critical warning
		$::d_source && Slim::Utils::Misc::msg( "Warning: $parameters{'filename'}: $parameters{'message'}\n");
	} else {
		# Critical error!
		$bail = 1;
		$::d_source && Slim::Utils::Misc::msg( "ERROR: $parameters{'filename'}: $parameters{'message'}\n");
	}
}

1;
