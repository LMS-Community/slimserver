package Slim::Formats::Movie;

# $Id: Movie.pm,v 1.17 2004/08/03 17:29:14 vidur Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

###############################################################################
# FILE: Slim::Formats::Movie.pm
#
# DESCRIPTION:
#   Extract Movie user data information and store in a hash for easy retrieval.
#
###############################################################################

use strict;
use QuickTime::Movie;

my @genre = (
   "N/A", "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk",
   "Grunge", "Hip-Hop", "Jazz", "Metal", "New Age", "Oldies",
   "Other", "Pop", "R&B", "Rap", "Reggae", "Rock",
   "Techno", "Industrial", "Alternative", "Ska", "Death Metal", "Pranks",
   "Soundtrack", "Euro-Techno", "Ambient", "Trip-Hop", "Vocal", "Jazz+Funk",
   "Fusion", "Trance", "Classical", "Instrumental", "Acid", "House",
   "Game", "Sound Clip", "Gospel", "Noise", "AlternRock", "Bass",
   "Soul", "Punk", "Space", "Meditative", "Instrumental Pop", "Instrumental Rock",
   "Ethnic", "Gothic", "Darkwave", "Techno-Industrial", "Electronic", "Pop-Folk",
   "Eurodance", "Dream", "Southern Rock", "Comedy", "Cult", "Gangsta",
   "Top 40", "Christian Rap", "Pop/Funk", "Jungle", "Native American", "Cabaret",
   "New Wave", "Psychadelic", "Rave", "Showtunes", "Trailer", "Lo-Fi",
   "Tribal", "Acid Punk", "Acid Jazz", "Polka", "Retro", "Musical",
   "Rock & Roll", "Hard Rock", "Folk", "Folk/Rock", "National Folk", "Swing",
   "Fast-Fusion", "Bebob", "Latin", "Revival", "Celtic", "Bluegrass", "Avantgarde",
   "Gothic Rock", "Progressive Rock", "Psychedelic Rock", "Symphonic Rock", "Slow Rock", "Big Band",
   "Chorus", "Easy Listening", "Acoustic", "Humour", "Speech", "Chanson",
   "Opera", "Chamber Music", "Sonata", "Symphony", "Booty Bass", "Primus",
   "Porn Groove", "Satire", "Slow Jam", "Club", "Tango", "Samba",
   "Folklore", "Ballad", "Power Ballad", "Rhythmic Soul", "Freestyle", "Duet",
   "Punk Rock", "Drum Solo", "A capella", "Euro-House", "Dance Hall",
   "Goa", "Drum & Bass", "Club House", "Hardcore", "Terror",
   "Indie", "BritPop", "NegerPunk", "Polsk Punk", "Beat",
   "Christian Gangsta", "Heavy Metal", "Black Metal", "Crossover", "Contemporary C",
   "Christian Rock", "Merengue", "Salsa", "Thrash Metal", "Anime", "JPop",
   "SynthPop"
);

my %tagMapping = (
	'©nam'	=> 'TITLE',
	'©ART'	=> 'ARTIST',
	'©alb'	=> 'ALBUM',
	'©wrt'	=> 'COMPOSER',
	'©day'	=> 'YEAR',
);

my %binaryTags = (
	'trkn'	=> 'TRACKNUM',
	'disk'	=> 'DISC',
	'gnre'	=> 'GENRE',
	'cpil'	=> 'COMPILATION',
	'covr'	=> 'PIC'
);

# Given a file, return a hash of name value pairs,
# where each name is a tag name.
sub getTag {

	my $file = shift || "";

	my $tags = QuickTime::Movie::readUserData($file);

	# lazy? no. efficient. =)
	if (ref $tags eq "HASH") {
	   while (my ($old,$new) = each %tagMapping) {
	      if (exists $tags->{$old}) {

			 $tags->{$new} = Slim::Utils::Misc::utf8toLatin1($tags->{$old});

			 delete $tags->{$old};
	      }
	   }
	   while (my ($old,$new) = each %binaryTags) {
	      if (exists $tags->{$old}) {
			 $tags->{$new} = $tags->{$old};
			 delete $tags->{$old};
	      }
	   }
	} else {
	   $tags = {};
	}

	$tags->{'SIZE'} = -s $file;
	if ($tags->{'TIMESCALE'} && $tags->{'DURATION'}) {
		$tags->{'SECS'} = $tags->{'DURATION'} / $tags->{'TIMESCALE'};
		$tags->{'BITRATE'} = $tags->{'SIZE'} * 8 / $tags->{'SECS'};
	}
	$tags->{'OFFSET'} = 0;
	
	# clean up binary tags
	$tags->{'COVER'} = 1 if ($tags->{'COVER'});
	$tags->{'TRACKNUM'} = unpack('N', $tags->{'TRACKNUM'}) if $tags->{'TRACKNUM'};
	$tags->{'GENRE'} = $genre[unpack('n', $tags->{'GENRE'})] if $tags->{'GENRE'};
	($tags->{'DISC'}, $tags->{'DISCC'}) = unpack('Nn', $tags->{'DISC'}) if $tags->{'DISC'};	
	$tags->{'COMPILATION'} = unpack('N', $tags->{'COMPILATION'}) if $tags->{'COMPILATION'};	

	return $tags;
}

sub getCoverArt {
	my $file = shift;
	my $tags = QuickTime::Movie::readUserData($file);

	my $coverart;
	
	$coverart = $tags->{'covr'};
	
	return $coverart;
}



1;
