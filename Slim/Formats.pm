package Slim::Formats;

# $Id$

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Class::Data::Inheritable);

use Slim::Music::Info;
use Slim::Utils::Misc;
use Slim::Utils::Unicode;

# Map our tag functions - so they can be dynamically loaded.
our (%tagClasses, %loadedTagClasses);

my $init = 0;

# Internal debug flags (need $::d_info for activation)
# dump tags found/processed
my $_dump_tags = 0;

=head1 NAME

Slim::Formats

=head1 SYNOPSIS

my $tags = Slim::Formats->readTags( $file );

=head1 METHODS

=head2 init()

Initialze the Formats/Metadata reading classes and subsystem.

=cut

sub init {
	my $class = shift;

	if ($init) {
		return 1;
	}

	# Our loader classes for tag formats.
	%tagClasses = (
		'mp3' => 'Slim::Formats::MP3',
		'mp2' => 'Slim::Formats::MP3',
		'ogg' => 'Slim::Formats::Ogg',
		'flc' => 'Slim::Formats::FLAC',
		'wav' => 'Slim::Formats::Wav',
		'aif' => 'Slim::Formats::AIFF',
		'wma' => 'Slim::Formats::WMA',
		'mov' => 'Slim::Formats::Movie',
		'shn' => 'Slim::Formats::Shorten',
		'mpc' => 'Slim::Formats::Musepack',
		'ape' => 'Slim::Formats::APE',

		# Playlist types
		'asx' => 'Slim::Formats::Playlists::ASX',
		'cue' => 'Slim::Formats::Playlists::CUE',
		'm3u' => 'Slim::Formats::Playlists::M3U',
		'pls' => 'Slim::Formats::Playlists::PLS',
		'pod' => 'Slim::Formats::Playlists::XML',
		'wax' => 'Slim::Formats::Playlists::ASX',
		'wpl' => 'Slim::Formats::Playlists::WPL',
		'xml' => 'Slim::Formats::Playlists::XML',
		'xpf' => 'Slim::Formats::Playlists::XSPF',

		# Remote types
		'http' => 'Slim::Formats::HTTP',
		'mms'  => 'Slim::Formats::MMS',
	);

	$init = 1;

	return 1;
}

=head2 loadTagFormatForType( $type )

Dynamically load the class needed to read the passed file type. 

Returns true on success, false on failure.

Example: Slim::Formats->loadTagFormatForType('flc');

=cut

sub loadTagFormatForType {
	my $class = shift;
	my $type  = shift;

	if ($loadedTagClasses{$type}) {
		return 1;
	}

	$class->init;

	$::d_info && msg("Trying to load $tagClasses{$type}\n");

	if (!Slim::bootstrap::tryModuleLoad($tagClasses{$type}) && $@) {

		msg("Couldn't load module: $tagClasses{$type} : [$@]\n");
		bt();
		return 0;

	} else {

		$loadedTagClasses{$type} = 1;
		return 1;
	}
}

=head2 classForFormat( $type )

Returns the class associated with the passed file type.

=cut

sub classForFormat {
	my $class = shift;
	my $type  = shift;

	$class->init;

	return $tagClasses{$type};
}

=head2 readTags( $filename )

Read and return the tags for any file we're handed.

=cut

sub readTags {
	my $class = shift;
	my $file  = shift || return {};

	my ($filepath, $tags, $anchor);

	if (Slim::Music::Info::isFileURL($file)) {
		$filepath = Slim::Utils::Misc::pathFromFileURL($file);
		$anchor   = Slim::Utils::Misc::anchorFromURL($file);
	} else {
		$filepath = $file;
	}

	# Get the type without updating the DB
	my $type   = Slim::Music::Info::typeFromPath($filepath);
	my $remote = Slim::Music::Info::isRemoteURL($file);

	# Only read local audio.
	if (Slim::Music::Info::isSong($file, $type) && !$remote) {

		# Extract tag and audio info per format
		if (my $tagReaderClass = $class->classForFormat($type)) {

			# Dynamically load the module in.
			$class->loadTagFormatForType($type);

			$tags = eval { $tagReaderClass->getTag($filepath, $anchor) };
		}

		if ($@) {
			errorMsg("Slim::Formats::readTags: While trying to ->getTag($filepath) : $@\n");
			bt();
		}

		$::d_info && !defined($tags) && msg("Slim::Formats::readTags: No tags found for $filepath\n");

		# Return early if we have a DRM track
		if ($tags->{'DRM'}) {
			return $tags;
		}

		# Turn the tag SET into DISC and DISCC if it looks like # or #/#
		if ($tags->{'SET'} and $tags->{'SET'} =~ /(\d+)(?:\/(\d+))?/) {

			# Strip leading 0s so that numeric compare at the db level works.
			$tags->{'DISC'}  = int($1);
			$tags->{'DISCC'} = int($2) if defined $2;
		}

		if (!defined $tags->{'TITLE'}) {

			$::d_info && msg("Info: no title found, using plain title for $file\n");
			#$tags->{'TITLE'} = Slim::Music::Info::plainTitle($file, $type);
			Slim::Music::Info::guessTags($file, $type, $tags);
		}

		# fix the genre
		if (defined($tags->{'GENRE'}) && $tags->{'GENRE'} =~ /^\((\d+)\)$/) {

			# some programs (SoundJam) put their genres in as text digits surrounded by parens.
			# in this case, look it up in the table and use the real value...
			if ($INC{'MP3/Info.pm'} && defined($MP3::Info::mp3_genres[$1])) {

				$tags->{'GENRE'} = $MP3::Info::mp3_genres[$1];
			}
		}

		# Mark it as audio in the database.
		if (!defined $tags->{'AUDIO'}) {

			$tags->{'AUDIO'} = 1;
		}

		# Set some defaults for the track if the tag reader didn't pull them.
		for my $key (qw(DRM LOSSLESS)) {

			$tags->{$key} ||= 0;
		}
	}

	# Last resort
	if (!defined $tags->{'TITLE'} || $tags->{'TITLE'} =~ /^\s*$/) {

		$::d_info && msg("Info: no title found, calculating title from url for $file\n");

		$tags->{'TITLE'} = Slim::Music::Info::plainTitle($file, $type);
	}

	# Bug 2996 - check for multiple DISC tags.
	if (ref($tags->{'DISC'}) eq 'ARRAY') {

		$tags->{'DISC'} = $tags->{'DISC'}->[0];
	}

	if (-e $filepath) {
		# cache the file size & date
		($tags->{'FILESIZE'}, $tags->{'TIMESTAMP'}) = (stat($filepath))[7,9];
	}

	# Only set if we couldn't read it from the file.
	$tags->{'CONTENT_TYPE'} ||= $type;

	$::d_info && $_dump_tags && msg("Slim::Formats::readTags(): Report for $file:\n");

	# Bug: 2381 - FooBar2k seems to add UTF8 boms to their values.
	# Bug: 3769 - Strip trailing nulls
	while (my ($tag, $value) = each %{$tags}) {

		if (defined $tags->{$tag}) {

			$tags->{$tag} =~ s/$Slim::Utils::Unicode::bomRE//;
			$tags->{$tag} =~ s/\000$//;
		}
		
		$::d_info && $_dump_tags && $value && msg(". $tag : $value\n");
	}

	return $tags;
}

1;

__END__
