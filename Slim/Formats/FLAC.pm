package Slim::Formats::FLAC;

# $tagsd: FLAC.pm,v 1.5 2003/12/15 17:57:50 daniel Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

###############################################################################
# FILE: Slim::Formats::FLAC.pm
#
# DESCRIPTION:
#   Extract FLAC tag information and store in a hash for easy retrieval.
#
###############################################################################

use strict;
use File::Basename;
use Audio::FLAC;
use MP3::Info ();
use Slim::Utils::Misc;
use Slim::Formats::Parse;

my %tagMapping = (
	'TRACKNUMBER'	=> 'TRACKNUM',
	'DATE'		=> 'YEAR',
	'DISCNUMBER'	=> 'SET',
	'URL'		=> 'URLTAG',
);

my @tagNames = qw(ALBUM ARTIST BAND COMPOSER CONDUCTOR DISCNUMBER TITLE TRACKNUMBER DATE);

# peem id (http://flac.sf.net/id.html http://peem.iconoclast.net/)
my $PEEM = 1835361648;

# Turn perl's internal string representation into UTF-8
if ($] > 5.007) {
	require Encode;
}

# Choose between returning a standard tag
# or parsing through an embedded cuesheet
sub getTag {
	my $file   = shift || "";
	my $anchor = shift || "";

	my $flac   = Audio::FLAC->new($file) || do {
		warn "Couldn't open file: [$file] for reading: $!\n";
		return {};
	};

	my $cuesheet = $flac->cuesheet();

	# if there's no embedded cuesheet, then we're either a single song
	# or we have pseudo CDTEXT in the external cuesheet.
	#
	# if we do have an embedded cuesheet, but no anchor then we need to parse
	# the cuesheet.
	#
	# if we have an anchor then we're already parsing it, and we look for 
	# metadata that matches our piece of the file.

	unless (@$cuesheet > 0) {

		# no embedded cuesheet.
		# this is either a single song, or has an external cuesheet
		return getStandardTag($file, $flac);
	}

	if ($anchor) {
		# we have an anchor, so lets find metadata for this piece
		return getSubFileTag($file, $anchor, $flac);
	}

	# no anchor, handle the base file
	# cue parsing will return file url references with start/end anchors
	# we can now pretend that this (bare no-anchor) file is a playlist

	my $tags = {};
	my $taginfo = getStandardTag($file, $flac);

	push(@$cuesheet, "    REM END " . sprintf("%02d:%02d:%02d",
		int(int($taginfo->{'SECS'})/60),
		int($taginfo->{'SECS'} % 60),
		(($taginfo->{'SECS'} - int($taginfo->{'SECS'})) * 75)
	));

	$tags->{'LIST'} = Slim::Formats::Parse::parseCUE($cuesheet, dirname($file));

	# set fields appropriate for a playlist
	$tags->{'CT'}    = "fec";

	return $tags;
}

# Given a file, return a hash of name value pairs,
# where each name is a tag name.
sub getStandardTag {
	my $file = shift;
	my $flac = shift;

	my $tags = $flac->tags() || {};

	# Check for the presence of the info block here
	return undef unless defined $flac->{'bitRate'};

	# There should be a TITLE tag if the VORBIS tags are to be trusted
	if (defined $tags->{'TITLE'}) {

		foreach my $tag (@tagNames) {

			next unless exists $tags->{$tag};

			if ($] > 5.007) {
				$tags->{$tag} = eval { Encode::decode("utf8", $tags->{$tag}) };
			} else {
				$tags->{$tag} = Slim::Utils::Misc::utf8toLatin1($tags->{$tag});
			}
		}

	} else {

		if (exists $flac->{'ID3V2Tag'}) {
			# Get the ID3V2 tag on there, sucka
			$tags = MP3::Info::get_mp3tag($file,2);
		}
	}

	doTagMapping($tags);
	addInfoTags($flac, $tags);

	return $tags;
}

sub doTagMapping {
	my $tags = shift;

	# map the existing tag names to the expected tag names
	while (my ($old,$new) = each %tagMapping) {

		if (exists $tags->{$old}) {
			$tags->{$new} = $tags->{$old};
			delete $tags->{$old};
		}
	}
}

sub addInfoTags {
	my $flac = shift;
	my $tags = shift;

	# add more information to these tags
	# these are not tags, but calculated values from the streaminfo
	$tags->{'SIZE'}    = $flac->{'fileSize'};
	$tags->{'SECS'}    = $flac->{'trackTotalLengthSeconds'};
	$tags->{'OFFSET'}  = $flac->{'startAudioData'};
	$tags->{'BITRATE'} = $flac->{'bitRate'};

	# Add the stuff that's stored in the Streaminfo Block
	my $flacInfo = $flac->info();
	$tags->{'RATE'}     = $flacInfo->{'SAMPLERATE'};
	$tags->{'CHANNELS'} = $flacInfo->{'NUMCHANNELS'};

	# stolen from MP3::Info
	$tags->{'MM'}	    = int $tags->{'SECS'} / 60;
	$tags->{'SS'}	    = int $tags->{'SECS'} % 60;
	$tags->{'MS'}	    = (($tags->{'SECS'} - ($tags->{'MM'} * 60) - $tags->{'SS'}) * 1000);
	$tags->{'TIME'}	    = sprintf "%.2d:%.2d", @{$tags}{'MM', 'SS'};

}

sub getSubFileTag {
	my $file   = shift;
	my $anchor = shift;
	my $flac   = shift;
	my $tags   = {};

	# There is no official standard for multi-song metadata in a flac file
	# so we try a few different approaches ordered from most useful to least
	#
	# as new methods are found in the wild, they can be added here. when
	# a de-facto standard emerges, unused ones can be dropped.
	#
	# TODO: streamline slimserver's flow so this parsing only happens once
	# instead of repeating for each track.

	# parse embedded xml metadata
	$tags = getXMLTag($file, $anchor, $flac);
	return $tags if defined $tags && keys %$tags > 0;

	# look for numbered vorbis comments
	$tags = getNumberedVC($file, $anchor, $flac);
	return $tags if defined $tags && keys %$tags > 0;

	# parse cddb style metadata
	$tags = getCDDBTag($file, $anchor, $flac);
	return $tags if defined $tags && keys %$tags > 0;	

	# parse cuesheet stuffed into a vorbis comment
	$tags = getCUEinVC($file, $anchor, $flac);
	return $tags if defined $tags && keys %$tags > 0;	

	# try parsing stacked vorbis comments
	$tags = getStackedVC($file, $anchor, $flac);
	return $tags if defined $tags && keys %$tags > 0;

	# a not very useful last resort
	return getStandardTag($file, $flac);
}

sub getXMLTag {
	my $file   = shift;
	my $anchor = shift;
	my $flac   = shift;
	my $tags   = {};

	# parse xml based metadata (musicbrainz rdf for example)
	# retrieve the xml content from the flac
	my $xml = $flac->application($PEEM) || return undef;

	# TODO: parse this using the same xml modules slimserver uses to parse iTunes

	# grab the cuesheet and figure out which track is current
	my $cuesheet = $flac->cuesheet();
	my $tracknum = _trackFromAnchor($cuesheet, $anchor);

	# crude regex matching until we get a real rdf/xml parser in place
	my $mbAlbum  = qr{"(http://musicbrainz.org/album/[\w-]+)"};
	my $mbArtist = qr{"(http://musicbrainz.org/artist/[\w-]+)"};
	my $mbTrack  = qr{"(http://musicbrainz.org/track/[\w-]+)"};

	# get list of albums included in this file
	# TODO: handle a collection of tracks without an album association (<mm:trackList> at a file level)
	my @albumList = ();

	if ($xml =~ m|<mm:albumList>(.+?)</mm:albumList>|m) {

		my $albumListSegment = $1;
		while ($albumListSegment =~ s|<rdf:li\s+rdf:resource=$mbAlbum\s*/>||m) {
			push(@albumList, $1);
		}
		
	} else {

		# assume only one album
		if ($xml =~ m|<mm:Album\s+rdf:about=$mbAlbum|m) {
			push(@albumList, $1);
		}
	}

	return undef unless @albumList > 0;

	# parse the individual albums to get list of tracks, etc.
	my $albumHash = {};
	my $temp      = $xml;

	while ($temp =~ s|(<mm:Album.*?</mm:Album>)||s) {

		my $albumsegment = $1;
		my $albumKey     = "";

		if ($albumsegment =~ m|<mm:Album\s+rdf:about=$mbAlbum|s) {
			$albumKey = $1;
			$albumHash->{$albumKey} = {};
		}

		if ($albumsegment =~ m|<dc:title>(.+?)</dc:title>|s) {
			$albumHash->{$albumKey}->{'ALBUM'} = $1;
		}

		if ($albumsegment =~ m|<dc:creator\s+rdf:resource=$mbArtist|s) {
			$albumHash->{$albumKey}->{'ARTISTID'} = $1;
		}

		if ($albumsegment =~ m|<mm:coverart rdf:resource="(/images/[^"+])"/>|s) { #" vim syntax
			$albumHash->{$albumKey}->{'COVER'} = $1 unless $1 eq "/images/no_coverart.png";
			# This need expanding upon to be actually useful
		}		

		# a cheezy way to get the first (earliest) release date
		if ($albumsegment =~ m|<rdf:Seq>\s*<rdf:li>\s*<mm:ReleaseDate>.*?<dc:date>(.+?)</dc:date>|s) {
			$albumHash->{$albumKey}->{'YEAR'} = $1;
		}

		# grab the actual track listing
		if ($albumsegment =~ m|<mm:trackList>\s*<rdf:Seq>(.+?)</rdf:Seq>\s*</mm:trackList>|s) {
			my $trackList = $1;
			while ($trackList =~ s|rdf:resource=$mbTrack||s) {
				push(@{$albumHash->{$albumKey}->{'TRACKLIST'}}, $1);
			}
		}
	}
	
	# merge track lists in order, and find which refers to us
	my @fileTrackList = [];

	for my $album (@albumList) {
		push(@fileTrackList, @{$albumHash->{$album}->{'TRACKLIST'}});
	}

	my $track = $fileTrackList[$tracknum];

	# final sanity check
	return undef unless defined $track;
	
	my $tempTags = {};

	# now process track info for just this track
	if ($xml =~ m|<mm:Track\s+rdf:about="$track">(.+?)</mm:Track>|s) {

		my $trackSegment = $1;
		if ($trackSegment =~ m|<dc:title>(.+?)</dc:title>|s) {
			$tempTags->{'TITLE'} = $1;
		}
		
		if ($trackSegment =~ m|<dc:creator rdf:resource=$mbArtist/>|s) {
			$tempTags->{'ARTISTID'} = $1;
		}
	}

	$tempTags->{'TRACKNUM'} = $tracknum;

	# add artist info
	if ($xml =~ m|<mm:Artist\s+rdf:about="$tempTags->{'ARTISTID'}"(.+?)</mm:Artist>|s) {
		my $artistSegment = $1;
		if ($artistSegment =~ m|<dc:title>(.+)</dc:title>|s) {
			$tempTags->{'ARTIST'} = $1;
		}
		if ($artistSegment =~ m|<mm:sortName>(.+)</mm:sortName>|s) {
			$tempTags->{'ARTISTSORT'} = $1;
		}
	}


	# now go back through the album list and find which one matches
	for my $album (@albumList) {
		for my $entry (@{$albumHash->{$album}->{'TRACKLIST'}}) {
			if ($entry eq $track) {
				$tempTags->{'ALBUMID'} = $album;
			}
		}
	}

	# merge the track and album results into the hash ref we intend to return
	%$tags = (%{$tempTags}, %{$albumHash->{$tempTags->{'ALBUMID'}}}) if defined $tempTags->{'TITLE'};;

	addInfoTags($flac, $tags) if keys %$tags > 0;
	return $tags;
}

sub getNumberedVC {
	my $file   = shift;
	my $anchor = shift;
	my $flac   = shift;
	my $tags   = {};

	# parse numbered vorbis comments
	# this looks for parenthetical numbers on comment keys, and
	# assumes the corrosponding key/value only applies to the
	# track index whose number matches.
	# note that we're matching against the "actual" track number
	# as reported by the cuesheet, not the "apparent" track number
	# as set with the TRACKNUMBER tag.
	# unnumbered keys are assumed to apply to every track.

	# as an example...
	#
	# ARTIST=foo
	# ALBUM=bar
	# TRACKNUMBER[1]=1
	# TITLE[1]=baz
	# TRACKNUMBER[2]=2
	# TITLE[2]=something

	# grab the raw comments for parsing
	my $rawTags = $flac->{'rawTags'};

	# grab the cuesheet for reference
	my $cuesheet = $flac->cuesheet();

	# look for a number of parenthetical TITLE keys that matches
	# the number of tracks in the cuesheet
	my $titletags = 0;
	my $cuetracks = 0;

	# to avoid conflicting with actual key characters,
	# we allow a few different options for bracketing the track number
	# allowed bracket types currently are () [] {} <>

	# we're playing a bit fast and loose here, we really should make sure
	# the same bracket types are used througout, not mixed and matched.
	for my $tag (@$rawTags) {
		$titletags++ if $tag =~ /^\s*TITLE\s*[\(\[\{\<]\d+[\)\]\}\>]\s*=/i;
	}

	for my $track (@$cuesheet) {
		$cuetracks++ if $track =~ /^\s*TRACK/i;
	}

	return undef unless $titletags == $cuetracks;

	# ok, let's see which tags apply to us
	my $track = _trackFromAnchor($cuesheet, $anchor);

	my $tempTags = {};

	for my $tag (@$rawTags) {

		# Match the key and value
		if ($tag =~ /^(.*?)=(.*)$/) {

			# Make the key uppercase
			my $tkey  = uc($1);
			my $value = $2;
			
			# Match track number
			my $group = "";
			if ($tkey =~ /^(.+)\s*[\(\[\{\<](\d+)[\)\]\}\>]/) {
				$tkey = $1;
				$group = $2;
			}

			$tempTags->{$tkey} = $value unless $group && $track != $group;
		}
	}
	
	$tags = $tempTags;
	doTagMapping($tags);
	addInfoTags($flac, $tags) if keys %$tags > 0;
	return $tags;
}

sub getCDDBTag {
	my $file   = shift;
	my $anchor = shift;
	my $flac   = shift;
	my $tags   = {};

	# parse cddb based metadata (foobar2000 does this, among others)
	# it's rather crude, but probably the most widely used currently.

	# TODO: detect various artist entries that reverse title and artist
	# this is non-trivial to do automatically, so I'm open to suggestions
	# currently we just expect you to have fairly clean tags.
	my $order = 'standard';

	$tags = $flac->tags() || {};

	# Detect CDDB style tags by presence of DTITLE, or return.
	return undef unless defined $tags->{'DTITLE'};

	if ($tags->{'DTITLE'} =~ m|^(.+)\s*/\s*(.+)$|) {
		$tags->{'ARTIST'} = $1;
		$tags->{'ALBUM'} = $2;
		delete $tags->{'DTITLE'};
	}

	if (exists $tags->{'DGENRE'}) {
		$tags->{'GENRE'} = $tags->{'DGENRE'};
		delete $tags->{'DGENRE'};
	}

	if (exists $tags->{'DYEAR'}) {
		$tags->{'YEAR'} = $tags->{'DYEAR'};
		delete $tags->{'DYEAR'};
	}

	# grab the cuesheet and figure out which track is current
	my $cuesheet = $flac->cuesheet();
	my $track    = _trackFromAnchor($cuesheet, $anchor);

	for my $key (keys(%$tags)) {

		if ($key =~ /TTITLE(\d+)/) {

			if ($track == $1) {

				if ($tags->{$key} =~ m|^(.+)\s*/\s*(.+)$|) {

					if ($order eq "standard") {
						$tags->{'ARTIST'} = $1;
						$tags->{'TITLE'} = $2;
					} else {
						$tags->{'ARTIST'} = $2;
						$tags->{'TITLE'} = $1;
					}

				} else {
					$tags->{'TITLE'} = $tags->{$key};
				}
				
				$tags->{'TRACKNUM'} = $track;
			}

			delete $tags->{$key};
		}
	}

	doTagMapping($tags);
	addInfoTags($flac, $tags) if keys %$tags > 0;
	return $tags;
}

sub getCUEinVC {
	my $file   = shift;
	my $anchor = shift;
	my $flac   = shift;
	my $tags   = {};

	# foobar2000 alternately can stuff an entire cuesheet, along with
	# the CDTEXT hack for storing metadata, into a vorbis comment tag.

	# TODO: we really should sanity check that this cuesheet matches the
        # cuesheet we pulled from the vorbis file.

        # Right now this section borrows heavily from the existing cuesheet
        # parsing code. Perhaps this should be abstracted out at some point.

	$tags = $flac->tags() || {};

	return undef unless defined $tags->{'CUESHEET'};

	# grab the cuesheet and figure out which track is current
	my $track    = _trackFromAnchor($flac->cuesheet(), $anchor);

	my $currtrack;

	# as mentioned, this parsing is ripped right out of Parse.pm
	# it's repeated here instead of calling Parse->parseCUE()
	# because we don't want to tweak song definitions or create
	# loops, just read tags.

	foreach (split(/\n/ ,$tags->{'CUESHEET'})) {

	  s/\s*$//;

	  if (/^TITLE\s+\"(.*)\"/i) {
	    $tags->{'ALBUM'} = $1;

	  } elsif (/^YEAR\s+\"(.*)\"/i) {
	    $tags->{'YEAR'} = $1

	  } elsif (/^GENRE\s+\"(.*)\"/i) {
	    $tags->{'GENRE'} = $1;

	  } elsif (/^COMMENT\s+\"(.*)\"/i) {
	    $tags->{'COMMENT'} = $1;

	  #} elsif (/^FILE\s+\"(.*)\"/i) {
	  #  $filename = $1;
	  #  $filename = Slim::Utils::Misc::fixPath($filename, $cuedir);

	  } elsif (/^\s+TRACK\s+(\d+)\s+AUDIO/i) {
	    $currtrack = int ($1);
	    next if ($currtrack < $track);
	    last if ($currtrack > $track);

	  } elsif (defined $currtrack and /^\s+PERFORMER\s+\"(.*)\"/i) {
	    $tags->{'ARTIST'} = $1;

	  } elsif (defined $currtrack and
		   /^\s+(TITLE|YEAR|GENRE|COMMENT)\s+\"(.*)\"/i) {
	    $tags->{uc $1} = $2;
	  }

	}
	$tags->{'TRACKNUM'} = $track;

	doTagMapping($tags);
	addInfoTags($flac, $tags) if keys %$tags > 0;
	return $tags;
}

sub getStackedVC {
	my $file   = shift;
	my $anchor = shift;
	my $flac   = shift;
	my $tags   = {};

	# parse "stacked" vorbis comments
	# this is tricky when it comes to matching which groups belong together
	# particularly for various artist, or multiple album compilations.
	# this as also not terribly efficent, so it's not our first choice.

	# here's a simple example of the sort of thing we're trying to work with
	#
	# ARTIST=foo
	# ALBUM=bar
	# TRACKNUMBER=1
	# TITLE=baz
	# TRACKNUMBER=2
	# TITLE=something

	# grab the raw comments for parsing
	my $rawTags = $flac->{'rawTags'};

	# grab the cuesheet for reference
	my $cuesheet = $flac->cuesheet();

	# validate number of TITLE tags against number of
	# tracks in the cuesheet
	my $titletags = 0;
	my $cuetracks = 0;

	for my $tag (@$rawTags) {
		$titletags++ if $tag =~ /^\s*TITLE=/i;
	}

	for my $track (@$cuesheet) {
		$cuetracks++ if $track =~ /^\s*TRACK/i;
	}

	return undef unless $titletags == $cuetracks;

	# ok, let's see which tags apply to us
	my $track = _trackFromAnchor($cuesheet, $anchor);

	my $group = 0;
	my $defaultTags = {};
	my $tempTags = {};

	for my $tag (@$rawTags) {

		# Match the key and value
		if (($track != $group) && ($tag =~ /^(.*?)=(.*)$/)) {

			# Make the key uppercase
			my $tkey  = uc($1);
			my $value = $2;
			
			if (defined $tempTags->{$tkey}) {
				$group++;
				my %merged = (%{$defaultTags}, %{$tempTags});
				$defaultTags = \%merged;
				$tempTags = {};
			}

			$tempTags->{$tkey} = $value unless $track == $group;
		}
	}
	
	%$tags = (%{$defaultTags}, %{$tempTags});
	doTagMapping($tags);
	addInfoTags($flac, $tags) if keys %$tags > 0;
	return $tags;
}

# determine a track number from a cuesheet and an anchor
sub _trackFromAnchor {
	my $cuesheet = shift;
	my $anchor   = shift;

	return -1 unless defined $cuesheet && defined $anchor;

	my ($start) = split('-',$anchor);

	my $time  = 0;
	my $track = 0;

	for my $line (@$cuesheet) {

		if ($line =~ /\s*TRACK\s+(\d+)/i) {
			$track = $1;
		}

		if ($line =~ /\s*INDEX\s+01\s+(\d+):(\d+):(\d+)/i) {
			$time = ($1 * 60) + $2 + ($3 / 75);
			
			# fudge this a bit to account for rounding
			my $difference = abs($time - $start);
			return $track if $difference < 0.01;
		}
	}
}

1;
