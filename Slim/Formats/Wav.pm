package Slim::Formats::Wav;

# $Id$

# SlimServer Copyright (c) 2001-2004 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Formats);

use Audio::Wav;
use MP3::Info;

use Slim::Utils::Log;

sub getTag {
	my $class = shift;
	my $file  = shift || return {};

	# This hash will map the keys in the tag to their values.
	my $tags  = MP3::Info::get_mp3tag($file) || {};

	# bogus files are considered empty
	$tags->{'SIZE'} ||= 0;
	$tags->{'SECS'} ||= 0;

	my $bail = undef;
	my $wav  = Audio::Wav->new();
	
	$wav->set_error_handler(sub {
		my %parameters = @_;

		if ( $parameters{'warning'} ) {

			# This is a non-critical warning
			logger('formats.audio')->warn("Warning: $parameters{'filename'}: $parameters{'message'}");

		} else {

			# Critical error!
			$bail = 1;

			logError("$parameters{'filename'}: $parameters{'message'}");
		}
	});

	my $read = $wav->read($file);

	if (!$bail) {

		my $details = $read->details();

		$tags->{'OFFSET'} = $read->offset();
		$tags->{'SIZE'}   = $read->length();
		$tags->{'SECS'}   = $read->length_seconds();
		$tags->{'RATE'}   = $details->{'sample_rate'};
		$tags->{'BITRATE'} = $details->{'bytes_sec'} * 8;
		$tags->{'CHANNELS'} = $details->{'channels'};
		$tags->{'SAMPLESIZE'} = $details->{'bits_sample'};
		$tags->{'BLOCKALIGN'} = $details->{'block_align'};
		$tags->{'ENDIAN'} = 0;
		
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

1;
