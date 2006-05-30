package Slim::Buttons::BrowseDB;

# $Id$

# SlimServer Copyright (C) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Scalar::Util qw(blessed);
use Storable;

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
			'hierarchy' => 'playlist,track',
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

			my $items       = $client->param('listRef');
			my $listIndex   = $client->param('listIndex');
			my $currentItem = $items->[$listIndex] || return;

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
	
			if ($client->linesPerScreen() == 1) {

				$line2 = $client->doubleString($string);

			} else {

				$line1 = $client->string($string);
				$line2 = browsedbItemName($client, $currentItem);

			}

			$client->showBriefly({
				'line1'    => $line1,
				'line2'    => $line2,
				'overlay2' => $client->symbols('notesymbol'),
			});

			my $hierarchy    = $client->param('hierarchy');
			my $level        = $client->param('level');
			my $descend      = $client->param('descend');
			my $findCriteria = $client->param('findCriteria');
			
			my @levels       = split(',', $hierarchy);
			my $all          = (!ref($currentItem) && $levels[$level] ne 'year');

			# Create the search term list that we will send along with our command.
			my @terms        = ();
			my $field        = $levels[$level];

			my $levelRS      = Slim::Schema->rs($field);
		
			if (my $transform = $levelRS->nameTransform) {
				$field = $transform;
			}
				
			# Include the current item
			if ($field ne 'track' && !$all) {
				push @terms, join('=', $field, $currentItem->id);
			}

			# And all the search terms for the current mode
			push @terms, map { $_ . '=' . 
				(ref $findCriteria->{$_} eq 'ARRAY' ? join '',@{$findCriteria->{$_}} : $findCriteria->{$_}) } 
					(keys %$findCriteria);
			my $termlist = join '&', @terms;

			# If we're dealing with a group of tracks...
			if ($descend || $all) {

				my $search = $client->param('search');

				# If we're dealing with the ALL option of a search,
				# perform the search and play the track results
				if ($all && $search) {

					my $items = [ Slim::Schema->search('Track', $search)->all ];

					$client->execute(["playlist", $command, 'listref', $items]); 

				} else {

					if ($all && $levelRS->allTransform) {

						$termlist .= sprintf('&fieldInfo=%s', $levelRS->allTransform);
					}

					# Otherwise rely on the execute to do the search for us
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

			my $Imports = Slim::Music::Import->importers;
		
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

				# store existing browsedb params for use later.
				my $params = {

					'parentParams'    => $client->modeParameterStack(-1),
					'listRef'         => \@mixers,
					'stringExternRef' => 1,
					'header'          => 'INSTANT_MIX',
					'headerAddCount'  => 1,
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

sub mixerExitHandler {
	my ($client, $exittype) = @_;

	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {

		my $Imports = Slim::Music::Import->importers;

		if (defined $Imports->{$mixer}->{'mixer'}) {

			$::d_plugins && msg("Running Mixer $mixer\n");
			&{$Imports->{$mixer}->{'mixer'}}($client);

		} else {

			$client->bumpRight();
		}
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

		my $items       = $client->param('listRef');
		my $hierarchy   = $client->param('hierarchy');
		my $level       = $client->param('level');
		my $descend     = $client->param('descend');

		my $currentItem = $items->[$listIndex];
		my @levels      = split(',', $hierarchy);

		my $levelRS     = Slim::Schema->rs($levels[$level]);

		my $all         = 0;

		if (defined $currentItem && $levels[$level+1]) {

			my $nextRS = Slim::Schema->rs($levels[$level+1]);

			if ($nextRS->allTitle && $nextRS->allTitle eq $currentItem) {

				$all = 1;
			}
		}

		if (!defined($currentItem)) {
			$client->bumpRight();
		}
		
		elsif ($currentItem eq 'FAVORITE') {

			my $num   = $client->param('favorite');
			my $track = Slim::Schema->find('Track', $client->param('findCriteria')->{'playlist'});

			if (!blessed($track) || !$track->can('title')) {

				errorMsg("Couldn't find a valid object for playlist!\n");

				$client->showBriefly($client->string('PROBLEM_OPENING'));

				return;
			}

			if ($num < 0) {

				$num = Slim::Utils::Favorites->clientAdd($client, $track, $track->title);

				$client->showBriefly($client->string('FAVORITES_ADDING'), $track->title);

				$client->param('favorite', $num);

			} else {

				Slim::Utils::Favorites->deleteByClientAndURL($client, $track);

				$client->showBriefly($client->string('FAVORITES_DELETING'), $track->title);

				$client->param('favorite', -1);
			}
		}
		# If we're dealing with a container or an ALL list
		elsif ($descend || $all) {

			my $findCriteria      = { %{$client->param('findCriteria')} };
			my $selectionCriteria = $client->param('selectionCriteria');
			my $field             = $levels[$level];

			if (my $transform = $levelRS->nameTransform) {
				$field = $transform;
			}

			# Include the current item in the find criteria for the next level down.
			if (!$all) {

				if ($field eq 'contributor' && 
					$currentItem->id eq Slim::Schema->variousArtistsObject->id &&
					Slim::Utils::Prefs::get('variousArtistAutoIdentification')) {

					$findCriteria->{'album.compilation'} = 1;

				} else {

					$findCriteria->{"$field.id"} = $currentItem->id;
				}
			}

			my %params = (
				hierarchy         => $hierarchy,
				level             => $level + 1,
				findCriteria      => $findCriteria,
				selectionCriteria => $selectionCriteria,
			);

			# Only include the search terms (i.e. those associated with
			# an actual tex search) if we're dealing with the ALL case.
			if ($all) {
				$params{'search'} = $client->param('search');
			}

			# Push recursively in to the same mode for the next level down.
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
	my $item   = shift;
	my $index  = shift;

	my $hierarchy = $client->param('hierarchy');
	my $level     = $client->param('level');

	my @levels    = split(',', $hierarchy);
	
	my $levelRS   = Slim::Schema->rs($levels[$level]);
	my $blessed   = blessed($item) ? 1 : 0;

	if (!$blessed && $levels[$level+1]) {

		my $nextRS = Slim::Schema->rs($levels[$level+1]);

		if ($nextRS->allTitle eq $item) {

			return $client->string($item);
		}
	}

	# special case favorites line, which must be determined dynamically
	if (!$blessed && $item eq 'FAVORITE') {

		if ((my $num = $client->param('favorite')) < 0) {
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

		my $items  = $client->param('listRef');

		# Pull the nameTransform if needed - for New Music, etc
		my $field  = $levelRS->nameTransform || $levels[$level];
		my $newObj = Slim::Schema->find($field, $item);

		if (!defined $newObj) {

			return $client->string($item);

		} elsif (blessed($newObj) && $newObj->can('id')) {

			${$client->param('valueRef')} = $items->[$index] = $item = $newObj;

		} else {

			return $client->string('OBJECT_RETRIEVAL_FAILURE');
		}
	}

	if ($levels[$level] eq 'track') {

		return Slim::Music::Info::standardTitle($client, $item);

	} elsif ($levels[$level] eq 'year') {

		return $item->year || $client->string('UNK');

	} elsif (($levels[$level] eq 'album') || ($levelRS->nameTransform eq 'album')) {

		my @name         = $item->name;
		my $findCriteria = $client->param('findCriteria') || {};

		if (Slim::Utils::Prefs::get('showYear') && !$findCriteria->{'album.year'}) {

			my $year = $item->year;

			push @name, " ($year)" if $year;
		}

		if (Slim::Utils::Prefs::get('showArtist') && !$findCriteria->{'contributor.id'}) {

			my @artists  = ();
			my $noArtist = $client->string('NO_ARTIST');

			for my $artist ($item->artists) {

				next if $artist->name eq $noArtist;

				push @artists, $artist->name;
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

	my $hierarchy = $client->param('hierarchy');
	my $level     = $client->param('level') || 0;
	my $filters   = $client->param('findCriteria') || {};
	my $search    = $client->param('search');
	my %find      = ();

	$::d_info && msg("browsedb - hierarchy: $hierarchy level: $level\n");
	msg("browsedb - hierarchy: $hierarchy level: $level\n");

	# Parse the hierarchy list into an array
	my @levels   = split(',', $hierarchy);

	my $maxLevel = scalar(@levels) - 1;

	if ($level > $maxLevel)	{
		$level = $maxLevel;
	}

	my $descend = ($level >= $maxLevel) ? undef : 1;

	my $levelRS = Slim::Schema->rs($levels[$level]);
	my $topRS   = Slim::Schema->rs($levels[0]);

	# First get the names of the specified parameters.
	# These could be necessary for titles.
	my %names      = ();
	my $setAllName = 0;

	my %levelMap = ();

	for (my $i = 1; $i < scalar @levels; $i++) {

		$levelMap{ lc($levels[$i-1]) } = lc($levels[$i]);
	}

	msg("levelmap:\n");
	print Data::Dumper::Dumper(\%levelMap);
	msg("filters:\n");
	print Data::Dumper::Dumper($filters);

	# hierarchy: contributor,album,track level: 2

	while (my ($param, $value) = each %{$filters}) {

		my ($levelName) = ($param =~ /^(\w+)(\.\w+)?$/);

		msg("param 1: [$param] value: [$value]\n");

		# Turn into me.* for the top level
		if ($param =~ /^$levels[0]\.(\w+)$/) {
			$param = sprintf('%s.%s', $topRS->{'attrs'}{'alias'}, $1);
			msg("param 2: [$param] value: [$value]\n");
		}

		# Turn into me.* for the current level
		if ($param =~ /^$levels[$level]\.(\w+)$/) {
			$param = sprintf('%s.%s', $levelRS->{'attrs'}{'alias'}, $1);
			msg("param 3: [$param] value: [$value]\n");
		}

		msg("working on levelname: [$levelName]\n");

		if (my $mapKey = $levelMap{$levelName}) {

			msg("mapKey: [$mapKey]\n");

			$find{$mapKey} = { $param => $value };
		}

		msg("\n");
	}

	msg("find:\n");
	print Data::Dumper::Dumper(\%find);

	# Build up the names for the top line
	for my $i (0..$#levels) {

		my $field = $levels[$i];
		my $rs    = Slim::Schema->rs($field) || next;

		if (my $transform = $rs->nameTransform) {
			# $field = $transform;
		}

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

	msg("levels: [$hierarchy]: names:\n");
	print Data::Dumper::Dumper(\%names);

	# Next to the actual query to get the items to display
	#
	# Ask for only IDs - so we can inflate on the fly.
	my @items = ();

	if (defined $search) {

		@items = $levelRS->searchNames($search)->all;

	} else {

		$topRS = $topRS->descend(\%find, {}, @levels[0..$level])->distinct;

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

			$header = $client->string($levelRS->title);
		}

	} elsif ($level == 1) {

		msg("working in level == 1. \$level-1 is: [$levels[$level-1]]\n");

		$header = $names{$levels[$level-1]}; 

	} else {

		msg("working in level > 1. \$level-2 is: [$levels[$level-2]] level-1 is: $levels[$level-1]]\n");

		$header = $names{$levels[$level-2]} . "/" . $names{$levels[$level-1]};
	}

	# Then see if we have to add an ALL option
	if (($descend || $search) && $count > 1 && !$levelRS->suppressAll) {

		# Use the ALL_ version of the next level down in the hirearchy
		if ($descend) {

			push @items, Slim::Schema->rs($levels[$level+1])->allTitle;

		} elsif ($level == 0) {

			# Unless this is a list of songs at the top level, in which
			# case, we add an ALL_SONGS
			push @items, $levelRS->allTitle;
		}
	}

	# Dynamically create a VA/Compilation item under artists, like iTunes does.
	if ($levels[$level] eq 'contributor' && !$search && Slim::Utils::Prefs::get('variousArtistAutoIdentification')) {

		# Only show VA if there exists valid data below this level.
		my %vaFind = %{$filters};

		$vaFind{'me.compilation'} = 1;

		delete $vaFind{'genre.id'};

		if (Slim::Schema->count('Album', \%vaFind)) {

			unshift @items, Slim::Schema->variousArtistsObject;
		}
	}

	# If the previous level is a playlist. IE: We're in playlistTracks -
	# let the user add a favorite for this playlist.
	if ($levels[$level-1] eq 'playlist') {

		my $track = Slim::Schema->find('Track', $filters->{'playlist'});

		if (blessed($track) && $track->can('id')) {
		
			my $fav = Slim::Utils::Favorites->findByClientAndURL($client, $track);

			if ($fav) {
				$client->param('favorite', $fav->{'num'});
			} else {
				$client->param('favorite', -1);
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
	
	} elsif ($selectionCriteria = $client->param('selectionCriteria')) {

		# Entering from trackinfo, so we need to set the selected item
		my $selection = $selectionCriteria->{$levels[$level]};
		my $j = 0;

		for my $item (@items) {

			# XXXX - need to optimize
			last if $selection == $item->name;
			$j++;
		}
		
		# set index to matching item from this level
		$listIndex = $j;

	} else {

		$selectionKey = join(':', $hierarchy, $level, Storable::freeze(\%find));

		$listIndex = $client->lastID3Selection($selectionKey) || 0;

		$::d_info && msg("last position from selection key $selectionKey is $listIndex\n");
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
		findCriteria      => \%find,
		selectionCriteria => $selectionCriteria,
	);

	$params{'favorite'}   = $client->param('favorite');

	# If this is a list of containers (e.g. albums, artists, genres)
	# that are not the result of a search, assume they are sorted.
	# sort at simple track level as well.
	if (($descend && !$search) || ($levels[$level] eq 'track' && !exists $find{'album.id'} && !$search)) {

		$params{'isSorted'}  = 'L';

		$params{'lookupRef'} = sub {
			my $index = shift;
			my $item  = $items[$index];

			# Pull the nameTransform if needed - for New Music, etc
			if (!ref($item)) {

				return $client->string($item);
			}

			return $item->namesort;
		};
	}

	msg("-" x 120 . "\n");

	Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);
}

sub searchTerm {
	my $t = shift;
	
	$t =~ s/^[\*\%]?(.+)[\*\%]$/$1/;

	return $t;
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:

