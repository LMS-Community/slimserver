package Slim::Formats::Playlists::XSPF;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Formats::Playlists::Base);

use XML::XSPF;

use Slim::Music::Info;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Unicode;

my $log = logger('formats.playlists');

sub read {
	my ($class, $file, $baseDir, $url) = @_;

	my @items  = ();
	my $title;

	main::INFOLOG && $log->info("Parsing: $url");

	my $xspf = XML::XSPF->parse($file) || do {

		logError("Couldn't parse data!");

		return @items;
	};

	for my $track ($xspf->trackList) {

		my $location = $track->location;
		my $title    = $track->title;

		$title = Slim::Utils::Unicode::utf8decode_guess($title);

		if ($class->playlistEntryIsValid($location, $url)) {

			main::DEBUGLOG && $log->debug("    entry: $location");
			main::DEBUGLOG && $log->debug("    title: $title");

			push @items, $class->_updateMetaData( $location, {
				'TITLE' => $title,
			}, $url );
		}
	}

	if ( main::INFOLOG && $log->is_info ) {
		$log->info("Parsed " . scalar(@items) . " items from XSPF\n");
	}

	return @items;
}

# So far the writer has a lot more than we can read in - need to factor
# _updateMetaData to handle more.
# 
# Currently there aren't any callers - we may want to make this the preferred
# default playlist format instead of M3U however. May need an extension to
# handle #CURRTRACK type functionality.
sub write {
	my $class        = shift;
	my $listref      = shift;
	my $playlistname = shift;
	my $filename     = shift;

	main::INFOLOG && $log->info("Writing out: $filename");

	my $string  = '';
	my $output  = $class->_filehandleFromNameOrString($filename, \$string) || return;

	my $homeURL = Slim::Utils::Network::serverURL();

	my $xspf    = XML::XSPF->new;
	my @tracks  = ();

	for my $item (@{$listref}) {

		my $obj = Slim::Schema->objectForUrl($item);

		if (!blessed($obj) || !$obj->can('title')) {

			logError("Couldn't retrieve objectForUrl: [$item] - skipping!");
			next;
		};
		
		my $track = XML::XSPF::Track->new;
		my $title = Slim::Utils::Unicode::utf8decode( $obj->title );

		if ($title) {
			$track->title($title);
		}

		if (blessed($obj->artist) && $obj->artist->name) {

			$track->creator($obj->artist->name);
		}

		if (blessed($obj->album) && $obj->album->title) {

			$track->album($obj->album->title);
		}

		if ($obj->tracknum) {
			$track->trackNum($obj->tracknum);
		}

		if ($obj->secs) {
			$track->duration($obj->secs * 1000);
		}

		if ($homeURL && $obj->cover) {

			$track->image(sprintf('%s/music/%s/cover.jpg', $homeURL, $obj->coverid));
		}

		$track->location($obj->url);
	}

	$xspf->trackList(\@tracks);

	print $output $xspf->toString;

	close $output if $filename;

	return $string;
}

1;

__END__
