package Slim::Formats::Playlists::PLS;

# $Id

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Formats::Playlists::Base);

use Scalar::Util qw(blessed);

use Slim::Music::Info;
use Slim::Utils::Misc;
use Slim::Utils::Strings;
use Slim::Utils::Unicode;

sub read {
	my ($class, $file, $baseDir, $url) = @_;

	my @urls   = ();
	my @titles = ();
	my @items  = ();
	my $foundBOM = 0;

	$::d_parse && msg("Parsing playlist: $url \n");

	while (my $line = <$file>) {

		chomp($line);

		$::d_parse && msg("Parsing line: $line\n");

		# strip carriage return from dos playlists
		$line =~ s/\cM//g;

		# strip whitespace from end
		$line =~ s/\s*$//;

		# Guess the encoding of each line in the file. Bug 1876
		# includes a playlist that has latin1 titles, and utf8 paths.
		my $enc = Slim::Utils::Unicode::encodingFromString($line);

		# Only strip the BOM off of UTF-8 encoded bytes. Encode will
		# handle UTF-16
		if (!$foundBOM && $enc eq 'utf8') {

			$line = Slim::Utils::Unicode::stripBOM($line);
			$foundBOM = 1;
		}

		$line = Slim::Utils::Unicode::utf8decode_guess($line, $enc);

		if ($line =~ m|File(\d+)=(.*)|i) {
			$urls[$1] = Slim::Utils::Unicode::utf8encode_locale($2);
			next;
		}

		if ($line =~ m|Title(\d+)=(.*)|i) {
			$titles[$1] = $2;
			next;
		}	
	}

	for (my $i = 1; $i <= $#urls; $i++) {

		next unless defined $urls[$i];

		my $entry = Slim::Utils::Misc::fixPath($urls[$i]);

		if ($class->playlistEntryIsValid($entry, $url)) {

			push @items, $class->_updateMetaData($entry, $titles[$i]);
		}
	}

	close $file if (ref($file) ne 'IO::String');

	return @items;
}

sub write {
	my $class        = shift;
	my $listRef      = shift;
	my $playlistname = shift || "SlimServer " . Slim::Utils::Strings::string("PLAYLIST");
	my $filename     = shift;

	my $string  = '';
	my $output  = $class->_filehandleFromNameOrString($filename, \$string) || return;
	my $itemnum = 0;

	print $output "[playlist]\nPlaylistName=$playlistname\n";

	for my $item (@{$listRef}) {

		$itemnum++;

		my $track = Slim::Schema->rs('Track')->objectForUrl($item);

		if (!blessed($track) || !$track->can('title')) {

			errorMsg("writePLS: Couldn't fetch track object for: [$item]\n");

			next;
		}

		printf($output "File%d=%s\n", $itemnum, $class->_pathForItem($track->url));

		my $title = $track->title();

		if ($title) {
			printf($output "Title%d=%s\n", $itemnum, $title);
		}

		printf($output "Length%d=%s\n", $itemnum, ($track->duration() || -1));
	}

	print $output "NumberOfItems=$itemnum\nVersion=2\n";

	close($output) if $filename;

	return $string;
}

1;

__END__
