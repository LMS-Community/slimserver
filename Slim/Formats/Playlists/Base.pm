package Slim::Formats::Playlists::Base;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License, version 2.

use strict;
use FileHandle ();
use IO::String;
use Scalar::Util qw(blessed);

use Slim::Music::Info;
use Slim::Utils::Log;
use Slim::Utils::Misc;

sub _updateMetaData {
	my $class    = shift;
	my $entry    = shift;
	my $metadata = shift;
	my $playlistUrl = shift;

	my $attributes = {};
	
	if ( Slim::Music::Info::isVolatile($playlistUrl) ) {
		$entry =~ s/^file/tmp/;
	}

	# Update title MetaData only if its not a local file with Title information already cached.
	if ($metadata && Slim::Music::Info::isRemoteURL($entry)) {

		my $track = Slim::Schema->objectForUrl($entry);

		if ((blessed($track) && $track->can('title')) || !blessed($track)) {

			$attributes = $metadata;
		}
	}
	
	# Bug 6294, only updateOrCreate the track if the track
	# doesn't already exist in the database.  $attributes will be
	# set if it's a remote playlist and we want to update the metadata
	# even if the track already exists.

	my $track;

	if ( !scalar keys %{$attributes} ) {
		$track = Slim::Schema->objectForUrl($entry);
	}
	
	if ( !defined $track ) {
		$track = Slim::Schema->updateOrCreate( {
			'url'        => $entry,
			'attributes' => $attributes,
			'readTags'   => 1,
		} );
	}
	
	return $track;
}

sub _pathForItem {
	my $class = shift;
	my $item  = shift;

	if (Slim::Music::Info::isFileURL($item) && !Slim::Music::Info::isFragment($item)) {
		return Slim::Utils::Misc::pathFromFileURL($item);
	}

	return $item;
}

sub _filehandleFromNameOrString {
	my $class     = shift;
	my $filename  = shift;
	my $outstring = shift;

	my $output;

	if ($filename) {

		$output = FileHandle->new($filename, "w") || do {

			logError("Could't open $filename for writing.");
			return undef;
		};

		# Always write out in UTF-8 with a BOM.
		if ($] > 5.007) {

			binmode($output, ":raw");

			print $output $File::BOM::enc2bom{'utf8'};

			binmode($output, ":encoding(utf8)");
		}

	} else {

		$output = IO::String->new($$outstring);
	}

	return $output;
}

sub playlistEntryIsValid {
	my ($class, $entry, $url) = @_;

	if (Slim::Music::Info::isRemoteURL($entry) || Slim::Music::Info::isRemoteURL($url)) {

		return 1;
	}

	# Be verbose to the user - this will let them fix their files / playlists.
	if ($entry eq $url) {

		logWarning("Found self-referencing playlist in:\n\t$entry == $url\n\t - skipping!");
		return 0;
	}

	if (!Slim::Music::Info::isFile($entry)) {

		logWarning("$entry found in playlist:\n\t$url doesn't exist on disk - skipping!");
		return 0;
	}

	return 1;
}

1;

__END__
