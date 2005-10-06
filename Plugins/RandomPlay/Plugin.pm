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
		$clientGenres{$item->name} = 1;
	}

	my @exclude = Slim::Utils::Prefs::getArray('plugin_random_exclude_genres');

	# Set excluded genres to 0 in genres hash
	@clientGenres{@exclude} = (0) x @exclude;
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
		if ($clientGenres{$genre}) {
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
	Slim::Control::Command::clearExecuteCallback(\&commandCallback);

	$type ||= 'track';
	$type   = lc($type);
	
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

	} elsif ($type ne 'disable' && ($type ne $type{$client} || $songsRemaining <= 0)) {
		# Old artist/album/year is finished or new random mix started.  Add a new one
		$numItems = 1;
	}

	if ($numItems) {
		unless ($addOnly) {
			Slim::Control::Command::execute($client, [qw(stop)]);
			Slim::Control::Command::execute($client, [qw(power 1)]);
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
		my $showTime = 5;		
		
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
					$showTime *= 2;
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
		if ($type ne $type{$client} || $type ne 'track') {
			if ($type eq 'track') {
				$string = $client->string("PLUGIN_RANDOM_TRACK");
			}
			$client->showBriefly(string($addOnly ? 'ADDING_TO_PLAYLIST' : 'NOW_PLAYING'),
								 $string, $showTime);
		}

		# Set the Now Playing title.
		#$client->currentPlaylist($string);
		
		# Never show random as modified, since its a living playlist
		$client->currentPlaylistModified(0);		

	} elsif ($type eq 'disable') {
		# Disable random play
				
		Slim::Control::Command::clearExecuteCallback(\&commandCallback);
		$::d_plugins && msg("RandomPlay: cyclic mode ended\n");
		$client->showBriefly(string('PLUGIN_RANDOM'), string('PLUGIN_RANDOM_DISABLED'));				
	}
	
	if ($type eq 'disable') {
		$type{$client} = undef;
	} else {
		$::d_plugins && msgf("RandomPlay: Playing continuous %s mode with %i items\n",
							 $type,
							 Slim::Player::Playlist::count($client));
		Slim::Control::Command::setExecuteCallback(\&commandCallback);
		
		# Do this last to prevent menu items changing too soon
		$type{$client} = $type;
		# Make sure that changes in menu items are displayed
		#$client->update();
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
	
	if ($item eq $type{$client}) {
		return string($displayText{$item} . '_PLAYING');
	} else {
		return string($displayText{$item});
	}
}

# Returns the overlay to be display next to items in the menu
sub getOverlay {
	my ($client, $item) = @_;

	# Put the right arrow by genre filter and notesymbol by any mix that isn't playing
	if ($item eq 'genreFilter') {
		return [undef, Slim::Display::Display::symbol('rightarrow')];
	} elsif ($item ne $type{$client}) {
		return [undef, Slim::Display::Display::symbol('notesymbol')];
	} else {
		return [undef, undef];
	}
}

# Returns the overlay for the select genres mode i.e. the checkbox state
sub getGenreOverlay {
	my ($client, $item) = @_;
	
	if($genres{$client}{$item}) {
		return [undef, '[X]'];
	} else {
		return [undef, '[ ]'];
	}
}

# Toggle the exclude state of a genre in the select genres mode
sub toggleGenreState {
	my ($client, $item) = @_;
	
	# Toggle the selected state of the current item
	$genres{$client}{$item} = ! $genres{$client}{$item};
	
	Slim::Utils::Prefs::set('plugin_random_exclude_genres', [getFilteredGenres($client, 1)]);
	
	$client->update();
}

# Do what's necessary when play or add button is pressed
sub handlePlayOrAdd {
	my ($client, $item, $add) = @_;
	$::d_plugins && msgf("RandomPlay: %s %s\n", $add ? 'Add' : 'Play', $item);
	
	# Don't play/add for genre filter or a mix that's already enabled
	if ($item ne 'genreFilter' && $item ne $type{$client}) {	
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
				
				Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', {
					header     => '{PLUGIN_RANDOM_GENRE_FILTER} {count}',
					listRef    => [sort keys %genreList],
					modeName   => 'RandomPlayGenreFilter',
					overlayRef => \&getGenreOverlay,
					onRight    => \&toggleGenreState,
				});
			} else {
				$client->bumpRight();
			}
		},
	);

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub commandCallback {
	my ($client, $paramsRef) = @_;

	my $slimCommand = $paramsRef->[0];

	# we dont care about generic ir blasts
	return if $slimCommand eq 'ir';

	$::d_plugins && msgf("RandomPlay: received command %s\n", join(' ', @$paramsRef));

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

	if ($slimCommand eq 'newsong'
		|| $slimCommand eq 'playlist' && $paramsRef->[1] eq 'delete' && $paramsRef->[2] > $songIndex) {

        if ($::d_plugins) {
			if ($slimCommand eq 'newsong') {
				msg("RandomPlay: new song detected ($songIndex)\n");
			} else {
				msg("RandomPlay: deletion detected ($paramsRef->[2]");
			}
		}
		
		my $songsToKeep = Slim::Utils::Prefs::get('plugin_random_number_of_old_tracks');
		if ($songIndex && $songsToKeep ne '') {
			$::d_plugins && msg("RandomPlay: Stripping off completed track(s)\n");

			Slim::Control::Command::clearExecuteCallback(\&commandCallback);
			# Delete tracks before this one on the playlist
			for (my $i = 0; $i < $songIndex - $songsToKeep; $i++) {
				Slim::Control::Command::execute($client, ['playlist', 'delete', 0]);
			}
			Slim::Control::Command::setExecuteCallback(\&commandCallback);
		}

		playRandom($client, $type{$client}, 1);
	} elsif (($slimCommand eq 'playlist') && exists $stopcommands{$paramsRef->[1]}) {

		$::d_plugins && msgf("RandomPlay: cyclic mode ending due to playlist: %s command\n", join(' ', @$paramsRef));
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
}

sub shutdownPlugin {
	Slim::Control::Command::clearExecuteCallback(\&commandCallback);
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

	Slim::Web::Pages::addLinks("browse", { 'PLUGIN_RANDOM' => $value });

	return \%pages;
}

# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;

	# Pass on the current pref values
	$params->{'pluginRandomGenreList'} = {getGenres($client)};
	$params->{'pluginRandomNumTracks'} = Slim::Utils::Prefs::get('plugin_random_number_of_tracks');
	$params->{'pluginRandomNumOldTracks'} = Slim::Utils::Prefs::get('plugin_random_number_of_old_tracks');

	return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
}

# Handles play requests from plugin's web page
sub handleWebMix {
	my ($client, $params) = @_;
	if (defined $client) {
		if ($params->{'type'}) {
			playRandom($client, $params->{'type'}, $params->{'addOnly'});
		}
	}
	return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
}

# Handles settings changes from plugin's web page
sub handleWebSettings {
	my ($client, $params) = @_;
	my %genres = getGenres($client);
	
	# %$params will contain a key called genre_<genre name> for each ticked checkbox on the page
	foreach my $genre (keys(%$params)) {
		if ($genre =~ s/^genre_//) {
			delete($genres{$genre});
		}
	}

	Slim::Utils::Prefs::set('plugin_random_number_of_tracks', $params->{'numTracks'});		
	Slim::Utils::Prefs::set('plugin_random_number_of_old_tracks', $params->{'numOldTracks'});	
	Slim::Utils::Prefs::set('plugin_random_exclude_genres', [keys(%genres)]);	

	handleWebList($client, $params);
}

sub checkDefaults {
	my $prefVal = Slim::Utils::Prefs::get('plugin_random_number_of_tracks');
	if (! defined $prefVal || $prefVal eq '') {
		Slim::Utils::Prefs::set('plugin_random_number_of_tracks', 10);
	}
	
	# Default to keeping all tracks
	if (!Slim::Utils::Prefs::isDefined('plugin_random_number_of_old_tracks')) {
		Slim::Utils::Prefs::set('plugin_random_number_of_old_tracks', '');
	}	

	if (!Slim::Utils::Prefs::isDefined('plugin_random_exclude_genres')) {
		Slim::Utils::Prefs::set('plugin_random_exclude_genres', []);
	}
}

sub strings {
	return <<EOF;
PLUGIN_RANDOM
	DE	Zufalls Mix
	EN	Random Mix
	ES	Mezcla al azar

PLUGIN_RANDOM_DISABLED
	DE	Zufalls Mix angehalten
	EN	Random Mix Stopped

PLUGIN_RANDOM_TRACK
	DE	Zufälliger Lieder Mix
	EN	Random Song Mix

PLUGIN_RANDOM_TRACK_PLAYING
	DE	Spiele zufällige Liederauswahl
	EN	Playing Random Songs

PLUGIN_RANDOM_ALBUM
	DE	Zufälliger Album Mix
	EN	Random Album Mix
	ES	Mezcla al azar por Álbum

PLUGIN_RANDOM_ALBUM_ITEM
	DE	Zufälliges album
	EN	Random Album

PLUGIN_RANDOM_ALBUM_PLAYING
	DE	Spiele zufällige Albenauswahl
	EN	Playing Random Albums

PLUGIN_RANDOM_ARTIST
	DE	Zufälliger Interpreten Mix
	EN	Random Artist Mix

PLUGIN_RANDOM_ARTIST_ITEM
	DE	Zufälliger Interpret
	EN	Random Artist

PLUGIN_RANDOM_ARTIST_PLAYING
	DE	Spiele zufälligen Interpreten
	EN	Playing Random Artists

PLUGIN_RANDOM_YEAR
	DE	Zufälliger Jahr Mix
	EN	Random Year Mix

PLUGIN_RANDOM_YEAR_ITEM
	DE	Zufälliger Jahrgang
	EN	Random Year

PLUGIN_RANDOM_YEAR_PLAYING
	DE	Spiele zufälligen Jahrgang
	EN	Playing Random Years

PLUGIN_RANDOM_GENRE_FILTER
	DE	Wähle zu berücksichtigende Stile
	EN	Select Genres To Include
	
PLUGIN_RANDOM_CHOOSE_DESC
	DE	Wählen Sie eine Zufallsmix-Methode:
	EN	Choose a random mix below:

PLUGIN_RANDOM_TRACK_DESC
	DE	Zufällige Lieder aus Ihrer Sammlung
	EN	Random songs from your whole library.

PLUGIN_RANDOM_ARTIST_DESC
	DE	Einen zufälligen Interpreten aus Ihrer Sammlung
	EN	Random artists from your whole library.

PLUGIN_RANDOM_ALBUM_DESC
	DE	Ein zufälliges Album aus Ihrer Sammlung
	EN	Random albums from your whole library.

PLUGIN_RANDOM_YEAR_DESC
	DE	Lieder eines zufälligen Jahres aus Ihrer Sammlung
	EN	Random years from your whole library.

SETUP_PLUGIN_RANDOM_DESC
	DE	Das Zufalls Mix Plugin erlaubt es, eine zufällige Auswahl von Liedern aus Ihrer Sammlung wiederzugeben.
	EN	The Random Mix plugin allows you to listen to random selections from your music library.

SETUP_MIX_SETTINGS
	EN	Mix Settings

SETUP_SELECT_GENRES_DESC
	EN	You can select the song genres that you wish to be included in random mixes.  Any genres left unticked will be excluded from mixes.

SETUP_PLUGIN_RANDOM_NUMBER_OF_TRACKS
	DE	Anzahl Lieder für Zufallsmix
	EN	Number of upcoming songs in a random mix

SETUP_PLUGIN_RANDOM_NUMBER_OF_TRACKS_DESC
	DE	Eine der möglichen zufälligen Mix-Arten ist der Lieder Mix. Dies erstellt eine Liste zufällig ausgewählter Musikstücke. Sie können bestimmen, wieviele Lieder im Voraus in der Wiedergabeliste angezeigt werden sollen.
	EN	One of the mixes provided by Random Mix is the Random Songs Mix.  This creates a random selection of songs from your music library.  You can specify how many upcoming songs should be displayed in this mode.

SETUP_PLUGIN_RANDOM_NUMBER_OF_OLD_TRACKS
	DE	Anzahl gespielter Lieder
	EN	Number of old songs in a random mix

SETUP_PLUGIN_RANDOM_NUMBER_OF_OLD_TRACKS_DESC
	DE	Lieder, die über einen Zufalls mix wiedergegeben wurden, können nach dem Abspielen aus der Wiedergabeliste entfernt werden. Sie können festlegen, wieviele der abgespielten Stücke in der Liste behalten werden sollen. Oder lassen Sie das Feld leer, falls die Liste nicht gelöscht werden soll. 
	EN	Songs that are played using Random Mix can be removed from the playlist after they are played.  You can specify how many songs should be kept, or leave this blank to keep all played songs.

EOF

}

1;

__END__
