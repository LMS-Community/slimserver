package Slim::Formats::AIFF;

# SlimServer Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

# Given a file, return a hash of name value pairs,
# where each name is a tag name.
sub get_aifftag {

	my $file = shift || "";

	my $filesize = -s $file;

	# This hash will map the keys in the tag to their values.
	my $tags = {};

	# Make sure the file exists.
	return undef unless $filesize && -r $file;
	my $f;
	my $chunkheader;
	
	open $f, "<$file" || return undef;
	
	return undef if read($f, $chunkheader, 12) < 12;

	my ($tag, $size, $format) = unpack "a4Na4", $chunkheader;
	
	return undef if ($tag ne 'FORM' || $format ne 'AIFF' || $size > $filesize);

	my $chunkpos = tell($f);

	my %readchunks = ();

	do {		
		return undef if read($f, $chunkheader, 8) < 8;
		($tag, $size) = unpack "a4N", $chunkheader;
		$readchunks{$tag} = 1;
				
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
			return if $size != 18;
			return undef if read($f, $commheader, 18) < 18;
			my ($numChannels, $numSampleFrames, $sampleSize, $sampleRateExp, $sampleRateMantissa) = unpack "nNnxCN", $commheader;
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
		}
		
		# skip to the next chunk
		seek($f, $chunkpos + $size + 8, 0);
		$chunkpos = tell($f);
		
	} while (tell($f) < $filesize);
	
	if (exists $readchunks{'COMM'} && exists $readchunks{'SSND'}) {
		$tags->{'BITRATE'} = $tags->{'RATE'} * $tags->{'SAMPLESIZE'} *  $tags->{'CHANNELS'};
		$tags->{'SECS'} = $tags->{'SIZE'} / ($tags->{'BITRATE'} / 8);
		$tags->{'FS'} = $filesize;
	}

	return $tags;
}

1;
