package Slim::Formats::AIFF;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use MP3::Info;  # because AIFF files sometimes have ID3 tags in them!

# Given a file, return a hash of name value pairs,
# where each name is a tag name.
sub getTag {

	my $file = shift || "";

	my $filesize = -s $file;

	# Make sure the file exists.
	return undef unless $filesize && -r $file;

	$::d_formats && Slim::Utils::Misc::msg( "Reading AIFF information for $file\n");

	# This hash will map the keys in the tag to their values.
	my $tags = MP3::Info::get_mp3tag($file);

	my $f;
	my $chunkheader;
	
	open $f, "<$file" || return undef;
	# print "opened file\n";
	return undef if read($f, $chunkheader, 12) < 12;

	my ($tag, $size, $format) = unpack "a4Na4", $chunkheader;
	my $chunkpos = 12;
	$tags->{'ENDIAN'} = 1; # unless told otherwise, AIFF/AIFC is big-endian
	
	# print "read first tag: $tag $size $format\n";
	
	return undef if ($tag ne 'FORM' || ($format ne 'AIFF' && $format ne 'AIFC'));  # itunes rips with bogus size info...  disabling: || $size > $filesize);

	my %readchunks = ();

	while ($chunkpos < $filesize) {
		return undef unless seek($f, $chunkpos, 0);
		return undef if read($f, $chunkheader, 8) < 8;
		($tag, $size) = unpack "a4N", $chunkheader;
		$readchunks{$tag} = 1;
		# print "read tag: $tag $size\n";
		# look for the sound chunk
		if ($tag eq 'SSND') {
			my $ssndheader;
			return undef if read($f, $ssndheader, 8) < 8; 
 			my ($dataoffset, $blocksize) = unpack "NN", $ssndheader;
  			#ignore the blocksize for now...
 			$tags->{'OFFSET'} = $chunkpos + 16 + $dataoffset;
 			$tags->{'SIZE'} = $size - 8 - $dataoffset;
 			
		# look for the chunk describing the format
		} elsif ($tag eq 'COMM') {
			my $commheader;
			my $expectedsize = $format eq 'AIFF' ? 18 : 22;
			return undef if ($size < $expectedsize);
			return undef if read($f, $commheader, $expectedsize) != $expectedsize;
			
			my ($numChannels, $numSampleFrames, $sampleSize, $sampleRateExp, $sampleRateMantissa, $encoding) = unpack "nNnxCNxxxxa4", $commheader;

			$tags->{'CHANNELS'} = $numChannels;
			$tags->{'SAMPLESIZE'} = $sampleSize;
			
			# calculate the sample rate (as an integer from the 80 bit IEEE floating point value, given the exponent and mantissa
   			$sampleRateExp = 30 - $sampleRateExp; 
   			
   			my $lastMantissa;
   			
		    while ($sampleRateExp--) {
				$lastMantissa = $sampleRateMantissa;
			 	$sampleRateMantissa = $sampleRateMantissa >> 1;
		   	}
		   	
		   	$sampleRateMantissa++ if ($lastMantissa & 0x00000001); 			
		   	
		   	$tags->{'RATE'} = $sampleRateMantissa;
		   	
		   	if ($format eq 'AIFC') {
		   		if ($encoding eq 'sowt') {
		   			$tags->{'ENDIAN'} = 0; # little-endian 'encoding'
		   		} elsif ($encoding ne 'NONE') {
		   			$::d_formats && msg("Unknown AIFC encoding: $encoding\n");
					return undef; # unable to handle compressed formats.
		   		}
		   	}
		}
	} continue {
		$chunkpos += 8 + $size + ($size & 1);
	}
	
	if (exists $readchunks{'COMM'} && exists $readchunks{'SSND'}) {
		$tags->{'BITRATE'} = $tags->{'RATE'} * $tags->{'SAMPLESIZE'} *  $tags->{'CHANNELS'};
		$tags->{'SECS'} = $tags->{'SIZE'} / ($tags->{'BITRATE'} / 8);
		$tags->{'FS'} = $filesize;
		$tags->{'BLOCKALIGN'} = $tags->{'SAMPLESIZE'} / 8 * $tags->{'CHANNELS'};
	}

	return $tags;
}

1;
