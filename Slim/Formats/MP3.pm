package Slim::Formats::MP3;

# $Id$

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Formats::MP3

=head1 SYNOPSIS

my $tags = Slim::Formats::MP3->getTag( $filename );

=head1 DESCRIPTION

Read tags & metadata embedded in MP3 files.

=head1 METHODS

=cut

use strict;
use base qw(Slim::Formats);

use Fcntl qw(:seek);
use IO::String;
use MP3::Info;
use MPEG::Audio::Frame;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::SoundCheck;
use Slim::Utils::Strings qw(string);

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

# Constant Bitrates
our %cbr = map { $_ => 1 } qw(32 40 48 56 64 80 96 112 128 160 192 224 256 320);

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

=head2 getTag( $filename )

Extract and return audio information & any embedded metadata found.

=cut

sub getTag {
	my $class = shift;
	my $file  = shift;

	my $log   = logger('formats.audio');

	if (!$file) {

		logWarning("No file was passed!");
		return {};
	}

	open(my $fh, $file) or do {

		logWarning("Couldn't open file: [$file] $!");
		return {};
	};

	# Bug: 4071 - Windows is lame.
	binmode($fh);

	# This is somewhat messy - Use a customized version of MP3::Info's
	# get_mp3tag, as we need custom logic.
	my (%tags, %ape) = ();

	$log->debug("Trying to read ID3v2 tags from $file");

	# Always take a v2 tag if we have it.
	MP3::Info::_get_v2tag($fh, 2, 0, \%tags);

	# If the only tag is TAGVERSION, that means we didn't parse the ID3v2
	# tag properly, or it's bogus. Look for a ID3v1 tag.
	if ((!scalar keys %tags) || (scalar keys %tags == 1 && defined $tags{'TAGVERSION'})) {

		$log->debug("Didn't find any ID3v2 tags, trying v1 tags.");

		# Only use v1 tags if there are no v2 tags.
		MP3::Info::_get_v1tag($fh, \%tags);
	}

	# Always add on any APE tags at the end. It may have ReplayGain data.
	if (MP3::Info::_parse_ape_tag($fh, -s $file, \%ape)) {

		if (scalar keys %ape) {

			$log->debug("Found APE tags as well.");

			%tags = (%tags, %ape);
		}
	}

	# Now fetch the audio header information.
	my $info = MP3::Info::get_mp3info($fh);

	# Some MP3 files don't have their header information readily
	# accessable. So try seeking in a bit further.
	if (!scalar keys %$info) {

		$log->debug("Didn't find audio information in first pass - trying harder.");

		$MP3::Info::try_harder = 6;

		$info = MP3::Info::get_mp3info($fh);

		$MP3::Info::try_harder = 0;
	}

	doTagMapping(\%tags);

	# we'll always have $info, as it's machine generated.
	if (scalar keys %tags && scalar keys %{$info}) {
		%$info = (%tags, %$info);
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

	if ( defined $start ) {
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

	return $info;
}

=head2 getCoverArt( $filename )

Extract and return cover image from the file.

=cut

sub getCoverArt {
	my $class = shift;
	my $file  = shift || return undef;

	my $tags = MP3::Info::get_mp3tag($file, 2) || {};

	if (defined $tags->{'PIC'} && defined $tags->{'PIC'}->{'DATA'}) {

		return $tags->{'PIC'}->{'DATA'};
	}

	return undef;
}

=head2 doTagMapping( $tags )

Map bad tag names to correct ones.

=cut

sub doTagMapping {
	my $tags = shift;

	# map the existing tag names to the expected tag names
	while (my ($old,$new) = each %tagMapping) {
		if (exists $tags->{$old}) {
			$tags->{$new} = delete $tags->{$old};
		}
	}
}

=head2 findFrameBoundaries( $fh, $offset, $seek )

Locate MP3 frame boundaries when seeking through a file.

=cut

sub findFrameBoundaries {
	my ($class, $fh, $offset, $seek) = @_;
	
	binmode $fh;

	my ($start, $end) = (0, 0);

	if (!defined $fh || !defined $offset) {

		logError("Invalid arguments!");

		return wantarray ? ($start, $end) : $start;
	}

	my $filelen   = -s $fh;
	if ($offset > $filelen) {
		$offset = $filelen;
	}

	# dup the filehandle, as MPEG::Audio::Frame uses read(), and not sysread()
	open(my $mpeg, '<&=', $fh) or do {

		logError("Couldn't dup filehandle!");

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

	logger('player.source')->debug("start: [$start] end: [$end]");

	if (defined $seek) {
		return ($start, $end);
	} else {
		return wantarray ? ($start, $end) : $start;
	}
}

=head2 getFrame( $fh )

Returns the first MPEG::Audio::Frame object found in the given filehandle.

=cut

sub getFrame {
	my ( $class, $fh ) = @_;

	binmode $fh;
	
	my $offset = tell $fh;
		
	# dup the filehandle, as MPEG::Audio::Frame uses read(), and not sysread()
	open(my $mpeg, '<&=', $fh) or do {

		logError("Couldn't dup filehandle!");
		return;
	};
	
	my $frame = MPEG::Audio::Frame->read($mpeg);
	
	# Seek back to where we started
	seek $fh, $offset, 0;
	
	close $mpeg;
	
	return $frame;
}

=head2 scanBitrate( $fh )

Scans a file and returns just the bitrate and VBR setting.  This is used
to determine the bitrate for remote streams.  We first look for a Xing VBR
header which gives us accurate VBR bitrates.  If this isn't found, we parse
each frame and calculate an average bitrate for all frames found.

We also look for any ID3 tags and set the title based on any that are found.

=cut

sub scanBitrate {
	my $class = shift;
	my $fh    = shift;
	my $url   = shift;
	
	# We can also read ID3 tags from this header to use for title information
	my %tags  = ();
	my $log   = logger('scan.scanner');

	if ( !MP3::Info::_get_v2tag( $fh, 2, 0, \%tags ) ) {

		# Only use v1 tags if there are no v2 tags.
		MP3::Info::_get_v1tag( $fh, \%tags );
	}
	
	if ( $tags{TITLE} ) {
		
		# Strip out any nulls.
		for my $key ( keys %tags ) {

			if ( defined $tags{$key} ) {
				$tags{$key} =~ s/\000+.*//g;
				$tags{$key} =~ s/\s+$//;
			}
		}
		
		# XXX: Schema ignores ARTIST, ALBUM, YEAR, and GENRE for remote URLs
		# so we have to format our title info manually.
		Slim::Schema->rs('Track')->updateOrCreate({
			url        => $url,
			attributes => {
				TITLE   => $tags{TITLE},
				ARTIST  => $tags{ARTIST},
				ALBUM   => $tags{ALBUM},
				YEAR    => $tags{YEAR},
				GENRE   => $tags{GENRE},
				COMMENT => $tags{COMMENT},
			},
		});
		
		if ( $log->is_debug ) {
			$log->debug("Read ID3 tags from stream: " . Data::Dump::dump(\%tags));
		}
		
		my $title = $tags{TITLE};
		$title .= ' ' . string('BY') . ' ' . $tags{ARTIST} if $tags{ARTIST};
		$title .= ' ' . string('FROM') . ' ' . $tags{ALBUM}  if $tags{ALBUM};
		
		Slim::Music::Info::setCurrentTitle( $url, $title );
	}

	# Check if first frame has a Xing VBR header
	# This will allow full files streamed from places like LMA or UPnP servers
	# to have accurate bitrate/length information
	my $frame = MPEG::Audio::Frame->read( $fh );
	if ( $frame && $frame->content =~ /(Xing.*)/ ) {
		my $xing = IO::String->new( $1 );
		my $vbr  = {};
		my $off  = 4;
		
		# Xing parsing code from MP3::Info
		my $unpack_head = sub { unpack('l', pack('L', unpack('N', $_[0]))) };

		seek $xing, $off, 0;
		read $xing, my $flags, 4;
		$off += 4;
		$vbr->{flags} = $unpack_head->($flags);
		
		if ( $vbr->{flags} & 1 ) {
			seek $xing, $off, 0;
			read $xing, my $bytes, 4;
			$off += 4;
			$vbr->{frames} = $unpack_head->($bytes);
		}

		if ( $vbr->{flags} & 2 ) {
			seek $xing, $off, 0;
			read $xing, my $bytes, 4;
			$off += 4;
			$vbr->{bytes} = $unpack_head->($bytes);
		}
		
		my $mfs = $frame->sample / ( $frame->version ? 144000 : 72000 );
		my $bitrate = sprintf "%.0f", $vbr->{bytes} / $vbr->{frames} * $mfs;
		
		$log->debug("Found Xing VBR header in stream, bitrate: $bitrate kbps VBR");
		
		return ($bitrate * 1000, 1);
	}
	
	# No Xing header, take an average of frame bitrates

	my @bitrates;
	my ($avg, $sum) = (0, 0);
	
	seek $fh, 0, 0;
	while ( my $frame = MPEG::Audio::Frame->read( $fh ) ) {
		
		# Sample all frames to try to see if we're VBR or not
		if ( $frame->bitrate ) {
			push @bitrates, $frame->bitrate;
			$sum += $frame->bitrate;
			$avg = int( $sum / @bitrates );
		}
	}

	if ( $avg ) {			
		my $vbr = undef;

		if ( !$cbr{$avg} ) {
			$vbr = 1;
		}
		
		$log->debug("Read average bitrate from stream: $avg " . ( $vbr ? 'VBR' : 'CBR' ));
		
		return ($avg * 1000, $vbr);
	}
	
	$log->warn("Unable to find any MP3 frames in stream!");

	return (-1, undef);
}	

1;
