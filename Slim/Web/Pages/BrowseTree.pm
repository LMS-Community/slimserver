package Slim::Web::Pages::BrowseTree;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use POSIX ();
use Scalar::Util qw(blessed);

use Slim::DataStores::Base;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Web::Pages;

sub init {
	
	Slim::Web::HTTP::addPageFunction(qr/^browsetree\.(?:htm|xml)/,\&browsetree);
	
	if (Slim::Utils::Prefs::get('audiodir')) {
		Slim::Web::Pages::Home::addLinks("browse",{'BROWSE_MUSIC_FOLDER'   => "browsetree.html"});
	} else {
		Slim::Web::Pages::Home::addLinks("browse",{'BROWSE_MUSIC_FOLDER' => undef});
	}
}

sub browsetree {
	my ($client, $params) = @_;

	my $hierarchy  = $params->{'hierarchy'} || '';
	my $player     = $params->{'player'};
	my $itemsPer   = $params->{'itemsPerPage'} || Slim::Utils::Prefs::get('itemsPerPage');

	my $ds         = Slim::Music::Info::getCurrentDataStore();
	my @levels     = split(/\//, $hierarchy);
	my $itemnumber = 0;

	# Pull the directory list, which will be used for looping.
	my ($topLevelObj, $items, $count) = Slim::Utils::Misc::findAndScanDirectoryTree(\@levels);

	# Page title
	$params->{'browseby'} = 'MUSIC';

	for (my $i = 0; $i < scalar @levels; $i++) {

		my $obj = $ds->objectForId('track', $levels[$i]);

		if (blessed($obj) && $obj->can('title')) {

			push @{$params->{'pwd_list'}}, {
				'hreftype'     => 'browseTree',
				'title'        => $i == 0 ? string('MUSIC') : $obj->title,
				'hierarchy'    => join('/', @levels[0..$i]),
			};
		}
	}

	my ($start, $end) = (0, $count);

	# Create a numeric pagebar if we need to.
	if ($count > $itemsPer) {

		($start, $end) = Slim::Web::Pages->pageBar({
				'itemCount'    => $count,
				'path'         => $params->{'path'},
				'otherParams'  => "hierarchy=$hierarchy&player=$player",
				'startRef'     => \$params->{'start'},
				'headerRef'    => \$params->{'browselist_header'},
				'pageBarRef'   => \$params->{'browselist_pagebar'},
				'skinOverride' => $params->{'skinOverride'},
				'perPage'      => $params->{'itemsPerPage'},
			}
		);
	}

	# Setup an 'All' button.
	# I believe this will play only songs, and not playlists.
	if ($count) {
		my %list_form = %$params;

		$list_form{'hierarchy'}	  = undef;
		$list_form{'descend'}     = 1;
		$list_form{'text'}        = string('ALL_SONGS');
		$list_form{'itemobj'}     = $topLevelObj;
		$list_form{'hreftype'}    = 'browseTree';

		push @{$params->{'browse_items'}}, \%list_form;
	}

	#
	my $topPath = $topLevelObj->path;
	my $osName  = Slim::Utils::OSDetect::OS();

	for my $relPath (@$items[$start..$end]) {

		my $url  = Slim::Utils::Misc::fixPath($relPath, $topPath) || next;

		# Amazingly, this just works. :)
		# Do the cheap compare for osName first - so non-windows users
		# won't take the penalty for the lookup.
		if ($osName eq 'win' && Slim::Music::Info::isWinShortcut($url)) {
			$url = Slim::Utils::Misc::fileURLFromWinShortcut($url);
		}

		my $item = $ds->objectForUrl($url, 1, 1, 1);

		if (!blessed($item) || !$item->can('content_type')) {

			next;
		}

		# Bug: 1360 - Don't show files referenced in a cuesheet
		next if ($item->content_type eq 'cur');

		my %list_form = '';

		# Turn the utf8 flag on for proper display - since this is
		# coming directly from the filesystem.
		$list_form{'text'}	    = Slim::Utils::Unicode::utf8decode_locale($relPath);

		$list_form{'hierarchy'}  = join('/', @levels, $item->id);
		$list_form{'descend'}    = Slim::Music::Info::isList($item) ? 1 : 0;
		$list_form{'odd'}        = ($itemnumber + 1) % 2;
		$list_form{'itemobj'}    = $item;
		$list_form{'hreftype'}   = 'browseTree';

		# Don't display the edit dialog for cue sheets.
		if ($item->isCUE) {
			$list_form{'noEdit'} = '&noEdit=1';
		}

		$itemnumber++;

		#$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsetree_list.html", \%list_form)};
		push @{$params->{'browse_items'}}, \%list_form;

		if (!$params->{'coverArt'} && $item->coverArt) {
			$params->{'coverArt'} = $item->id;
		}
	}

	$params->{'descend'} = 1;
	
	if (Slim::Music::Import::stillScanning()) {
		$params->{'warn'} = 1;
	}

	# we might have changed - flush to the db to be in sync.
	$topLevelObj->update;
	
	return Slim::Web::HTTP::filltemplatefile("browsedb.html", $params);
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
