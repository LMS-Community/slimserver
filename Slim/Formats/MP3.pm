package Slim::Formats::MP3;

# $Id: MP3.pm,v 1.7 2004/06/01 22:47:51 dean Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use IO::Seekable qw(SEEK_SET);
use MP3::Info ();

sub getTag {

	my $file = shift || "";

	my $tags = MP3::Info::get_mp3tag($file); 
	my $info = MP3::Info::get_mp3info($file);

	# we'll always have $info, as it's machine generated.
	if ($tags && $info) {
		%$info = (%$info, %$tags);
	}

	# sometimes we don't get this back correctly
	$info->{'OFFSET'} += 0;
	
	my ($start, $end);
	open my $fh, "< $file\0";
	if ($fh) {
		($start, $end) = seekNextFrame($fh, $info->{'OFFSET'}, 1);
		close $fh;
	}
	
	if ($start) {
		$info->{'OFFSET'} = $start;
	}
	
	# when scanning we brokenly align by bytes.  
	$info->{'BLOCKALIGN'} = 1;
	
	# bitrate is in bits per second, not kbits per second.
	$info->{'BITRATE'} = $info->{'BITRATE'} * 1000 if ($info->{'BITRATE'});

	return $info;
}


my $DEBUG = 0;
my $MINFRAMELEN = 96;    # 144 * 32000 kbps / 48000 kHz + 0 padding
my $MAXDISTANCE = 8192;  # (144 * 320000 kbps / 32000 kHz + 1 padding + fudge factor) for garbage data * 2 frames

# seekNextFrame:
# starts seeking from $startoffset (bytes relative to beginning of file) until 
# it finds the next valid frame header. Returns the offset of the first and last
# bytes of the frame if any is found, otherwise (0,0).
#
# when scanning forward ($direction=1), simply detects the next frame header.
#
# when scanning backwards ($direction=-1), returns the next frame header whose
# frame length is within the distance scanned (so that when scanning backwards 
# from EOF, it skips any truncated frame at the end of file.
#
sub seekNextFrame {
	my ($fh, $startoffset, $direction) =@_;
	defined($fh) || die;
	defined($startoffset) || die;
	defined($direction) || die;

	my $foundsync=0;
	my ($seekto, $buf, $len, $h, $pos, $start, $end,$calculatedlength, $numgarbagebytes);
	my ($found_at_offset);

	$seekto = ($direction == 1) ? $startoffset : $startoffset-$MAXDISTANCE;
	$DEBUG && print("reading $MAXDISTANCE bytes at: $seekto (to scan direction: $direction) \n");
	sysseek($fh, $seekto, SEEK_SET);
	sysread $fh, $buf, $MAXDISTANCE, 0;

	$len = length($buf);
	if ($len<4) {
		$DEBUG && print "got less than 4 bytes\n";
		return (0,0) 
	}

	if ($direction==1) {
		$start = 0;
		$end = $len-4;
	} else {
		#assert($direction==-1);
		$start = $len-$MINFRAMELEN;
		$end=-1;
	}

	$DEBUG && printf("scanning: len = $len, start = $start, end = $end\n");

	for ($pos = $start; $pos!=$end; $pos+=$direction) {
		#$DEBUG && printf "looking at $pos\n";
		
		my $h = MP3::Info::_get_head(substr($buf, $pos, 4));
		
		next if !MP3::Info::_is_mp3($h);
		
		$found_at_offset = $startoffset + (($direction==1) ? $pos : ($pos-$len));		
		
		$calculatedlength = int(144 * $h->{bitrate} * 1000 / $h->{fs}) + $h->{padding_bit};

		# double check by making sure the next frame has a good header
		next if (($pos + $calculatedlength + 4) > length($buf));
		my $j= MP3::Info::_get_head(substr($buf, $pos + $calculatedlength, 4));
		
		next if !MP3::Info::_is_mp3($j);
		
		if ($DEBUG) {
			printf "sync at offset %d\n", $found_at_offset;
			
			foreach my $k (sort keys %$h) {
				print  $k . ":\t" . $h->{$k} . "\n";
			}
			print "\nCalculated length including header: $calculatedlength\n";
		}
		
		# when scanning backwards, skip any truncated frame at the end of the buffer
		if ($direction == -1) {
			$numgarbagebytes = $len-$pos+1 - $calculatedlength;
			$DEBUG && printf "%d byte(s) of crap at the end.\n", $numgarbagebytes;

			if ($numgarbagebytes<0) {
				$DEBUG && print "calculated length > bytes remaining. Either this wasn't a real frame header, or the frame was truncated. Searching further...\n\n";
				$foundsync=0;
				next;
			}
		}
		
		my $frame_end =  $found_at_offset + $calculatedlength - 1;
		$DEBUG && printf "Frame found at offset: $found_at_offset (started looking at $startoffset) frame end: $frame_end\n\n";

		return($found_at_offset, $frame_end);
	}

	if (!$foundsync) {
		!$DEBUG && printf("Couldn't find any frame header\n");
		return(0,0);
	}
}


1;
