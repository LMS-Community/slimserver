package Slim::Formats::Shorten;

# $Id$

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
use base qw(Slim::Formats);

use Audio::Wav;
use MP3::Info;

use Slim::Utils::Log;

# Given a file, return a hash of name value pairs, where each name is
# a tag name.
sub getTag {
	my $class = shift;
	my $file  = shift || return {};

	# Extract the file and read from the pipe; redirect stderr to
	# /dev/null since we will be closing the pipe before the
	# entire file has been extracted and we don't want to see
	# shorten's error message "failed to write decompressed
	# stream".  Note that this requires a slightly modified
	# Audio/Wav.pm
	my $shorten = Slim::Utils::Misc::findbin('shorten') || return undef;
	
	if (Slim::Utils::OSDetect::OS() eq 'win') {
		$file = $shorten . " -x \"$file\" - 2>nul|";
	} else {
		$file = $shorten . " -x \Q$file\E - 2>/dev/null|";
	}

	my $log = logger('formats.audio');

	$log->debug("Reading WAV information from $file");

	# This hash will map the keys in the tag to their values.
	# Don't use MP3::Info since we can't seek around the stream
	# and don't want to open it multiple times
	my $tags = {};

	# bogus files are considered empty
	$tags->{'SIZE'} ||= 0;
	$tags->{'SECS'} ||= 0;

	my $bail = undef;
	my $wav  = Audio::Wav->new();

	$wav->set_error_handler(sub {

		my %parameters = @_;

		if ($parameters{'warning'} or
		     # When reading from a pipeline, the seek done in
		     # Audio::Wav::move_to will fail, but we don't really care about that
		     ($parameters{'filename'} =~ /\|$/ and
		      $parameters{'message'} =~ /^can\'t move to position/)) {

			# This is a non-critical warning
			$log->warn("Warning: $parameters{'filename'}: $parameters{'message'}");

		} else {

			# Critical error!
			$bail = 1;
			logError("$parameters{'filename'}: $parameters{'message'}");
		}
	});

	my $read = $wav->read($file);

	if (!$bail) {
		$tags->{'OFFSET'} = $read->position();
		$tags->{'SIZE'}   = $read->length();
		$tags->{'SECS'}   = $read->length_seconds();
	}

	return $tags;
}

1;
