package Slim::Buttons::BrowseTree;

# $Id$

# SlimServer Copyright (C) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Scalar::Util qw(blessed);

use Slim::Buttons::Block;
use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Buttons::TrackInfo;
use Slim::Music::Info;
use Slim::Music::MusicFolderScan;
use Slim::Utils::Misc;

our %functions = ();

sub init {

	Slim::Buttons::Block::init();

	my $name = 'BROWSE_MUSIC_FOLDER';
	my $mode = 'browsetree';
	my $menu = {
		'useMode'  => $mode,
		'hierarchy' => '',
	};

	Slim::Buttons::Common::addMode($mode, Slim::Buttons::BrowseTree::getFunctions(), \&Slim::Buttons::BrowseTree::setMode);

	Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC', $name, $menu);
	Slim::Buttons::Home::addMenuOption($name, $menu);

	%functions = (
		'play' => sub {
			my $client = shift;
			my $button = shift;
			my $addorinsert = shift || 0;

			my $items       = $client->param('listRef');
			my $listIndex   = $client->param('listIndex');
			my $currentItem = $items->[$listIndex] || return;
			my $descend     = Slim::Music::Info::isList($currentItem) ? 1 : 0;

			my ($command, $line1, $line2, $string);

			# Based on the button pressed, we determine what to display
			# and which command to send to modify the playlis
			if ($addorinsert == 1) {

				$string = 'ADDING_TO_PLAYLIST';
				$command = "add";	

			} elsif ($addorinsert == 2) {

				$string = 'INSERT_TO_PLAYLIST';
				$command = "insert";

			} else {

				$command = "play";

				if (Slim::Player::Playlist::shuffle($client)) {
					$string = 'PLAYING_RANDOMLY_FROM';
				} else {
					$string = 'NOW_PLAYING_FROM';
				}
			}
	
			if ($client->linesPerScreen() == 1) {

				$line2 = $client->doubleString($string);

			} else {

				$line1 = $client->string($string);
				$line2 = browseTreeItemName($client, $currentItem);

			}

			$client->showBriefly( {
				'line1' => $line1,
				'line2' => $line2,
				'overlay2' => $client->symbols('notesymbol'),
			});

			if ($descend || !Slim::Utils::Prefs::get('playtrackalbum') || $addorinsert || !Slim::Music::Info::isSong($currentItem)) {

				$client->execute(['playlist', $command, $currentItem]);

			## playing other songs in folder, ONLY on play command from remote.
			## non-objects are quickly converted to urls so that the playlist render
			## can do lazy object conversion later.
			} else {

				my $wasShuffled = Slim::Player::Playlist::shuffle($client);

				Slim::Player::Playlist::shuffle($client, 0);

				$client->execute(['playlist', 'clear']);

				$::d_playlist && msg("Playing all in folder, starting with $listIndex\n");

				my @playlist;
				
				# iterate through list in reverse order, so that dropped items don't affect the index as we subtract.
				for my $i (reverse (0..scalar @{$items}-1)) {

					if (!ref $items->[$i]) {
						$items->[$i] =  Slim::Utils::Misc::fixPath($items->[$i], $client->param('topLevelPath'));
					}

					unless (Slim::Music::Info::isSong($items->[$i])) {
						$::d_playlist && msgf("Dropping %s from play all in folder at index %d\n",$items->[$i],$i);
						if ($i < $listIndex) {
							$listIndex --;
						}
						next;
					}

					unshift (@playlist, $items->[$i]);
				}

				$::d_playlist && msg("Load folder playlist, now starting at index: $listIndex\n");
				$client->execute(['playlist', 'addtracks','listref', \@playlist]);
				$client->execute(['playlist', 'jump', $listIndex]);

				if ($wasShuffled) {
					$client->execute(['playlist', 'shuffle', 1]);
				}
			}
		},
	);
}

sub getFunctions {
	return \%functions;
}

# Callback invoked by INPUT.List when we're going to leave this mode
sub browseTreeExitCallback {
	my ($client, $exittype) = @_;

	$exittype = uc($exittype);

	# Left means pop out of this mode
	if ($exittype eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);
		return;

	} elsif ($exittype ne 'RIGHT') {

		$client->bumpRight();
		return;
	}

	my $currentItem = ${$client->param('valueRef')};

	my $descend     = Slim::Music::Info::isList($currentItem) ? 1 : 0;

	my @levels      = split(/\//, $client->param('hierarchy'));

	if (!defined $currentItem) {

		$client->bumpRight();

	} elsif ($descend) {

		my $params = {};

		# If this is a playlist - send the user over to browsedb
		if ($currentItem->isPlaylist) {

			$params->{'hierarchy'}    = 'playlist,playlistTrack';
			$params->{'level'}        = 1;
			$params->{'findCriteria'} = { 'playlist' => $currentItem->id };

			Slim::Buttons::Common::pushModeLeft($client, 'browsedb', $params);

		} else {

			$params->{'hierarchy'} = join('/', @levels, $currentItem->id);

			# Push recursively in to the same mode for the next level down.
			Slim::Buttons::Common::pushModeLeft($client, 'browsetree', $params);
		}

	} else {

		# For a track, push into the track information mode
		Slim::Buttons::Common::pushModeLeft($client, 'trackinfo', { 'track' => $currentItem });
	}
}

# Method invoked by INPUT.List to map an item in the list
# to a display name.
sub browseTreeItemName {
	my ($client, $item, $index) = @_;

	if (!ref($item)) {

		# Dynamically pull the object from the DB. This prevents us from
		# having to do so at initial load time of possibly hundreds of items.
		my $url = Slim::Utils::Misc::fixPath($item, $client->param('topLevelPath')) || return;

		if (Slim::Music::Info::isWinShortcut($url)) {

			$url = Slim::Utils::Misc::fileURLFromWinShortcut($url);
		}

		my $items = $client->param('listRef');

		my $track = Slim::Schema->objectForUrl({
			'url'      => $url,
			'create'   => 1,
			'readTags' => 1,
			'commit'   => 1,

		}) || return $url;

		${$client->param('valueRef')} = $item = $items->[$index] = $track;
	}

	return Slim::Utils::Unicode::utf8on( Slim::Music::Info::fileName($item->url) );
}

# Method invoked by INPUT.List to map an item in the list
# to overlay characters.
sub browseTreeOverlay {
	my $client = shift;
	my $item   = shift || return;

	my ($overlay1, $overlay2);

	# A text item generally means ALL_, so overlay an arrow
	if (!ref $item) {
		return (undef, Slim::Display::Display::symbol('rightarrow'));
	}

	if (Slim::Music::Info::isSong($item)) {
		$overlay2 = Slim::Display::Display::symbol('notesymbol');
	} else {
		$overlay2 = Slim::Display::Display::symbol('rightarrow');
	}

	return ($overlay1, $overlay2);
}

sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	# Parse the hierarchy list into an array
	my $hierarchy = $client->param('hierarchy');
	my @levels    = split(/\//, $hierarchy);

	my ($topLevelObj, $items, $count) = Slim::Utils::Misc::findAndScanDirectoryTree(\@levels);

	# Next get the first line of the mode
	my @headers = ();

	# top level, we show MUSIC FOLDER
	if (scalar @levels == 1) {

		push @headers, $client->string('MUSIC');

	} else {

		# one level down we show the folder name, below that we show two levels
		my $level = (scalar @levels > 2) ? $levels[-2] : $levels[-1];
		my $obj   = Slim::Schema->find('Track', $level);

		if (blessed($obj) && $obj->can('title')) {

			push @headers, $obj->title;
		}
	}
	
	# Finally get the last selection position within the list	
	my $listIndex    = $client->lastID3Selection($hierarchy) || 0;
	my $topLevelPath = $topLevelObj->path;

	my %params = (

		# Parameters for INPUT.List
		'header'         => join('/', @headers),
		'headerAddCount' => ($count > 0),
		'listRef'        => $items,
		'listIndex'      => $listIndex,
		'noWrap'         => ($count <= 1),
		'callback'       => \&browseTreeExitCallback,

		# Have the callback give us the listIndex - which is needed
		# for on-the-fly object creation.
		'externRef'      => \&browseTreeItemName,
		'externRefArgs'  => 'CVI',

		'overlayRef'     => \&browseTreeOverlay,

		'onChange'       => sub {
			my ($client, $curDepth) = @_;

			$client->lastID3Selection($hierarchy, $curDepth);
		},

		'onChangeArgs'   => 'CI',

		# Parameters that reflect the state of this mode
		'hierarchy'      => join('/', @levels),
		'descend'        => 1,
		'topLevelPath'   => $topLevelPath,

		# This allows a sort to be done on the list.
		# There might be a more optimized way to handle this, but it's
		# good for now.
		'isSorted'     => 'L',

		'lookupRef'    => sub {
			my $index = shift;

			return Slim::Utils::Text::ignoreCaseArticles($items->[$index]);
		},
	);

	Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:

