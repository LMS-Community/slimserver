package Slim::Music::Artwork;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use Path::Class;
use Scalar::Util qw(blessed);

use Slim::Music::Info;
use Slim::Music::TitleFormatter;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

# Global caches:
my $artworkDir   = '';

# Public class methods
sub getImageContentAndType {
	my $class = shift;
	my $path  = shift;

	use bytes;
	my $content;

	if (open (TEMPLATE, $path)) { 
		local $/ = undef;
		binmode(TEMPLATE);
		$content = <TEMPLATE>;
		close TEMPLATE;
	}

	if (defined($content) && length($content)) {

		return ($content, $class->_imageContentType(\$content));
	}

	$::d_artwork && msg("getImageContent: Image File empty or couldn't read: $path : $!\n");

	return undef;
}

sub readCoverArt {
	my $class = shift;
	my $track = shift;  
	my $image = shift || 'cover';

	my $url  = Slim::Utils::Misc::stripAnchorFromURL($track->url);
	my $file = $track->path;

	# Try to read a cover image from the tags first.
	my ($body, $contentType, $path) = $class->_readCoverArtTags($track, $file);

	# Nothing there? Look on the file system.
	if (!defined $body) {
		($body, $contentType, $path) = $class->_readCoverArtFiles($track, $file, $image);
	}

	return ($body, $contentType, $path);
}

# Private class methods
sub _imageContentType {
	my $class = shift;
	my $body  = shift;

	use bytes;

	# iTunes sometimes puts PNG images in and says they are jpeg
	if ($$body =~ /^\x89PNG\x0d\x0a\x1a\x0a/) {

		return 'image/png';

	} elsif ($$body =~ /^\xff\xd8\xff\xe0..JFIF/) {

		return 'image/jpeg';
	}

	return 'application/octet-stream';
}

sub _readCoverArtTags {
	my $class = shift;
	my $track = shift;
	my $file  = shift;

	my ($body, $contentType);
	
	$::d_artwork && msg("readCoverArtTags: Looking for a covert art image in the tags of: [$file]\n");

	if (blessed($track) && $track->can('audio') && $track->audio) {

		if (isMP3($track) || isWav($track) || isAIFF($track)) {

			Slim::Music::Info::loadTagFormatForType('mp3');

			$body = Slim::Formats::MP3::getCoverArt($file);

		} elsif (isMOV($track)) {

			Slim::Music::Info::loadTagFormatForType('mov');

			$body = Slim::Formats::Movie::getCoverArt($file);

		} elsif (isFLAC($track)) {

			Slim::Music::Info::loadTagFormatForType('flc');

			$body = Slim::Formats::FLAC::getCoverArt($file);
		}

		if ($body) {

			$::d_artwork && msg("found image in $file of length " . length($body) . " bytes \n");

			$contentType = $class->_imageContentType(\$body);

			$::d_info && msg( "found $contentType image\n");

			# jpeg images must start with ff d8 ff e0 or they ain't jpeg, sometimes there is junk before.
			if ($contentType && $contentType eq 'image/jpeg') {

				$body =~ s/^.*?\xff\xd8\xff\xe0/\xff\xd8\xff\xe0/;
			}

			return ($body, $contentType, 1);
		}

 	} else {

		$::d_info && msg("readCoverArtTags: Not file we can extract artwork from. Skipping: $file\n");
	}

	return undef;
}

sub _readCoverArtFiles {
	my $class = shift;
	my $track = shift;
	my $path  = shift;
	my $image = shift || 'cover';

	my @filestotry = ();
	my @names      = qw(cover thumb album albumartsmall folder);
	my @ext        = qw(jpg gif);
	my $artwork    = undef;

	my $file       = file($path);
	my $parentDir  = $file->dir;

	$::d_artwork && msg("Looking for image files in $parentDir\n");

	my %nameslist = map { $_ => [do { my $t = $_; map { "$t.$_" } @ext }] } @names;
	
	if ($image eq 'thumb') {

		# these seem to be in a particular order - not sure if that means anything.
		@filestotry = map { @{$nameslist{$_}} } qw(thumb albumartsmall cover folder album);

		$artwork = Slim::Utils::Prefs::get('coverThumb');

	} else {

		# these seem to be in a particular order - not sure if that means anything.
		@filestotry = map { @{$nameslist{$_}} } qw(cover folder album thumb albumartsmall);

		$artwork = Slim::Utils::Prefs::get('coverArt');
	}

	# If the user has specified a pattern to match the artwork on, we need
	# to generate that pattern. This is nasty.
	if (defined($artwork) && $artwork =~ /^%(.*?)(\..*?){0,1}$/) {

		my $suffix = $2 ? $2 : ".jpg";

		$artwork = Slim::Music::TitleFormatter::infoFormat(
			Slim::Utils::Misc::fileURLFromPath($track->url), $1
		)."$suffix";

		$::d_artwork && msgf(
			"Variable %s: %s from %s\n", ($image eq 'thumb' ? 'Thumbnail' : 'Cover'), $artwork, $1
		);

		my $artPath = $parentDir->file($artwork);

		my ($body, $contentType) = $class->getImageContentAndType($artPath);

		my $artDir  = dir(Slim::Utils::Prefs::get('artfolder'));

		if (!$body && defined $artDir) {

			$artPath = $artDir->file($artwork);

			($body, $contentType) = $class->getImageContentAndType($artPath);
		}

		if ($body && $contentType) {

			$::d_artwork && msg("Found $image file: $artPath\n");

			return ($body, $contentType, $artPath);
		}

	} elsif (defined $artwork) {

		unshift @filestotry, $artwork;
	}

	if (defined $artworkDir && $artworkDir eq $parentDir) {

		if (exists $lastFile{$image} && $lastFile{$image} != 1) {

			$::d_artwork && msg("Using existing $image: $lastFile{$image}\n");

			my ($body, $contentType) = $class->getImageContentAndType($lastFile{$image});

			return ($body, $contentType, $lastFile{$image});

		} elsif (exists $lastFile{$image}) {

			$::d_artwork && msg("No $image in $artworkDir\n");

			return undef;
		}

	} else {

		$artworkDir = $parentDir;
		%lastFile = ();
	}

	for my $file (@filestotry) {

		$file = $parentDir->file($file);

		next unless -r $file;

		my ($body, $contentType) = $class->getImageContentAndType($file);

		if ($body && $contentType) {

			$::d_artwork && msg("Found $image file: $file\n");

			return ($body, $contentType, $file);

		} else {

			$lastFile{$image} = 1;
		}
	}

	return undef;
}

1;
