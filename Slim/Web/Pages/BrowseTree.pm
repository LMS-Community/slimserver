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

use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Web::Pages;

sub init {
	
	Slim::Web::HTTP::addPageFunction(qr/^browsetree\.(?:htm|xml)/,\&browsetree);
	
	if (Slim::Utils::Prefs::get('audiodir')) {
		Slim::Web::Pages::Home->addPageLinks("browse",{'BROWSE_MUSIC_FOLDER'   => "browsetree.html"});
	} else {
		Slim::Web::Pages::Home->addPageLinks("browse",{'BROWSE_MUSIC_FOLDER' => undef});
	}

	if (Slim::Utils::Prefs::get('playlistdir')) {
		Slim::Web::Pages->addPageLinks("browse",{'SAVED_PLAYLISTS'   => "browsetree.html?topDir=playlistdir"});
	} else {
		Slim::Web::Pages->addPageLinks("browse",{'SAVED_PLAYLISTS' => undef});
	}
}

sub browsetree {
	my ($client, $params) = @_;

	my $hierarchy  = $params->{'hierarchy'} || '';
	my $player     = $params->{'player'};
	my $topDir     = $params->{'topDir'} || 'audiodir';
	my $itemsPer   = $params->{'itemsPerPage'} || Slim::Utils::Prefs::get('itemsPerPage');

	my @levels     = split(/\//, $hierarchy);
	my $itemnumber = 0;

	# We can browse either directory.
	# Set the page title as well
	if ($topDir eq 'playlistdir') {
		$topDir = Slim::Utils::Prefs::get('playlistdir');
		$params->{'browseby'} = 'SAVED_PLAYLISTS';
	} else {
		$topDir = Slim::Utils::Prefs::get('audiodir');
		$params->{'browseby'} = 'MUSIC';
	}

	# Pull the directory list, which will be used for looping.
	my ($topLevelObj, $items, $count) = Slim::Utils::Misc::findAndScanDirectoryTree(\@levels, $topDir);

	unshift @$items, $ds->getPlaylists('external');

	for (my $i = 0; $i < scalar @levels; $i++) {

		my $obj = Slim::Schema->find('Track', $levels[$i]);

		if (blessed($obj) && $obj->can('title')) {

			push @{$params->{'pwd_list'}}, {
				'hreftype'     => 'browseTree',
				'title'        => $i == 0 ? string($params->{'browseby'}) : $obj->title,
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
		my %form = %$params;

		$form{'hierarchy'}	  = undef;
		$form{'descend'}     = 1;
		$form{'text'}        = string('ALL_SONGS');
		$form{'itemobj'}     = $topLevelObj;
		$form{'hreftype'}    = 'browseTree';

		push @{$params->{'browse_items'}}, \%form;
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

		my $item = Slim::Schema->objectForUrl({
			'url'      => $url,
			'create'   => 1,
			'readTags' => 1,
		});

		if (!blessed($item) || !$item->can('content_type')) {

			next;
		}

		# Bug: 1360 - Don't show files referenced in a cuesheet
		next if ($item->content_type eq 'cur');

		# Turn the utf8 flag on for proper display - since this is
		# coming directly from the filesystem.
		my %form = (
			'text'	    => Slim::Utils::Unicode::utf8decode_locale($relPath),
			'hierarchy' => join('/', @levels, $item->id),
			'descend'   => Slim::Music::Info::isList($item) ? 1 : 0,
			'odd'       => ($itemnumber + 1) % 2,
			'itemobj'   => $item,
			'hreftype'  => 'browseTree',
		);

		if (Slim::Music::Info::isPlaylist($item)) {

			$list_form{'descend'}  = 1;
			$list_form{'hreftype'} = 'browsePlaylist';

		} elsif (Slim::Music::Info::isList($item)) {

			$list_form{'descend'}  = 1;
			$list_form{'hreftype'} = 'browseTree';

		} else {

			$list_form{'descend'}  = 0;
			$list_form{'hreftype'} = 'browseTree';
		}

		# Don't display the edit dialog for playlists (includes CUE sheets).
		if (($topDir eq 'playlistdir' && $item->isCUE) || 
		    ($topDir eq 'audiodir'    && $item->isPlaylist)) {

			$form{'noEdit'} = '&noEdit=1';
		}

		$itemnumber++;

		push @{$params->{'browse_items'}}, \%form;

		if (!$params->{'coverArt'} && $item->coverArt) {
			$params->{'coverArt'} = $item->id;
		}
	}

	$params->{'descend'} = 1;
	
	if (Slim::Music::Import->stillScanning()) {
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
