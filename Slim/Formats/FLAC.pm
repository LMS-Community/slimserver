package Slim::Formats::FLAC;

# $tagsd: FLAC.pm,v 1.5 2003/12/15 17:57:50 daniel Exp $

# Logitech Media Server Copyright 2001-2011 Logitech.
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

use Audio::Scan;
use Fcntl qw(:seek);
use File::Basename;
use MIME::Base64 qw(decode_base64);

use Slim::Formats::MP3;
use Slim::Formats::Playlists::CUE;
use Slim::Schema::Contributor;
use Slim::Utils::Log;
use Slim::Utils::Misc;

my $log       = logger('formats.playlists');
my $sourcelog = logger('player.source');

my %tagMapping = (
	'TRACKNUMBER'               => 'TRACKNUM',
	'DISCNUMBER'                => 'DISC',
	'DISCTOTAL'                 => 'DISCC',
	'URL'                       => 'URLTAG',
	'MUSICBRAINZ_SORTNAME'      => 'ARTISTSORT',
	'MUSICBRAINZ_ALBUMARTIST'   => 'ALBUMARTIST',
	'MUSICBRAINZ_ALBUMARTISTID' => 'MUSICBRAINZ_ALBUMARTIST_ID',
	'MUSICBRAINZ_ALBUMID'       => 'MUSICBRAINZ_ALBUM_ID',
	'MUSICBRAINZ_ALBUMSTATUS'   => 'MUSICBRAINZ_ALBUM_STATUS',
	'MUSICBRAINZ_ALBUMTYPE'     => 'MUSICBRAINZ_ALBUM_TYPE',
	'MUSICBRAINZ_ARTISTID'      => 'MUSICBRAINZ_ARTIST_ID',
	'MUSICBRAINZ_TRACKID'       => 'MUSICBRAINZ_ID',
	'MUSICBRAINZ_TRMID'         => 'MUSICBRAINZ_TRM_ID',
	'DESCRIPTION'               => 'COMMENT',

	# J.River once again.. can't these people use existing standards?
	'REPLAY GAIN'               => 'REPLAYGAIN_TRACK_GAIN',
	'PEAK LEVEL'                => 'REPLAYGAIN_TRACK_PEAK',
	'DISC #'                    => 'DISC',
	'ALBUM ARTIST'              => 'ALBUMARTIST',

	# for dBpoweramp CD Ripper
	'TOTALDISCS'                => 'DISCC',
);

my @tagNames = (Slim::Schema::Contributor->contributorRoles, qw(ALBUM DISCNUMBER TITLE TRACKNUMBER DATE GENRE));

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
	
	my $s = Audio::Scan->scan($file);
	
	return unless $s->{info}->{samplerate};
	
	my $tags = $class->_getStandardTag($s);
	
	my $hasCue = exists $tags->{CUESHEET_BLOCK} || exists $tags->{CUESHEET};		

	if ( !$hasCue ) {
		# no embedded cuesheet.
		# this is either a single song, or has an external cuesheet
		return $tags;
	}
	
	my $cuesheet;	
	if ( $tags->{CUESHEET} ) {
		# user-supplied cuesheet in a single tag
		$cuesheet = [ split /\s*\n/, $tags->{CUESHEET} ];
	}
	else {
		$cuesheet = $tags->{CUESHEET_BLOCK};
	}
	
	# if we do have an embedded cuesheet, we need to parse the metadata
	# for the individual tracks.
	#
	# cue parsing will return file url references with start/end anchors
	# we can now pretend that this (bare no-anchor) file is a playlist
	push @$cuesheet, "    REM END " . $tags->{SECS};

	$tags->{FILENAME} = $file;

	# get the tracks from the cuesheet - tell parseCUE that we're dealing
	# with an embedded cue sheet by passing in the filename
	my $tracks = Slim::Formats::Playlists::CUE->parse($cuesheet, dirname($file), $file);
	
	# Fail if bad cuesheet was found
	if ( !$tracks || !scalar keys %{$tracks} ) {
		return $tags;
	}

	# suck in metadata for all these tags
	my $items = $class->_getSubFileTags($s, $tracks);

	# fallback if we can't parse metadata
	if ( $items < 1 ) {
		logWarning("Unable to find metadata for tracks referenced by cuesheet: [$file]");
		return $tags;
	}

	# set fields appropriate for a playlist
	$tags->{CT}    = "fec";
	$tags->{AUDIO} = 0;

	# set a resonable "title" for the bare file
	# First choice: TITLE value from the cue sheet (stored in $tracks->{ALBUM}), or ALBUM tag
	$tags->{TITLE} = $tracks->{1}->{ALBUM} || $tags->{ALBUM};

	my $fileurl = Slim::Utils::Misc::fileURLFromPath($file) . "#$anchor";
	my $fileage = (stat($file))[9];
	my $rs      = Slim::Schema->rs('Track');

	# Do the actual data store
	for my $key ( sort { $a <=> $b } keys %$tracks ) {

		my $track = $tracks->{$key};

		# Allow FLACs with embedded cue sheets to have a date and size
		$track->{AGE} = $fileage;
		$track->{FS}  = $tags->{SIZE};
		
		# Mark track as virtual
		$track->{VIRTUAL} = 1;

		next unless exists $track->{URI};

		Slim::Formats::Playlists::CUE->processAnchor($track);

		$rs->updateOrCreate( {
			url        => $track->{URI},
			attributes => $track,
			readTags   => 0,  # avoid the loop, don't read tags
		} );

		# if we were passed in an anchor, then the caller is expecting back tags for
		# the single track indicated.
		if ( $anchor && $track->{URI} eq $fileurl ) {
			$tags = $track;

			main::DEBUGLOG && logger('formats.playlists')->debug("    found tags for $file\#$anchor");
		}
	}

	main::DEBUGLOG && logger('formats.playlists')->debug("    returning $items items");

	return $tags;
}

=head2 getCoverArt( $filename )

Return any cover art embedded in the FLAC file's metadata.

=cut

sub getCoverArt {
	my $class = shift;
	my $file  = shift;

	# Enable artwork in Audio::Scan
	local $ENV{AUDIO_SCAN_NO_ARTWORK} = 0;
	
	my $s = Audio::Scan->scan($file);
	
	my $tags = $s->{tags};

	$class->_addArtworkTags($s, $tags);

	return $tags->{ARTWORK};
}

# Given a file, return a hash of name value pairs,
# where each name is a tag name.
sub _getStandardTag {
	my ($class, $s) = @_;

	my $tags = $s->{tags} || {};

	$class->_addInfoTags($s, $tags);
	$class->_doTagMapping($tags);
	$class->_addArtworkTags($s, $tags);

	return $tags;
}

sub _doTagMapping {
	my ($class, $tags) = @_;
	
	# Map ID3 tags first, so FLAC tags win out
	if ( $tags->{TAGVERSION} ) {
		# Tell MP3 tag mapper to not overwrite existing tags
		Slim::Formats::MP3->doTagMapping( $tags, 1 );
	}

	# map the existing tag names to the expected tag names
	while ( my ($old, $new) = each %tagMapping ) {
		if ( exists $tags->{$old} ) {
			$tags->{$new} = delete $tags->{$old};
		}
	}

	# Special handling for DATE tags
	# Parse the date down to just the year, for compatibility with other formats
	if (defined $tags->{DATE} && !defined $tags->{YEAR}) {
		# bug 18112 - Sometimes we get a list of dates. Pick the first.
		if (ref $tags->{DATE} eq 'ARRAY') {
			my @years = sort @{$tags->{DATE}};
			$tags->{DATE} = $years[0];
		}
		
		($tags->{YEAR} = $tags->{DATE}) =~ s/.*(\d\d\d\d).*/$1/;
	}
}

sub _addInfoTags {
	my ($class, $s, $tags) = @_;
	
	my $info = $s->{info};
	
	# Add info tags
	$tags->{SIZE}       = $info->{file_size};
	$tags->{SECS}       = $info->{song_length_ms} / 1000;
	$tags->{OFFSET}     = 0; # the header is an important part of the file. don't skip it
	$tags->{BITRATE}    = sprintf "%d", $info->{bitrate};
	$tags->{VBR_SCALE}  = 1;
	$tags->{RATE}       = $info->{samplerate};
	$tags->{SAMPLESIZE} = $info->{bits_per_sample};
	$tags->{CHANNELS}   = $info->{channels};
	$tags->{LOSSLESS}   = 1;
	
	# Map ID3 tags if file has them
	if ( $info->{id3_version} ) {
		$tags->{TAGVERSION} = 'FLAC, ' . $info->{id3_version};
	}
}

sub _addArtworkTags {
	my ($class, $s, $tags) = @_;

	# Standard picture block, try to find the front cover first
	if ( $tags->{ALLPICTURES} ) {
		my @allpics = sort { $a->{picture_type} <=> $b->{picture_type} } 
				@{ $tags->{ALLPICTURES} };
				
		if ( my @frontcover = grep ($_->{picture_type} == 3,@allpics)) {
			# in case of many type 3 (front cover) just use the first one
			$tags->{ARTWORK} = $frontcover[0]->{image_data};
		} else {
			# fall back to use lowest type image found
			$tags->{ARTWORK} = $allpics[0]->{image_data};
		}
		
	}

	# As seen in J.River Media Center FLAC files.
	elsif ( $tags->{COVERART} ) {
		$tags->{ARTWORK} = eval { decode_base64( delete $tags->{COVERART} ) };
	}

	# Escient artwork app block
	elsif ( $tags->{APPLICATION} && $tags->{APPLICATION}->{$ESCIENT_ARTWORK} ) {
		my $artwork = $tags->{APPLICATION}->{$ESCIENT_ARTWORK};
		if ( substr($artwork, 0, 4, '') eq 'PIC1' ) {
			$tags->{ARTWORK} = $artwork;
		}
	}
	
	# Flag if we have embedded cover art
	if ( $tags->{ARTWORK} ) {
		if ( $ENV{AUDIO_SCAN_NO_ARTWORK} ) {
			# In 'no artwork' mode, ARTWORK is the length
			$tags->{COVER_LENGTH} = $tags->{ARTWORK};
		}
		else {
			$tags->{COVER_LENGTH} = length( $tags->{ARTWORK} );
		}
	}

	return $tags;
}

sub _getSubFileTags {
	my ( $class, $s, $tracks ) = @_;

	my $items  = 0;

	# There is no official standard for multi-song metadata in a flac file
	# so we try a few different approaches ordered from most useful to least
	#
	# as new methods are found in the wild, they can be added here. when
	# a de-facto standard emerges, unused ones can be dropped.

	# parse embedded xml metadata
	$items = $class->_getXMLTags($s, $tracks);
	return $items if $items > 0;

	# look for numbered vorbis comments
	$items = $class->_getNumberedVCs($s, $tracks);
	return $items if $items > 0;

	# parse cddb style metadata
	$items = $class->_getCDDBTags($s, $tracks);
	return $items if $items > 0;

	# parse cuesheet stuffed into a vorbis comment
	$items = $class->_getCUEinVCs($s, $tracks);
	return $items if $items > 0;

	# try parsing stacked vorbis comments
	$items = $class->_getStackedVCs($s, $tracks);
	return $items if $items > 0;
	
	# This won't yield good results - but without it, we regress from 6.0.2
	my $tags = $class->_getStandardTag($s);

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

	return 0;
}

sub _getXMLTags {
	my ($class, $s, $tracks) = @_;

	# parse xml based metadata (musicbrainz rdf for example)
	# retrieve the xml content from the flac
	my $xml = $s->{tags}->{APPLICATION}->{$PEEM} || return 0;

	# TODO: parse this using the same xml modules Logitech Media Server uses to parse iTunes
	# even better, use RDF::Simple::Parser

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

	$class->_addInfoTags($s, $defaultTags);

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

		my $message = "    ARTISTID: $artistid" if $log->is_debug;

		if ($artistSegment =~ m|<dc:title>(.+)</dc:title>|s) {

			$artistHash->{$artistid}->{'ARTIST'} = $1;

			$message .= " ARTIST: " . $artistHash->{$artistid}->{'ARTIST'} if $log->is_debug;
		}

		if ($artistSegment =~ m|<mm:sortName>(.+)</mm:sortName>|s) {

			$artistHash->{$artistid}->{'ARTISTSORT'} = $1;
		}

		main::DEBUGLOG && $log->is_debug && $log->debug($message);
	}

	# $tracks is keyed to the cuesheet TRACK number, which is sequential
	# in some cases, that may not match the tracks official TRACKNUM
	my $cuesheetTrack = 0;

	for my $album (@albumList) {

		my $tracknumber = 0;

		main::DEBUGLOG && $log->is_debug && $log->debug("    ALBUM: " . $albumHash->{$album}->{'ALBUM'});

		for my $track (@{$albumHash->{$album}->{'TRACKLIST'}}) {

			my $tempTags = {};

			$cuesheetTrack++;
			$tracknumber++;

			if (!exists $tracks->{$cuesheetTrack}) {
				next;
			}

			main::DEBUGLOG && $log->is_debug && $log->debug("    processing track $cuesheetTrack -- $track");

			$tracks->{$cuesheetTrack}->{'TRACKNUM'} = $tracknumber;

			main::DEBUGLOG && $log->is_debug && $log->debug("    TRACKNUM: $tracknumber");

			%{$tracks->{$cuesheetTrack}} = (%{$tracks->{$cuesheetTrack}}, %{$albumHash->{$album}});

			# now process track info
			if ($xml =~ m|<mm:Track\s+rdf:about="$track">(.+?)</mm:Track>|s) {

				my $trackSegment = $1;
				if ($trackSegment =~ m|<dc:title>(.+?)</dc:title>|s) {

					$tracks->{$cuesheetTrack}->{'TITLE'} = $1;

					main::DEBUGLOG && $log->is_debug && $log->debug("    TITLE: " . $tracks->{$cuesheetTrack}->{'TITLE'});
				}

				if ($trackSegment =~ m|<dc:creator rdf:resource="([^"]+)"/>|s) { #"

					%{$tracks->{$cuesheetTrack}} = (%{$tracks->{$cuesheetTrack}}, %{$artistHash->{$1}});

					main::DEBUGLOG && $log->is_debug && $log->debug("    ARTIST: " . $tracks->{$cuesheetTrack}->{'ARTIST'});
				}
			}

			%{$tracks->{$cuesheetTrack}} = (%{$defaultTags}, %{$tracks->{$cuesheetTrack}});

			$class->_doTagMapping($tracks->{$cuesheetTrack});
		}
	}

	return $cuesheetTrack;
}

sub _getNumberedVCs {
	my ($class, $s, $tracks) = @_;
	
	my $isDebug = $log->is_debug;

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
	my $tags = $s->{tags};

	# grab the cuesheet for reference
	my $cuesheet = $tags->{CUESHEET_BLOCK};

	# look for a number of parenthetical TITLE keys that matches
	# the number of tracks in the cuesheet
	my $titletags = 0;
	my $cuetracks = 0;

	# to avoid conflicting with actual key characters,
	# we allow a few different options for bracketing the track number
	# allowed bracket types currently are () [] {} <>

	# we're playing a bit fast and loose here, we really should make sure
	# the same bracket types are used througout, not mixed and matched.
	for my $tag ( keys %{$tags} ) {
		$titletags++ if $tag =~ /^\s*TITLE\s*[\(\[\{\<]\d+[\)\]\}\>]$/i;
	}

	if ($titletags == 0) {
		return 0;
	}

	for my $track (@$cuesheet) {
		$cuetracks++ if $track =~ /^\s*TRACK/i;
	}

	if ($titletags != $cuetracks) {

		logError("This file has tags for $titletags tracks but the cuesheet has $cuetracks tracks");

		return 0;
	}

	# ok, let's see which tags apply to us
	my $defaultTags = {};

	$class->_addInfoTags($s, $defaultTags);

	while ( my ($tkey, $value) = each %{$tags} ) {

		# Match track number
		my $group;

		if ($tkey =~ /^(.+)\s*[\(\[\{\<](\d+)[\)\]\}\>]$/) {
			$tkey = $1;
			$group = $2 + 0;

			main::DEBUGLOG && $isDebug && $log->debug("grouped $tkey for track $group");
		}

		if (defined $group) {
			$tracks->{$group}->{$tkey} = $value;
		} else {
			$defaultTags->{$tkey} = $value;
		}
	}

	# merge in the global tags
	for (my $num = 1; $num <= $titletags; $num++) {

		%{$tracks->{$num}} = (%{$defaultTags}, %{$tracks->{$num}});

		$class->_doTagMapping($tracks->{$num});

		$tracks->{$num}->{TRACKNUM} = $num unless exists $tracks->{$num}->{TRACKNUM};
	}

	return $titletags;
}

sub _getCDDBTags {
	my ($class, $s, $tracks) = @_;
	
	my $isDebug = $log->is_debug;

	my $items = 0;

	# parse cddb based metadata (foobar2000 does this, among others)
	# it's rather crude, but probably the most widely used currently.

	# TODO: detect various artist entries that reverse title and artist
	# this is non-trivial to do automatically, so I'm open to suggestions
	# currently we just expect you to have fairly clean tags.
	my $order = 'standard';

	my $tags  = $s->{tags} || {};

	# Detect CDDB style tags by presence of DTITLE, or return.
	if (!defined $tags->{'DTITLE'}) {
		return 0;
	}

	if ($tags->{'DTITLE'} =~ m|^(.+)\s*/\s*(.+)$|) {

		$tags->{'ARTIST'} = $1;
		$tags->{'ALBUM'}  = $2;

		delete $tags->{'DTITLE'};

		$isDebug && $log->debug("    ARTIST: $tags->{'ARTIST'}");
		$isDebug && $log->debug("    ALBUM: $tags->{'ALBUM'}");
	}

	if (exists $tags->{'DGENRE'}) {

		$tags->{'GENRE'} = $tags->{'DGENRE'};
		delete $tags->{'DGENRE'};

		$isDebug && $log->debug("    GENRE: $tags->{'GENRE'}");
	}

	if (exists $tags->{'DYEAR'}) {

		$tags->{'YEAR'} = $tags->{'DYEAR'};
		delete $tags->{'DYEAR'};

		$isDebug && $log->debug("    YEAR: $tags->{'YEAR'}");
	}

	# grab the cuesheet and process the individual tracks
	for my $key (keys(%$tags)) {

		if ($key =~ /TTITLE(\d+)/) {
			my $tracknum = $1;

			if ($tags->{$key} =~ m|^(.*\S)\s+/\s+(.+)$|) {
				
				if ($order eq "standard") {
					$tracks->{$tracknum}->{'ARTIST'} = $1;
					$tracks->{$tracknum}->{'TITLE'} = $2;
				} else {
					$tracks->{$tracknum}->{'ARTIST'} = $2;
					$tracks->{$tracknum}->{'TITLE'} = $1;
				}

				$isDebug && $log->debug("    ARTIST: $tracks->{$tracknum}->{'ARTIST'}");

			} else {

				$tracks->{$tracknum}->{'TITLE'} = $tags->{$key};
			}


			$tracks->{$tracknum}->{'TRACKNUM'} = $tracknum;

			$isDebug && $log->debug("    TITLE: $tracks->{$tracknum}->{'TITLE'}");
			$isDebug && $log->debug("    TRACKNUM: $tracks->{$tracknum}->{'TRACKNUM'}");

			delete $tags->{$key};

			$items++;
		}
	}

	$class->_addInfoTags($s, $tags);

	# merge in the global tags
	for my $key (keys %$tracks) {

		%{$tracks->{$key}} = (%{$tags}, %{$tracks->{$key}});

		$class->_doTagMapping($tracks->{$key});
	}

	return $items;
}

sub _getCUEinVCs {
	my ($class, $s, $tracks) = @_;

	my $items = 0;
	
	# foobar2000 alternately can stuff an entire cuesheet, along with
	# the CDTEXT hack for storing metadata, into a vorbis comment tag.

	# TODO: we really should sanity check that this cuesheet matches the
	# cuesheet we pulled from the vorbis file.

	my $tags = $s->{tags} || {};
	
	return 0 unless exists $tags->{CUESHEET};

	my @cuesheet = split(/\s*\n/, $tags->{'CUESHEET'});
	
	push @cuesheet, "    REM END " . $tags->{'SECS'};

	# we don't have a proper dir to send parseCUE(), but we already have urls,
	# so we can just fake it. Tell parseCUE that we're an embedded cue sheet
	my $metadata = Slim::Formats::Playlists::CUE->parse(\@cuesheet, "/BOGUS/PATH/", 1);

	# grab file info tags
	# don't pass $metadata through addInfoTags() or it'll decodeUTF8 too many times
	my $infoTags = {};

	$class->_addInfoTags($s, $infoTags);

	# merge the existing track data and cuesheet metadata
	for my $key (keys %$tracks) {

		if (!exists $metadata->{$key}) {

			logWarning("No metadata found for track $tracks->{$key}->{'URI'}");

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
	my ($class, $s, $tracks) = @_;

	my $items  = 0;

	# XXX: can't support this using Audio::Scan, this is a stupid tag scheme anyway!
	return 0;

=pod
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

			main::DEBUGLOG && logger('formats.playlists')->debug("    $tkey: $value");
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
=cut
}

=head2 findFrameBoundaries( $fh, $offset, $time )

Returns offset to audio frame containing $time.

The only caller is L<Slim::Player::Source> at this time.

=cut

sub findFrameBoundaries {
	my ( $class, $fh, $offset, $time ) = @_;

	if ( !defined $fh || !defined $time ) {
		return 0;
	}
	
	return Audio::Scan->find_frame_fh( flac => $fh, int($time * 1000) );
}

=head2 scanBitrate( $fh, $url )

Intended to scan the bitrate of a remote stream, although for FLAC this data
is not accurate, but we can get the duration of the remote file from the header,
so we use this to set the track duaration value.

=cut

sub scanBitrate {
	my ( $class, $fh, $url ) = @_;
	
	seek $fh, 0, 0;
	
	my $s = Audio::Scan->scan_fh( flac => $fh );
	
	my $info = $s->{info};
	
	if ( !$info->{song_length_ms} ) {
		return (-1, undef);
	}

	# The bitrate from parsing a short FLAC header is wrong, but we can get the
	# correct track length from song_length_ms
	my $secs = $info->{song_length_ms} / 1000;
	if ( $secs ) {
		main::DEBUGLOG && logger('scan.scanner')->debug("Read duration from stream: $secs seconds");

		Slim::Music::Info::setDuration( $url, $secs );
	}

	# FLAC bitrate is not accurate with a small header file, so don't bother
	return (-1, undef);
}

sub canSeek { 1 }

=head1 SEE ALSO

L<Slim::Formats>

L<Slim::Formats::Playlists::CUE>

L<Slim::Player::Source>

=cut

1;
