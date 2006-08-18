package Slim::Formats::FLAC;

# $tagsd: FLAC.pm,v 1.5 2003/12/15 17:57:50 daniel Exp $

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Formats::FLAC

=head1 SYNOPSIS

my $tags = Slim::Formats::FLAC->getTag( $filename );

=head1 DESCRIPTION

Read tags & cue sheets embedded in FLAC files.

=head1 METHODS

=cut

use strict;
use base qw(Slim::Formats);

use Audio::FLAC::Header;
use Fcntl qw(:seek);
use File::Basename;
use MIME::Base64 qw(decode_base64);

use Slim::Formats::Playlists::CUE;
use Slim::Schema::Contributor;
use Slim::Utils::Cache;
use Slim::Utils::Misc;
use Slim::Utils::Unicode;

my %tagMapping = (
	'TRACKNUMBER'			=> 'TRACKNUM',
	'DISCNUMBER'			=> 'DISC',
	'URL'				=> 'URLTAG',
	'musicbrainz_sortname'		=> 'ARTISTSORT',
	'MUSICBRAINZ_ALBUMARTISTID'	=> 'MUSICBRAINZ_ALBUMARTIST_ID',
	'MUSICBRAINZ_ALBUMID'		=> 'MUSICBRAINZ_ALBUM_ID',
	'MUSICBRAINZ_ALBUMSTATUS'	=> 'MUSICBRAINZ_ALBUM_STATUS',
	'MUSICBRAINZ_ALBUMTYPE'		=> 'MUSICBRAINZ_ALBUM_TYPE',
	'MUSICBRAINZ_ARTISTID'		=> 'MUSICBRAINZ_ARTIST_ID',
	'MUSICBRAINZ_SORTNAME'		=> 'MUSICBRAINZ_SORTNAME',
	'MUSICBRAINZ_TRACKID'		=> 'MUSICBRAINZ_ID',
	'MUSICBRAINZ_TRMID'		=> 'MUSICBRAINZ_TRM_ID',

	# J.River once again.. can't these people use existing standards?
	'REPLAY GAIN'			=> 'REPLAYGAIN_TRACK_GAIN',
	'PEAK LEVEL'			=> 'REPLAYGAIN_TRACK_PEAK',
	'DISC #'			=> 'DISC',
);

my @tagNames = (Slim::Schema::Contributor->contributorRoles, qw(ALBUM DISCNUMBER TITLE TRACKNUMBER DATE));

# peem id (http://flac.sf.net/id.html http://peem.iconoclast.net/)
my $PEEM = 1885693293;

# Escient sticks artwork in the application metadata block. The data is stored
# as PIC1 + artwork. So the raw data is +4 from the beginning.
my $ESCIENT_ARTWORK = 1163084622;

=head2 getTag( $filename )

Extract and return audio information & any embedded metadata found.

Choose between returning a standard tag or parsing through an embedded cuesheet.

=cut

sub getTag {
	my $class  = shift;
	my $file   = shift || return {};
	my $anchor = shift || "";

	my $flac   = Audio::FLAC::Header->new($file) || do {

		errorMsg("Couldn't open file: [$file] for reading: $!\n");
		return {};
	};

	my $tags = $class->_getStandardTag($file, $flac);
	my $cuesheet = $flac->cuesheet();

	# Handle all the UTF-8 decoding into perl's native format.
	# basefile tags first
	$class->_decodeUTF8($tags);

	# if there's no embedded cuesheet, then we're either a single song
	# or we have pseudo CDTEXT in the external cuesheet.
	unless (@$cuesheet > 0) {

		# no embedded cuesheet.
		# this is either a single song, or has an external cuesheet
		return $tags;
	}

	# if we do have an embedded cuesheet, we need to parse the metadata
	# for the individual tracks.
	#
	# cue parsing will return file url references with start/end anchors
	# we can now pretend that this (bare no-anchor) file is a playlist
	push(@$cuesheet, "    REM END " . sprintf("%02d:%02d:%02d",
		int(int($tags->{'SECS'})/60),
		int($tags->{'SECS'} % 60),
		(($tags->{'SECS'} - int($tags->{'SECS'})) * 75)
	));

	$tags->{'FILENAME'} = $file;

	# get the tracks from the cuesheet - tell parseCUE that we're dealing
	# with an embedded cue sheet.
	my $tracks = Slim::Formats::Playlists::CUE->parse($cuesheet, dirname($file), 1);

	# suck in metadata for all these tags
	my $items = $class->_getSubFileTags($flac, $tracks);

	# fallback if we can't parse metadata
	if ($items < 1) {
		$::d_parse && msg("Unable to find metadata for tracks referenced by cuesheet\n");
		return $tags;
	}

	# set fields appropriate for a playlist
	$tags->{'CT'}    = "fec";
	$tags->{'AUDIO'} = 0;

	# set a resonable "title" for the bare file
	$tags->{'TITLE'} = $tags->{'ALBUM'};

	my $fileurl = Slim::Utils::Misc::fileURLFromPath($file) . "#$anchor";
	my $fileage = (stat($file))[9];

	# Do the actual data store
	for my $key (sort { $a <=> $b } keys %$tracks) {

		my $track = $tracks->{$key};

		# Allow FLACs with embedded cue sheets to have a date.
		$track->{'AGE'} = $fileage;

		next unless exists $track->{'URI'};

		# Handle all the UTF-8 decoding into perl's native format.
		# for each track
		$class->_decodeUTF8($track);

		Slim::Formats::Playlists::CUE->processAnchor($track);

		Slim::Schema->rs('Track')->updateOrCreate({
			'url'        => $track->{'URI'},
			'attributes' => $track,
			'readTags'   => 0,  # avoid the loop, don't read tags
		});

		# if we were passed in an anchor, then the caller is expecting back tags for
		# the single track indicated.
		if ($anchor && $track->{'URI'} eq $fileurl) {
			$tags = $track;
			$::d_parse && msg("    found tags for $file#$anchor\n");	
		}
	}

	$::d_parse && msg("    returning: $items items\n");	

	return $tags;
}

=head2 getCoverArt( $filename )

Return any cover art embedded in the FLAC file's metadata.

=cut

sub getCoverArt {
	my $class = shift;
	my $file  = shift;

	my $cache = Slim::Utils::Cache->new;

	if (my $tags = $cache->get($file)) {

		# Invalidate the cache
		$cache->remove($file);

		return $tags->{'ARTWORK'};
	}

	my $flac = Audio::FLAC::Header->new($file) || do {
		errorMsg("FLAC: Couldn't open file: [$file] for reading: $!\n");
		return;
	};

	my $tags = $flac->tags() || {};

	addArtworkTags($flac, $tags);

	return $tags->{'ARTWORK'};
}

# Given a file, return a hash of name value pairs,
# where each name is a tag name.
sub _getStandardTag {
	my ($class, $file, $flac) = @_;

	my $tags = $flac->tags() || {};

	# Check for the presence of the info block here
	return undef unless defined $flac->{'bitRate'};

	# There should be a TITLE tag if the VORBIS tags are to be trusted
	unless (defined $tags->{'TITLE'}) {

		if (exists $flac->{'ID3V2Tag'}) {

			if (Slim::Formats->loadTagFormatForType('mp3')) {

				# Get the ID3V2 tag on there, sucka
				$tags = MP3::Info::get_mp3tag($file, 2);
			}
		}
	}

	$class->_doTagMapping($tags);
	$class->_addInfoTags($flac, $tags);
	$class->_addArtworkTags($flac, $tags);

	Slim::Utils::Cache->new->set($file, $tags, 60);

	return $tags;
}

sub _doTagMapping {
	my ($class, $tags) = @_;

	# map the existing tag names to the expected tag names
	while (my ($old,$new) = each %tagMapping) {

		if (exists $tags->{$old}) {

			$tags->{$new} = delete $tags->{$old};
		}
	}

	# Special handling for DATE tags
	# Parse the date down to just the year, for compatibility with other formats
	if (defined $tags->{'DATE'} && !defined $tags->{'YEAR'}) {
		($tags->{'YEAR'} = $tags->{'DATE'}) =~ s/.*(\d\d\d\d).*/$1/;
	}
}

sub _addInfoTags {
	my ($class, $flac, $tags) = @_;

	if (!defined $tags || ref($tags) ne 'HASH') {
		return;
	}

	# add more information to these tags
	# these are not tags, but calculated values from the streaminfo
	$tags->{'SIZE'}    = $flac->{'fileSize'};
	$tags->{'SECS'}    = $flac->{'trackTotalLengthSeconds'};
	$tags->{'OFFSET'}  = 0; # the header is an important part of the file. don't skip it
	$tags->{'BITRATE'} = $flac->{'bitRate'};

	# Add the stuff that's stored in the Streaminfo Block
	my $flacInfo = $flac->info();
	$tags->{'RATE'}     = $flacInfo->{'SAMPLERATE'};
	$tags->{'CHANNELS'} = $flacInfo->{'NUMCHANNELS'};

	# FLAC files are always lossless
	$tags->{'LOSSLESS'} = 1;

	# stolen from MP3::Info
	$tags->{'MM'}	    = int $tags->{'SECS'} / 60;
	$tags->{'SS'}	    = int $tags->{'SECS'} % 60;
	$tags->{'MS'}	    = (($tags->{'SECS'} - ($tags->{'MM'} * 60) - $tags->{'SS'}) * 1000);
	$tags->{'TIME'}	    = sprintf "%.2d:%.2d", @{$tags}{'MM', 'SS'};
}

sub _addArtworkTags {
	my ($class, $flac, $tags) = @_;

	# As seen in J.River Media Center FLAC files.
	if ($tags->{'COVERART'}) {

		$tags->{'ARTWORK'} = decode_base64($tags->{'COVERART'});

		delete $tags->{'COVERART'};

	} elsif (my $artwork = $flac->application($ESCIENT_ARTWORK)) {

		if (substr($artwork, 0, 4, '') eq 'PIC1') {
			$tags->{'ARTWORK'} = $artwork;
		}
	}

	return $tags;
}

sub _getSubFileTags {
	my ($class, $flac, $tracks) = @_;

	my $items  = 0;

	# There is no official standard for multi-song metadata in a flac file
	# so we try a few different approaches ordered from most useful to least
	#
	# as new methods are found in the wild, they can be added here. when
	# a de-facto standard emerges, unused ones can be dropped.

	# parse embedded xml metadata
	$items = $class->_getXMLTags($flac, $tracks);
	return $items if $items > 0;

	# look for numbered vorbis comments
	$items = $class->_getNumberedVCs($flac, $tracks);
	return $items if $items > 0;

	# parse cddb style metadata
	$items = $class->_getCDDBTags($flac, $tracks);
	return $items if $items > 0;

	# parse cuesheet stuffed into a vorbis comment
	$items = $class->_getCUEinVCs($flac, $tracks);
	return $items if $items > 0;

	# try parsing stacked vorbis comments
	$items = $class->_getStackedVCs($flac, $tracks);
	return $items if $items > 0;

	# This won't yield good results - but without it, we regress from 6.0.2
	my $tags = $class->_getStandardTag($flac->{'FILENAME'}, $flac);

	if (scalar keys %$tags) {

		for my $num (sort keys %$tracks) {

			while (my ($key, $value) = each %$tags) {
				$tracks->{$num}->{$key} = $value unless defined $tracks->{$num}->{$key};
			}
		}

		return scalar keys %$tracks;
	}

	# if we really wanted to, we could parse "standard" tags and apply to every track
	# but that doesn't seem very useful.
	$::d_parse && msg("No useable metadata found for this FLAC file.\n");

	return 0;
}

sub _getXMLTags {
	my ($class, $flac, $tracks) = @_;

	# parse xml based metadata (musicbrainz rdf for example)
	# retrieve the xml content from the flac
	my $xml = $flac->application($PEEM) || return 0;

	# TODO: parse this using the same xml modules slimserver uses to parse iTunes
	# even better, use RDF::Simple::Parser

	# grab the cuesheet and figure out which track is current
	my $cuesheet = $flac->cuesheet();

	# crude regex matching until we get a real rdf/xml parser in place
	my $mbAlbum  = qr{"(http://musicbrainz.org/(?:mm-2.1/)album/[\w-]+)"};
	my $mbArtist = qr{"(http://musicbrainz.org/(?:mm-2.1/)artist/[\w-]+)"};
	my $mbTrack  = qr{"(http://musicbrainz.org/(?:mm-2.1/)track/[\w-]+)"};

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

	return 0 unless @albumList > 0;

	my $defaultTags = {};

	$class->_addInfoTags($flac, $defaultTags);

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

	# grab artist info
	my $artistHash = {};

	while ($xml =~ s|<mm:Artist\s+rdf:about="([^"]+)">(.+?)</mm:Artist>||s) { #"
		my $artistid = $1;
		my $artistSegment = $2;
		$artistHash->{$artistid} = {};

		$artistHash->{$artistid}->{'ARTISTID'} = $artistid;

		my $message = "    ARTISTID: $artistid" if $::d_parse;

		if ($artistSegment =~ m|<dc:title>(.+)</dc:title>|s) {
			$artistHash->{$artistid}->{'ARTIST'} = $1;

			$message .= " ARTIST: " . $artistHash->{$artistid}->{'ARTIST'} if $::d_parse;
		}
		if ($artistSegment =~ m|<mm:sortName>(.+)</mm:sortName>|s) {
			$artistHash->{$artistid}->{'ARTISTSORT'} = $1;
		}

		$::d_parse && msg("$message\n");

	}


	# $tracks is keyed to the cuesheet TRACK number, which is sequential
	# in some cases, that may not match the tracks official TRACKNUM
	my $cuesheetTrack = 0;

	for my $album (@albumList) {

		my $tracknumber = 0;

		$::d_parse && msg("    ALBUM: " . $albumHash->{$album}->{'ALBUM'} . "\n");

		for my $track (@{$albumHash->{$album}->{'TRACKLIST'}}) {
			my $tempTags = {};
			$cuesheetTrack++;
			$tracknumber++;

			$::d_parse && msg("    processing track $cuesheetTrack -- $track\n");

			next unless exists $tracks->{$cuesheetTrack};

			$tracks->{$cuesheetTrack}->{'TRACKNUM'} = $tracknumber;
			$::d_parse && msg("    TRACKNUM: $tracknumber\n");

			%{$tracks->{$cuesheetTrack}} = (%{$tracks->{$cuesheetTrack}}, %{$albumHash->{$album}});
			
			# now process track info
			if ($xml =~ m|<mm:Track\s+rdf:about="$track">(.+?)</mm:Track>|s) {

				my $trackSegment = $1;
				if ($trackSegment =~ m|<dc:title>(.+?)</dc:title>|s) {
					$tracks->{$cuesheetTrack}->{'TITLE'} = $1;

					$::d_parse && msg("    TITLE: " . $tracks->{$cuesheetTrack}->{'TITLE'} . "\n");
				}

				if ($trackSegment =~ m|<dc:creator rdf:resource="([^"]+)"/>|s) { #"
					%{$tracks->{$cuesheetTrack}} = (%{$tracks->{$cuesheetTrack}}, %{$artistHash->{$1}});

					$::d_parse && msg("    ARTIST: " . $tracks->{$cuesheetTrack}->{'ARTIST'} . "\n");
				}
			}

			%{$tracks->{$cuesheetTrack}} = (%{$defaultTags}, %{$tracks->{$cuesheetTrack}});

			$class->_doTagMapping($tracks->{$cuesheetTrack});
		}
	}

	return $cuesheetTrack;
}

sub _getNumberedVCs {
	my ($class, $flac, $tracks) = @_;

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

	return 0 if $titletags == 0;

	for my $track (@$cuesheet) {
		$cuetracks++ if $track =~ /^\s*TRACK/i;
	}

	if ($titletags != $cuetracks) {
		$::d_parse && msg("ERROR: This file has tags for "
			. $titletags . " tracks but the cuesheet has "
			. $cuetracks . " tracks\n");
		return 0;
	}

	# ok, let's see which tags apply to us

	my $defaultTags = {};

	$class->_addInfoTags($flac, $defaultTags);

	for my $tag (@$rawTags) {

		# Match the key and value
		if ($tag =~ /^(.*?)=(.*)$/) {

			# Make the key uppercase
			my $tkey  = uc($1);
			my $value = $2;

			$::d_parse && msg("matched: $tkey = $value\n");
			
			# Match track number
			my $group;
			if ($tkey =~ /^(.+)\s*[\(\[\{\<](\d+)[\)\]\}\>]/) {
				$tkey = $1;
				$group = $2 + 0;
				$::d_parse && msg("grouped as track $group\n");
			}			

			if (defined $group) {
				$tracks->{$group}->{$tkey} = $value;
			} else {
				$defaultTags->{$tkey} = $value;
			}
		}
	}

	# merge in the global tags
	for (my $num = 1; $num <= $titletags; $num++) {

		%{$tracks->{$num}} = (%{$defaultTags}, %{$tracks->{$num}});

		$class->_doTagMapping($tracks->{$num});

		$tracks->{$num}->{'TRACKNUM'} = $num unless exists $tracks->{$num}->{'TRACKNUM'};
	}

	return $titletags;
}

sub _getCDDBTags {
	my ($class, $flac, $tracks) = @_;

	my $items = 0;

	# parse cddb based metadata (foobar2000 does this, among others)
	# it's rather crude, but probably the most widely used currently.

	# TODO: detect various artist entries that reverse title and artist
	# this is non-trivial to do automatically, so I'm open to suggestions
	# currently we just expect you to have fairly clean tags.
	my $order = 'standard';

	my $tags = $flac->tags() || {};

	# Detect CDDB style tags by presence of DTITLE, or return.
	return 0 unless defined $tags->{'DTITLE'};

	if ($tags->{'DTITLE'} =~ m|^(.+)\s*/\s*(.+)$|) {
		$tags->{'ARTIST'} = $1;
		$tags->{'ALBUM'} = $2;
		delete $tags->{'DTITLE'};

		$::d_parse && msg("    ARTIST: " . $tags->{'ARTIST'} . "\n");
		$::d_parse && msg("    ALBUM: " . $tags->{'ALBUM'} . "\n");
	}

	if (exists $tags->{'DGENRE'}) {
		$tags->{'GENRE'} = $tags->{'DGENRE'};
		delete $tags->{'DGENRE'};

		$::d_parse && msg("    GENRE: " . $tags->{'GENRE'} . "\n");
	}

	if (exists $tags->{'DYEAR'}) {
		$tags->{'YEAR'} = $tags->{'DYEAR'};
		delete $tags->{'DYEAR'};

		$::d_parse && msg("    YEAR: " . $tags->{'YEAR'} . "\n");
	}

	# grab the cuesheet and process the individual tracks
	my $cuesheet = $flac->cuesheet();

	for my $key (keys(%$tags)) {

		if ($key =~ /TTITLE(\d+)/) {
			my $tracknum = $1;

			if ($tags->{$key} =~ m|^(.+\S)\s*/\s*(.+)$|) {
				
				if ($order eq "standard") {
					$tracks->{$tracknum}->{'ARTIST'} = $1;
					$tracks->{$tracknum}->{'TITLE'} = $2;
				} else {
					$tracks->{$tracknum}->{'ARTIST'} = $2;
					$tracks->{$tracknum}->{'TITLE'} = $1;
				}

				$::d_parse && msg("    ARTIST: " . $tracks->{$tracknum}->{'ARTIST'} . "\n");
				
			} else {
				$tracks->{$tracknum}->{'TITLE'} = $tags->{$key};
			}

			$::d_parse && msg("    TITLE: " . $tracks->{$tracknum}->{'TITLE'} . "\n");

			$tracks->{$tracknum}->{'TRACKNUM'} = $tracknum;

			$::d_parse && msg("    TRACKNUM: " . $tracks->{$tracknum}->{'TRACKNUM'} . "\n");

			delete $tags->{$key};
			$items++;
		}
	}

	$class->_addInfoTags($flac, $tags);

	# merge in the global tags
	for my $key (keys %$tracks) {

		%{$tracks->{$key}} = (%{$tags}, %{$tracks->{$key}});

		$class->_doTagMapping($tracks->{$key});
	}

	return $items;
}

sub _getCUEinVCs {
	my ($class, $flac, $tracks) = @_;

	my $items  = 0;

	# foobar2000 alternately can stuff an entire cuesheet, along with
	# the CDTEXT hack for storing metadata, into a vorbis comment tag.

	# TODO: we really should sanity check that this cuesheet matches the
	# cuesheet we pulled from the vorbis file.

	my $tags = $flac->tags() || {};

	return 0 unless exists $tags->{'CUESHEET'};

	my @cuesheet = split(/\s*\n/, $tags->{'CUESHEET'});
	push(@cuesheet, "    REM END " . sprintf("%02d:%02d:%02d",
		int(int($tags->{'SECS'})/60),
		int($tags->{'SECS'} % 60),
		(($tags->{'SECS'} - int($tags->{'SECS'})) * 75)
	));

	# we don't have a proper dir to send parseCUE(), but we already have urls,
	# so we can just fake it. Tell parseCUE that we're an embedded cue sheet
	my $metadata = Slim::Formats::Playlists::CUE->parse(\@cuesheet, "/BOGUS/PATH/", 1);

	# grab file info tags
	# don't pass $metadata through addInfoTags() or it'll decodeUTF8 too many times
	my $infoTags = {};

	$class->_addInfoTags($flac, $infoTags);

	# merge the existing track data and cuesheet metadata
	for my $key (keys %$tracks) {

		if (!exists $metadata->{$key}) {
			$::d_parse && msg("No metadata found for track " . $tracks->{$key}->{'URI'} . "\n");
			next;
		}

		%{$tracks->{$key}} = (%{$infoTags}, %{$metadata->{$key}}, %{$tracks->{$key}});

		# Add things like GENRE, etc to the tracks - if they weren't
		# in the cue sheet. See bug 2304
		while (my ($tag,$value) = each %{$tags}) {

			if (!defined $tracks->{$key}->{$tag} && $tag !~ /^cuesheet$/i) {

				$tracks->{$key}->{$tag} = $value;
			}
		}

		$class->_doTagMapping($tracks->{$key});

		$items++;
	}

	return $items;
}

sub _getStackedVCs {
	my ($class, $flac, $tracks) = @_;

	my $items  = 0;

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

	return 0 unless $titletags == $cuetracks;
	

	# ok, let's see which tags apply to which tracks

	my $tempTags = {};
	my $defaultTags = {};

	$class->_addInfoTags($flac, $defaultTags);

	for my $tag (@$rawTags) {

		# Match the key and value
		if ($tag =~ /^(.*?)=(.*?)[\r\n]*$/) {

			# Make the key uppercase
			my $tkey  = uc($1);
			my $value = $2;
			
			# use duplicate detection to find track boundries
			# retain file wide values as defaults
			if (defined $tempTags->{$tkey}) {
				$items++;
				my %merged = (%{$defaultTags}, %{$tempTags});				
				$defaultTags = \%merged;
				$tempTags = {};

				# set the tags on the track
				%{$tracks->{$items}} = (%{$tracks->{$items}}, %{$defaultTags});

				$class->_doTagMapping($tracks->{$items});

				if (!exists $tracks->{$items}->{'TRACKNUM'}) {
					$tracks->{$items}->{'TRACKNUM'} = $items;
				}

			}

			$tempTags->{$tkey} = $value;
			$::d_parse && msg("    $tkey: $value\n");
		}
	}

	# process the final track
	$items++;

	%{$tracks->{$items}} = (%{$tracks->{$items}}, %{$defaultTags}, %{$tempTags});

	$class->_doTagMapping($tracks->{$items});

	if (!exists $tracks->{$items}->{'TRACKNUM'}) {
		$tracks->{$items}->{'TRACKNUM'} = $items;
	}

	return $items;
}

sub _decodeUTF8 {
	my ($class, $tags) = @_;

	# Do the UTF-8 handling here, after all the different types of tags are read.
	for my $tag (@tagNames) {

		next unless exists $tags->{$tag};

		my $count  = 1;
		my $values = [ $tags->{$tag} ];

		if (ref($tags->{$tag}) eq 'ARRAY') {

			# Make a copy.
			$values = [ @{$tags->{$tag}} ];
			$count  = scalar @$values;

			# Empty out the old value while we work on a copy.
			@{$tags->{$tag}} = ();
		}

		for my $value (@$values) {

			if ($] > 5.007) {
				$value = Slim::Utils::Unicode::utf8decode($value, 'utf8');
			} else {
				$value = Slim::Utils::Unicode::utf8toLatin1($value);
			}

			if ($count == 1) {

				$tags->{$tag} = $value;

			} else {

				push @{$tags->{$tag}}, $value;
			}
		}
	}
}

our @crc8_table = (
	0x00, 0x07, 0x0E, 0x09, 0x1C, 0x1B, 0x12, 0x15,
	0x38, 0x3F, 0x36, 0x31, 0x24, 0x23, 0x2A, 0x2D,
	0x70, 0x77, 0x7E, 0x79, 0x6C, 0x6B, 0x62, 0x65,
	0x48, 0x4F, 0x46, 0x41, 0x54, 0x53, 0x5A, 0x5D,
	0xE0, 0xE7, 0xEE, 0xE9, 0xFC, 0xFB, 0xF2, 0xF5,
	0xD8, 0xDF, 0xD6, 0xD1, 0xC4, 0xC3, 0xCA, 0xCD,
	0x90, 0x97, 0x9E, 0x99, 0x8C, 0x8B, 0x82, 0x85,
	0xA8, 0xAF, 0xA6, 0xA1, 0xB4, 0xB3, 0xBA, 0xBD,
	0xC7, 0xC0, 0xC9, 0xCE, 0xDB, 0xDC, 0xD5, 0xD2,
	0xFF, 0xF8, 0xF1, 0xF6, 0xE3, 0xE4, 0xED, 0xEA,
	0xB7, 0xB0, 0xB9, 0xBE, 0xAB, 0xAC, 0xA5, 0xA2,
	0x8F, 0x88, 0x81, 0x86, 0x93, 0x94, 0x9D, 0x9A,
	0x27, 0x20, 0x29, 0x2E, 0x3B, 0x3C, 0x35, 0x32,
	0x1F, 0x18, 0x11, 0x16, 0x03, 0x04, 0x0D, 0x0A,
	0x57, 0x50, 0x59, 0x5E, 0x4B, 0x4C, 0x45, 0x42,
	0x6F, 0x68, 0x61, 0x66, 0x73, 0x74, 0x7D, 0x7A,
	0x89, 0x8E, 0x87, 0x80, 0x95, 0x92, 0x9B, 0x9C,
	0xB1, 0xB6, 0xBF, 0xB8, 0xAD, 0xAA, 0xA3, 0xA4,
	0xF9, 0xFE, 0xF7, 0xF0, 0xE5, 0xE2, 0xEB, 0xEC,
	0xC1, 0xC6, 0xCF, 0xC8, 0xDD, 0xDA, 0xD3, 0xD4,
	0x69, 0x6E, 0x67, 0x60, 0x75, 0x72, 0x7B, 0x7C,
	0x51, 0x56, 0x5F, 0x58, 0x4D, 0x4A, 0x43, 0x44,
	0x19, 0x1E, 0x17, 0x10, 0x05, 0x02, 0x0B, 0x0C,
	0x21, 0x26, 0x2F, 0x28, 0x3D, 0x3A, 0x33, 0x34,
	0x4E, 0x49, 0x40, 0x47, 0x52, 0x55, 0x5C, 0x5B,
	0x76, 0x71, 0x78, 0x7F, 0x6A, 0x6D, 0x64, 0x63,
	0x3E, 0x39, 0x30, 0x37, 0x22, 0x25, 0x2C, 0x2B,
	0x06, 0x01, 0x08, 0x0F, 0x1A, 0x1D, 0x14, 0x13,
	0xAE, 0xA9, 0xA0, 0xA7, 0xB2, 0xB5, 0xBC, 0xBB,
	0x96, 0x91, 0x98, 0x9F, 0x8A, 0x8D, 0x84, 0x83,
	0xDE, 0xD9, 0xD0, 0xD7, 0xC2, 0xC5, 0xCC, 0xCB,
	0xE6, 0xE1, 0xE8, 0xEF, 0xFA, 0xFD, 0xF4, 0xF3
);

sub _crc8 {
	my ($bytes, $len) = @_;
	my $crc = 0;
	
	for (my $i = 0; $i < $len; $i++) {
		$crc = $crc8_table[$crc ^ $bytes->[$i]];
	}
	
	return $crc;
}

sub _isFLACHeader {
	my $buffer = shift;
	
	my @bytes = unpack("C16", $buffer);
	my ($sync1, $sync2, $block_size, $sample_rate, $channel, $sample_size,
	    $padding) = ($bytes[0], $bytes[1] >> 2, ($bytes[2] >> 4),
			 ($bytes[2] & 0x0F), ($bytes[3] >> 4),
			 ($bytes[3] >> 1)&0x07, ($bytes[3]&0x1));
	return 0 if ($sync1 != 0xFF ||
		     $sync2 != 0x3E ||
		     $sample_rate == 0xF ||
		     $channel > 0xC ||
		     $sample_size == 0x3 ||
		     $sample_size == 0x7 ||
		     $padding);
	
	my $len = 4;
	if (!($bytes[4] & 0x80)) {
		$len += 1;
	}
	elsif($bytes[4] & 0xC0 && !($bytes[4] & 0x20)) {
		$len += 2;
	}
	elsif($bytes[4] & 0xE0 && !($bytes[4] & 0x10)) {
		$len += 3;
	}
	elsif($bytes[4] & 0xF0 && !($bytes[4] & 0x08)) {
		$len += 4;
	}
	elsif($bytes[4] & 0xF8 && !($bytes[4] & 0x04)) {
		$len += 5;
	}
	elsif($bytes[4] & 0xFC && !($bytes[4] & 0x02)) {
		$len += 6;
	}
	elsif($bytes[4] & 0xFE && !($bytes[4] & 0x01)) {
		$len += 7;
	}

	if ($block_size == 0x6) {
		$len += 1;
	}
	elsif ($block_size == 0x7) {
		$len += 2;
	}

	if ($sample_rate == 0xc) {
		$len += 1;
	}
	elsif ($block_size == 0xd || $block_size == 0xe) {
		$len += 2;
	}
	
	my $crc = $bytes[$len];
	return 0 if $crc != _crc8(\@bytes, $len);
	
	return 1;
}

my $HEADERLEN   = 16;
my $MAXDISTANCE = 18448;  # frame header size (16 bytes) + 4608 stereo 16-bit samples (higher than 4608 is possible, but not done)

# seekNextFrame:
#
# when scanning forward ($direction=1), simply detects the next frame header.
#
# when scanning backwards ($direction=-1), returns the next frame header whose
# frame length is within the distance scanned (so that when scanning backwards 
# from EOF, it skips any truncated frame at the end of block.

sub _seekNextFrame {
	my ($class, $fh, $startoffset, $direction) = @_;

	use bytes;

	if (!defined $fh || !defined $startoffset || !defined $direction) {
		errorMsg("seekNextFrame: Invalid arguments!\n");
		return 0;
	}

	my $filelen = -s $fh;
	if ($startoffset > $filelen) {
		$startoffset = $filelen;
	}

	my $seekto = ($direction == 1) ? $startoffset : $startoffset - $MAXDISTANCE;

	$::d_source && msg("seekNextFrame: reading $MAXDISTANCE bytes at: $seekto (to scan direction: $direction) \n");

	sysseek($fh, $seekto, SEEK_SET);
	sysread($fh, my $buf, $MAXDISTANCE, 0);

	my $len = length($buf);

	if ($len < 16) {
		$::d_source && msg("seekNextFrame: got less than 16 bytes\n");
		return 0;
	}

	my ($start, $end) = (0, 0);

	if ($direction == 1) {
		$start = 0;
		$end   = $len - $HEADERLEN;
	} else {
		$start = $len - $HEADERLEN;
		$end   = 0;
	}

	$::d_source && msg("seekNextFrame: scanning: len = $len, start = $start, end = $end\n");

	for (my $pos = $start; $pos != $end; $pos += $direction) {

		my $head = substr($buf, $pos, 16);

		if (ord($head) != 0xff) {
			next;
		}

		if (!_isFLACHeader($head)) {
			next;
		}

		my $found_at_offset = $seekto + $pos;

		$::d_source && msg("seekNextFrame: Found frame header at $found_at_offset\n");

		return $found_at_offset;
	}

	$::d_source && msg("seekNextFrame: Couldn't find any frame header\n");

	return 0;
}

=head2 findFrameBoundaries( $fh, $offset, $seek )

Starts seeking from $offset (bytes relative to beginning of file) until it
finds the next valid frame header. Returns the offset of the first and last
bytes of the frame if any is found, otherwise (0, 0).

If the caller does not request an array context, only the first (start) position is returned.

The only caller is L<Slim::Player::Source> at this time.

=cut

sub findFrameBoundaries {
	my ($class, $fh, $offset, $seek) = @_;

	if (!defined $fh || !defined $offset) {
		errorMsg("findFrameBoundaries: Invalid arguments!\n");
		return wantarray ? (0, 0) : 0;
	}

	my $start = $class->_seekNextFrame($fh, $offset, 1);
	my $end   = 0;

	if (defined $seek) {

		$end = $class->seekNextFrame($fh, $offset + $seek, -1);

		return ($start, $end);
	}

	return wantarray ? ($start, $end) : $start;
}

=head1 SEE ALSO

L<Slim::Formats>

L<Slim::Formats::Playlists::CUE>

L<Slim::Player::Source>

L<Audio::FLAC::Header>

L<MP3::Info>

=cut

1;
