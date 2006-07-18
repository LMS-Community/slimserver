package Slim::Formats::Playlists;

# $Id$

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License, version 2.

use strict;
use FileHandle;
use File::Slurp;
use IO::String;
use Scalar::Util qw(blessed);
use URI::Find;

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
	else {
		# Try to guess what kind of playlist it is		
		$::d_parse && msg("parseList: Unknown content type $type, trying to guess\n");
		
		my $content = read_file($file);
		
		# look for known strings that would indicate a certain content-type
		if ( $content =~ /\[playlist\]/i ) {
			$type = 'pls';
		}
		elsif ( $content =~ /(?:asx|\[Reference\])/i ) {
			$type = 'asx';
		}
		
		if ( $type =~ /(?:asx|pls)/ ) {
			# Re-parse using known content-type
			$file->seek(0);
			return $class->parseList( $list, $file, $base, $type );
		}
		
		# no luck there, so just use URI::Find to look for URLs
		
		$::d_parse && msg("parseList: Couldn't guess, so trying to simply read all URLs from content\n");
		
		my $finder = URI::Find->new( sub {
			my ( $uri, $orig_uri ) = @_;
			push @results, $orig_uri;
		} );
		$finder->find(\$content);
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
