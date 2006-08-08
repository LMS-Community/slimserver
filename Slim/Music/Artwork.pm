package Slim::Music::Artwork;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Basename qw(dirname);
use File::Slurp;
use File::Spec::Functions qw(:ALL);
use Path::Class;
use Scalar::Util qw(blessed);
use Tie::Cache::LRU;

use Slim::Music::Info;
use Slim::Music::TitleFormatter;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Unicode;
use Slim::Utils::OSDetect;

# Global caches:
my $artworkDir   = '';

tie my %lastFile, 'Tie::Cache::LRU', 32;

# Public class methods
sub findArtwork {
	my $class = shift;
	my $track = shift;

	# Only look for track/album combos that don't already have artwork.
	my $cond = {
		'me.audio'      => 1,
		'album.artwork' => { '=' => undef },
	};

	my $attr = {
		'join'     => 'album',
		'group_by' => 'album',
	};

	# If the user passed in a track (dir) object, match on that base directory.
	if (blessed($track) && $track->content_type eq 'dir') {

		$cond->{'me.url'} = { 'like' => sprintf('%s%%', $track->url) };

	} elsif (blessed($track) && $track->audio) {

		$cond->{'me.url'} = { 'like' => sprintf('%s%%', dirname($track->url)) };
	}

	# Find distinct albums to check for artwork.
	my $tracks = Slim::Schema->search('Track', $cond, $attr);

	my $progress = undef;
	my $count    = $tracks->count;

	if ($count) {
		$progress = Slim::Utils::ProgressBar->new({ 'total' => $count });
	}

	while (my $track = $tracks->next) {

		if ($track->coverArt('cover') || $track->coverArt('thumb')) {

			my $album = $track->album;

			$::d_import && !$progress && msgf("Import: Album [%s] has artwork.\n", $album->name);

			$album->artwork($track->id);
			$album->update;
		}

		$progress->update if $progress;
	}

	$progress->final($count) if $progress;

	Slim::Music::Import->endImporter('findArtwork');
}

sub getImageContentAndType {
	my $class = shift;
	my $path  = shift;

	# Bug 3245 - for systems who's locale is not UTF-8 - turn our UTF-8
	# path into the current locale.
	my $locale = Slim::Utils::Unicode::currentLocale();

	if ($locale ne 'utf8') {
		$path = Slim::Utils::Unicode::encode($locale, $path);
	}

	my $content = eval { read_file($path, 'binmode' => ':raw') };

	if (defined($content) && length($content)) {

		return ($content, $class->_imageContentType(\$content));
	}

	$::d_artwork && msg("getImageContent: Image File empty or couldn't read: $path : $! [$@]\n");

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

	} elsif ($$body =~ /^GIF(\d\d)([a-z])/) {

		return 'image/gif';

	} elsif ($$body =~ /^.*?(\xff\xd8\xff)/) {

		my $header = $1;

		# See http://www.obrador.com/essentialjpeg/headerinfo.htm for
		# the JPEG header spec.
		#
		# jpeg images must start with ff d8 or they are not jpeg,
		# the next table will always start with ff as well, so look
		# for that. JFIF is an addition to the standard, we've seen
		# baseline images (bug 3850) without a JFIF header.
		# sometimes there is junk before.
		$$body =~ s/^.*?$header/$header/;

		return 'image/jpeg';

	} elsif ($$body =~ /^BM/) {

		return 'image/bmp';
	}

	return 'application/octet-stream';
}

sub _readCoverArtTags {
	my $class = shift;
	my $track = shift;
	my $file  = shift;

	$::d_artwork && msg("readCoverArtTags: Looking for a cover art image in the tags of: [$file]\n");

	if (blessed($track) && $track->can('audio') && $track->audio) {

		my $ct          = Slim::Schema->contentType($track);
		my $formatClass = Slim::Music::Info::classForFormat($ct);
		my $body        = undef;

		if (Slim::Music::Info::loadTagFormatForType($ct) && $formatClass->can('getCoverArt')) {

			$body = $formatClass->getCoverArt($file);
		}

		if ($body) {

			my $contentType = $class->_imageContentType(\$body);

			$::d_artwork && msgf("readCoverArtTags: Found image of length [%d] bytes with type: [$contentType]\n", length($body));

			return ($body, $contentType, 1);
		}

 	} else {

		$::d_info && msg("readCoverArtTags: Not file we can extract artwork from. Skipping.\n");
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

		if (Slim::Utils::OSDetect::OS() eq 'win') {
			# Remove illegal characters from filename.
			$artwork =~ s/\\|\/|\:|\*|\?|\"|<|>|\|//g;
		}

		my $artPath = $parentDir->file($artwork)->stringify;

		my ($body, $contentType) = $class->getImageContentAndType($artPath);

		my $artDir  = dir(Slim::Utils::Prefs::get('artfolder'));

		if (!$body && defined $artDir) {

			$artPath = $artDir->file($artwork)->stringify;

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

		if (exists $lastFile{$image} && $lastFile{$image} ne 1) {

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

		$file = $parentDir->file($file)->stringify;

		next unless -f $file;

		my ($body, $contentType) = $class->getImageContentAndType($file);

		if ($body && $contentType) {

			$::d_artwork && msg("Found $image file: $file\n");

			$lastFile{$image} = $file;

			return ($body, $contentType, $file);

		} else {

			$lastFile{$image} = 1;
		}
	}

	return undef;
}

1;
