package Slim::Formats::Playlists::M3U;

# $Id$

# SlimServer Copyright (c) 2001-2007 Logitech.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Formats::Playlists::Base);

use HTML::Entities;
use Scalar::Util qw(blessed);
use Socket qw(:crlf);

use Slim::Music::Info;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Unicode;

my $log = logger('formats.playlists');

sub read {
	my ($class, $file, $baseDir, $url) = @_;

	my @items  = ();
	my ($secs, $artist, $album, $title);
	my $foundBOM = 0;

	$log->info("Parsing M3U: $url");

	while (my $entry = <$file>) {

		chomp($entry);

		# strip carriage return from dos playlists
		$entry =~ s/\cM//g;  

		# strip whitespace from beginning and end
		$entry =~ s/^\s*//; 
		$entry =~ s/\s*$//; 
		
		# decode any HTML entities in-place
		HTML::Entities::decode_entities($entry);

		# Guess the encoding of each line in the file. Bug 1876
		# includes a playlist that has latin1 titles, and utf8 paths.
		my $enc = Slim::Utils::Unicode::encodingFromString($entry);

		# Only strip the BOM off of UTF-8 encoded bytes. Encode will
		# handle UTF-16
		if (!$foundBOM && $enc eq 'utf8') {

			$entry = Slim::Utils::Unicode::stripBOM($entry);
			$foundBOM = 1;
		}

		$entry = Slim::Utils::Unicode::utf8decode_guess($entry, $enc);

		$log->debug("  entry from file: $entry");

		if ($entry =~ /^#EXTINF\:(.*?),<(.*?)> - <(.*?)> - <(.*?)>/) {

			$secs   = $1;
			$artist = $2;
			$album  = $3;
			$title  = $4;

			$log->debug("  found secs: $secs, title: $title, artist: $artist, album: $album");

		} elsif ($entry =~ /^#EXTINF:(.*?),(.*)$/) {

			$secs  = $1;
			$title = $2;	

			$log->debug("  found secs: $secs, title: $title");
		}

		next if $entry =~ /^#/;
		next if $entry =~ /#CURTRACK/;
		next if $entry eq "";

		$entry =~ s|$LF||g;
		$entry = Slim::Utils::Unicode::utf8encode_locale($entry);	
		$entry = Slim::Utils::Misc::fixPath($entry, $baseDir);

		if ($class->playlistEntryIsValid($entry, $url)) {

			$log->debug("    entry: $entry");

			push @items, $class->_updateMetaData( $entry, {
				'TITLE'  => $title,
				'ALBUM'  => $album,
				'ARTIST' => $artist,
				'SECS'   => ( defined $secs && $secs > 0 ) ? $secs : undef,
			} );

			# reset the title
			$title = undef;
		}
	}

	if ( $log->is_info ) {
		$log->info("Parsed " . scalar(@items) . " items in playlist");
	}

	close($file);

	return @items;
}

sub readCurTrackForM3U {
	my $class = shift;
	my $path  = shift;

	# do nothing to the index if we can't open the list
	open(FH, $path) || return 0;
		
	# retrieve comment with track number in it
	my $line = <FH>;

	close(FH);
 
	if ($line =~ /#CURTRACK (\d+)$/) {

		$log->info("Found track: $1");

		return $1;
	}

	return 0;
}

sub writeCurTrackForM3U {
	my $class = shift;
	my $path  = shift || return 0;
	my $track = shift || 0;

	$log->info("Writing out: $path");

	# do nothing to the index if we can't open the list
	open(IN, $path) || return 0;
	open(OUT, ">$path.tmp") || return 0;
		
	while (my $line = <IN>) {

		if ($line =~ /#CURTRACK (\d+)$/) {

			$line =~ s/(#CURTRACK) (\d+)$/$1 $track/;
		}

		print OUT $line;
	}

	close(IN);
	close(OUT);

	if (-w $path) {

		rename("$path.tmp", $path);
	} else {
		unlink("$path.tmp");
	}
}

sub write {
	my $class        = shift;
	my $listref      = shift;
	my $playlistname = shift;
	my $filename     = shift;
	my $addTitles    = shift;
	my $resumetrack  = shift;

	$log->info("Writing out: $filename");

	my $string = '';
	my $output = $class->_filehandleFromNameOrString($filename, \$string) || return;

	print $output "#CURTRACK $resumetrack\n" if defined($resumetrack);
	print $output "#EXTM3U\n" if $addTitles;

	for my $item (@{$listref}) {

		my $track = Slim::Schema->rs('Track')->objectForUrl($item);
	
		if (!blessed($track) || !$track->can('title')) {
	
			logError("Couldn't retrieve objectForUrl: [$item] - skipping!");
			next;
		};

		if ($addTitles) {
			
			my $title = Slim::Utils::Unicode::utf8decode( $track->title );

			if ($title) {
				print $output "#EXTINF:-1,$title\n";
			}
		}

		# XXX - we still have a problem where there can be decomposed
		# unicode characters. I don't know how this happens - it's
		# coming from the filesystem.
		my $path = Slim::Utils::Unicode::utf8decode( $class->_pathForItem($track->url, 1) );

		print $output "$path\n";
	}

	close $output if $filename;

	return $string;
}

1;

__END__
