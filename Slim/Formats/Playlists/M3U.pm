package Slim::Formats::Playlists::M3U;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
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
use Slim::Utils::Prefs;
use Slim::Utils::Unicode;

my $log   = logger('formats.playlists');
my $prefs = preferences('server');

sub read {
	my ($class, $file, $baseDir, $url) = @_;

	my @items  = ();
	my ($secs, $artist, $album, $title, $trackurl);
	my $foundBOM = 0;
	my $fh;
	my $mediadirs;

	if (defined $file && ref $file) {
		$fh = $file;	# filehandle passed
	} else {
		if (!defined $file) {
			$file = Slim::Utils::Misc::pathFromFileURL($url);
			if (!$file) {
				$log->warn("Cannot get filepath from $url");
				return @items;
			}
		}
		open($fh, $file) || do {
			$log->warn("Cannot open $file: $!");
			return @items;
		};
	}
	
	main::INFOLOG && $log->info("Parsing M3U: $url");

	while (my $entry = <$fh>) {

		chomp($entry);

		# strip carriage return from dos playlists
		$entry =~ s/\cM//g;  

		# strip whitespace from beginning and end
		$entry =~ s/^\s*//; 
		$entry =~ s/\s*$//; 
		
		# If the line is not a filename (starts with #), handle encoding
		# If it's a filename, accept it as raw bytes
		if ( $entry =~ /^#/ ) {
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
		}

		main::DEBUGLOG && $log->debug("  entry from file: $entry");

		if ($entry =~ /^#EXTINF\:(.*?),<(.*?)> - <(.*?)> - <(.*?)>/) {

			$secs   = $1;
			$artist = $2;
			$album  = $3;
			$title  = $4;

			main::DEBUGLOG && $log->debug("  found secs: $secs, title: $title, artist: $artist, album: $album");

		}
		elsif ($entry =~ /^#EXTINF:(.*?),(.*)$/) {

			$secs  = $1;
			$title = $2;	

			main::DEBUGLOG && $log->debug("  found secs: $secs, title: $title");
		}
		elsif ( $entry =~ /^#EXTINF:(.*?)$/ ) {
			$title = $1;
			
			main::DEBUGLOG && $log->debug("  found title: $title");
		}

		elsif ( $entry =~ /^#EXTURL:(.*?)$/ ) {
			$trackurl = $1;
			
			main::DEBUGLOG && $log->debug("  found trackurl: $trackurl");
		}

		next if $entry =~ /^#/;
		next if $entry =~ /#CURTRACK/;
		next if $entry eq "";
		
		# if an invalid playlist is downloaded as HTML, ignore it
		last if $entry =~ /^<(?:!DOCTYPE\s*)?html/;
		next if $entry =~ /^</;

		$entry =~ s|$LF||g;

		if (!$trackurl) {

			if (Slim::Music::Info::isRemoteURL($entry)) {
	
				$trackurl = $entry;
	
			} else {
	
				if (main::ISWINDOWS && !Slim::Music::Info::isFileURL($entry)) {
					$entry = Win32::GetANSIPathName($entry);	
				}
				
				$trackurl = Slim::Utils::Misc::fixPath($entry, $baseDir);
			}
		}
		
		if ($class->playlistEntryIsValid($trackurl, $url)) {

			push @items, $class->_item($trackurl, $artist, $album, $title, $secs, $url);

		}
		else {
			# Check if the playlist entry is relative to audiodir
			$mediadirs ||= Slim::Utils::Misc::getAudioDirs();
			
			foreach my $audiodir (@$mediadirs) {
				$trackurl = Slim::Utils::Misc::fixPath($entry, $audiodir);
				
				if ($class->playlistEntryIsValid($trackurl, $url)) {

					push @items, $class->_item($trackurl, $artist, $album, $title, $secs, $url);
					
					last;
				}
			}
		}

		# reset the title
		($secs, $artist, $album, $title, $trackurl) = ();
	}

	if ( main::INFOLOG && $log->is_info ) {
		$log->info("Parsed " . scalar(@items) . " items in playlist");
	}

	close($fh);

	return @items;
}

sub _item {
	my ($class, $trackurl, $artist, $album, $title, $secs, $playlistUrl) = @_;

	main::DEBUGLOG && $log->debug("    valid entry: $trackurl");
	
	return $class->_updateMetaData( $trackurl, {
		'TITLE'  => $title,
		'ALBUM'  => $album,
		'ARTIST' => $artist,
		'SECS'   => ( defined $secs && $secs > 0 ) ? $secs : undef,
	}, $playlistUrl );
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

		main::INFOLOG && $log->info("Found track: $1");

		return $1;
	}

	return 0;
}

sub writeCurTrackForM3U {
	my $class = shift;
	my $path  = shift || return 0;
	my $track = shift || 0;

	main::INFOLOG && $log->info("Writing out: $path");

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

	main::INFOLOG && $log->info("Writing out: $filename");

	my $string = '';
	my $output = $class->_filehandleFromNameOrString($filename, \$string) || return;

	print $output "#CURTRACK $resumetrack\n" if defined($resumetrack);
	print $output "#EXTM3U\n" if $addTitles;

	my $i = 0;
	for my $item (@{$listref}) {

		my $track = Slim::Schema->objectForUrl($item);
	
		if (!blessed($track) || !$track->can('title')) {
	
			logError("Couldn't retrieve objectForUrl: [$item] - skipping!");
			next;
		};
		
		# Bug 16683: put the 'file:///' URL in an extra extension
		print $output "#EXTURL:", $track->url, "\n";

		if ($addTitles) {
			
			my $title = $track->title;
			my $secs = int($track->secs || -1);

			if ($title) {
				print $output "#EXTINF:$secs,$title\n";
			}
		}
		
		my $path = Slim::Utils::Unicode::utf8decode_locale( $class->_pathForItem($track->url) );
		print $output $path, "\n";
		
		main::idleStreams() if ! (++$i % 20);
	}

	close $output if $filename;

	return $string;
}

1;

__END__
