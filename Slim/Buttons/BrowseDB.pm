package Slim::Buttons::BrowseDB;

# $Id$

# SlimServer Copyright (C) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Buttons::BrowseDB

=head1 DESCRIPTION

L<Slim::Buttons::BrowseTree> is a SlimServer module which adds several
modes for browsing a music collection using a variety of 'hierarchies' and 
music metadata stored in a database.

=cut

use strict;
use Scalar::Util qw(blessed);
use Storable;

use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Buttons::TrackInfo;
use Slim::Music::Info;
use Slim::Utils::Log;
use Slim::Utils::Misc;

our %functions = ();
our $mixer;

=head1 METHODS

=head2 init( )

Create menu items for entering each hierarchy, starting with Browse by- New Music, Genre, Artist, Year and browse playlists.
Registers the generic 'browsedb' mode used by all of the hierarchies.

=cut

# Code to browse music folder by ID3 information.
sub init {

	Slim::Buttons::Common::addMode('browsedb',Slim::Buttons::BrowseDB::getFunctions(),\&Slim::Buttons::BrowseDB::setMode);

	my %browse = (

		'BROWSE_NEW_MUSIC' => {
			'useMode'   => 'browsedb',
			'hierarchy' => 'age,track',
			'level'     => 0,
		},

		'BROWSE_BY_GENRE'  => {
			'useMode'   => 'browsedb',
			'hierarchy' => 'genre,contributor,album,track',
			'level'     => 0,
		},

		'BROWSE_BY_ARTIST' => {
			'useMode'   => 'browsedb',
			'hierarchy' => 'contributor,album,track',
			'level'     => 0,
		},

		'BROWSE_BY_ALBUM'  => {
			'useMode'   => 'browsedb',
			'hierarchy' => 'album,track',
			'level'     => 0,
		},

		'BROWSE_BY_YEAR'  => {
			'useMode'   => 'browsedb',
			'hierarchy' => 'year,album,track',
			'level'     => 0,
		},

		'BROWSE_BY_SONG'   => {
			'useMode'   => 'browsedb',
			'hierarchy' => 'track',
			'level'     => 0,
		},

		'SAVED_PLAYLISTS'  => {
			'useMode'   => 'browsedb',
			'hierarchy' => 'playlist,playlistTrack',
			'level'     => 0,
		},
	);
	
	for my $name (sort keys %browse) {

		if ($name ne 'BROWSE_BY_SONG') {
			Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC', $name, $browse{$name});
		}

		Slim::Buttons::Home::addMenuOption($name, $browse{$name});
	}

	%functions = (
		'play' => sub  {
			my $client = shift;
			my $button = shift;
			my $addorinsert = shift || 0;

			my $items       = $client->modeParam('listRef');
			my $listIndex   = $client->modeParam('listIndex');
			my $currentItem = $items->[$listIndex] || return;

			if ($client->modeParam('header') eq 'CREATE_MIX') {

				# Bug 3459: short circuit for mixers
				mixerExitHandler($client, 'RIGHT');
				return;
			}

			my ($command, $line1, $line2, $string);

			# Based on the button pressed, we determine what to display
			# and which command to send to modify the playlist
			if ($addorinsert == 1) {

				$string = 'ADDING_TO_PLAYLIST';
				$command = "addtracks";	

			} elsif ($addorinsert == 2) {

				$string  = 'INSERT_TO_PLAYLIST';
				$command = "inserttracks";

			} else {

				$command = "loadtracks";

				if (Slim::Player::Playlist::shuffle($client)) {
					$string = 'PLAYING_RANDOMLY_FROM';
				} else {
					$string = 'NOW_PLAYING_FROM';
				}
			}
	
			if ($client->linesPerScreen == 1) {

				$line2 = $client->doubleString($string);

			} else {

				$line1 = $client->string($string);
				$line2 = browsedbItemName($client, $currentItem);
			}

			$client->showBriefly({
				'line'    => [ $line1, $line2 ],
				'overlay' => [ undef, $client->symbols('notesymbol') ],
			});

			my $hierarchy    = $client->modeParam('hierarchy');
			my $level        = $client->modeParam('level');
			my $descend      = $client->modeParam('descend');
			my $findCriteria = $client->modeParam('findCriteria');
			my $search       = $client->modeParam('search');

			my @levels       = split(',', $hierarchy);
			my $all          = !blessed($currentItem);
			my $levelName    = $levels[$level];

			# Include the current item
			if ($levelName ne 'track' && !$all) {

				$findCriteria->{"$levelName.id"} = $currentItem->id;
			}

			# Handle the ALL_* case from a search. Pass off to Commands.
			if ($all && $search) {

				my $field = 'me.titlesearch';

				if ($levelName eq 'contributor') {

					$field = 'contributor.titlesearch';

				} elsif ($levelName eq 'album') {

					$field = 'album.titlesearch';
				}

				$findCriteria->{$field} = { 'like' => $search };
			}

			# If we're dealing with a group of tracks...
			if ($descend || $all) {

				# If we're dealing with the ALL option of a search,
				# perform the search and play the track results
				#my $levelRS = Slim::Schema->rs($levelName);

				#if ($all && $levelRS->allTransform) {

					# $termlist .= sprintf('&fieldInfo=%s', $levelRS->allTransform);
				#}

				# Otherwise rely on the execute to do the search for us
				$client->execute(["playlist", $command, $findCriteria]);
			}
			# Else if we pick a single song
			else {
				# find out if this item is part of a container, such as an album or playlist previously selected.
				my $container = 0;

				if ($levels[$level-1] =~ /^(?:playlist|album|age)$/ && 
					grep { /^(?:playlist|me|album|age)\.id$/ } keys %{$findCriteria}) {

					$container = 1;
				}

				# In some cases just deal with the song individually
				if ($addorinsert || !$container || !Slim::Utils::Prefs::get('playtrackalbum')) {

					$command = 'playtracks';
					$command = 'addtracks'    if $addorinsert == 1;
					$command = 'inserttracks' if $addorinsert == 2;

					$client->execute(["playlist", $command, 'listref', [ $currentItem ]]); 
				}
				# Otherwise deal with it in the context of the 
				# containing album or playlist.
				else {
					my $wasShuffled = Slim::Player::Playlist::shuffle($client);

					Slim::Player::Playlist::shuffle($client, 0);

					$client->execute(["playlist", "clear"]);
					$client->execute(["playlist", "addtracks", $findCriteria]);
					$client->execute(["playlist", "jump", $listIndex]);

					if ($wasShuffled) {
						$client->execute(["playlist", "shuffle", 1]);
					}
				}
			}
		},

		'create_mix' => sub  {
			my $client = shift;

			my $items       = $client->modeParam('listRef');
			my $listIndex   = $client->modeParam('listIndex');
			my $currentItem = $items->[$listIndex] || return;

			my $Imports = Slim::Music::Import->importers;

			my @mixers = ();

			for my $import (keys %{$Imports}) {

				next if !$Imports->{$import}->{'mixer'};
				next if !$Imports->{$import}->{'use'};

				if (eval {$import->mixable($currentItem)}) {
					push @mixers, $import;
				}
			}

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
					'overlayRef'      => sub { return (undef, Slim::Display::Display::symbol('rightarrow')) },
					'overlayRefArgs'  => '',
					'valueRef'        => \$mixer,
				};

				Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', $params);
			
			} else {
			
				# if we don't have mix generation, then just play
				(getFunctions())->{'play'}($client);
			}
		},
	);
}

=head2 mixerExitHandler( $client, $exittype)

Special List exist handler for triggering a mixer.  Mixers are specialised plugins that will generate playlist information based
on a given seed.  The $client param is required, as well as the $exittype string.  Plugins that wish to use the mixer AIP must register an 
Importer with a mixer function.

=cut

sub mixerExitHandler {
	my ($client, $exittype) = @_;

	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {

		my $Imports = Slim::Music::Import->importers;

		if (defined $Imports->{$mixer}->{'mixer'}) {

			logger('server.plugin')->info("Running Mixer $mixer");

			&{$Imports->{$mixer}->{'mixer'}}($client);

		} else {

			$client->bumpRight();
		}
	}
}

sub getFunctions {
	return \%functions;
}

=head2 browsedbExitCallback( $client, $exittype)

Callback invoked by INPUT.List when we're going to leave the 'browsedb' mode or 
move to the next level of the current hierarchy.

=cut

sub browsedbExitCallback {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);

	# Set the last selection position within the list
	my $listIndex = $client->modeParam('listIndex');

	# Left means pop out of this mode
	if ($exittype eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);

	# Right means select the current item
	} elsif ($exittype eq 'RIGHT') {

		my $items       = $client->modeParam('listRef');
		my $hierarchy   = $client->modeParam('hierarchy');
		my $level       = $client->modeParam('level');
		my $descend     = $client->modeParam('descend');

		my $currentItem = $items->[$listIndex];
		my @levels      = split(',', $hierarchy);

		my $levelRS     = Slim::Schema->rs($levels[$level]);

		my $all         = 0;

		if (defined $currentItem && $levels[$level+1]) {

			my $nextRS = Slim::Schema->rs($levels[$level+1]);

			if ($nextRS && $nextRS->allTitle && $nextRS->allTitle eq $currentItem) {

				$all = 1;
			}

		} elsif (!ref($currentItem) && $levels[$level] eq 'track') {

			# If we're at all and the track level - bump right.
			# Getting the same list of songs again is pointless.
			$currentItem = undef;
		}

		if (!defined $currentItem) {

			$client->bumpRight;

		} elsif ($currentItem eq 'FAVORITE') {

			my $num   = $client->modeParam('favorite');
			my $track = Slim::Schema->find('Track', $client->modeParam('findCriteria')->{'playlist.id'});

			if (!blessed($track) || !$track->can('title')) {

				logError("Couldn't find a valid object for playlist!");

				$client->showBriefly($client->string('PROBLEM_OPENING'));

				return;
			}

			if ($num < 0) {

				$num = Slim::Utils::Favorites->clientAdd($client, $track, $track->title);

				$client->showBriefly($client->string('FAVORITES_ADDING'), $track->title);

				$client->modeParam('favorite', $num);

			} else {

				Slim::Utils::Favorites->deleteByClientAndURL($client, $track);

				$client->showBriefly($client->string('FAVORITES_DELETING'), $track->title);

				$client->modeParam('favorite', -1);
			}

		} elsif ($descend || $all) {

			# If we're dealing with a container or an ALL list
			my $findCriteria      = Storable::dclone($client->modeParam('findCriteria'));
			my $selectionCriteria = $client->modeParam('selectionCriteria');
			my $field             = $levels[$level];

			# Include the current item in the find criteria for the next level down.
			if (!$all) {

				if ($field eq 'contributor' && 
					$currentItem->id eq Slim::Schema->variousArtistsObject->id &&
					Slim::Utils::Prefs::get('variousArtistAutoIdentification')) {

					$findCriteria->{'album.compilation'} = 1;
				}

				$findCriteria->{"$field.id"} = $currentItem->id;
			}

			my %params = (
				'hierarchy'         => $hierarchy,
				'level'             => $level + 1,
				'findCriteria'      => $findCriteria,
				'selectionCriteria' => $selectionCriteria,
			);

			# Only include the search terms (i.e. those associated with
			# an actual text search) if we're dealing with the ALL case.
			if ($all) {
				$params{'search'} = $client->modeParam('search');
			}

			# Push recursively in to the same mode for the next level down.
			Slim::Buttons::Common::pushModeLeft($client, 'browsedb', \%params);

		} else {

			# For a track, push into the track information mode
			Slim::Buttons::Common::pushModeLeft($client, 'trackinfo', { 'track' => $currentItem });
		}

	} else {

		$client->bumpRight();
	}
}

# Method invoked by INPUT.List to map an item in the list
# to a display name.
sub browsedbItemName {
	my $client = shift;
	my $item   = shift;
	my $index  = shift;

	my $hierarchy = $client->modeParam('hierarchy');
	my $level     = $client->modeParam('level');

	my @levels    = split(',', $hierarchy);
	
	my $levelRS   = Slim::Schema->rs($levels[$level]);
	my $blessed   = blessed($item) ? 1 : 0;

	if (!$blessed && $levels[$level+1]) {

		my $nextRS = Slim::Schema->rs($levels[$level+1]);

		if ($nextRS->allTitle eq $item) {

			return $client->string($item);
		}

	} elsif (!$blessed && $levels[$level] eq 'track') {

		if ($levelRS->allTitle eq $item) {

			return $client->string($item);
		}
	}

	# special case favorites line, which must be determined dynamically
	if (!$blessed && $item eq 'FAVORITE') {

		if ((my $num = $client->modeParam('favorite')) < 0) {
			$item = $client->string('FAVORITES_RIGHT_TO_ADD');
		} else {
			$item = $client->string('FAVORITES_FAVORITE_NUM') . "$num " . $client->string('FAVORITES_RIGHT_TO_DELETE');
		}

		return $item
	}
	
	# Inflate IDs to objects on the fly.
	if (!$blessed) {

		# Short circuit for the VA/Compilation string
		if ($levels[$level] eq 'contributor' && 
			$item->id eq Slim::Schema->variousArtistsObject->id) {

			return $item->name;
		}

		my $items  = $client->modeParam('listRef');
		my $field  = $levels[$level];
		my $newObj = Slim::Schema->find($field, $item);

		if (!defined $newObj) {

			return $client->string($item);

		} elsif (blessed($newObj) && $newObj->can('id')) {

			${$client->modeParam('valueRef')} = $items->[$index] = $item = $newObj;

		} else {

			return $client->string('OBJECT_RETRIEVAL_FAILURE');
		}
	}

	if ( $levels[$level] =~ /(?:track|playlistTrack)/ ) {

		return Slim::Music::Info::standardTitle($client, $item);

	} elsif ($levels[$level] eq 'album' || $levels[$level] eq 'age') {

		my @name         = $item->name;
		my $findCriteria = $client->modeParam('findCriteria') || {};

		if (Slim::Utils::Prefs::get('showYear') && !$findCriteria->{'year.id'}) {

			if (my $year = $item->year) {

				push @name, " ($year)";
			}
		}

		if (Slim::Utils::Prefs::get('showArtist') && !$findCriteria->{'contributor.id'}) {

			my @artists  = ();
			my $noArtist = $client->string('NO_ARTIST');

			for my $artist ($item->artists) {

				if (blessed($artist)) {

					next if $artist->name eq $noArtist;

					push @artists, $artist->name;
				}
			}

			if (scalar @artists) {

				push @name, sprintf(' %s %s', $client->string('BY'), join(', ', @artists));
			}
		}

		return join('', @name);

	} else {

		return $item->name;
	}
}

# Method invoked by INPUT.List to map an item in the list
# to overlay characters.
sub browsedbOverlay {
	my $client = shift;
	my $item   = shift;

	my ($overlay1, $overlay2);

	my $hierarchy = $client->modeParam('hierarchy');
	my $level     = $client->modeParam('level') || 0;
	my @levels    = split(',', $hierarchy);

	# No overlay if the list is empty
	if (!defined($item)) {

		return (undef, undef);

	} elsif (!ref($item)) {

		# A text item means ALL_, so overlay a note & arrow. But not
		# for the track item, which we're already at the lowest level.
		if ($levels[$level] ne 'track') {

			return (undef, join('', 
				Slim::Display::Display::symbol('notesymbol'),
				Slim::Display::Display::symbol('rightarrow')
			));

		} else {

			return (undef, Slim::Display::Display::symbol('notesymbol'));
		}

	} else {

		# Music Magic is everywhere
		my $Imports = Slim::Music::Import->importers;

		for my $import (keys %{$Imports}) {
			if ($import->can('mixable') && $import->mixable($item)) {
				$overlay1 = Slim::Display::Display::symbol('mixable');
			}
		}
	}

	if ($client->modeParam('descend')) {
		$overlay2 = Slim::Display::Display::symbol('rightarrow');
	} else {
		$overlay2 = Slim::Display::Display::symbol('notesymbol');
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

	my $hierarchy = $client->modeParam('hierarchy');
	my $level     = $client->modeParam('level') || 0;
	my $search    = $client->modeParam('search');
	my $log       = logger('database.info');

	$log->debug("hierarchy: $hierarchy level: $level");

	# Parse the hierarchy list into an array
	my @levels   = split(',', $hierarchy);

	my $maxLevel = scalar(@levels) - 1;

	if ($level > $maxLevel)	{
		$level = $maxLevel;
	}

	my $descend = ($level >= $maxLevel) ? undef : 1;

	my $rs      = Slim::Schema->rs($levels[$level]);
	my $topRS   = Slim::Schema->rs($levels[0]);
	my %names   = ();

	# First get the names of the specified parameters.
	# These could be necessary for titles.
	my $setAllName = 0;

	my ($filters, $find, $sort) = $topRS->generateConditionsFromFilters({
		'rs'      => $rs,
		'level'   => $level,
		'levels'  => \@levels,
		'params'  => ($client->modeParam('findCriteria') || {}),
	});

	# Build up the names for the top line
	for my $i (0..$#levels) {

		my $field = $levels[$i];
		my $rs    = Slim::Schema->rs($field) || next;

		if ($setAllName && $rs->allTitle) {

			$names{$levels[$i-1]} = $client->string($rs->allTitle);
		}

		if (defined($filters->{"$field.id"})) {

			$names{$levels[$i]} = $rs->find($filters->{"$field.id"})->name;

			$setAllName = 0;

		} else {

			$setAllName = 1;
		}
	}

	# Next to the actual query to get the items to display
	my @items = ();

	if (defined $search) {

		@items = $rs->searchNames($search)->all;

	} else {

		# Bug: 3654 Pass a copy of the find ref, so we don't modify it.
		# This isn't an issue for the webUI, as it reconstructs $find every time.
		$topRS = $topRS->descend(Storable::dclone($filters), Storable::dclone($find), $sort, @levels[0..$level]);

		if ($levels[$level] eq 'age') {

			@items = $topRS->slice(0, (Slim::Utils::Prefs::get('browseagelimit') - 1));

		} else {

			@items = $topRS->all;
		}
	}

	# Next get the first line of the mode
	my $header;
	my $count = scalar @items;

	if ($level == 0) {

		if ($search) {

			my $plural = $count > 1 ? 'S' : '';

			$header = $client->string(uc($levels[$level]).$plural.'MATCHING') . " \"" . searchTerm($search->[0]) . "\"";

		} else {

			$header = $client->string($rs->title);
		}

	} elsif ($level == 1) {

		$header = $names{$levels[$level-1]}; 

	} else {

		$header = $names{$levels[$level-2]} . "/" . $names{$levels[$level-1]};
	}

	# Then see if we have to add an ALL option
	if (($descend || $search) && $count > 1 && !$rs->suppressAll) {

		# Use the ALL_ version of the next level down in the hirearchy
		if ($descend) {

			push @items, Slim::Schema->rs($levels[$level+1])->allTitle;

		} elsif ($level == 0) {

			# Unless this is a list of songs at the top level, in which
			# case, we add an ALL_SONGS
			push @items, $rs->allTitle;
		}
	}

	# Dynamically create a VA/Compilation item under artists, like iTunes does.
	if ($levels[$level] eq 'contributor' && !$search && Slim::Utils::Prefs::get('variousArtistAutoIdentification')) {

		# Only show VA if there exists valid data below this level.
		if (Slim::Schema->variousArtistsAlbumCount($filters)) {

			unshift @items, Slim::Schema->variousArtistsObject;
		}
	}

	# If the previous level is a playlist. IE: We're in playlistTracks -
	# let the user add a favorite for this playlist.
	if ($levels[$level-1] eq 'playlist') {

		my $track = Slim::Schema->find('Track', $filters->{'playlist.id'});

		if (blessed($track) && $track->can('id')) {
		
			my $fav = Slim::Utils::Favorites->findByClientAndURL($client, $track);

			if ($fav) {
				$client->modeParam('favorite', $fav->{'num'});
			} else {
				$client->modeParam('favorite', -1);
			}

			push @items, 'FAVORITE';
		}
	}

	# Finally get the last selection position within the list	
	my $listIndex = 0;
	my $selectionKey;
	my $selectionCriteria;

	if (defined $search) {

		$listIndex = 0;

	} elsif ($selectionCriteria = $client->modeParam('selectionCriteria')) {

		# Entering from trackinfo, so we need to set the selected item
		my $selection = $selectionCriteria->{sprintf('%s.id', $levels[$level])} || -1;
		my $j = 0;

		# search for matching selection in reverse order, so if not found we end up at item 0.
		for my $item (@items) {
			
			if (blessed($item) && $selection == $item->id) {
				$listIndex = $j;
				last;
			}
			
			$j++;
		}

	} else {

		$selectionKey = join(':', $hierarchy, $level, Storable::freeze($find));
		$listIndex    = $client->lastID3Selection($selectionKey) || 0;

		$log->debug("last position from selection key $selectionKey is $listIndex");
	}

	my %params = (

		# Parameters for INPUT.List
		header            => $header,
		headerAddCount    => (scalar(@items) > 0),
		listRef           => \@items,
		listIndex         => $listIndex,
		noWrap            => (scalar(@items) <= 1),
		callback          => \&browsedbExitCallback,
		externRef         => \&browsedbItemName,
		externRefArgs     => 'CVI',
		overlayRef        => \&browsedbOverlay,
		onChange          => sub { $_[0]->lastID3Selection($selectionKey, $_[1]) },
		onChangeArgs      => 'CI',

		# Parameters that reflect the state of this mode
		hierarchy         => $hierarchy,
		level             => $level,
		descend           => $descend,
		search            => $search,
		selectionKey      => $selectionKey,
		findCriteria      => $filters,
		selectionCriteria => $selectionCriteria,
		favorite          => $client->modeParam('favorite'),
	);

	# If this is a list of containers (e.g. albums, artists, genres)
	# that are not the result of a search, assume they are sorted.
	# sort at simple track level as well.

	# Test reworked, see Bug 4437
	if (($descend || !($levels[$level] eq 'track' || $levels[$level] eq 'playlistTrack')) && !$search) {

		$params{'isSorted'}  = 'L';

		$params{'lookupRef'} = sub {
			my $index = shift;
			my $item  = $items[$index];

			if (!ref($item)) {
				return $client->string($item);
			}

			return $item->namesort;
		};
	}

	Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);
}

sub searchTerm {
	my $t = shift;
	
	$t =~ s/^[\*\%]?(.+)[\*\%]$/$1/;

	return $t;
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

L<Slim::Buttons::TrackInfo>

L<Slim::Music::Import>

L<Slim::Schema>

=cut

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:

