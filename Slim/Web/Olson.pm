package Slim::Web::Olson;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use POSIX;
use Slim::Utils::Misc;

use Slim::Utils::Strings qw(string);

my($NEWLINE) = "\012";

sub olsonmain {
	my($client, $paramsref) = @_;
	my @items = ();
	my @songlist = ();

	my $song = $$paramsref{'song'};
	my $artist = $$paramsref{'artist'};
	my $album = $$paramsref{'album'};
	my $genre = $$paramsref{'genre'};
	my $player = $$paramsref{'player'};
	my $descend;
	my %list_form;
	my $itemnumber = 0;
	my $lastAnchor = '';

	# warn the user if the scanning isn't complete.
	if (Slim::Utils::Misc::stillScanning()) {
		$$paramsref{'warn'} = 1;
	}

	if (Slim::Music::iTunes::useiTunesLibrary()) {
		$$paramsref{'itunes'} = 1;
	}

	if (defined($genre) && $genre eq '*' && 
	    defined($artist) && $artist eq '*') {
		$$paramsref{'browseby'} = string('BROWSE_BY_ALBUM');
	} elsif (defined($genre) && $genre eq '*') {
		$$paramsref{'browseby'} = string('BROWSE_BY_ARTIST');
	} else {
	    $$paramsref{'browseby'} = string('BROWSE_BY_GENRE');
	};

	if (defined($genre) && $genre ne '*' && 
	    defined($artist) && $artist ne '*') {
		%list_form=();
		$list_form{'song'} = '';
		$list_form{'artist'} = '';
		$list_form{'album'} = '';
		$list_form{'genre'} = '';
		$list_form{'player'} = $player;
	        $list_form{'pwditem'} = string('BROWSE_BY_GENRE');
		$$paramsref{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("olsonmain_pwdlist.html", \%list_form)};
	      $$paramsref{'browseby'} = $genre;
	};

	my $otherparams = 'player=' . Slim::Web::HTTP::escape($player) . 
					  '&genre=' . Slim::Web::HTTP::escape($genre) . 
					  '&artist=' . Slim::Web::HTTP::escape($artist) . 
					  '&album=' . Slim::Web::HTTP::escape($album) . 
					  '&song=' . Slim::Web::HTTP::escape($song) . '&';
	if (!$genre) {
		@items = Slim::Music::Info::genres([], [$artist], [$album], [$song]);
		if (scalar(@items)) {
			my ($start,$end) = Slim::Web::Pages::alphapagebar(\@items,$$paramsref{'path'},$otherparams,\$$paramsref{'start'},\$$paramsref{'browselist_pagebar'},0);
			$descend = 'true';
			foreach my $item ( @items[$start..$end] ) {
				%list_form=();
				$list_form{'genre'}	  = $item;
				$list_form{'artist'}  = $artist;
				$list_form{'album'}	  = $album;
				$list_form{'song'}	  = $song;
				$list_form{'title'}   = $item;
				$list_form{'descend'} = $descend;
				$list_form{'player'} = $player;
				$list_form{'odd'}	  = ($itemnumber + 1) % 2;

				$list_form{'song_count'} = addsongsuffix(&Slim::Music::Info::songCount([$item],[],[],[]));

				my $anchor = Slim::Web::Pages::anchor($item,0);
				if ($lastAnchor ne $anchor) {
					$list_form{'anchor'}  = $anchor;
					$lastAnchor = $anchor;
				}
				$itemnumber++;
				$$paramsref{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("olson_tomain.html", \%list_form)};
			}
		}
	} elsif (!$artist) {
		@items = Slim::Music::Info::artists([$genre], [], [$album], [$song]);
		if (scalar(@items)) {
			my ($start,$end) = Slim::Web::Pages::alphapagebar(\@items,$$paramsref{'path'},$otherparams,\$$paramsref{'start'},\$$paramsref{'browselist_pagebar'},1);
			$descend = 'true';
			foreach my $item ( @items[$start..$end] ) {
				%list_form=();
				$list_form{'genre'}	  = $genre;
				$list_form{'artist'}  = $item;
				$list_form{'album'}	  = $album;
				$list_form{'song'}	  = $song;
				$list_form{'title'}   = $item;
				$list_form{'descend'} = $descend;
				$list_form{'player'} = $player;
				$list_form{'odd'} = ($itemnumber + 1) % 2;

				$list_form{'song_count'} = addsongsuffix(&Slim::Music::Info::songCount([$genre],[$item],[],[]));

				my $anchor = Slim::Web::Pages::anchor($item,1);
				if ($lastAnchor ne $anchor) {
					$list_form{'anchor'}  = $anchor;
					$lastAnchor = $anchor;
				}
				$itemnumber++;
				$$paramsref{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("olson_todetail.html", \%list_form)};
			}
		}
	} elsif (!$album) {
		@items = Slim::Music::Info::albums([$genre], [$artist], [], [$song]);
		if (scalar(@items)) {
			my ($start,$end) = Slim::Web::Pages::alphapagebar(\@items,$$paramsref{'path'},$otherparams,\$$paramsref{'start'},\$$paramsref{'browselist_pagebar'},1);
			$descend = 'true';
			foreach my $item ( @items[$start..$end] ) {
				%list_form=();
				$list_form{'genre'}	  = $genre;
				$list_form{'artist'}  = $artist;
				$list_form{'album'}	  = $item;
				$list_form{'song'}	  = $song;
				$list_form{'title'}   = $item;
				$list_form{'descend'} = $descend;
				$list_form{'player'} = $player;
				$list_form{'odd'}	  = ($itemnumber + 1) % 2;

				$list_form{'song_count'} = addsongsuffix(&Slim::Music::Info::songCount([$genre],[$artist],[$item],[]));

				my $anchor = Slim::Web::Pages::anchor($item,1);
				if ($lastAnchor ne $anchor) {
					$list_form{'anchor'}  = $anchor;
					$lastAnchor = $anchor;
				}
				$itemnumber++;
				$$paramsref{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("olson_todetail.html", \%list_form)};
			}
		}
	}
	$$paramsref{'descend'} = $descend;

	return Slim::Web::HTTP::filltemplatefile("olsonmain.html", $paramsref);
}


sub olsondetail {
	my($client, $paramsref) = @_;
	my @items = ();
	my @songlist = ();

	my $song = $$paramsref{'song'};
	my $artist = $$paramsref{'artist'};
	my $album = $$paramsref{'album'};
	my $genre = $$paramsref{'genre'};
	my $player = $$paramsref{'player'};
	my $descend;
	my %list_form;
	my $itemnumber = 0;
	my $lastAnchor = '';

	# warn the user if the scanning isn't complete.
	if (Slim::Utils::Misc::stillScanning()) {
		$$paramsref{'warn'} = 1;
	}

	if (Slim::Music::iTunes::useiTunesLibrary()) {
		$$paramsref{'itunes'} = 1;
	}

	$$paramsref{'pwd_list'} = "";

	if (defined($artist) && $artist ne '' &&
	    $artist ne '*' && defined($album) && $album ne '') {
		%list_form=();
		$list_form{'song'} = '';
		$list_form{'artist'} = $artist;
		$list_form{'album'} = '';
		$list_form{'genre'} = $genre;
		$list_form{'player'} = $player;
  	        $list_form{'pwditem'} = "Back to " . $artist;
		$$paramsref{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("olsondetail_pwdlist.html", \%list_form)};
		$$paramsref{'browseby'} = $artist . ' / ' . $album;
	} elsif (defined($artist) && $artist ne '' && $artist ne '*') {
		$$paramsref{'browseby'} = $artist;
	} elsif (defined($album) && $album ne '') {
		$$paramsref{'browseby'} = $album;
	} 

	my $otherparams = 'player=' . Slim::Web::HTTP::escape($player) . 
					  '&genre=' . Slim::Web::HTTP::escape($genre) . 
					  '&artist=' . Slim::Web::HTTP::escape($artist) . 
					  '&album=' . Slim::Web::HTTP::escape($album) . 
					  '&song=' . Slim::Web::HTTP::escape($song) . '&';
	if (!$album) {
		@items = Slim::Music::Info::albums([$genre], [$artist], [], [$song]);
		if (scalar(@items)) {
			my ($start,$end) = Slim::Web::Pages::alphapagebar(\@items,$$paramsref{'path'},$otherparams,\$$paramsref{'start'},\$$paramsref{'browselist_pagebar'},1);
			$descend = 'true';
			foreach my $item ( @items[$start..$end] ) {
				%list_form=();
				$list_form{'genre'}	  = $genre;
				$list_form{'artist'}  = $artist;
				$list_form{'album'}	  = $item;
				$list_form{'song'}	  = $song;
				$list_form{'title'}   = $item;
				$list_form{'descend'} = $descend;
				$list_form{'player'} = $player;
				$list_form{'odd'}	  = ($itemnumber + 1) % 2;

				$list_form{'song_count'} = addsongsuffix(&Slim::Music::Info::songCount([],[$artist],[$item],[]));

				my $anchor = Slim::Web::Pages::anchor($item,1);
				if ($lastAnchor ne $anchor) {
					$list_form{'anchor'}  = $anchor;
					$lastAnchor = $anchor;
				}
				$itemnumber++;
				$$paramsref{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("olson_todetail.html", \%list_form)};
			}
		}
	} else {
		@items = Slim::Music::Info::songs([$genre], [$artist], [$album], []);
		if (scalar(@items)) {
			my ($start,$end) = Slim::Web::Pages::pagebar(scalar(@items),$$paramsref{'path'},0,$otherparams,\$$paramsref{'start'},\$$paramsref{'browselist_header'},\$$paramsref{'browselist_pagebar'},0);
			$descend = undef;
			foreach my $item ( @items[$start..$end] ) {
				%list_form=();
				my $title = Slim::Music::Info::standardTitle(undef, $item);
				$list_form{'genre'}	  = Slim::Music::Info::genre($item);
				$list_form{'artist'}  = Slim::Music::Info::artist($item);
				$list_form{'album'}	  = Slim::Music::Info::album($item);
				$list_form{'itempath'} = $item;
				$list_form{'title'}   = $title;
				$list_form{'descend'} = $descend;
				$list_form{'player'} = $player;
				$list_form{'odd'}	  = ($itemnumber + 1) % 2;
				$itemnumber++;
				$$paramsref{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("olson_todetail.html", \%list_form)};
			}
		}
	}
	$$paramsref{'descend'} = $descend;

	return Slim::Web::HTTP::filltemplatefile("olsondetail.html", $paramsref);
}

sub addsongsuffix {
	my $number = shift;

	my $output = $number;
	if (scalar($number) > 1) { 
		$output .= ' songs'; 
	} else { 
		$output .= ' song'; 
	}
	return ($output);
}


1;
