package Slim::Formats::Playlists;

# $Id$

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License, version 2.

use strict;
use FileHandle;
use IO::String;
use Scalar::Util qw(blessed);

use Slim::Music::Info;
use Slim::Utils::Misc;

sub registerParser {
	my ($class, $type, $playlistClass) = @_;

	$::d_parse && msg("registerParser: Registering external parser for type $type - class: $playlistClass\n");

	$Slim::Music::Info::tagClasses{$type} = $playlistClass;
}

sub parseList {
	my $class = shift;
	my $list  = shift;
	my $file  = shift;
	my $base  = shift;

	# Allow the caller to pass a content type
	my $type = shift || Slim::Music::Info::contentType($list);

	# We want the real type from a internal playlist.
	if ($type eq 'ssp') {
		$type = Slim::Music::Info::typeFromSuffix($list);
	}

	$::d_parse && msg("parseList (type: $type): $list\n");

	my @results = ();

	if (my $playlistClass = Slim::Music::Info::classForFormat($type)) {

		# Dynamically load the module in.
		Slim::Music::Info::loadTagFormatForType($type);

		@results = eval { $playlistClass->read($file, $base, $list) };

		if ($@) {

			errorMsg("parseList: While running $playlistClass->read()\n");
			errorMsg("$@\n");
		}
	}

	return wantarray() ? @results : $results[0];
}

sub writeList {
	my ($class, $listRef, $playlistName, $fullDir) = @_;

	my $type    = Slim::Music::Info::typeFromSuffix($fullDir);
	my @results = ();

	if (my $playlistClass = Slim::Music::Info::classForFormat($type)) {

		# Dynamically load the module in.
		Slim::Music::Info::loadTagFormatForType($type);

		@results = eval {

			$playlistClass->write($listRef, $playlistName, Slim::Utils::Misc::pathFromFileURL($fullDir), 1);
		};

		if ($@) {

			errorMsg("writeList: While running $playlistClass->read()\n");
			errorMsg("$@\n");
		}
	}

	return wantarray() ? @results : $results[0];
}

1;

__END__
