package Slim::Buttons::BrowseDB;

# $Id: BrowseDB.pm 2765 2005-03-27 22:01:07Z vidur $

# SlimServer Copyright (C) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Buttons::TrackInfo;
use Slim::Music::Info;
use Slim::Utils::Misc;

our %functions = ();
our $mixer;

# Code to browse music folder by ID3 information.
sub init {

	Slim::Buttons::Common::addMode('browsedb',Slim::Buttons::BrowseDB::getFunctions(),\&Slim::Buttons::BrowseDB::setMode);

	my %browse = (

		'BROWSE_NEW_MUSIC' => {
			'useMode'  => 'browsedb',
			'hierarchy' => 'age,track',
			'level' => 0,
		},

		'BROWSE_BY_GENRE'  => {
			'useMode'  => 'browsedb',
			'hierarchy' => 'genre,artist,album,track',
			'level' => 0,
		},

		'BROWSE_BY_ARTIST' => {
			'useMode'  => 'browsedb',
			'hierarchy' => 'artist,album,track',
			'level' => 0,
		},

		'BROWSE_BY_ALBUM'  => {
			'useMode'  => 'browsedb',
			'hierarchy' => 'album,track',
			'level' => 0,
		},

		'BROWSE_BY_SONG'   => {
			'useMode'  => 'browsedb',
			'hierarchy' => 'track',
			'level' => 0,
		},

		'SAVED_PLAYLISTS'  => {
			'useMode'  => 'browsedb',
			'hierarchy' => 'playlist,track',
			'level' => 0,
		},
	);
	
	for my $name (sort keys %browse) {

		if ($name ne 'BROWSE_BY_SONG') {
			Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC', $name, $browse{$name});
		}

		Slim::Buttons::Home::addMenuOption($name, $browse{$name});
	};

	%functions = (
		'play' => sub  {
			my $client = shift;
			my $button = shift;
			my $addorinsert = shift || 0;

			my $items = $client->param('listRef');
			my $listIndex = $client->param('listIndex');
			my $currentItem = $items->[$listIndex];

			return unless defined($currentItem);

			my $command;
			my ($line1, $line2);

			# Based on the button pressed, we determine what to display
			# and which command to send to modify the playlis
			if ($addorinsert == 1) {

				$line1 = $client->string('ADDING_TO_PLAYLIST');
				$command = "addtracks";	

			} elsif ($addorinsert == 2) {

				$line1 = $client->string('INSERT_TO_PLAYLIST');
				$command = "inserttracks";

			} else {

				$command = "loadtracks";

				if (Slim::Player::Playlist::shuffle($client)) {
					$line1 = $client->string('PLAYING_RANDOMLY_FROM');
				} else {
					$line1 = $client->string('NOW_PLAYING_FROM');
				}
			}
	
			# Get the name of the items we're currently displaying
			$line2 = browsedbItemName($client, $currentItem);

			$client->showBriefly(
				$client->renderOverlay($line1, $line2, undef, Slim::Display::Display::symbol('notesymbol')),
				undef,
				1
			);

			my $hierarchy = $client->param('hierarchy');
			my $level     = $client->param('level');
			my $descend   = $client->param('descend');
			my $findCriteria = $client->param('findCriteria');
			my $all = !ref($currentItem);
			
			my @levels = split(",", $hierarchy);

			my $ds = Slim::Music::Info::getCurrentDataStore();
			my $fieldInfo = Slim::Web::Pages::fieldInfo();

			# Create the search term list that we will send along with
			# our command.
			my @terms = ();
			my $field = $levels[$level];
			my $info = $fieldInfo->{$field} || $fieldInfo->{'default'};
		
			if (my $transform = $info->{'nameTransform'}) {
				$field = $transform;
			}
				
			# Include the current item
			if ($field ne 'track' && !$all) {
				push @terms, $field . '=' . &{$info->{'resultToId'}}($currentItem);
			}

			# And all the search terms for the current mode
			push @terms, map { $_ . '=' . $findCriteria->{$_} } (keys %$findCriteria);
			my $termlist = join '&', @terms;

			# If we're dealing with a group of tracks...
			if ($descend || $all) {
				my $search = $client->param('search');

				# If we're dealing with the ALL option of a search,
				# perform the search and play the track results
				if ($all && $search) {
					$info = $fieldInfo->{$levels[0]} || $fieldInfo->{'default'};
					my $items = &{$info->{'search'}}($ds, $search, 'track');

					$client->execute(["playlist", $command, 'listref', $items]); 
				}
				# Otherwise rely on the execute to do the search for us
				else {
					$client->execute(["playlist", $command, $termlist]);
				}
			}
			# Else if we pick a single song
			else {
				# find out if this item is part of a container, such as an album or playlist previously selected.
				my $container = ${$client->param('findCriteria')}{'album'} || ${$client->param('findCriteria')}{'playlist'};

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
					$client->execute(["playlist", "addtracks", $termlist]);
					$client->execute(["playlist", "jump", $listIndex]);

					if ($wasShuffled) {
						$client->execute(["playlist", "shuffle", 1]);
					}
				}
			}
		},

		'create_mix' => sub  {
			my $client = shift;

			my $Imports = Slim::Music::Import::importers();
		
			my @mixers = ();
			
			for my $import (keys %{$Imports}) {
			
				if (defined $Imports->{$import}->{'mixer'} && $Imports->{$import}->{'use'}) {
					push @mixers, $import;
				}
			}

			if (scalar @mixers == 1) {
				
				$::d_plugins && msg("Running Mixer $mixers[0]\n");
				&{$Imports->{$mixers[0]}->{'mixer'}}($client);
				
			} elsif (@mixers) {
				my $params;
				
				# store existing browsedb params for use later.
				$params->{'parentParams'} = $client->modeParameterStack(-1);
				
				$params->{'listRef'} = \@mixers;
				$params->{'stringExternRef'} = 1;
				
				$params->{'header'} = 'INSTANT_MIX';
				$params->{'headerAddCount'} = 1;
				$params->{'callback'} = \&mixerExitHandler;
		
				$params->{'overlayRef'} = sub { return (undef, Slim::Display::Display::symbol('rightarrow')) };
		
				$params->{'overlayRefArgs'} = '';
				$params->{'valueRef'} = \$mixer;
				
				Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', $params);
			
			} else {
			
				# if we don't have mix generation, then just play
				(getFunctions())->{'play'}($client);
			}
		},
	);
}

sub mixerExitHandler {
	my ($client,$exittype) = @_;
	
	$exittype = uc($exittype);
	
	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
	
	} elsif ($exittype eq 'RIGHT') {
		my $Imports = Slim::Music::Import::importers();
	
		if (defined $Imports->{$mixer}->{'mixer'}) {
			$::d_plugins && msg("Running Mixer $mixer\n");
			&{$Imports->{$mixer}->{'mixer'}}($client);
		} else {
			$client->bumpRight();
		}
	
	} else {
		return;
	}
}

sub getFunctions {
	return \%functions;
}

# Callback invoked by INPUT.List when we're going to leave this mode
sub browsedbExitCallback {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);

	# Set the last selection position within the list
	my $listIndex = $client->param('listIndex');

	# Left means pop out of this mode
	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
	} 
	# Right means select the current item
	elsif ($exittype eq 'RIGHT') {
		my $items = $client->param('listRef');
		my $hierarchy = $client->param('hierarchy');
		my $level     = $client->param('level');
		my $descend   = $client->param('descend');

		my $currentItem = $items->[$listIndex];

		my $all = !ref($currentItem);

		my @levels = split(",", $hierarchy);

		if (!defined($currentItem)) {
			$client->bumpRight();
		}
		# If we're dealing with a container or an ALL list
		elsif ($descend || $all) {
			my $fieldInfo = Slim::Web::Pages::fieldInfo();

			my $findCriteria = { %{$client->param('findCriteria')} };
			my $field = $levels[$level];
			my $info = $fieldInfo->{$field} || $fieldInfo->{'default'};
				
			if (my $transform = $info->{'nameTransform'}) {
				$field = $transform;
			}
				
			# Include the current item in the find criteria for the
			# next level down.
			if (!$all) {
				$findCriteria->{$field} = &{$info->{'resultToId'}}($currentItem);
			}

			my %params = (
				hierarchy => $hierarchy,
				level => $level + 1,
				findCriteria => $findCriteria,
			);

			# Only include the search terms (i.e. those associated with
			# an actual tex search) if we're dealing with the ALL case.
			if ($all) {
				$params{'search'} = $client->param('search');
			}

			# Push recursively in to the same mode for the next level
			# down.
			Slim::Buttons::Common::pushModeLeft($client, 'browsedb', \%params);
		}
		# For a track, push into the track information mode
		else {
			Slim::Buttons::Common::pushModeLeft($client, 'trackinfo', { 'track' => $currentItem });
		}
	}
	else {
		$client->bumpRight();
	}
}

# Method invoked by INPUT.List to map an item in the list
# to a display name.
sub browsedbItemName {
	my $client = shift;
	my $item = shift;

	if (defined($item) && !ref($item)) {
		return $client->string($item);
	}

	my $hierarchy = $client->param('hierarchy');
	my $level     = $client->param('level');

	my @levels = split(",", $hierarchy);
	
	my $fieldInfo = Slim::Web::Pages::fieldInfo();
	my $levelInfo = $fieldInfo->{$levels[$level]} || $fieldInfo->{'default'};
	
	if ($levels[$level] eq 'track') {

		return Slim::Music::Info::standardTitle($client, $item);

	} elsif (($levels[$level] eq 'album') && $level == 0) {

		my $name = &{$levelInfo->{'resultToName'}}($item);
		
		if (my $showYear = Slim::Utils::Prefs::get('showYear')) {

			my $year = $item->year;

			$name .= " ($year)" if $year;
		}
		
		if (my $showArtist = Slim::Utils::Prefs::get('showArtist')) {
			
			my $artist;
			my ($track) = $item->tracks;
			
			if ($track) {
				$artist  = $track->artist;
			} else {
				msg("Item has no tracks\n");
				use Data::Dumper;
				print Dumper($item);
			}

			if (defined $artist && $artist ne $client->string('NO_ARTIST')) {
				$name .= ' ' . Slim::Utils::Strings::string('BY') . " $artist";
			}
		}

		return $name;

	} else {

		return &{$levelInfo->{'resultToName'}}($item);
	}
}

# Method invoked by INPUT.List to map an item in the list
# to overlay characters.
sub browsedbOverlay {
	my $client = shift;
	my $item = shift;
	my ($overlay1, $overlay2);

	# No overlay if the list is empty
	if (!defined($item)) {
		return (undef, undef);
	}
	# A text item generally means ALL_, so overlay an arrow
	elsif (!ref($item)) {
		return (undef, Slim::Display::Display::symbol('rightarrow'));
	}
	# Music Magic is everywhere, MoodLogic doesn't exist on albums
	elsif (($item->can('moodlogic_mixable') && $item->moodlogic_mixable()) || $item->musicmagic_mixable()) {
		$overlay1 = Slim::Display::Display::symbol('mixable');
	}

	my $descend   = $client->param('descend');
	if ($descend) {
		$overlay2 = Slim::Display::Display::symbol('rightarrow');
	}
	else {
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

	my $hierarchy = $client->param('hierarchy') || "genre";
	my $level     = $client->param('level') || 0;
	my $findCriteria = $client->param('findCriteria') || {};
	my $search    = $client->param('search');

	$::d_files && msg("browsedb - hierarchy: $hierarchy level: $level\n");

	# Parse the hierarchy list into an array
	my @levels = split(",", $hierarchy);

	my $maxLevel = scalar(@levels) - 1;

	if ($level > $maxLevel)	{
		$level = $maxLevel;
	}
	my $descend = ($level >= $maxLevel) ? undef : 'true';

	my $ds = Slim::Music::Info::getCurrentDataStore();
	my $fieldInfo = Slim::Web::Pages::fieldInfo();

	# First get the names of the specified parameters. These
	# could be necessary for titles.
	my %names = ();
	my $setAllName = 0;
	for my $i (0..$#levels) {
		my $field = $levels[$i];
		my $info = $fieldInfo->{$field} || $fieldInfo->{'default'};
		
		if (my $transform = $info->{'nameTransform'}) {
			$field = $transform;
		}

		if ($setAllName && $info->{'allTitle'}) {
			$names{$levels[$i-1]} = $client->string($info->{'allTitle'});
		}

		if (defined($findCriteria->{$field})) {
			$names{$field} = &{$info->{'idToName'}}($ds, $findCriteria->{$field});
			$setAllName = 0;
		}
		else {
			$setAllName = 1;
		}
	}

	my $levelInfo = $fieldInfo->{$levels[$level]} || $fieldInfo->{'default'};

	# Next to the actual query to get the items to display
	my $items;
	if (defined($search)) {
		my $info = $fieldInfo->{$levels[0]} || $fieldInfo->{'default'};

		$items = &{$info->{'search'}}($ds, $search, $levels[$level]);
	}
	else {
		$items = &{$levelInfo->{'find'}}($ds, $levels[$level], $findCriteria);
	}

	# Next get the first line of the mode
	my $header;
	if ($level == 0) {
		if ($search) {
			my $plural = scalar @$items > 1 ? 'S' : '';
			$header = $client->string(uc($levels[$level]).$plural.'MATCHING') . " \"" . searchTerm($search->[0]) . "\"";
		}
		else {
			$header = $client->string($levelInfo->{'title'});
		}
	}
	elsif ($level == 1) {
		$header = $names{$fieldInfo->{$levels[$level-1]}->{'nameTransform'}} || $names{$levels[$level-1]}; 
	}
	else {
		$header = $names{$levels[$level-2]} . "/" . $names{$levels[$level-1]};
	}

	# Then see if we have to add an ALL option
	if (($descend || $search) && scalar(@$items) > 1 && 
		!$levelInfo->{'suppressAll'}) {

		# Since we're going to modify, we have to make a copy
		$items = [ @$items ];

		# Use the ALL_ version of the next level down in the hirearchy
		if ($descend) {
			my $nextLevel  = $levels[$level+1];
			my $nextLevelInfo = $fieldInfo->{$nextLevel} || $fieldInfo->{'default'};
			
			push @$items, $nextLevelInfo->{'allTitle'};
		}
		
		# Unless this is a list of songs at the top level, in which
		# case, we add an ALL_SONGS
		elsif ($level == 0) {
			push @$items, $levelInfo->{'allTitle'};
		}
	}

	# Finally get the last selection position within the list	
	my $listIndex;
	my $selectionKey;
	if (defined($search)) {
		$listIndex = 0;
	}
	else {
		$selectionKey = $hierarchy . ':' . $level . ':';
		while (my ($k, $v) = each %$findCriteria) {
			$selectionKey .= $k . '=' . $v;
		}
		$listIndex = $client->lastID3Selection($selectionKey) || 0;
		$::d_files && msg("last position from selection key $selectionKey is $listIndex\n");
	}

	my %params = (

		# Parameters for INPUT.List
		header => $header,
		headerAddCount => (scalar(@$items) > 0),
		listRef => $items,
		listIndex => $listIndex,
		noWrap => (scalar(@$items) <= 1),
		callback => \&browsedbExitCallback,
		externRef => \&browsedbItemName,
		overlayRef => \&browsedbOverlay,
		onChange => sub {
			$_[0]->lastID3Selection($selectionKey,$_[1]);
		},
		onChangeArgs => 'CI',

		# Parameters that reflect the state of this mode
		hierarchy => $hierarchy,
		level => $level,
		descend => $descend,
		search => $search,
		selectionKey => $selectionKey,
		findCriteria => $findCriteria,
	);

	# If this is a list of containers (e.g. albums, artists, genres)
	# that are not the result of a search, assume they are sorted.
	if ($descend && !$search) {
		$params{'isSorted'} = 'L';
		$params{'lookupRef'} = sub {
			my $index = shift;
			my $item = $items->[$index];
			
			if (defined($item) && !ref($item)) {
				return $client->string($item);
			}
			
			my $levelInfo = $fieldInfo->{$levels[$level]} || $fieldInfo->{'default'};
			
			return &{$levelInfo->{'resultToSortedName'}}($item);
		};
	}

	Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);
}

sub searchTerm {
	my $t = shift;
	
	$t =~ s/^\*?(.+)\*$/$1/;
	return $t;
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:

