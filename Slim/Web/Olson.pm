package Slim::Web::Olson;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);

use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

# This seems mostly duplicated from Pages.pm

sub olsonmain {
	my ($client, $params) = @_;

	my $song   = $params->{'song'};
	my $artist = $params->{'artist'};
	my $album  = $params->{'album'};
	my $genre  = $params->{'genre'};
	my $player = $params->{'player'};

	my $descend;
	my $itemnumber = 0;
	my $lastAnchor;

	# warn the user if the scanning isn't complete.
	if (Slim::Utils::Misc::stillScanning()) {
		$params->{'warn'} = 1;
	}

	#if (Slim::Music::iTunes::useiTunesLibrary()) {
	#	$params->{'itunes'} = 1;
	#}
	if (defined(Slim::Utils::Prefs::get('audiodir'))) {
		$params->{'audiodir'} = 1;
	}

	if (defined($genre) && $genre eq '*' && defined($artist) && $artist eq '*') {

		$params->{'browseby'} = string('BROWSE_BY_ALBUM');

	} elsif (defined($genre) && $genre eq '*') {

		$params->{'browseby'} = string('BROWSE_BY_ARTIST');

	} else {
		$params->{'browseby'} = string('BROWSE_BY_GENRE');
	}

	if (defined($genre) && $genre ne '*' && defined($artist) && $artist ne '*') {

		my %list_form = %$params;

		$list_form{'song'}    = '';
		$list_form{'artist'}  = '';
		$list_form{'album'}   = '';
		$list_form{'genre'}   = '';
		$list_form{'player'}  = $player;
	        $list_form{'pwditem'} = string('BROWSE_BY_GENRE');

		$params->{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("olsonmain_pwdlist.html", \%list_form)};
		$params->{'browseby'} = $genre;
	}

	my $otherparams = 
		'player='  . Slim::Web::HTTP::escape($player || '') . 
		'&genre='  . Slim::Web::HTTP::escape($genre  || '') . 
		'&artist=' . Slim::Web::HTTP::escape($artist || '') . 
		'&album='  . Slim::Web::HTTP::escape($album  || '') . 
		'&song='   . Slim::Web::HTTP::escape($song   || '') . '&';

	if (!$genre) {

		my @items = Slim::Music::Info::genres([], [$artist], [$album], [$song]);

		if (scalar(@items)) {

			my ($start,$end) = Slim::Web::Pages::alphaPageBar(
				\@items,
				$params->{'path'},
				$otherparams,
				\$params->{'start'},
				\$params->{'browselist_pagebar'},
				0
			);

			$descend = 'true';

			foreach my $item (@items[$start..$end]) {

				my %list_form = %$params;

				$list_form{'genre'}   = $item;
				$list_form{'artist'}  = $artist;
				$list_form{'album'}   = $album;
				$list_form{'song'}    = $song;
				$list_form{'title'}   = $item;
				$list_form{'descend'} = $descend;
				$list_form{'player'}  = $player;
				$list_form{'odd'}     = ($itemnumber + 1) % 2;

				$list_form{'song_count'} = _addSongSuffix(&Slim::Music::Info::songCount([$item],[],[],[]));

				my $anchor = Slim::Web::Pages::anchor($item,0);

				if ($lastAnchor ne $anchor) {
					$list_form{'anchor'} = $anchor;
					$lastAnchor          = $anchor;
				}

				$itemnumber++;

				$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("olson_tomain.html", \%list_form)};
			}
		}

	} elsif (!$artist) {

		my @items = Slim::Music::Info::artists([$genre], [], [$album], [$song]);

		if (scalar(@items)) {

			my ($start,$end) = Slim::Web::Pages::alphaPageBar(
				\@items,
				$params->{'path'},
				$otherparams,
				\$params->{'start'},
				\$params->{'browselist_pagebar'},
				1
			);

			$descend = 'true';

			foreach my $item (@items[$start..$end]) {

				my %list_form = %$params;

				$list_form{'genre'}   = $genre;
				$list_form{'artist'}  = $item;
				$list_form{'album'}   = $album;
				$list_form{'song'}    = $song;
				$list_form{'title'}   = $item;
				$list_form{'descend'} = $descend;
				$list_form{'player'}  = $player;
				$list_form{'odd'}     = ($itemnumber + 1) % 2;

				$list_form{'song_count'} = _addSongSuffix(&Slim::Music::Info::songCount([$genre],[$item],[],[]));

				my $anchor = Slim::Web::Pages::anchor($item,1);

				if ($lastAnchor ne $anchor) {
					$list_form{'anchor'} = $anchor;
					$lastAnchor          = $anchor;
				}

				$itemnumber++;

				$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("olson_todetail.html", \%list_form)};
			}
		}

	} elsif (!$album) {

		my @items = Slim::Music::Info::albums([$genre], [$artist], [], [$song]);

		if (scalar(@items)) {

			my ($start,$end) = Slim::Web::Pages::alphaPageBar(
				\@items,
				$params->{'path'},
				$otherparams,
				\$params->{'start'},
				\$params->{'browselist_pagebar'},
				1
			);

			$descend = 'true';

			foreach my $item (@items[$start..$end]) {

				my %list_form = %$params;

				$list_form{'genre'}   = $genre;
				$list_form{'artist'}  = $artist;
				$list_form{'album'}   = $item;
				$list_form{'song'}    = $song;
				$list_form{'title'}   = $item;
				$list_form{'descend'} = $descend;
				$list_form{'player'}  = $player;
				$list_form{'odd'}     = ($itemnumber + 1) % 2;

				$list_form{'song_count'} = _addSongSuffix(&Slim::Music::Info::songCount([$genre],[$artist],[$item],[]));

				my $anchor = Slim::Web::Pages::anchor($item,1);

				if ($lastAnchor ne $anchor) {
					$list_form{'anchor'} = $anchor;
					$lastAnchor          = $anchor;
				}

				$itemnumber++;

				$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("olson_todetail.html", \%list_form)};
			}
		}
	}

	$params->{'descend'} = $descend;

	return Slim::Web::HTTP::filltemplatefile("olsonmain.html", $params);
}


sub olsondetail {
	my ($client, $params) = @_;

	my $song   = $params->{'song'};
	my $artist = $params->{'artist'};
	my $album  = $params->{'album'};
	my $genre  = $params->{'genre'};
	my $player = $params->{'player'};

	my $descend;
	my $itemnumber = 0;
	my $lastAnchor = '';

	# warn the user if the scanning isn't complete.
	if (Slim::Utils::Misc::stillScanning()) {
		$params->{'warn'} = 1;
	}

	#if (Slim::Music::iTunes::useiTunesLibrary()) {
	#	$params->{'itunes'} = 1;
	#}
	if (defined(Slim::Utils::Prefs::get('audiodir'))) {
		$params->{'audiodir'} = 1;
	}

	$params->{'pwd_list'} = "";

	if (defined($artist) && $artist ne '' && $artist ne '*' && defined($album) && $album ne '') {

		my %list_form = %$params;

		$list_form{'song'}    = '';
		$list_form{'artist'}  = $artist;
		$list_form{'album'}   = '';
		$list_form{'genre'}   = $genre;
		$list_form{'player'}  = $player;
		$list_form{'pwditem'} = "Back to " . $artist;

		$params->{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("olsondetail_pwdlist.html", \%list_form)};
		$params->{'browseby'} = $artist . ' / ' . $album;

	} elsif (defined($artist) && $artist ne '' && $artist ne '*') {

		$params->{'browseby'} = $artist;

	} elsif (defined($album) && $album ne '') {

		$params->{'browseby'} = $album;
	} 

	my $otherparams = 
		'player='  . Slim::Web::HTTP::escape($player || '') . 
		'&genre='  . Slim::Web::HTTP::escape($genre  || '') . 
		'&artist=' . Slim::Web::HTTP::escape($artist || '') . 
		'&album='  . Slim::Web::HTTP::escape($album  || '') . 
		'&song='   . Slim::Web::HTTP::escape($song   || '') . '&';

	if (!$album) {

		my @items = Slim::Music::Info::albums([$genre], [$artist], [], [$song]);

		if (scalar(@items)) {

			my ($start,$end) = Slim::Web::Pages::alphaPageBar(
				\@items,
				$params->{'path'},
				$otherparams,
				\$params->{'start'},
				\$params->{'browselist_pagebar'},
				1
			);

			$descend = 'true';

			foreach my $item (@items[$start..$end]) {

				my %list_form = %$params;

				$list_form{'genre'}   = $genre;
				$list_form{'artist'}  = $artist;
				$list_form{'album'}   = $item;
				$list_form{'song'}    = $song;
				$list_form{'title'}   = $item;
				$list_form{'descend'} = $descend;
				$list_form{'player'}  = $player;
				$list_form{'odd'}     = ($itemnumber + 1) % 2;

				$list_form{'song_count'} = _addSongSuffix(&Slim::Music::Info::songCount([],[$artist],[$item],[]));

				my $anchor = Slim::Web::Pages::anchor($item,1);

				if ($lastAnchor ne $anchor) {
					$list_form{'anchor'} = $anchor;
					$lastAnchor          = $anchor;
				}

				$itemnumber++;

				$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("olson_todetail.html", \%list_form)};
			}
		}

	} else {

		my @items = Slim::Music::Info::songs([$genre], [$artist], [$album], []);

		if (scalar(@items)) {

			my ($start,$end) = Slim::Web::Pages::pageBar(
				scalar(@items),
				$params->{'path'},
				0,
				$otherparams,
				\$params->{'start'},
				\$params->{'browselist_header'},
				\$params->{'browselist_pagebar'},
				0
			);

			$descend = undef;

			foreach my $item (@items[$start..$end]) {

				my %list_form = %$params;

				my $title = Slim::Music::Info::standardTitle(undef, $item);

				$list_form{'genre'}    = Slim::Music::Info::genre($item);
				$list_form{'artist'}   = Slim::Music::Info::artist($item);
				$list_form{'album'}    = Slim::Music::Info::album($item);
				$list_form{'itempath'} = $item;
				$list_form{'title'}    = $title;
				$list_form{'descend'}  = $descend;
				$list_form{'player'}   = $player;
				$list_form{'odd'}      = ($itemnumber + 1) % 2;

				$itemnumber++;

				$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("olson_todetail.html", \%list_form)};
			}
		}
	}

	$params->{'descend'} = $descend;

	return Slim::Web::HTTP::filltemplatefile("olsondetail.html", $params);
}

# XXX - this should be moved to Utils maybe?
sub _addSongSuffix {
	my $number = shift;

	return $number > 1 ? "$number songs" : "$number song";
}

1;
