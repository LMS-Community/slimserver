package Plugins::RandomPlay::Plugin;

# $Id$
#
# Originally written by Kevin Deane-Freeman (slim-mail (A_t) deane-freeman.com).
#
# New world order by Dan Sully - <dan | at | slimdevices.com>
# Fairly substantial rewrite by Max Spicer

# This code is derived from code with the following copyright message:
#
# SlimServer Copyright (C) 2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

my %stopcommands = ();
# Random play type for each client
my %type         = ();
# Display text for each mix type
my %displayText  = ();
# Genres for each client (don't access this directly - use getGenres())
my %genres       = ();

my $htmlTemplate = 'plugins/RandomPlay/randomplay_list.html';
my $ds = Slim::Music::Info::getCurrentDataStore();

sub getDisplayName {
	return 'PLUGIN_RANDOM';
}

# Find tracks matching parameters and add them to the playlist
sub findAndAdd {
	my ($client, $type, $find, $limit, $addOnly) = @_;

	$::d_plugins && msg("RandomPlay: Starting random selection of $limit items for type: $type\n");
	
	my $items = $ds->find({
		'field'  => $type,
		'find'   => $find,
		'sortBy' => 'random',
		'limit'  => $limit,
		'cache'  => 0,
	});

	$::d_plugins && msgf("RandomPlay: Find returned %i items\n", scalar @$items);
			
	# Pull the first track off to add / play it if needed.
	my $item = shift @{$items};

	if ($item && ref($item)) {
		my $string = $type eq 'artist' ? $item->name : $item->title;
		$::d_plugins && msgf("RandomPlay: %s %s: %s, %d\n",
							 $addOnly ? 'Adding' : 'Playing',
							 $type, $string, $item->id);

		# Replace the current playlist with the first item / track or add it to end
		$client->execute(['playlist', $addOnly ? 'addtracks' : 'loadtracks',
		                  sprintf('%s=%d', $type, $item->id)]);
		
		# Add the remaining items to the end
		if ($type eq 'track') {
			if (! defined $limit || $limit > 1) {
				$::d_plugins && msgf("Adding %i tracks to end of playlist\n", scalar @$items);
				$client->execute(['playlist', 'addtracks', 'listRef', $items]);
			}
		}
		return $string;
	} else {
		return undef;
	}
}

# Returns a hash whose keys are the genres in the db
sub getGenres {
	my ($client) = @_;

	# Should use genre.name in following find, but a bug in find() doesn't allow this	
   	my $items = $ds->find({
		'field'  => 'genre',
		'cache'  => 0,
	});
	
	# Extract each genre name into a hash
	my %clientGenres = ();
	foreach my $item (@$items) {
		$clientGenres{$item->{'name'}} = {
		                                 # Put the name here as well so the hash can be passed to
		                                 # INPUT.Choice as part of listRef later on
		                                 name    => $item->{'name'},
		                                 id      => $item->{'id'},
		                                 enabled => 1,
									 };
	}

	my @exclude = Slim::Utils::Prefs::getArray('plugin_random_exclude_genres');

	# Set excluded genres to 0 in genres hash
	foreach my $item (@exclude) {
		# excluded genres could include some that no longer exist
		if ($clientGenres{$item}) {
			$clientGenres{$item}{'enabled'} = 0;
		}
	}
	$genres{$client} = {%clientGenres};

	return %{$genres{$client}};
}

# Returns an array of the non-excluded genres in the db
sub getFilteredGenres {
	my ($client, $returnExcluded) = @_;
	my %clientGenres;

	# If $returnExcluded, just return the current state of excluded genres
	if (! $returnExcluded) {
		%clientGenres = getGenres($client);
	} else {
		%clientGenres = %{$genres{$client}};
	}
	
	my @filteredGenres = ();
	my @excludedGenres = ();

	for my $genre (keys %clientGenres) {
		if ($clientGenres{$genre}{'enabled'}) {
			push (@filteredGenres, $genre) unless $returnExcluded;
		} else {
			push (@excludedGenres, $genre) unless ! $returnExcluded;
		}
	}

	if ($returnExcluded) {
		return @excludedGenres;
	} else {
		return @filteredGenres;
	}
}

sub getRandomYear {
	my $filteredGenresRef = shift;
	
	$::d_plugins && msg("RandomPlay: Starting random year selection\n");

   	my $items = $ds->find({
		'field'  => 'year',
		'find'   => {
			'genre.name' => $filteredGenresRef,
		},
		'sortBy' => 'random',
		'limit'  => 1,
		'cache'  => 0,
	});
	
	$::d_plugins && msgf("RandomPlay: Selected year %s\n", @$items[0]);

	return @$items[0];	
}

# Add random tracks to playlist if necessary
sub playRandom {
	# If addOnly, then track(s) are appended to end.  Otherwise, a new playlist is created.
	my ($client, $type, $addOnly) = @_;

	# disable this during the course of this function, since we don't want
	# to retrigger on commands we send from here.
	Slim::Control::Request::unsubscribe(\&commandCallback);


	$::d_plugins && msg("RandomPlay: playRandom called with type $type\n");

	$type ||= 'track';
	$type   = lc($type);
	# Whether to keep adding tracks after generating the initial playlist
	my $continuousMode = Slim::Utils::Prefs::get('plugin_random_keep_adding_tracks');;
	
	my $songIndex = Slim::Player::Source::streamingSongIndex($client);
	my $songsRemaining = Slim::Player::Playlist::count($client) - $songIndex - 1;
	$::d_plugins && msg("RandomPlay: $songsRemaining songs remaining, songIndex = $songIndex\n");

	# Work out how many items need adding
	my $numItems = 0;
	if ($type eq 'track') {
		# Add new tracks if there aren't enough after the current track
		my $numRandomTracks = Slim::Utils::Prefs::get('plugin_random_number_of_tracks');
		if (! $addOnly) {
			$numItems = $numRandomTracks;
		} elsif ($songsRemaining < $numRandomTracks - 1) {
			$numItems = $numRandomTracks - 1 - $songsRemaining;
		} else {
			$::d_plugins && msgf("RandomPlay: $songsRemaining items remaining so not adding new track\n");
		}

	} elsif ($type ne 'disable' && ($type ne $type{$client} || ! $addOnly || $songsRemaining <= 0)) {
		# Old artist/album/year is finished or new random mix started.  Add a new one
		$numItems = 1;
	}

	if ($numItems) {
		unless ($addOnly) {
			Slim::Control::Request::executeRequest($client, [qw(stop)]);
			Slim::Control::Request::executeRequest($client, [qw(power 1)]);
		}
		Slim::Player::Playlist::shuffle($client, 0);
		
		# Initialize find to only include user's selected genres.  If they've deselected
		# all genres, this clause will be ignored by find, so all genres will be used.
		my @filteredGenres = getFilteredGenres($client);
		my $find = {'genre.name' => \@filteredGenres};
		
		if ($type eq 'track' || $type eq 'year') {
			# Find only tracks, not albums etc
			$find->{'audio'} = 1;
		}
		
		# String to show with showBriefly
		my $string = '';
		if ($type ne 'track') {
			$string = $client->string('PLUGIN_RANDOM_' . $type . '_ITEM') . ': ';
		}
		
		# If not track mode, add tracks then go round again to check whether the playlist only
		# contains one track (i.e. the artist/album/year only had one track in it).  If so,
		# add another artist/album/year or the plugin would never add more when the first finished. 
		for (my $i = 0; $i < 2; $i++) {
			if ($i == 0 || ($type ne 'track' && Slim::Player::Playlist::count($client) == 1)) {
				# Genre filters don't apply in year mode as I don't know how to restrict the
				# random year to a genre.
				my $year;
				if($type eq 'year') {
					$year = getRandomYear(\@filteredGenres);
					$find->{'year'} = $year;
				}
				
				if ($i == 1) {
					$string .= ' // ';
				}
				# Get the tracks.  year is a special case as we do a find for all tracks that match
				# the previously selected year
				my $findString = findAndAdd($client,
				                            $type eq 'year' ? 'track' : $type,
				                            $find,
				                            $type eq 'year' ? undef : $numItems,
								            # 2nd time round just add tracks to end
										    $i == 0 ? $addOnly : 1);
				if ($type eq 'year') {
					$string .= $year;
				} else {
					$string .= $findString;
				}
			}
		}

		# Do a show briefly the first time things are added, or every time a new album/artist/year
		# is added
		if (!$addOnly || $type ne $type{$client} || $type ne 'track') {
			if ($type eq 'track') {
				$string = $client->string("PLUGIN_RANDOM_TRACK");
			}
			# Don't do showBrieflys if visualiser screensavers are running as the display messes up
			if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {
				$client->showBriefly(string($addOnly ? 'ADDING_TO_PLAYLIST' : 'NOW_PLAYING'),
									 $string, 2, undef, undef, 1);
			}
		}

		# Set the Now Playing title.
		#$client->currentPlaylist($string);
		
		# Never show random as modified, since its a living playlist
		$client->currentPlaylistModified(0);		
	}
	
	if ($type eq 'disable') {
#		Slim::Control::Command::clearExecuteCallback(\&commandCallback);
		Slim::Control::Request::unsubscribe(\&commandCallback);
		$::d_plugins && msg("RandomPlay: cyclic mode ended\n");
		# Don't do showBrieflys if visualiser screensavers are running as the display messes up
		if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {
			$client->showBriefly(string('PLUGIN_RANDOM'), string('PLUGIN_RANDOM_DISABLED'));
		}
		$type{$client} = undef;
	} else {
		$::d_plugins && msgf("RandomPlay: Playing %s %s mode with %i items\n",
							 $continuousMode ? 'continuous' : 'static',
							 $type,
							 Slim::Player::Playlist::count($client));

		if ($continuousMode) {
			# Watch out for songs ending in order to add new songs
#			Slim::Control::Command::setExecuteCallback(\&commandCallback);
			Slim::Control::Request::subscribe(\&commandCallback, 
				[['playlist'], ['newsong', 'delete', keys %stopcommands]]);

			# Record current mix type.  Do this last to prevent menu items changing too soon
			$type{$client} = $type;
		}
	}
}

# Returns the display text for the currently selected item in the menu
sub getDisplayText {
	my ($client, $item) = @_;
	
	if (! %displayText) {
		%displayText = (
			track  => 'PLUGIN_RANDOM_TRACK',
			album  => 'PLUGIN_RANDOM_ALBUM',
			artist => 'PLUGIN_RANDOM_ARTIST',
			year   => 'PLUGIN_RANDOM_YEAR',
			genreFilter => 'PLUGIN_RANDOM_GENRE_FILTER'
		)
	}	
	# if showing the current mode, show altered string
	if ($item eq $type{$client}) {
		return string($displayText{$item} . '_PLAYING');
		
	# if a mode is active, handle the temporarily added disable option
	} elsif ($item eq 'disable' && $type{$client}) {
		return string('PLUGIN_RANDOM_PRESS_RIGHT')." ".string('PLUGIN_RANDOM_'.uc($type{$client}).'_DISABLE');
	
	} else {
		return string($displayText{$item});
	}
}

# Returns the overlay to be display next to items in the menu
sub getOverlay {
	my ($client, $item) = @_;

	# Put the right arrow by genre filter and notesymbol by mixes
	if ($item eq 'genreFilter') {
		return [undef, Slim::Display::Display::symbol('rightarrow')];
	
	} elsif ($item ne 'disable') {
		return [undef, Slim::Display::Display::symbol('notesymbol')];
	
	} else {
		return [undef, undef];
	}
}

# Returns the overlay for the select genres mode i.e. the checkbox state
sub getGenreOverlay {
	my ($client, $item) = @_;
	my $rv = 0;
	my %genres = getGenres($client);	
	
	if ($item->{'selectAll'}) {
		# This item should be ticked if all the genres are selected
		my $genresEnabled = 0;
		foreach my $genre (keys %genres) {
			if ($genres{$genre}{'enabled'}) {
				$genresEnabled ++;
			}
		}
		$rv = $genresEnabled == scalar keys %genres;
		$item->{'enabled'} = $rv;
	} else {
		$rv = $genres{$item->{'name'}}{'enabled'};
	}
	
	if($rv) {
		return [undef, '[X]'];
	} else {
		return [undef, '[ ]'];
	}
}

# Toggle the exclude state of a genre in the select genres mode
sub toggleGenreState {
	my ($client, $item) = @_;
	
	if ($item->{'selectAll'}) {
		$item->{'enabled'} = ! $item->{'enabled'};
		# Enable/disable every genre
		foreach my $genre (keys %{$genres{$client}}) {
			$genres{$client}{$genre}{'enabled'} = $item->{'enabled'};
		}
	} else {
		# Toggle the selected state of the current item
		$genres{$client}{$item->{'name'}}{'enabled'} = ! $genres{$client}{$item->{'name'}}{'enabled'};		
	}
	Slim::Utils::Prefs::set('plugin_random_exclude_genres', [getFilteredGenres($client, 1)]);
	$client->update();
}

# Do what's necessary when play or add button is pressed
sub handlePlayOrAdd {
	my ($client, $item, $add) = @_;
	$::d_plugins && msgf("RandomPlay: %s %s\n", $add ? 'Add' : 'Play', $item);
	
	# reconstruct the list of options, adding and removing the 'disable' option where applicable
	if ($item ne 'genreFilter') {
		my $listRef = Slim::Buttons::Common::param($client, 'listRef');
		
		if ($item eq 'disable') {
			pop @$listRef;
		
		# only add disable option if starting a mode from idle state
		} elsif (!$type{$client}) {
			push @$listRef, 'disable';
		}
		Slim::Buttons::Common::param($client, 'listRef', $listRef);
	}

	# Don't play/add for genre filter or a mix that's already enabled
	if ($item ne 'genreFilter') {	
		playRandom($client, $item, $add);
	}
}

sub setMode {
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header     => '{PLUGIN_RANDOM} {count}',
		listRef    => [qw(track album artist year genreFilter)],
		name       => \&getDisplayText,
		overlayRef => \&getOverlay,
		modeName   => 'RandomPlay',
		onPlay     => sub {
			my ($client, $item) = @_;
			handlePlayOrAdd($client, $item, 0);		
		},
		onAdd      => sub {
			my ($client, $item) = @_;
			handlePlayOrAdd($client, $item, 1);
		},
		onRight    => sub {
			my ($client, $item) = @_;
			if ($item eq 'genreFilter') {
				my %genreList = getGenres($client);

				# Insert Select All option at top of genre list
				my @listRef = ({
							       name => $client->string('PLUGIN_RANDOM_SELECT_ALL'),
							       # Mark the fact that isn't really a genre
								   selectAll => 1
							   });
				# Add the genres
				foreach my $genre (sort keys %genreList) {
					push @listRef, $genreList{$genre};
				}
				
				Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', {
					header     => '{PLUGIN_RANDOM_GENRE_FILTER} {count}',
					listRef    => \@listRef,
					modeName   => 'RandomPlayGenreFilter',
					overlayRef => \&getGenreOverlay,
					onRight    => \&toggleGenreState,
				});
			} elsif ($item eq 'disable') {
				handlePlayOrAdd($client, $item, 0);
			} else {
				$client->bumpRight();
			}
		},
	);

	# if we have an active mode, temporarily add the disable option to the list.
	if ($type{$client}) {
		push @{$params{listRef}},'disable';
	}

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub commandCallback {
#	my ($client, $paramsRef) = @_;
	my $request = shift;
	
	my $client = $request->client();

#	my $slimCommand = $request->getRequest(0);

	# we dont care about generic ir blasts
#	return if $slimCommand eq 'ir';

	#$::d_plugins && msgf("RandomPlay: received command %s\n", join(' ', @$paramsRef));
	$::d_plugins && msgf("RandomPlay: received command %s\n", $request->getRequestString());

	# Fred: because of the filter this should never happen
	# Fred: in addition there are valid commands (rescan f.e.) that have no
	# Fred: client so the bt() is strange here
	if (!defined $client || !defined $type{$client}) {

		if ($::d_plugins) {
			msg("RandomPlay: No client!\n");
			bt();
		}
		return;
	}
	
	$::d_plugins && msgf("RandomPlay: while in mode: %s, from %s\n",
						 $type{$client}, $client->name);

	my $songIndex = Slim::Player::Source::streamingSongIndex($client);

#	if ($slimCommand eq 'newsong'
#		|| $slimCommand eq 'playlist' && $paramsRef->[1] eq 'delete' && $paramsRef->[2] > $songIndex) {
	if ($request->isCommand([['playlist'], ['newsong']])
		|| $request->isCommand([['playlist'], ['delete']]) && $request->getParam('_index') > $songIndex) {

        if ($::d_plugins) {
			if ($request->isCommand([['playlist'], ['newsong']])) {
				msg("RandomPlay: new song detected ($songIndex)\n");
			} else {
#				msg("RandomPlay: deletion detected ($paramsRef->[2]");
				msg("RandomPlay: deletion detected (" . $request->getParam('_index') . ")\n");
			}
		}
		
		my $songsToKeep = Slim::Utils::Prefs::get('plugin_random_number_of_old_tracks');
		if ($songIndex && $songsToKeep ne '') {
			$::d_plugins && msg("RandomPlay: Stripping off completed track(s)\n");

#			Slim::Control::Command::clearExecuteCallback(\&commandCallback);
			Slim::Control::Request::unsubscribe(\&commandCallback);
			# Delete tracks before this one on the playlist
			for (my $i = 0; $i < $songIndex - $songsToKeep; $i++) {
				Slim::Control::Request::executeRequest($client, ['playlist', 'delete', 0]);
			}
#			Slim::Control::Command::setExecuteCallback(\&commandCallback);
			Slim::Control::Request::subscribe(\&commandCallback, 
				[['playlist'], ['newsong', 'delete', keys %stopcommands]]);
		}

		playRandom($client, $type{$client}, 1);
#	} elsif (($slimCommand eq 'playlist') && exists $stopcommands{$paramsRef->[1]}) {
	} elsif ($request->isCommand([['playlist'], [keys %stopcommands]])) {

		$::d_plugins && msgf("RandomPlay: cyclic mode ending due to playlist: %s command\n", $request->getRequestString());
		playRandom($client, 'disable');
	}
}

sub initPlugin {
	# playlist commands that will stop random play
	%stopcommands = (
		'clear'		 => 1,
		'loadtracks' => 1, # multiple play
		'playtracks' => 1, # single play
		'load'		 => 1, # old style url load (no play)
		'play'		 => 1, # old style url play
		'loadalbum'	 => 1, # old style multi-item load
		'playalbum'	 => 1, # old style multi-item play
	);
	
	checkDefaults();
}

sub shutdownPlugin {
#	Slim::Control::Command::clearExecuteCallback(\&commandCallback);
	Slim::Control::Request::unsubscribe(\&commandCallback);
}

sub getFunctions {
	# Functions to allow mapping of mixes to keypresses
	return {
		'tracks' => sub {
			my $client = shift;
	
			playRandom($client, 'track');
		},
	
		'albums' => sub {
			my $client = shift;
	
			playRandom($client, 'album');
		},
	
		'artists' => sub {
			my $client = shift;
	
			playRandom($client, 'artist');
		},
		
		'year' => sub {
			my $client = shift;
	
			playRandom($client, 'year');
		},
	}
}

sub webPages {

	my %pages = (
		"randomplay_list\.(?:htm|xml)"     => \&handleWebList,
		"randomplay_mix\.(?:htm|xml)"      => \&handleWebMix,
		"randomplay_settings\.(?:htm|xml)" => \&handleWebSettings,
	);

	my $value = $htmlTemplate;

	if (grep { /^RandomPlay::Plugin$/ } Slim::Utils::Prefs::getArray('disabledplugins')) {

		$value = undef;
	}

	Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_RANDOM' => $value });

	return (\%pages);
}

# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;

	# Pass on the current pref values and now playing info
	$params->{'pluginRandomGenreList'} = {getGenres($client)};
	$params->{'pluginRandomNumTracks'} = Slim::Utils::Prefs::get('plugin_random_number_of_tracks');
	$params->{'pluginRandomNumOldTracks'} = Slim::Utils::Prefs::get('plugin_random_number_of_old_tracks');
	$params->{'pluginRandomContinuousMode'} = Slim::Utils::Prefs::get('plugin_random_keep_adding_tracks');
	$params->{'pluginRandomNowPlaying'} = $type{$client};
	
	return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
}

# Handles play requests from plugin's web page
sub handleWebMix {
	my ($client, $params) = @_;
	if (defined $client && $params->{'type'}) {
		playRandom($client, $params->{'type'}, $params->{'addOnly'});
	}
	handleWebList($client, $params);
}

# Handles settings changes from plugin's web page
sub handleWebSettings {
	my ($client, $params) = @_;
	my %genres = getGenres($client);

	# Build a lookup table to go from genre id to genre name	
	my @lookup = ();
	foreach my $genre (keys %genres) {
		@lookup[$genres{$genre}{'id'}] = $genre;
	}

	# %$params will contain a key called genre_<genre id> for each ticked checkbox on the page
	foreach my $genre (keys(%$params)) {
		if ($genre =~ s/^genre_//) {
			delete($genres{$lookup[$genre]});
		}
	}
	Slim::Utils::Prefs::set('plugin_random_exclude_genres', [keys(%genres)]);	

	if ($params->{'numTracks'} =~ /^[0-9]+$/) {
		Slim::Utils::Prefs::set('plugin_random_number_of_tracks', $params->{'numTracks'});
	} else {
		$::d_plugins && msg("RandomPlay: Invalid value for numTracks\n");
	}
	if ($params->{'numOldTracks'} eq '' || $params->{'numOldTracks'} =~ /^[0-9]+$/) {
		Slim::Utils::Prefs::set('plugin_random_number_of_old_tracks', $params->{'numOldTracks'});	
	} else {
		$::d_plugins && msg("RandomPlay: Invalid value for numOldTracks\n");
	}
	Slim::Utils::Prefs::set('plugin_random_keep_adding_tracks', $params->{'continuousMode'} ? 1 : 0);

	# Pass on to check if the user requested a new mix as well
	handleWebMix($client, $params);
}

sub checkDefaults {
	my $prefVal = Slim::Utils::Prefs::get('plugin_random_number_of_tracks');
	if (! defined $prefVal || $prefVal !~ /^[0-9]+$/) {
		$::d_plugins && msg("RandomPlay: Defaulting plugin_random_number_of_tracks to 10\n");
		Slim::Utils::Prefs::set('plugin_random_number_of_tracks', 10);
	}
	
	$prefVal = Slim::Utils::Prefs::get('plugin_random_number_of_old_tracks');
	if (! defined $prefVal || $prefVal !~ /^$|^[0-9]+$/) {
		# Default to keeping all tracks
		$::d_plugins && msg("RandomPlay: Defaulting plugin_random_number_of_old_tracks to ''\n");
		Slim::Utils::Prefs::set('plugin_random_number_of_old_tracks', '');
	}

	if (! defined Slim::Utils::Prefs::get('plugin_random_keep_adding_tracks')) {
		# Default to continous mode
		$::d_plugins && msg("RandomPlay: Defaulting plugin_random_keep_adding_tracks to 1\n");
		Slim::Utils::Prefs::set('plugin_random_keep_adding_tracks', 1);
	}

	if (!Slim::Utils::Prefs::isDefined('plugin_random_exclude_genres')) {
		# Include all genres by default
		Slim::Utils::Prefs::set('plugin_random_exclude_genres', []);
	}
}

sub strings {
	return <<EOF;
PLUGIN_RANDOM
	DE	Zufalls Mix
	EN	Random Mix
	ES	Mezcla al azar
	HE	מיקס אקראי
	NL	Willekeurige mix

PLUGIN_RANDOM_DISABLED
	DE	Zufalls Mix angehalten
	EN	Random Mix Stopped
	ES	Mezcla al Azar Detenida
	HE	מיקס אקראי מופסק
	NL	Willekeurige mix gestopt

PLUGIN_RANDOM_TRACK
	DE	Zufälliger Lieder Mix
	EN	Random Song Mix
	ES	Mezcla por Canción al Azar
	HE	מיקס שיר אקראי
	NL	Willekeurige liedjesmix

PLUGIN_RANDOM_TRACK_PLAYING
	DE	Spiele zufällige Liederauswahl
	EN	Playing Random Songs
	ES	Reproduciendo Canciones al Azar
	NL	Speelt willekeurige liedjes

PLUGIN_RANDOM_TRACK_DISABLE
	DE	keine Lieder mehr hinzuzufügen
	EN	stop adding songs
	ES	dejar de añadir canciones
	NL	stop toevoegen liedjes

PLUGIN_RANDOM_ALBUM
	DE	Zufälliger Album Mix
	EN	Random Album Mix
	ES	Mezcla al azar por Álbum
	HE	מיקס אלבום אקראי
	NL	Willekeurige albummix

PLUGIN_RANDOM_ALBUM_ITEM
	DE	Zufälliges Album
	EN	Random Album
	ES	Álbum al Azar
	NL	Willekeurig album

PLUGIN_RANDOM_ALBUM_PLAYING
	DE	Spiele zufällige Albenauswahl
	EN	Playing Random Albums
	ES	Reproduciendo Álbumes al Azar
	NL	Speelt willekeurige albums

PLUGIN_RANDOM_ALBUM_DISABLE
	DE	keine Alben mehr hinzuzufügen
	EN	stop adding albums
	NL	stop toevoegen albums

PLUGIN_RANDOM_ARTIST
	DE	Zufälliger Interpreten Mix
	EN	Random Artist Mix
	ES	Mezcla por Artista al Azar
	HE	מיקס אמן אקראי
	NL	Willekeurige artiestenmix

PLUGIN_RANDOM_ARTIST_ITEM
	DE	Zufälliger Interpret
	EN	Random Artist
	ES	Artista al Azar
	NL	Willekeurige artiest

PLUGIN_RANDOM_ARTIST_PLAYING
	DE	Spiele zufälligen Interpreten
	EN	Playing Random Artists
	ES	Reproduciendo Artistas al Azar
	NL	Speelt willekeurige artiesten

PLUGIN_RANDOM_ARTIST_DISABLE
	DE	keine Interpreten mehr hinzuzufügen
	EN	stop adding artists
	ES	dejar de añadir artistas
	NL	stop toevoegen artiesten

PLUGIN_RANDOM_YEAR
	DE	Zufälliger Jahr Mix
	EN	Random Year Mix
	ES	Mezcla por Año al Azar
	NL	Willekeurige jaarmix

PLUGIN_RANDOM_YEAR_ITEM
	DE	Zufälliger Jahrgang
	EN	Random Year
	ES	Año al Azar
	NL	Willekeurig jaar

PLUGIN_RANDOM_YEAR_PLAYING
	DE	Spiele zufälligen Jahrgang
	EN	Playing Random Years
	ES	Reproduciendo Años al Azar
	NL	Speelt willekeurige jaren

PLUGIN_RANDOM_YEAR_DISABLE
	DE	keine Jahrgänge mehr hinzuzufügen
	EN	stop adding years
	ES	dejar de añadir años
	NL	stop toevoegen jaren

PLUGIN_RANDOM_GENRE_FILTER
	DE	Zu berücksichtigende Stile wählen
	EN	Select Genres To Include
	ES	Elegir Géneros A Incluir
	NL	Selecteer genres om toe te voegen

PLUGIN_RANDOM_SELECT_ALL
	DE	Alle wählen
	EN	Select All
	ES	Elegir Todo
	HE	בחר הכל
	NL	Selecteer alles

PLUGIN_RANDOM_SELECT_NONE
	DE	Alle abwählen
	EN	Select None
	ES	No Elegir Ninguno
	NL	Selecteer niets

PLUGIN_RANDOM_CHOOSE_BELOW
	DE	Wählen Sie einen zufälligen Mix von Musik aus Ihrer Sammlung:
	EN	Choose a random mix of music from your library:
	ES	Elegir una mezcla al azar de mósica de tu colección:
	HE	בחר מיקס אקראי
	NL	Kies een willekeurige muziekmix vanuit je muziekcollectie:

PLUGIN_RANDOM_TRACK_WEB
	DE	Zufällige Lieder
	EN	Random songs
	ES	Canciones al azar
	HE	שירים באקראי
	NL	Willekeurige liedjes

PLUGIN_RANDOM_ARTIST_WEB
	DE	Zufällige Interpreten
	EN	Random artists
	ES	Artistas al azar
	HE	אמנים באקראי
	NL	Willekeurige artiesten

PLUGIN_RANDOM_ALBUM_WEB
	DE	Zufällige Alben
	EN	Random albums
	ES	Álbumes al azar
	HE	אלבומים באקראי
	NL	Willekeurige albums

PLUGIN_RANDOM_YEAR_WEB
	DE	Zufällige Jahrgänge
	EN	Random years
	ES	Años al azar
	HE	שנים באקראי
	NL	Willekeurige jaren

PLUGIN_RANDOM_GENRE_FILTER_WEB
	DE	Im Mix zu berücksichtigende Stile: 
	EN	Genres to include in your mix:
	ES	Géneros a incluir en tu mezcla:
	HE	סוגי מוזיקה שיכללו
	NL	Genres om toe te voegen in je mix:

PLUGIN_RANDOM_BEFORE_NUM_TRACKS
	DE	Die Wiedergabeliste wird
	EN	Now Playing will show
	ES	Se Está Escuchando mostrará
	IT	Riproduzione in corso mostrera'
	NL	Speelt nu laat zien

PLUGIN_RANDOM_AFTER_NUM_TRACKS
	DE	noch abzuspielende und
	EN	upcoming songs and
	ES	próximas canciones y
	HE	מספר השירים שנוגנו ויוצגו
	NL	volgende liedje en

PLUGIN_RANDOM_AFTER_NUM_OLD_TRACKS
	DE	wiedergegebene Lieder anzeigen.
	EN	recently played songs.
	ES	canciones escuchadas recientemente.
	HE	מספר השירים הבאים שיוצגו
	NL	recent afgespeelde liedjes.

PLUGIN_RANDOM_CONTINUOUS_MODE
	DE	Neue Objekte ergänzen, wenn alte fertig gespielt sind
	EN	Add new items when old ones finish
	NL	Voeg nieuwe items toe zodra oude eindigen

PLUGIN_RANDOM_GENERAL_HELP
	DE	Sie können jederzeit Lieder aus dem Mix entfernen oder neue hinzufügen. Um den Zufallsmix anzuhalten löschen Sie bitte die Wiedergabeliste oder klicken, um
	EN	You can add or remove songs from your mix at any time. To stop a random mix, clear your playlist or click to
	ES	Se puede añadir o eliminar canciones de la mezcla en cualquier momento. Para detener una mezcla al azar, limpiar la lista o presionar
	NL	Je kunt op elk moment liedjes toevoegen aan of verwijderen uit je mix. Maak je playlist leeg om een willekeurige mix te stoppen of klik naar

PLUGIN_RANDOM_PRESS_RIGHT
	DE	RECHTS drücken um
	EN	Press RIGHT to

EOF

}

1;

__END__
