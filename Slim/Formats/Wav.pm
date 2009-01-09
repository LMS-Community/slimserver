package Slim::Formats::Wav;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
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
	my $tags = {};

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
		my $wavtags = $read->get_info();
		
		if ($wavtags) { 
			$tags->{'ALBUM'} = $wavtags->{'product'};
			$tags->{'GENRE'} = $wavtags->{'genre'};
			$tags->{'ARTIST'} = $wavtags->{'artist'};
			$tags->{'TITLE'} = $wavtags->{'name'};
			$tags->{'COMMENT'} = $wavtags->{'comment'};
			$tags->{'TRACKNUM'} = $wavtags->{'track'};
		}
		elsif ( $details->{'id3_offset'} ) {
			# Look for ID3 tags in the file starting at id3 offset
			open my $fh, '<&=', $read->{'handle'};
			seek $fh, 0, 0;
			MP3::Info::_get_v2tag( $fh, 2, 0, $tags, $details->{'id3_offset'} );
			close $fh;
		}
		
		# Add other details about the file
		$tags->{'OFFSET'} = $read->offset();
		$tags->{'SIZE'}   = $read->length();
		$tags->{'SECS'}   = $read->length_seconds();
		$tags->{'RATE'}   = $details->{'sample_rate'};
		$tags->{'BITRATE'} = $details->{'bytes_sec'} * 8;
		$tags->{'CHANNELS'} = $details->{'channels'};
		$tags->{'SAMPLESIZE'} = $details->{'bits_sample'};
		$tags->{'BLOCKALIGN'} = $details->{'block_align'};
		$tags->{'ENDIAN'} = 0;
	}

	return $tags;
}

sub getInitialAudioBlock {
	my ($class, $fh, $track) = @_;
	
	# bug 10026: do not provide header when streaming as PCM
	print(${*$fh}{'streamFormat'}, "\n");
	if (${*$fh}{'streamFormat'} eq 'pcm') {
		return '';
	}
	
	my $length = $track->audio_offset() || return undef;
	
	open(my $localFh, '<&=', $fh);
	
	seek($localFh, 0, 0);
	logger('player.source')->debug("Reading initial audio block: length $length");
	read ($localFh, my $buffer, $length);
	seek($localFh, 0, 0);
	close($localFh);
	
	return $buffer;
}

sub canSeek {1}

1;
