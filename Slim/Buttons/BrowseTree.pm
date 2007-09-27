package Slim::Buttons::BrowseTree;

# $Id$

# SqueezeCenter Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Buttons::BrowseTree

=head1 DESCRIPTION

L<Slim::Buttons::BrowseTree> is a SqueezeCenter module for browsing through a
folder structure and displaying information about music files on a Slim
Devices Player display.

=cut

use strict;
use Scalar::Util qw(blessed);

use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Buttons::TrackInfo;
use Slim::Music::Info;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

our %functions = ();
our $mixer;

=head1 METHODS

=head2 init( )

When a music folder preference exists for SqueezeCenter, init will create a menu item for Browse Music Folder and register the required mode
init() also creates the function hash for the required button handling whiel in 'browsetree' mode.

=cut

sub init {

	my $name = 'BROWSE_MUSIC_FOLDER';
	my $mode = 'browsetree';
	my $menu = {
		'useMode'  => $mode,
		'hierarchy' => '',
	};

	if ($prefs->get('audiodir')) {
		Slim::Buttons::Common::addMode($mode, Slim::Buttons::BrowseTree::getFunctions(), \&Slim::Buttons::BrowseTree::setMode);
	
		Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC', $name, $menu);
		Slim::Buttons::Home::addMenuOption($name, $menu);
	} else {
		Slim::Buttons::Home::delSubMenu('BROWSE_MUSIC', $name, $menu);
		Slim::Buttons::Home::delMenuOption($name, $menu);
	}
	
	%functions = (
		'play' => sub {
			my $client = shift;
			my $button = shift;
			my $addorinsert = shift || 0;

			my $items       = $client->modeParam('listRef');
			my $listIndex   = $client->modeParam('listIndex');
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
				'line'    => [ $line1, $line2 ],
				'overlay' => [ undef, $client->symbols('notesymbol') ]
			});

			if ($descend || !$prefs->get('playtrackalbum') || $addorinsert || !Slim::Music::Info::isSong($currentItem)) {

				$client->execute(['playlist', $command, $currentItem]);

			## playing other songs in folder, ONLY on play command from remote.
			## non-objects are quickly converted to urls so that the playlist render
			## can do lazy object conversion later.
			} else {

				my $wasShuffled = Slim::Player::Playlist::shuffle($client);
				my $log         = logger('player.playlist');

				Slim::Player::Playlist::shuffle($client, 0);

				$client->execute(['playlist', 'clear']);

				$log->info("Playing all in folder, starting with $listIndex");

				my @playlist = ();

				# iterate through list in reverse order, so that dropped items don't affect the index as we subtract.
				for my $i (reverse (0..scalar @{$items}-1)) {

					if (!ref $items->[$i]) {
						$items->[$i] =  Slim::Utils::Misc::fixPath($items->[$i], $client->modeParam('topLevelPath'));
					}

					if (!Slim::Music::Info::isSong($items->[$i])) {

						$log->info("Dropping $items->[$i] from play all in folder at index $i");

						if ($i < $listIndex) {
							$listIndex--;
						}

						next;
					}

					unshift (@playlist, $items->[$i]);
				}

				$log->info("Load folder playlist, now starting at index: $listIndex");

				$client->execute(['playlist', 'addtracks','listref', \@playlist]);
				$client->execute(['playlist', 'jump', $listIndex]);

				if ($wasShuffled) {
					$client->execute(['playlist', 'shuffle', 1]);
				}
			}
		},
		
		'create_mix' => sub  {
			my $client = shift;

			my $items       = $client->modeParam('listRef');
			my $listIndex   = $client->modeParam('listIndex');
			my $currentItem = $items->[$listIndex] || return;
			my $descend     = Slim::Music::Info::isList($currentItem) ? 1 : 0;

			my $Imports = Slim::Music::Import->importers;

			my @mixers = ();

# 			TODO: bug 3869 ir map uses play.hold for mixing.  we should add mixing from BMF where possible
#			For now, we'll set this up to fall back to play.
#			for my $import (keys %{$Imports}) {

#				next if !$Imports->{$import}->{'mixer'};
#				next if !$Imports->{$import}->{'use'};

#				if (!$descend && $import->mixable($currentItem)) {
#					push @mixers, $import;
#				}
#			}

			if (scalar @mixers == 1) {

				logger('server.plugin')->info("Running Mixer $mixers[0]");

				&{$Imports->{$mixers[0]}->{'mixer'}}($client);

			} elsif (@mixers) {

				# store existing browsedb params for use later.
				my $params = {
					'parentParams'    => $client->modeParameterStack(-1),
					'listRef'         => \@mixers,
					'externRef'       => sub { return $_[0]->string($_[1]->title) },
					'externRefArgs'   => 'CV',
					'header'          => 'CREATE_MIX',
					'headerAddCount'  => 1,
					'stringHeader'    => 1,
					'callback'        => \&mixerExitHandler,
					'overlayRef'      => sub { return (undef, shift->symbols('rightarrow')) },
					'overlayRefArgs'  => 'C',
					'valueRef'        => \$mixer,
				};

				Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', $params);

			} else {

				# if we don't have mix generation, then just play
				(getFunctions())->{'play'}($client);
			}
		}
	);
}

sub getFunctions {
	return \%functions;
}

=head2 browseTreeExitCallback( $client, $exittype)

When returning from INPUT>List mode used by browse tree for list navigation, the browseTreeExitCallback function is called, with the $client structure
and the string to identify the $exittype from INPUT.List. (usually either 'LEFT' or 'RIGHT').  The callback then updates the params required and moves
to the next appropriate level of the folder structure.  At the track level, navigating right enters 'trackinfo' mode.

=cut

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

	my $currentItem = ${$client->modeParam('valueRef')};

	my $descend     = Slim::Music::Info::isList($currentItem) ? 1 : 0;

	my @levels      = split(/\//, $client->modeParam('hierarchy'));

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

=head2 browseTreeExitCallback( $client, $item, $index)

Method invoked by INPUT.List to map an item in the list to a display name.
This requires the $client structure as well as a reference to the selected item, or a url, plus the zero-referenced $index
for the position in the current list of items.

=cut

sub browseTreeItemName {
	my ($client, $item, $index) = @_;

	if (!ref($item)) {

		# Dynamically pull the object from the DB. This prevents us from
		# having to do so at initial load time of possibly hundreds of items.
		my $url = Slim::Utils::Misc::fixPath($item, $client->modeParam('topLevelPath')) || return;

		if (Slim::Music::Info::isWinShortcut($url)) {

			$url = Slim::Utils::Misc::fileURLFromWinShortcut($url);
		}

		my $items = $client->modeParam('listRef');

		my $track = Slim::Schema->rs('Track')->objectForUrl({
			'url'      => $url,
			'create'   => 1,
			'readTags' => 1,
			'commit'   => 1,

		}) || return $url;

		${$client->modeParam('valueRef')} = $item = $items->[$index] = $track;
	}

	return Slim::Utils::Unicode::utf8on( Slim::Music::Info::fileName($item->url) );
}

=head2 browseTreeExitCallback( $client, $item)

Method invoked by INPUT.List to map an item in the list to overlay characters.

=cut

sub browseTreeOverlay {
	my $client = shift;
	my $item   = shift || return;

	my ($overlay1, $overlay2);

	# A text item generally means ALL_, so overlay an arrow
	if (!ref $item) {
		return (undef, $client->symbols('rightarrow'));
	}

	if (Slim::Music::Info::isSong($item)) {
		$overlay2 = $client->symbols('notesymbol');
	} else {
		$overlay2 = $client->symbols('rightarrow');
	}

	return ($overlay1, $overlay2);
}

=head2 browseTreeExitCallback( $client, $item)

Method invoked by Slim::Buttons::Common to preset the required parameters and enter the 'browsetree' mode.

=cut

sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	# Parse the hierarchy list into an array
	my $hierarchy = $client->modeParam('hierarchy') || '';
	my @levels    = split(/\//, $hierarchy);

	# Show a blocking animation
	$client->block({
		'line' => [ $client->string( $client->linesPerScreen() == 1 ? 'LOADING' : 'LOADING_BROWSE_MUSIC_FOLDER' ) ],
	});

	my ($topLevelObj, $items, $count) = Slim::Utils::Misc::findAndScanDirectoryTree( { 'id' => $levels[-1] } );

	# if we have no level, we just sent undef to findAndScanDirectoryTree with our $levels[-1]
	# findAndScanDirectoryTree will fall back to some sensible default if sent undef
	# use this sensible default to create the @levels array
	if (!scalar(@levels)) {
		# FIXME: ?? this will die if findAndScanDirectoryTree does not return a valid $topLevelObj
		push @levels, $topLevelObj->id();
	}
	
	$client->unblock;

	# Next get the first line of the mode
	my @headers = ();

	# top level, we show MUSIC FOLDER
	if (scalar @levels == 1) {

		push @headers, $client->string('MUSIC');

	} else {

		# one level down we show the folder name, below that we show two levels

		for (my $x = (scalar @levels > 2 ? -2 : -1); $x <= -1; $x++) {

			my $obj   = Slim::Schema->find('Track', $levels[$x]);

			if (blessed($obj) && $obj->can('title')) {

				push @headers, ($obj->title ? $obj->title : Slim::Music::Info::fileName($obj->url));
			}
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

			return ref $items->[$index] && $items->[$index]->can('titlesort') ? 
				$items->[$index]->titlesort : Slim::Utils::Text::ignoreCaseArticles($items->[$index]);
		},
	);

	Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

L<Slim::Buttons::TrackInfo>

L<Slim::Music::Info>

=cut

1;

__END__
