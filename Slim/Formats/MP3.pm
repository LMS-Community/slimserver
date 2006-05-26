package Slim::Formats::MP3;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use IO::Seekable qw(SEEK_SET);
use MP3::Info;

use Slim::Utils::Misc;

my %tagMapping = (
	'Unique file identifier'	=> 'MUSICBRAINZ_ID',
	'MUSICBRAINZ ALBUM ARTIST ID'	=> 'MUSICBRAINZ_ALBUMARTIST_ID',
	'MUSICBRAINZ ALBUM ID'		=> 'MUSICBRAINZ_ALBUM_ID',
	'MUSICBRAINZ ALBUM STATUS'	=> 'MUSICBRAINZ_ALBUM_STATUS',
	'MUSICBRAINZ ALBUM TYPE'	=> 'MUSICBRAINZ_ALBUM_TYPE',
	'MUSICBRAINZ ARTIST ID'		=> 'MUSICBRAINZ_ARTIST_ID',
	'MUSICBRAINZ TRM ID'		=> 'MUSICBRAINZ_TRM_ID',

	# J.River Media Center uses messed up tags. See Bug 2250
	'MEDIA JUKEBOX: REPLAY GAIN'    => 'REPLAYGAIN_TRACK_GAIN',
	'MEDIA JUKEBOX: ALBUM GAIN'     => 'REPLAYGAIN_ALBUM_GAIN',
	'MEDIA JUKEBOX: PEAK LEVEL'     => 'REPLAYGAIN_TRACK_PEAK',
	'MEDIA JUKEBOX: ALBUM ARTIST'   => 'ALBUMARTIST',
);

# Allow us to reuse tag data when fetching artwork if we can.
my $tagCache = [];

{
	# Don't try and convert anything to latin1
	if ($] > 5.007) {

		MP3::Info::use_mp3_utf8(1);
	}

	#
	MP3::Info::use_winamp_genres();

	# also get the album, performer and title sort information
	$MP3::Info::v2_to_v1_names{'TSOA'} = 'ALBUMSORT';
	$MP3::Info::v2_to_v1_names{'TSOP'} = 'ARTISTSORT';
	$MP3::Info::v2_to_v1_names{'XSOP'} = 'ARTISTSORT';
	$MP3::Info::v2_to_v1_names{'TSOT'} = 'TITLESORT';

	# get composers
	$MP3::Info::v2_to_v1_names{'TCM'}  = 'COMPOSER';
	$MP3::Info::v2_to_v1_names{'TCOM'} = 'COMPOSER';

	# get band/orchestra
	$MP3::Info::v2_to_v1_names{'TP2'}  = 'BAND';
	$MP3::Info::v2_to_v1_names{'TPE2'} = 'BAND';	

	# get artwork
	$MP3::Info::v2_to_v1_names{'PIC'}  = 'PIC';
	$MP3::Info::v2_to_v1_names{'APIC'} = 'PIC';	

	# Set info
	$MP3::Info::v2_to_v1_names{'TPA'}  = 'SET';
	$MP3::Info::v2_to_v1_names{'TPOS'} = 'SET';	

	# get conductors
	$MP3::Info::v2_to_v1_names{'TP3'}  = 'CONDUCTOR';
	$MP3::Info::v2_to_v1_names{'TPE3'} = 'CONDUCTOR';
	
	$MP3::Info::v2_to_v1_names{'TBP'}  = 'BPM';
	$MP3::Info::v2_to_v1_names{'TBPM'} = 'BPM';

	$MP3::Info::v2_to_v1_names{'ULT'}  = 'LYRICS';
	$MP3::Info::v2_to_v1_names{'USLT'} = 'LYRICS';

	# Pull the Relative Volume Adjustment tags
	$MP3::Info::v2_to_v1_names{'RVA'}  = 'RVAD';
	$MP3::Info::v2_to_v1_names{'RVAD'} = 'RVAD';
	$MP3::Info::v2_to_v1_names{'RVA2'} = 'RVA2';

	# TDRC is a valid field for a year.
	$MP3::Info::v2_to_v1_names{'TDRC'} = 'YEAR';

	# iTunes writes out it's own tag denoting a compilation
	$MP3::Info::v2_to_v1_names{'TCMP'} = 'COMPILATION';
}

sub getTag {
	my $class = shift;
	my $file  = shift || return {};

	open(my $fh, $file) or return {};

	# Try to pull ID3v2 tags first. If those don't exist, proceed to v1
	# Also try and get an APE tag, which may have ReplayGain data.
	my $tags = MP3::Info::get_mp3tag($fh, 2, undef, 1); 

	if (!scalar keys %$tags) {

		$tags = MP3::Info::get_mp3tag($fh, 1); 
	}

	# Now fetch the audio header information.
	my $info = MP3::Info::get_mp3info($fh);

	# Some MP3 files don't have their header information readily
	# accessable. So try seeking in a bit further.
	if (!scalar keys %$info) {

		$MP3::Info::try_harder = 6;

		$info = MP3::Info::get_mp3info($fh);

		$MP3::Info::try_harder = 0;
	}

	doTagMapping($tags);

	# we'll always have $info, as it's machine generated.
	if ($tags && $info) {
		%$info = (%$info, %$tags);
	}

	# sometimes we don't get this back correctly
	$info->{'OFFSET'} += 0;

	return undef if (!$info->{'SIZE'});

	my ($start, $end);

	($start, undef) = seekNextFrame($fh, $info->{'OFFSET'}, 1);
	(undef, $end)   = seekNextFrame($fh, $info->{'OFFSET'} + $info->{'SIZE'}, -1);

	if ($start) {
		$info->{'OFFSET'} = $start;
		if ($end) {
			$info->{'SIZE'} = $end - $start + 1;
		}
	}

	close($fh);
	
	# when scanning we brokenly align by bytes.  
	$info->{'BLOCKALIGN'} = 1;
	
	# bitrate is in bits per second, not kbits per second.
	$info->{'BITRATE'} = $info->{'BITRATE'} * 1000 if ($info->{'BITRATE'});

	# same with sample rate
	$info->{'RATE'} = $info->{'FREQUENCY'} * 1000 if ($info->{'FREQUENCY'});

	# Pull out Relative Volume Adjustment information
	if ($info->{'RVAD'} && $info->{'RVAD'}->{'RIGHT'}) {

		for my $type (qw(REPLAYGAIN_TRACK_GAIN REPLAYGAIN_TRACK_PEAK)) {

			$info->{$type} = $info->{'RVAD'}->{'RIGHT'}->{$type};
		}

		delete $info->{'RVAD'};

	} elsif ($info->{'RVA2'}) {

		if ($info->{'RVA2'}->{'MASTER'}) {

			while (my ($type, $gain) = each %{$info->{'RVA2'}->{'MASTER'}}) {

				$info->{$type} = $gain;
			}

		} elsif ($info->{'RVA2'}->{'FRONT_RIGHT'} && $info->{'RVA2'}->{'FRONT_LEFT'}) {

			while (my ($type, $gain) = each %{$info->{'RVA2'}->{'FRONT_RIGHT'}}) {

				$info->{$type} = $gain;
			}		
		}

		delete $info->{'RVA2'};
	}

	# Allow getCoverArt to reuse what we just fetched.
	$tagCache = [ $file, $info ];

	return $info;
}

sub getCoverArt {
	my $file = shift || return undef;

	# Try to save a re-read
	if ($tagCache->[0] && $tagCache->[0] eq $file && ref($tagCache->[1]) eq 'HASH') {

		my $pic = $tagCache->[1]->{'PIC'}->{'DATA'};

		# Don't leave anything around.
		$tagCache = [];

		return $pic;
	}

	my $tags = MP3::Info::get_mp3tag($file, 2) || {};

	if (defined $tags->{'PIC'} && defined $tags->{'PIC'}->{'DATA'}) {

		$tagCache = [ $file, $tags ];

		return $tags->{'PIC'}->{'DATA'};
	}

	return undef;
}

sub doTagMapping {
	my $tags = shift;

	# map the existing tag names to the expected tag names
	while (my ($old,$new) = each %tagMapping) {
		if (exists $tags->{$old}) {
			$tags->{$new} = delete $tags->{$old};
		}
	}
}

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
	use bytes;
	my ($fh, $startoffset, $direction) =@_;
	defined($fh) || die;
	defined($startoffset) || die;
	defined($direction) || die;

	my $foundsync=0;
	my ($seekto, $buf, $len, $h, $pos, $start, $end,$calculatedlength, $numgarbagebytes, $head);
	my ($found_at_offset);

	my $filelen = -s $fh;
	$startoffset = $filelen if ($startoffset > $filelen); 

	$seekto = ($direction == 1) ? $startoffset : $startoffset-$MAXDISTANCE;
	$::d_mp3 && msg("reading $MAXDISTANCE bytes at: $seekto (to scan direction: $direction) \n");
	sysseek($fh, $seekto, SEEK_SET);
	sysread $fh, $buf, $MAXDISTANCE, 0;

	$len = length($buf);
	if ($len<4) {
		$::d_mp3 && msg("got less than 4 bytes\n");
		return (0,0) 
	}

	if ($direction==1) {
		$start = 0;
		$end = $len-4;
	} else {
		#assert($direction==-1);
		$start = $len-$MINFRAMELEN;
		$end=0;
	}

	$::d_mp3 && msg("scanning: len = $len, start = $start, end = $end\n");
	for ($pos = $start; $pos!=$end; $pos+=$direction) {
		#$::d_mp3 && msg("looking at $pos\n");

		$head = substr($buf, $pos, 4);
		next if (ord($head) != 0xff);

		$h = MP3::Info::_get_head($head);
		
		next if !MP3::Info::_is_mp3($h);
		
		$found_at_offset = $seekto + $pos;
		
		$calculatedlength = int(144 * $h->{bitrate} * 1000 / $h->{fs}) + $h->{padding_bit};

		# skip if we haven't scanned back by the calculated length
		next if (($pos + $calculatedlength + 4) > $len);

		# if we're scanning forward, double check by making sure the next frame has a good header
		if ($direction == 1) {
			my $j= MP3::Info::_get_head(substr($buf, $pos + $calculatedlength, 4));
			next if !MP3::Info::_is_mp3($j);
		} else {
			# continue to scan backwards one frame and make sure that it's valid...
			# TODO - we may get false positives at the end of some files.	
		}
		
#		if ($::d_mp3) {
#			msg(printf "sync at offset %d (%x %x %x %x)\n", $found_at_offset, (unpack 'CCCC', $head));
#			
#			foreach my $k (sort keys %$h) {
#				msg(  $k . ":\t" . $h->{$k} . "\n");
#			}
#			msg( "Calculated length including header: $calculatedlength\n");
#		}
				
		my $frame_end =  $found_at_offset + $calculatedlength - 1;
#		$::d_mp3 && msg("Frame found at offset: $found_at_offset (started looking at $startoffset) frame end: $frame_end\n");

		return($found_at_offset, $frame_end);
	}

	if (!$foundsync) {
		$::d_mp3 && msg("Couldn't find any frame header\n");
		return(0,0);
	}
}

1;
