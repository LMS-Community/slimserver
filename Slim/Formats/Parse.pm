package Slim::Formats::Parse;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use FileHandle;
use IO::Socket qw(:crlf);
use IO::String;

use Slim::Utils::Misc;

sub parseList {
	my $list = shift;
	my $file = shift;
	my $base = shift;
	my @items;
	
	if (Slim::Music::Info::isM3U($list)) {
		return M3U($file, $base);
	} elsif (Slim::Music::Info::isPLS($list)) {
		return PLS($file);
	} elsif (Slim::Music::Info::isCUE($list)) {
		return CUE($file, $base);
	}
}

sub _updateMetaData {
	my $entry = shift;
	my $title = shift;

	if (Slim::Music::Info::isCached($entry)) {

		if (!Slim::Music::Info::isKnownType($entry)) {
			$::d_parse && msg("    entry: $entry not known type\n"); 
			Slim::Music::Info::setContentType($entry,'mp3');
		}

	} else {
		Slim::Music::Info::setContentType($entry,'mp3');
	}

	if (defined($title)) {
		Slim::Music::Info::setTitle($entry, $title);
		$title = undef;
	}
}

sub M3U {
	my $m3u    = shift;
	my $m3udir = shift;

	my @items  = ();
	
	$::d_parse && msg("parsing M3U: $m3u\n");
	
	while (my $entry = <$m3u>) {

		chomp($entry);
		# strip carriage return from dos playlists
		$entry =~ s/\cM//g;  

		# strip whitespace from beginning and end
		$entry =~ s/^\s*//; 
		$entry =~ s/\s*$//; 

		$::d_parse && msg("  entry from file: $entry\n");

		my $title;

		if ($entry =~ /^#EXTINF:.*?,(.*)$/) {
			$title = $1;	
		}
		
		next if $entry =~ /^#/;
		next if $entry eq "";

		$entry =~ s|$LF||g;
		
		$entry = Slim::Utils::Misc::fixPath($entry, $m3udir);
		
		$::d_parse && msg("    entry: $entry\n");

		_updateMetaData($entry, $title);
		
		push @items, $entry;
	}

	$::d_parse && msg("parsed " . scalar(@items) . " items in m3u playlist\n");

	return @items;
}

sub PLS {
	my $pls = shift;

	my @urls   = ();
	my @titles = ();
	my @items  = ();
	
	# parse the PLS file format

	$::d_parse && msg("Parsing playlist: $pls \n");
	
	while (<$pls>) {
		$::d_parse && msg("Parsing line: $_\n");

		# strip carriage return from dos playlists
		s/\cM//g;  

		# strip whitespace from end
		s/\s*$//; 
		
		if (m|File(\d+)=(.*)|i) {
			$urls[$1] = $2;
			next;
		}
		
		if (m|Title(\d+)=(.*)|i) {
			$titles[$1] = $2;
			next;
		}	
	}

	for (my $i = 1; $i <= $#urls; $i++) {

		next unless defined $urls[$i];

		my $entry = $urls[$i];
		my $title = $titles[$i];

		_updateMetaData($entry, $title);

		push @items, $entry;
	}

	return @items;
}

sub parseCUE {
	my $lines = shift;
	my $cuedir = shift;
	my @items;

	my $album;
	my $year;
	my $genre;
	my $comment;
	my $filename;
	my $currtrack;
	my %tracks;
	
	foreach (@$lines) {

		# strip whitespace from end
		s/\s*$//; 

		if (/^TITLE\s+\"(.*)\"/i) {
			$album = $1;
		} elsif (/^YEAR\s+\"(.*)\"/i) {
			$year = $1;
		} elsif (/^GENRE\s+\"(.*)\"/i) {
			$genre = $1;
		} elsif (/^COMMENT\s+\"(.*)\"/i) {
			$comment = $1;
		} elsif (/^FILE\s+\"(.*)\"/i) {
			$filename = $1;
			$filename = Slim::Utils::Misc::fixPath($filename, $cuedir);
		} elsif (/^\s+TRACK\s+(\d+)\s+AUDIO/i) {
			$currtrack = int ($1);
		} elsif (defined $currtrack and /^\s+PERFORMER\s+\"(.*)\"/i) {
			$tracks{$currtrack}->{'ARTIST'} = $1;
		} elsif (defined $currtrack and
			 /^\s+(TITLE|YEAR|GENRE|COMMENT)\s+\"(.*)\"/i) {
		   $tracks{$currtrack}->{uc $1} = $2;
		} elsif (defined $currtrack and
			 /^\s+INDEX\s+01\s+(\d+):(\d+):(\d+)/i) {
			$tracks{$currtrack}->{'START'} = ($1 * 60) + $2 + ($3 / 75);
		} elsif (defined $currtrack and
			 /^\s+END\s+01\s+(\d+):(\d+):(\d+)/i) {
			$tracks{$currtrack}->{'END'} = ($1 * 60) + $2 + ($3 / 75);
		}
	}

	# calc song ending times from start of next song from end to beginning.
	my $lastpos = Slim::Music::Info::durationSeconds($filename);
	foreach my $key (sort {$b <=> $a} keys %tracks) {
		my $track = $tracks{$key};
		if (!defined $track->{'END'}) {$track->{'END'} = $lastpos};
		$lastpos = $track->{'START'};
	}
	
	foreach my $key (sort {$a <=> $b} keys %tracks) {

		my $track = $tracks{$key};
		if (!defined $track->{'START'} || !defined $track->{'END'} || !defined $filename ) { next; }
		my $url = "$filename#".$track->{'START'}."-".$track->{'END'};
		$::d_parse && msg("    url: $url\n");
		push @items, $url;

		my $cacheEntry = Slim::Music::Info::cacheEntry($url);
		
		$cacheEntry->{'CT'} = Slim::Music::Info::typeFromPath($url, 'mp3');
		
		$cacheEntry->{'TRACKNUM'} = $key;
		$::d_parse && msg("    tracknum: $key\n");
		$cacheEntry->{'TITLE'} = $track->{'TITLE'};
		$::d_parse && msg("    title: " . $cacheEntry->{'TITLE'} . "\n");
		$cacheEntry->{'ARTIST'} = $track->{'ARTIST'};
		$::d_parse && msg("    artist: " . $cacheEntry->{'ARTIST'} . "\n");
		if (exists $track->{'YEAR'}) {
			$cacheEntry->{'YEAR'} = $track->{'YEAR'};
			$::d_parse && msg("    year: " . $cacheEntry->{'YEAR'} . "\n");
		} elsif (defined $year) {
			$cacheEntry->{'YEAR'} = $year;
			$::d_parse && msg("    year: " . $year . "\n");
		}
		if (exists $track->{'GENRE'}) {
			$cacheEntry->{'GENRE'} = $track->{'GENRE'};
			$::d_parse && msg("    genre: " . $cacheEntry->{'GENRE'} . "\n");
		} elsif (defined $genre) {
			$cacheEntry->{'GENRE'} = $genre;
			$::d_parse && msg("    genre: " . $genre . "\n");
		}
		if (exists $track->{'COMMENT'}) {
			$cacheEntry->{'COMMENT'} = $track->{'COMMENT'};
			$::d_parse && msg("    comment: " . $cacheEntry->{'COMMENT'} . "\n");
		} elsif (defined $comment) {
			$cacheEntry->{'COMMENT'} = $comment;
			$::d_parse && msg("    comment: " . $comment . "\n");
		}
		$cacheEntry->{'ALBUM'} = $album;
		$::d_parse && msg("    album: " . $cacheEntry->{'ALBUM'} . "\n");

		Slim::Music::Info::readTags($url);
		Slim::Music::Info::updateCacheEntry($url, $cacheEntry);
		Slim::Music::Info::updateGenreCache($url, $cacheEntry);

	}
	$::d_parse && msg("    returning: " . scalar(@items) . " items\n");	
	return @items;
}

sub CUE {
	my $cue = shift;
	my $cuefile = shift;

	$::d_parse && msg("Parsing cue: $cuefile \n");

	my @lines = ();

	while (my $line = <$cue>) {
		chomp($line);
		$line =~ s/\cM//g;  
		push @lines, $line;
	}

	return (parseCUE([@lines], $cuefile));
}

sub writePLS {
	my $listref = shift;
	my $playlistname = shift || "SlimServer " . Slim::Utils::Strings::string("PLAYLIST");
	my $filename = shift;
	my $output;
	my $outstring = '';
	my $writeproc;

	if ($filename && -e $filename) {

		$output = FileHandle->new($filename, "w") || do {
			msg("Could not open $filename for writing.\n");
			return;
		};

	} else {

		$output = IO::String->new($outstring);
	}

	print $output "[playlist]\nPlaylistName=$playlistname\n";
	my $itemnum = 0;

	foreach my $item (@{$listref}) {

		$itemnum++;

		print $output "File$itemnum=$item\n";

		my $title = Slim::Music::Info::title($item);

		if ($title) {
			print $output "Title$itemnum=$title\n";
		}

		my $dur = Slim::Music::Info::duration($item) || -1;
		print $output "Length$itemnum=$dur\n";
	}

	print $output "NumberOfItems=$itemnum\nVersion=2\n";

	if ($filename) {
		close $output;
		return;
	}

	return $outstring;
}

sub writeM3U {
	my $listref = shift;
	my $filename = shift;
	my $addTitles = shift;
	my $resumetrack = shift;
	my $output;
	my $outstring = '';
	my $writeproc;

	if ($filename && -e $filename) {

		$output = FileHandle->new($filename, "w") || do {
			msg("Could not open $filename for writing.\n");
			return;
		};

	} else {
		$output = IO::String->new($outstring);
	}

	print $output "#CURTRACK $resumetrack\n" if defined($resumetrack);
	print $output "#EXTM3U\n" if $addTitles;
	
	foreach my $item (@{$listref}) {

		if ($addTitles && Slim::Music::Info::isURL($item)) {

			my $title = Slim::Music::Info::title($item);

			if ($title) {
				print $output "#EXTINF:-1,$title\n";
			}
		}

		print $output "$item\n";
	}

	if ($filename) {
		close $output;
		return;
	}

	return $outstring;
}

1;
__END__
