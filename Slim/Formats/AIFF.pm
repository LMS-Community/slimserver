package Slim::Formats::AIFF;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use MP3::Info;  # because WAV files sometimes have ID3 tags in them!

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
	
	# print "read first tag: $tag $size $format\n";
	
	return undef if ($tag ne 'FORM' || ($format ne 'AIFF' && $format ne 'AIFC'));  # itunes rips with bogus size info...  disabling: || $size > $filesize);

	my $chunkpos = tell($f);

	my %readchunks = ();

	do {		
		return undef if read($f, $chunkheader, 8) < 8;
		($tag, $size) = unpack "a4N", $chunkheader;
		$readchunks{$tag} = 1;
		# print "read tag: $tag $size\n";
		# look for the sound chunk
		if ($tag eq 'SSND') {
			my $ssndheader;
			return undef if read($f, $ssndheader, 8) < 8; 
			my ($chunkoffset, $blocksize) = unpack "NN", $ssndheader; 
			#ignore the blocksize for now...
			$tags->{'OFFSET'} = tell($f) + $chunkoffset;
			$tags->{'SIZE'} = $size - 8;
			
		# look for the chunk describing the format
		} elsif ($tag eq 'COMM') {
			my $commheader;
			my $expectedsize = $format eq 'AIFF' ? 18 : 22;
			return if ($size <= $expectedsize);
			return undef if read($f, $commheader, $expectedsize) != $expectedsize;
			
			my ($numChannels, $numSampleFrames, $sampleSize, $sampleRateExp, $sampleRateMantissa, $encoding) = unpack "nNnxCNa4", $commheader;

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
		   		
		   		} elsif ($encoding eq 'NONE') {
		   			$tags->{'ENDIAN'} = 0;
		   		} else {
		   			$::d_formats && msg("Unknown AIFC encoding: $encoding\n");
		   		}
		   	} else {
		   		$tags->{'ENDIAN'} = 1;
		   	}
		}
		
		# skip to the next chunk
		seek($f, $chunkpos + $size + 8, 0);
		$chunkpos = tell($f);
		
	} while (tell($f) < $filesize);
	
	if (exists $readchunks{'COMM'} && exists $readchunks{'SSND'}) {
		$tags->{'BITRATE'} = $tags->{'RATE'} * $tags->{'SAMPLESIZE'} *  $tags->{'CHANNELS'};
		$tags->{'SECS'} = $tags->{'SIZE'} / ($tags->{'BITRATE'} / 8);
		$tags->{'FS'} = $filesize;
		$tags->{'BLOCKALIGN'} = $tags->{'SAMPLESIZE'} / 8 * $tags->{'CHANNELS'};
	}

	return $tags;
}

1;
