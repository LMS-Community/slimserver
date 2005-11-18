package Slim::Formats::AIFF;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use MP3::Info;

sub getTag {
	my $class = shift;
	my $file  = shift || return {};

	my $filesize = -s $file;

	# Make sure the file exists.
	return undef unless $filesize && -r $file;

	$::d_formats && msg( "Reading AIFF information for $file\n");

	# This hash will map the keys in the tag to their values.
	my $tags = MP3::Info::get_mp3tag($file);

	my $f;
	my $chunkheader;
	
	open $f, $file || return undef;

	return undef if read($f, $chunkheader, 12) < 12;

	my ($tag, $size, $format) = unpack "a4Na4", $chunkheader;
	my $chunkpos = 12;

	$size += 8; # size is chunk data size, without the chunk header.
	$tags->{'ENDIAN'} = 1; # unless told otherwise, AIFF/AIFC is big-endian
	$tags->{'FS'} = $filesize;
	
	$::d_formats && msg("read first tag: $tag $size $format\n");
	
	return undef if ($tag ne 'FORM' || ($format ne 'AIFF' && $format ne 'AIFC'));
	if ($::d_formats && $size != $filesize) {

	# iTunes rips with bogus size info...
		msg("AIFF::getTag: ignores invalid filesize in header = $size, actual file size = $filesize\n");
	}

	my %readchunks = ();

	while ($chunkpos < $filesize) {
		return undef unless seek($f, $chunkpos, 0);
		return undef if read($f, $chunkheader, 8) < 8;
		($tag, $size) = unpack "a4N", $chunkheader;
		$readchunks{$tag} = 1;
		$::d_formats && msg("read tag: $tag $size at file offset $chunkpos\n");
		# look for the sound chunk
		if ($tag eq 'SSND') {
			my $ssndheader;
			return undef if read($f, $ssndheader, 8) < 8; 
 			my ($dataoffset, $blocksize) = unpack "NN", $ssndheader;
  			#ignore the blocksize for now...
 			$tags->{'OFFSET'} = $chunkpos + 16 + $dataoffset;
			$::d_formats && msg("  dataoffset=$dataoffset -> $tags->{'OFFSET'}\n");
 			
		# look for the chunk describing the format
		} elsif ($tag eq 'COMM') {
			my $commheader;
			my $expectedsize = $format eq 'AIFF' ? 18 : 22;
			return undef if ($size < $expectedsize);
 			return undef if read($f, $commheader, $expectedsize) != $expectedsize;
 			
 			my ($numChannels, $numSampleFrames, $sampleSize, $sampleRateExp, $sampleRateMantissa, $encoding) = unpack "nNnxCNxxxxa4", $commheader;
 			$::d_formats && msg("  c=$numChannels, nsf=$numSampleFrames, ss=$sampleSize, sre=$sampleRateExp, srm=$sampleRateMantissa, enc=$encoding\n");
 
 			$tags->{'CHANNELS'} = $numChannels;
 			$tags->{'SAMPLESIZE'} = $sampleSize;
 			$tags->{'SIZE'} = $numSampleFrames * $numChannels * $sampleSize / 8;
 			
 			# calculate the sample rate (as an integer from the 80 bit IEEE floating point value, given the exponent and mantissa
    			$sampleRateExp = 30 - $sampleRateExp;
    			my $lastMantissa;
 		    while ($sampleRateExp--) {
 				$lastMantissa = $sampleRateMantissa;
 			 	$sampleRateMantissa = $sampleRateMantissa >> 1;
 		   	}
 		   	$sampleRateMantissa++ if ($lastMantissa & 0x00000001); 			
 			my $samplesPerSecond = $sampleRateMantissa;
 			return undef if $samplesPerSecond < 100 || $samplesPerSecond > 99123;
 		   	
 		   	$tags->{'RATE'} = $samplesPerSecond;
 		   	$tags->{'BITRATE'} = $samplesPerSecond * $numChannels * $sampleSize;
 			$tags->{'SECS'} = $numSampleFrames / $samplesPerSecond;
 			$tags->{'BLOCKALIGN'} = $numChannels * $sampleSize / 8;
 		   	
 		   	if ($format eq 'AIFC') {
 		   		if ($encoding eq 'sowt') {
 		   			$tags->{'ENDIAN'} = 0; # little-endian 'encoding'
 		   		} elsif ($encoding ne 'NONE') {
 					return undef; # unable to handle compressed formats.
 		   		}
 		   	}
		}
	} continue {
		$chunkpos += 8 + $size + ($size & 1);
	}

	if (!$readchunks{'COMM'}) {
		# we don't know anything about sample rates, number of channels, sample size, etc...
		# could be 8-bit mono, 16-bit stereo, ...
		$::d_formats && msg("AIFF: Missing COMM chunk\n");
		return undef;
	}

	return $tags;
}

1;
