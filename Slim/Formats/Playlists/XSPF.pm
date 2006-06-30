package Slim::Formats::Playlists::XSPF;

# $Id$

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Formats::Playlists::Base);

use XML::XSPF;

use Slim::Music::Info;
use Slim::Utils::Misc;
use Slim::Utils::Unicode;

sub read {
	my ($class, $file, $baseDir, $url) = @_;

	my @items  = ();
	my $title;

	$::d_parse && msg("parsing XSPF: $url\n");

	my $xspf   = XML::XSPF->parse($file) || do {

		errorMsg("XSPF->read: Couldn't parse data!\n");
		return @items;
	};

	for my $track ($xspf->trackList) {

		my $location = $track->location;
		my $title    = $track->title;

		my $enc = Slim::Utils::Unicode::encodingFromString($title);
		 $title = Slim::Utils::Unicode::utf8decode_guess($title, $enc);

		if ($class->playlistEntryIsValid($location, $url)) {

			$::d_parse && msg("    entry: $location\n");

			push @items, $class->_updateMetaData( $location, {
				'TITLE' => $title,
			} );
		}
	}

	$::d_parse && msg("parsed " . scalar(@items) . " items in xspf playlist\n");

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

	my $string  = '';
	my $output  = $class->_filehandleFromNameOrString($filename, \$string) || return;

	my $homeURL = Slim::Utils::Prefs::homeURL();

	my $xspf    = XML::XSPF->new;
	my @tracks  = ();

	for my $item (@{$listref}) {

		my $obj = Slim::Schema->rs('Track')->objectForUrl($item);

		if (!blessed($obj) || !$obj->can('title')) {

			errorMsg("XSPF->write: Couldn't retrieve objectForUrl: [$item] - skipping!\n");
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

			$track->image(sprintf('%s/music/%d/cover.jpg', $homeURL, $obj->id));
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
