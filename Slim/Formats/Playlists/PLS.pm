package Slim::Formats::Playlists::PLS;

# $Id

# Logitech Media Server Copyright 2001-2011 Logitech.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Formats::Playlists::Base);

use File::Slurp;
use IO::Socket qw(:crlf);
use Scalar::Util qw(blessed);

use Slim::Music::Info;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings;
use Slim::Utils::Unicode;

my $log = logger('formats.playlists');

sub read {
	my ($class, $file, $baseDir, $url) = @_;

	my @urls   = ();
	my @titles = ();
	my @items  = ();
	my $data   = '';

	main::INFOLOG && $log->info("Parsing: $url");

	# Bug: 3697 - Haven't seen pls files used on disk (or at least with
	# multiple encodings perl file), but have seen UTF-16 playlists on
	# remote sites. We need to decode the entire string as a UTF-16
	# encoded chunk, instead of each line.
	{
		$data = read_file($file);

		my $enc  = Slim::Utils::Unicode::encodingFromString($data);

		if ($enc eq 'utf8') {
			$data = Slim::Utils::Unicode::stripBOM($data);
		}

		$data = Slim::Utils::Unicode::utf8decode_guess($data, $enc);
	}
	
	# Bug 4127, make sure we have proper line-endings
	$data =~ s/\r\n?/\n/g;

	for my $line (split(/\n/, $data)) {

		main::DEBUGLOG && $log->debug("Parsing line: $line");

		# strip carriage return from dos playlists
		$line =~ s/\cM//g;

		# strip whitespace from end
		$line =~ s/\s*$//;

		if ($line =~ m|File(\d+)=(.*)|i) {
			$urls[$1] = $2;
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

			push @items, $class->_updateMetaData( $entry, {
				'TITLE' => $titles[$i]
			}, $url );
		}
	}

	close $file if (ref($file) ne 'IO::String');

	return @items;
}

sub write {
	my $class        = shift;
	my $listRef      = shift;
	my $playlistname = shift || "Squeezebox " . Slim::Utils::Strings::string("PLAYLIST");
	my $filename     = shift;

	main::INFOLOG && $log->info("Writing out: $filename");

	my $string  = '';
	my $output  = $class->_filehandleFromNameOrString($filename, \$string) || return;
	my $itemnum = 0;

	print $output "[playlist]\nPlaylistName=$playlistname\n";

	for my $item (@{$listRef}) {

		$itemnum++;

		my $track = Slim::Schema->objectForUrl($item);

		if (!blessed($track) || !$track->can('title')) {

			logError("Couldn't fetch track object for: [$item]");

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
