package Slim::Formats::MP3;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use Fcntl qw(:seek);
use MP3::Info;
use MPEG::Audio::Frame;

use Slim::Utils::SoundCheck;

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
	$MP3::Info::v2_to_v1_names{'TCP'}  = 'COMPILATION';
	$MP3::Info::v2_to_v1_names{'TCMP'} = 'COMPILATION';
}

sub getTag {
	my $class = shift;
	my $file  = shift || return {};

	open(my $fh, $file) or return {};

	# This is somewhat messy - Use a customized version of MP3::Info's
	# get_mp3tag, as we need custom logic.
	my (%tags, %ape) = ();

	# Always take a v2 tag if we have it.
	if (!MP3::Info::_get_v2tag($fh, 2, 0, \%tags)) {

		# Only use v1 tags if there are no v2 tags.
		MP3::Info::_get_v1tag($fh, \%tags);
	}

	# Always add on any APE tags at the end. It may have ReplayGain data.
	if (MP3::Info::_parse_ape_tag($fh, -s $file, \%ape)) {

		%tags = (%tags, %ape);
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

	doTagMapping(\%tags);

	# we'll always have $info, as it's machine generated.
	if (scalar keys %tags && scalar keys %{$info}) {
		%$info = (%$info, %tags);
	}

	# Strip out any nulls.
	for my $key (keys %{$info}) {

		if (defined $info->{$key}) {
			$info->{$key} =~ s/\000+.*//g;
			$info->{$key} =~ s/\s+$//;
		}
	}

	# sometimes we don't get this back correctly
	$info->{'OFFSET'} += 0;

	if (!$info->{'SIZE'}) {
		return undef;
	}

	my ($start, $end) = $class->findFrameBoundaries($fh, $info->{'OFFSET'}, $info->{'SIZE'});

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

	# Look for iTunes SoundCheck data
	if ($info->{'COMMENT'}) {

		Slim::Utils::SoundCheck::commentTagTodB($info);
	}

	# Allow getCoverArt to reuse what we just fetched.
	$tagCache = [ $file, $info ];

	return $info;
}

sub getCoverArt {
	my $class = shift;
	my $file  = shift || return undef;

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

sub findFrameBoundaries {
	my ($class, $fh, $offset, $seek) = @_;

	my ($start, $end) = (0, 0);

	if (!defined $fh || !defined $offset) {
		errorMsg("findFrameBoundaries: Invalid arguments!\n");
		return wantarray ? ($start, $end) : $start;
	}

	my $filelen   = -s $fh;
	if ($offset > $filelen) {
		$offset = $filelen;
	}

	# dup the filehandle, as MPEG::Audio::Frame uses read(), and not sysread()
	open(my $mpeg, '<&=', $fh) or do {
		errorMsg("findFrameBoundaries: Couldn't dup filehandle!\n");
		return wantarray ? ($start, $end) : $start;
	};

	seek($mpeg, $offset, SEEK_SET);

	# Find the first frame.
	my $frame1 = MPEG::Audio::Frame->read($mpeg);

	if (defined $frame1) {
		$start = $frame1->offset;
	}

	# If the caller (Source.pm) has requested a seek position, that means we want to look backwards.
	if (defined $seek && defined $frame1) {

		seek($mpeg, ($start - ($frame1->length * 1.5) + $seek), SEEK_SET);

		while (my $frame2 = MPEG::Audio::Frame->read($mpeg)) {

			if (($frame2->offset + ($frame2->length * 2)) > $start + $seek) {

				$end = $frame2->offset + $frame2->length - 1;
				last;
			}
		}
	}

	close($mpeg);

	$::d_source && Slim::Utils::Misc::msgf("findFrameBoundaries: start: [%d] end: [%d]\n", $start, $end);

	if (defined $seek) {
		return ($start, $end);
	} else {
		return wantarray ? ($start, $end) : $start;
	}
}

1;
