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

use Slim::Formats;
use Slim::Music::Info;
use Slim::Utils::Misc;

sub registerParser {
	my ($class, $type, $playlistClass) = @_;

	$::d_parse && msg("registerParser: Registering external parser for type $type - class: $playlistClass\n");

	$Slim::Music::Info::tagClasses{$type} = $playlistClass;
}

sub parseList {
	my $class = shift;
	my $url   = shift;
	my $fh    = shift;
	my $base  = shift;

	# Allow the caller to pass a content type
	my $type = shift || Slim::Music::Info::contentType($url);

	# We want the real type from a internal playlist.
	if ($type eq 'ssp') {
		$type = Slim::Music::Info::typeFromSuffix($url);
	}

	$::d_parse && msg("parseList (type: $type): $url\n");

	my @results = ();
	my $closeFH = 0;

	if ( !Slim::Music::Info::isRemoteURL($url) ) {
		
		# If a filehandle wasn't passed in, open it.
		if (!ref($fh) || !fileno($fh)) {

			my $path = $url;

			if (Slim::Music::Info::isFileURL($url)) {

				$path = Slim::Utils::Misc::pathFromFileURL($url);
			}

			$fh = FileHandle->new($path);

			$closeFH = 1;
		}
	}

	if (my $playlistClass = Slim::Formats->classForFormat($type)) {

		# Dynamically load the module in.
		Slim::Formats->loadTagFormatForType($type);

		@results = eval { $playlistClass->read($fh, $base, $url) };

		if ($@) {

			errorMsg("parseList: While running \$playlistClass->read()\n");
			errorMsg("$@\n");
		}
	}
	else {
		# Try to guess what kind of playlist it is		
		$::d_parse && msg("parseList: Unknown content type $type, trying to guess\n");

		my $content = read_file($fh);

		# look for known strings that would indicate a certain content-type
		if ( $content =~ /\[playlist\]/i ) {

			$type = 'pls';

		} elsif ( $content =~ /(?:asx|\[Reference\])/i ) {

			$type = 'asx';
		}

		if ( $type =~ /(?:asx|pls)/ ) {
			# Re-parse using known content-type
			$fh->seek(0);

			return $class->parseList( $url, $fh, $base, $type );
		}

		# no luck there, so just use URI::Find to look for URLs
		$::d_parse && msg("parseList: Couldn't guess, so trying to simply read all URLs from content\n");

		my $finder = URI::Find->new( sub {
			my ( $uri, $orig_uri ) = @_;
			push @results, $orig_uri;
		} );

		$finder->find(\$content);
	}

	# Don't leak
	if ($closeFH) {
		close($fh);
	}

	return wantarray() ? @results : $results[0];
}

sub writeList {
	my ($class, $listRef, $playlistName, $fullDir) = @_;

	my $type    = Slim::Music::Info::typeFromSuffix($fullDir);
	my @results = ();

	if (my $playlistClass = Slim::Formats->classForFormat($type)) {

		# Dynamically load the module in.
		Slim::Formats->loadTagFormatForType($type);

		@results = eval {

			$playlistClass->write($listRef, $playlistName, Slim::Utils::Misc::pathFromFileURL($fullDir), 1);
		};

		if ($@) {

			errorMsg("writeList: While running \$playlistClass->read()\n");
			errorMsg("$@\n");
		}
	}

	return wantarray() ? @results : $results[0];
}

1;

__END__
