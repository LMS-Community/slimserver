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
# Information on each clients random mix
my %mixInfo      = ();
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
		my $request = $client->execute(['playlist', 
				                        $addOnly ? 'addtracks' : 'loadtracks',
		                                sprintf('%s=%d', $type, $item->id())]);
		# indicate request source
		$request->source('PLUGIN_RANDOM');
		
		# Add the remaining items to the end
		if ($type eq 'track') {

			if (! defined $limit || $limit > 1) {

				$::d_plugins && 
					msgf("RandomPlay: Adding %i tracks to end of playlist\n", 
					scalar @$items);
					
				$request = $client->execute(['playlist', 
				                             'addtracks', 
				                             'listRef', 
				                             $items]);
				$request->source('PLUGIN_RANDOM');
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

	$::d_plugins && msg("RandomPlay: playRandom called with type $type\n");

	$type ||= 'track';
	$type = lc($type);
	
	# Whether to keep adding tracks after generating the initial playlist
	my $continuousMode = Slim::Utils::Prefs::get('plugin_random_keep_adding_tracks');;
	
	# If this is a new mix, store the start time
	my $startTime = undef;
	if ($continuousMode && $mixInfo{$client}->{'type'} ne $type) {
		$startTime = time();
	}

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

	} elsif ($type ne 'disable' && ($type ne $mixInfo{$client}->{'type'} || ! $addOnly || $songsRemaining <= 0)) {
		# Old artist/album/year is finished or new random mix started.  Add a new one
		$numItems = 1;
	}

	if ($numItems) {
		unless ($addOnly) {
			$client->execute(['stop']);
			$client->execute(['power', '1']);
		}
		Slim::Player::Playlist::shuffle($client, 0);
		
		# Initialize find to only include user's selected genres.  If they've deselected
		# all genres, this clause will be ignored by find, so all genres will be used.
		my @filteredGenres = getFilteredGenres($client);
		my $find = {'genre.name' => \@filteredGenres};

		# Prevent items that have already been played from being played again
		# Following doesn't work as it excludes tracks that haven't
		# ever been played.  Need to be able to say NULL OR < startTime
		# Additionally, this fails when multiple clients are playing
		# random mixes.  -- Max
		#if ($mixInfo{$client}->{'startTime'}) {
		#	$find->{'lastPlayed'} = {'<' => $mixInfo{$client}->{'startTime'}};
		#}
		
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
		if (!$addOnly || $type ne $mixInfo{$client}->{'type'} || $type ne 'track') {
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

		$::d_plugins && msg("RandomPlay: cyclic mode ended\n");

		# Don't do showBrieflys if visualiser screensavers are running as 
		# the display messes up
		if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {

			$client->showBriefly(string('PLUGIN_RANDOM'), 
                                 string('PLUGIN_RANDOM_DISABLED'));
		}
		$mixInfo{$client} = undef;

	} else {

		$::d_plugins && msgf("RandomPlay: Playing %s %s mode with %i items\n",
							 $continuousMode ? 'continuous' : 'static',
							 $type,
							 Slim::Player::Playlist::count($client));

		# $startTime will only be defined if this is a new (or restarted) mix
		if (defined $startTime) {
			# Record current mix type and the time it was started.
			# Do this last to prevent menu items changing too soon
			$::d_plugins && msgf("RandomPlay: New mix started at %i\n", $startTime);
			$mixInfo{$client}->{'type'} = $type;
			$mixInfo{$client}->{'startTime'} = $startTime;
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
	if ($item eq $mixInfo{$client}->{'type'}) {
		return string($displayText{$item} . '_PLAYING');
		
	# if a mode is active, handle the temporarily added disable option
	} elsif ($item eq 'disable' && $mixInfo{$client}) {
		return string('PLUGIN_RANDOM_PRESS_RIGHT')
			   . ' '
			   . string('PLUGIN_RANDOM_' . uc($mixInfo{$client}->{'type'}) . '_DISABLE');
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
	$::d_plugins && msgf("RandomPlay: %s button pushed on type %s\n", $add ? 'Add' : 'Play', $item);
	
	# reconstruct the list of options, adding and removing the 'disable' option where applicable
	if ($item ne 'genreFilter') {
		my $listRef = Slim::Buttons::Common::param($client, 'listRef');
		
		if ($item eq 'disable') {
			pop @$listRef;
		
		# only add disable option if starting a mode from idle state
		} elsif (! $mixInfo{$client}) {
			push @$listRef, 'disable';
		}
		Slim::Buttons::Common::param($client, 'listRef', $listRef);

		# Clear any current mix type in case user is restarting an already playing mix
		$mixInfo{$client} = undef;

		# Go go go!
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
	if ($mixInfo{$client} && $mixInfo{$client}->{'type'}) {
		push @{$params{listRef}},'disable';
	}

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub commandCallback {
	my $request = shift;
	
	my $client = $request->client();

	if ($request->source() eq 'PLUGIN_RANDOM') {
		return;
	}

	if (!defined $client || !defined $mixInfo{$client}) {
		# This is nothing unexpected - some events don't provide $client
		# e.g. rescan
		return;
	}
	
	if ($::d_plugins) {
		msgf("RandomPlay: received command %s\n", 
				$request->getRequestString());
		msgf("RandomPlay: while in mode: %s, from %s\n",
				$mixInfo{$client}->{'type'}, $client->name);
	}

	my $songIndex = Slim::Player::Source::streamingSongIndex($client);

	if ($request->isCommand([['playlist'], ['newsong']]) || 
	    $request->isCommand([['playlist'], ['delete']]) && 
	    $request->getParam('_index') > $songIndex) {

        if ($::d_plugins) {
			if ($request->isCommand([['playlist'], ['newsong']])) {
				msg("RandomPlay: new song detected ($songIndex)\n");
			} else {
				msg("RandomPlay: deletion detected (" 
					. $request->getParam('_index') . ")\n");
			}
		}
		
		my $songsToKeep = 
			Slim::Utils::Prefs::get('plugin_random_number_of_old_tracks');
			
		if ($songIndex && $songsToKeep ne '') {
			$::d_plugins && 
				msg("RandomPlay: Stripping off completed track(s)\n");

			# Delete tracks before this one on the playlist
			for (my $i = 0; $i < $songIndex - $songsToKeep; $i++) {
			
				my $request = $client->execute(['playlist', 'delete', 0]);
				$request->source('PLUGIN_RANDOM');
			}
		}

		playRandom($client, $mixInfo{$client}->{'type'}, 1);

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

	# set up our subscription
	Slim::Control::Request::subscribe(\&commandCallback, 
		[['playlist'], ['newsong', 'delete', keys %stopcommands]]);
}

sub shutdownPlugin {
	# unsubscribe
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
	$params->{'pluginRandomNowPlaying'} = $mixInfo{$client}->{'type'};
	
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
PLUGIN_HEALTH
	DE	Server & Netzwerk Zustand
	EN	Server & Network Health
	ES	Salud del Servidor y la Red
	FI	Palvelimen ja verkon tila
	HE	תקינות השרת
	NL	Server- en netwerktoestand

PLUGIN_HEALTH_PERF_ENABLE
	DE	Leistungsüberwachung aktivieren
	EN	Enable Performance Monitoring
	ES	Habilitar Monitoreo de Perfomance
	NL	Schakel prestatiemonitoring in

PLUGIN_HEALTH_PERF_DISABLE
	DE	Leistungsüberwachung deaktivieren
	EN	Disable Performance Monitoring
	ES	Deshabilitar Monitoreo de Perfomance
	NL	Schakel prestatiemonitoring uit

PLUGIN_HEALTH_PERF_CLEAR
	DE	Zähler zurücksetzen
	EN	Reset Counters
	ES	Reiniciar Contadores
	FI	Tyhjennä laskurit
	NL	Terugzetten tellers

PLUGIN_HEALTH_PERF_UPDATE
	DE	Seite aktualisieren
	EN	Update Page
	ES	Actualizar Página
	FI	Päivityssivu
	NL	Ververs pagina

PLUGIN_HEALTH_PERFOFF_DESC
	DE	Die Leistungsüberwachung ist zurzeit nicht aktiviert.
	EN	Performance monitoring is not currently enabled on your server.
	ES	El monitoreo de perfomance no se encuentra habilitado actualmente en el servidor.
	FI	Suorituskyvyn valvonta ei ole tällä hetkellä kytketty päälle palvelimella.
	NL	Prestatiemonitoring is op dit moment niet actief op je server.

PLUGIN_HEALTH_PERFON_DESC
	DE	Die Leistungsüberwachung ist auf ihrem Server aktiviert. Der Server sammelt während der Ausführung Leistungsdaten.
	EN	Performance monitoring is currently enabled on your server.	Performance statistics are being collected in the background while your server is running.
	ES	El monitoreo de Perfomance está actualmente habilitado en su servidor. Las estadísticas de perfomance se recopilan en el fondo, mientras el servidor esta corriendo.
	FI	Suorituskyvyn valvonta on tällä hetkellä kytketty päälle palvelimellasi. Palvelin kerää tilastotietoa taustalla.
	HE	תוסף איסוף סטטיסטיקות מופעל
	NL	Prestatiemonitoring is op dit moment actief op je server. Prestatiestatistieken worden bijgehouden in de achtergrond terwijl je server draait.

PLUGIN_HEALTH_SUMMARY
	DE	Zusammenfassung
	EN	Summary
	ES	Sumario
	NL	Samenvatting

PLUGIN_HEALTH_SUMMARY_DESC
	DE	Bitte erstellen Sie eine Wiedergabeliste auf ihrem Player und starten Sie die Wiedergabe. Drücken Sie dann "Zähler zurücksetzen", um die Statistiken neu zu starten und die Anzeige zu aktualisieren.
	EN	Please queue up several tracks to play on this player and start them playing.  Then press the Reset Counters link above to clear the statistics and update this display.
	ES	Por favor, encolar varias pistas para escuchar en este reproductor, y empezar a reproducir. Luego presionar en el link "Reiniciar Contadores" más arriba para limpiar las estadísticas y actualizar el display.
	NL	et een aantal liedjes in de playlist voor deze speler en start afspelen. Klik dan op Terugzetten tellers hierboven om de statistieken leeg te maken en het scherm bij te werken.

PLUGIN_HEALTH_PLAYERDETAIL
	DE	Player-Leistung
	EN	Player Performance
	ES	Performance del Reproductor
	FI	Soittimen suorituskyky
	NL	Speler prestatie

PLUGIN_HEALTH_PLAYERDETAIL_DESC
	DE	Die folgenden Graphen zeigen den Langzeit-Trend für alle Player-Leistungsdaten auf. Sie zeigen die Anzahl und den Prozentanteil der Messungen, die in eine bestimmte Wertekategorie fallen.<p>Es ist wichtig, den Player eine Weile Musik spielen zu lassen, um aussagekräftige Werte zu erhalten.
	EN	The graphs shown here record the long term trend for each of the player performance measurements below.  They display the number and percentage of measurements which fall within each measurement band.<p>It is imporant to leave the player playing for a while and then assess the graphs.
	ES	Los gráficos mostrados aquí registran la tendencia a largo plazo de las mediciones de perfomance de los reproductores debajo. Muestran el nómero y porcentaje de mediciones que caen dentro de cada banda de medición.    Es importante dejar el reproductor funcionando durante un tiempo antes de considerar los gráficos.
	HE	הגרף מציג סטטיסטיקות. בדוק אותו לאחר הפעלת התוסף המתאים לאורך זמן מה
	NL	De hier getoonde grafieken laten de langetermijn trend zien voor de speler prestatiemetingen hieronder. Ze laten het getal en percentage zien van de metingen die in elk metingsgebied valt.  <br>Het is belangrijk om de speler een tijdje te laten spelen en daarna de grafieken te raadplegen.

PLUGIN_HEALTH_SIGNAL
	DE	Signalstärke
	EN	Player Signal Strength
	ES	Potencia de la Señal  del Reproductor
	FI	Soittimen signaalivoimakkuus
	NL	Spelersignaalsterkte

PLUGIN_HEALTH_SIGNAL_DESC
	DE	Diese Graphik zeigt die Signalstärke der Wireless Netzwerkverbindung ihres Players. Höhere Werte sind besser. Der Player gibt die Signalstärke während der Wiedergabe zurück.
	EN	This graph shows the strength of the wireless signal received by your player.  Higher signal strength is better.  The player reports signal strength while it is playing.
	ES	Este gráfico muestra la energía de la señal inalámbrica recibida por tu reproductor. Un valor alto de energía es mejor.El reproductor reporta la energía de la señal mientras está reproduciendo.
	NL	Deze grafiek toont de signaalsterkte van je draadloze netwerk zoals ontvangen door je speler. Hogere signaalsterkte is beter. De speler rapporteert de signaalsterkte tijdens het afspelen.

PLUGIN_HEALTH_BUFFER
	DE	Puffer-Füllstand
	EN	Buffer Fullness
	ES	Llenado del Buffer
	FI	Puskurin täyttöaste
	NL	Bufferniveau

PLUGIN_HEALTH_BUFFER_DESC
	DE	Diese Graphik zeigt den Puffer-Füllstand ihres Players. Höhere Werte sind besser. Beachten Sie bitte, dass der Puffer nur während der Wiedergabe gefüllt wird.<p>Die Squeezebox1 besitzt nur einen kleinen Puffer, der während der Wiedergabe stets voll sein sollte. Fällt der Wert auf 0, so ist mit Aussetzern in der Wiedergabe zu rechnen. Dies wäre vermutlich auf Netzwerkprobleme zurückzuführen.<p>Die Squeezebox2/3 verwendet einen grossen Puffer. Dieser wird am Ende jedes wiedergegebenen Liedes geleert (Füllstand 0) um dann wieder aufzufüllen. Der Füllstand sollte also meist hoch sein.<p>Die Wiedergabe von Online-Radiostationen kann zu niedrigem Puffer-Füllstand führen, da der Player auf die Daten von einem entfernten Server warten muss. Dies ist normales Verhalten und kein Grund zur Beunruhigung.
	EN	This graph shows the fill of the player\'s buffer.  Higher buffer fullness is better.  Note the buffer is only filled while the player is playing tracks.<p>Squeezebox1 uses a small buffer and it is expected to stay full while playing.  If this value drops to 0 it will result in audio dropouts.  This is likely to be due to network problems.<p>Squeezebox2/3 uses a large buffer.  This drains to 0 at the end of each track and then refills for the next track.  You should only be concerned if the buffer fill is not high for the majority of the time a track is playing.<p>Playing remote streams can lead to low buffer fill as the player needs to wait for data from the remote server.  This is not a cause for concern.
	ES	Este gráfico muestra el llenado del buffer del reproductor. Cuanto más lleno esté mejor es. Notar que el buffer solo se llena cuando el reproductor está reproduciendo pistas.    Squeezebox1 utiliza un buffer pequeño y se espera que permanezca lleno mientras se reproduce. Si este valor cae a 0 se producirán interrupciones en el audio. Esto se debe muy probablemente a problemas de red.    Squeezebox2/3 utiliza un buffer grande. Este se vacía (vuelve a 0) al final de cada pista y luego se llena nuevamente para la próxima pista. Solo debería precupar el caso en que el llenado del buffer no tiene un nivel alto durante la mayoría del tiempo en que se esta reproduciendo una pista.    El reproducir streams remotos puede producir que el buffer tenga un nivel de llenado bajo, ya que el reproductor necesitas esperar que lleguen datos del servidor remoto. Esto no es causa para preocuparse.
	HE	תצוגה גרפית של סטטיסטיקות
	NL	Deze grafiek toont bufferniveau. Hoger niveau is beter. De buffer is alleen gevuld tijdens het afspelen van muziek.  <br>Squeezebox1 gebruikt een kleine buffer die normaal gesproken altijd vol is. Als het niveau naar 0 gaat zal er hapering in het geluid optreden. Dit komt vaak door netwerkproblemen.  <br>Squeezebox2/3 gebruikt een grote buffer. Hier loopt het bufferniveau naar 0 toe aan het einde van een liedje en vult zich weer aan het begin van het volgende liedje. Alleen als de buffer de meeste tijd niet gevuld is tijdens het spelen moet je actie nemen.  <br>Het spelen van streams op afstand (Internet radio) geeft een laag bufferniveau omdat de speler moet wachten op de server op afstand. Dit is geen gevolg van problemen.

PLUGIN_HEALTH_CONTROL
	DE	Kontrollverbindung
	EN	Control Connection
	ES	Conexión de Control
	FI	Hallintayhteys
	NL	Controleconnectie

PLUGIN_HEALTH_CONTROL_DESC
	DE	Diese Graphik zeigt die Anzahl von aufgestauten Meldungen, die über die Kontroll-Verbindung zum Player geschickt werden sollten. Die Messung findet statt, wenn eine Meldung zum Player geschickt wird. Werte über 1-2 weisen auf eine mögliche Netzwerk-Überlastung hin, oder dass die Verbindung zum Player unterbrochen wurde.
	EN	This graph shows the number of messages queued up to send to the player over the control connection.  A measurement is taken every time a new message is sent to the player.  Values above 1-2 indicate potential network congestion or that the player has become disconnected.
	ES	Esta gráfico muestra el nómero de mensajes encolados para ser enviados al reproductor sobre la conexión de control. Una medición se toma cada vez que un nuevo mensaje es enviado hacia el reproductor. Los valores mayores a 1-2 indican una congestión potencial de la red o que el reprodcutor se ha desconectado.
	HE	אם הערכים בגרף הם מעל 1 או 2 בדוק רשת
	NL	Deze grafiek toont de hoeveelheid boodschappen in de rij gezet om te versturen naar de speler over de controleconnectie. Bij elke verstuurde boodschap wordt een meting gedaan. Waarden boven 1-2 geven een potentieel een netwerkcongestie aan of dat de speler losgekoppeld is van het netwerk.

PLUGIN_HEALTH_STREAM
	DE	Streaming-Verbindung
	EN	Streaming Connection
	ES	Conexión para Streaming
	NL	Streaming connectie

PLUGIN_HEALTH_SERVER_PERF
	DE	Server-Leistung
	EN	Server Performance
	ES	Perfomance del Servidor
	FI	Palvelimen suorituskyky
	NL	Serverprestatie

PLUGIN_HEALTH_SERVER_PERF_DESC
	DE	Die folgenden Graphen zeigen den Langzeit-Trend für alle Server-Leistungsdaten auf. Sie zeigen die Anzahl und den Prozentanteil der Messungen, die in eine bestimmte Wertekategorie fallen.
	EN	The graphs shown here record the long term trend for each of the server performance measurements below.  They display the number and percentage of measurements which fall within each measurement band.
	ES	Los gráficos mostrados aquíÂ­ registran la tendencia a largo plazo de las mediciones de perfomance de   los servidores debajo. Muestran el nómero y porcentaje de mediciones que caen dentro de cada banda de medición.
	NL	De hier getoonde grafieken laten de langetermijn trend zien van de server prestatiemetingen hieronder. Ze laten het getal en percentage zien van de metingen die in elk metingsgebied valt.

PLUGIN_HEALTH_TIMER_LATE
	DE	Timer Genauigkeit
	EN	Timer Accuracy
	ES	Precisión del Timer
	NL	Timeraccuraatheid

PLUGIN_HEALTH_TIMER_LATE_DESC
	DE	SlimServer benutzt einen Timer, um Ereignisse wie z.B. Updates der Programmoberfläche zu steuern. Diese Graphik zeigt die Genauigkeit, mit welcher Timer-gesteuerte Abläufe im Vergleich zum vorgesehenen zeitlichen Ablauf ausgeführt werden. Die Masseinheit ist Sekunden.<p>Aufgaben werden auf einen bestimmten Zeitpunkt festgelegt. Da stets nur ein Timer ablaufen kann und der Server auch andere Aktivitäten ausführt, kommt es stets zu einer minimalen Verzögerung. Kommt es allerdings zu einer markanten Verzögerung, so kann es zu wahrnehmbaren Störungen der Benutzeroberfläche kommen.
	EN	Slimserver uses a timer mechanism to trigger events such as updating the user interface.  This graph shows how accurately each timer task is run relative to the time it was intended to be run.  It is measured in seconds.<p>Timer tasks are scheduled by the server to run at some point in the future.  As only one timer task can run at once and the server may also be performing other activity, timer tasks always run slightly after the time they are scheduled for.  However if timer tasks run significantly after they are scheduled this can become noticable through delay in the user interface.
	ES	Slimserver usa un mecanismo de "timer" para disparar eventos, tales como la actualización de la interface de usuario.  Este gráfico muestra que tan preciso es cada tarea del "timer" para ejecutarse en relación al momento en que se intentaba que corriera. Se mide en segundos.    Las tareas de "timers" con planificadas por el servidor para ser corridas en algón momento en el futuro. Como solo una tarea de "timer" puede correr por vez, y ademá el servidor puede estar desarrollando alguna otra actividad, las tareas de "timer"siempre corren levemente después del momento para el cual se las había planificado.   Sin embargo, si las tareas corren significativamente más tarde de lo planificado, esto puede percibirse como un retraso en la interface de usuario.
	HE	זמן התגובה לרענון ממשק האינטרנט
	NL	SlimServer gebruikt een timermechanisme om zaken zoals het bijwerken van de gebruikersinterface te activeren. Deze grafiek toont hoe accuraat elke timertaak is uitgevoerd relatief tot de tijd waarin het uitgevoerd had moeten worden. De uitkomst is in seconden.  <br>Timertaken worden gepland door de server om op een moment in de toekomst te draaien. Daar slechts &eacute;&eacute;n timertaak tegelijk kan draaien en de server ook andere taken uitvoert draaien timertaken altijd korte tijd nadat ze gepland zijn. Als timertaken echter significant later draaien dan gepland kan dit in de gebruikersinterface merkbaar worden als vertraging.

PLUGIN_HEALTH_TIMER_LENGTH
	DE	Timer Ausführungsdauer
	EN	Timer Task Duration
	ES	Duración de Tarea de Timer
	FI	Ajastimen tehtävän kesto
	NL	Timertaakduur

PLUGIN_HEALTH_TIMER_LENGTH_DESC
	DE	Diese Graphik zeigt die Dauer, während der Timer-gesteuerte Abläufe ausgeführt werden. Die Masseinheit ist Sekunden. Braucht ein Vorgang länger als 0.5 Sekunden, so führt das mit grosser Wahrscheinlichkeit zu Störungen der Benutzeroberfläche.
	EN	This graph shows how long each timer task runs for.  It is measured in seconds.  If any timer task takes more than 0.5 seconds this is likely to impact the user interface.
	ES	Este gráfico muestra durante cuanto tiempo corre cada "timer". Se mide en segundos. Si cualquier tarea de un "timer" toma más de 0.5 segundos, es muy probable que esto impacte en la interface de usuario.
	HE	במידה והגרף מציג זמנים ארוכים מחצי שניה, בדוק עומס על השרת
	NL	Deze grafiek toont hoe lang elke timertaak duurt. De uitkomst is in seconden. Als een timertaak langer duurt dan 0.5 seconden is het waarschijnlijk dat deze impact heeft op de gebruikersinterface.

PLUGIN_HEALTH_RESPONSE
	DE	Server Antwortzeiten
	EN	Server Response Time
	ES	Tiempo de Respuesta del Servidor
	NL	Serverreactietijd

PLUGIN_HEALTH_RESPONSE_DESC
	DE	Diese Graphik zeigt die Zeitdauer, die zwischen zwei Anfragen von beliebigen Playern vergeht. Die Masseinheit ist Sekunden. Geringere Werte sind besser. Antwortzeiten über einer Sekunde können zu Problemen bei der Audio-Wiedergabe führen.<p>Gründe für solche Verzögerungen können andere ausgeführte Programme oder komplexe Verarbeitungen im SlimServer sein.
	EN	This graph shows the length of time between slimserver responding to requests from any player.  It is measured in seconds. Lower numbers are better.  If you notice response times of over 1 second this could lead to problems with audio performance.<p>The cause of long response times could be either other programs running on the server or slimserver processing a complex task.
	ES	Este gráfico muestra el tiempo de respuesta de Slimserver a requerimientos de cualquier reproductor. Se mide en segundos. Valores bajos son mejores. Si se nota tiempos de respuesta de más de 1 segundo esto puede producir problemas con la perfomance de audio.    La causa de tiempos de respuesta grandes puede ser o bien otros programas corriendo en el servidor, o bien que Slimserver esté procesando una tarea compleja.
	HE	במידה וגרף זה מציג זמנים מעל שניה אחת יש בעיה ברשת או שהשרת עמוס
	NL	Deze grafiek toont de tijd waarbinnen SlimServer reageert op verzoeken van de speler. De uitkomst is in seconden. Lagere waardes zijn beter. Als je reactietijden hebt van meer dan 1 seconde kan dit leiden tot problemen bij afspelen van audio.  <br>De oorzaak van lange reactietijden kan liggen bij andere programma's die draaien op de server of dat SlimServer een complexe taak uitvoert.

PLUGIN_HEALTH_SCHEDULER
	DE	Geplante Aufgaben
	EN	Scheduled Tasks
	ES	Tareas Planificadas
	NL	Geplande taken

PLUGIN_HEALTH_SCHEDULER_DESC
	DE	Der Server führt Prozessor-intensive Aufgaben wie z.B. das Durchsuchen nach neuen Musikstücken in Etappen aus, welche zwischen Anfragen von Playern durchgeführt werden. Diese Graphik zeigt die Länge in Sekunden, die eine Ausführung dauert, bevor der Server die Kontrolle wieder übernehmen kann. Aufgaben, welche länger als 0.5 Sekunden dauern, können zu Störungen der Benutzeroberfläche führen.
	EN	The server runs processor intensive tasks (such as scanning your music collection) by breaking them into short pieces which are scheduled when when active players are not requesting data.  This graph shows the length of time in seconds that a scheduled task runs for before returning control to the server.  Tasks taking over 0.5 second may lead to reduced performance for the user interface.
	ES	El servidor ejecuta tareas que son intensivas en el procesador (tales como recopilar la colección musical) diviendolas en piezas mas pequeñas, que se planifican para ejecutar cuando los reproductores activos no están requiriendo datos. Este gráfico muestra el tiempo (en segundos) durante el que corre una tarea planificada antes de devolver el control al servidor. Las tareas que toman más de 0.5 segundo pueden influir en reducir la perfomance de la interface de usuario.
	HE	במחשבים ישנים עליית השרת יכולה להעמיס על המחשב ולהאט אותו. ביר כאן לעליה מבוקרת של השרת
	NL	De server draait processorintensieve taken (zoals het scannen van je muziekcollectie) door deze op te breken in korte stukken die vervolgens gepland worden op momenten dat spelers niet vragen om gegevens. Deze grafiek toont de tijd in seconden dat een geplande taak draait voordat hij controle teruggeeft aan de server. Taken die meer tijd in beslag nemen dan 0.5 seconden kunnen leiden tot een slechtere prestatie van de gebruikersinterface (haperende menu's).

PLUGIN_HEALTH_IRRESPONSE
	DE	Infrarot Antwortzeit
	EN	IR Response Time

PLUGIN_HEALTH_IRRESPONSE_DESC
	DE	Die Graphik zeigt die Zeit auf, die zwischen dem Empfang und der Verarbeitung von Fernsteuerungs-Befehlen liegt. Wenn der Server ausgelastet ist, dann werden die Befehle in eine Warteschlange gestellt. Diese Graphik gibt Informationen darüber, wie lange ein Befehl in der Warteschlange stand.
	EN	This graph shows the time between the server receiving remote control key presses and processing them.  When the server is busy remote key presses are stored for processing later.  This graph gives an indication of how long key presses are stored for.

PLUGIN_HEALTH_WARNINGS
	DE	Warnungen
	EN	Warnings
	ES	Advertencias
	NL	Waarschuwingen

PLUGIN_HEALTH_OK
	EN	OK

PLUGIN_HEALTH_FAIL
	DE	Gestört
	EN	Fail
	ES	Falla
	NL	Gefaald

PLUGIN_HEALTH_CONGEST
	DE	Überlastung
	EN	Congested
	ES	Congestionado
	FI	Ruuhkautunut
	NL	Congestie

PLUGIN_HEALTH_INACTIVE
	DE	Inaktiv
	EN	Inactive
	ES	Inactivo
	FI	Ei aktiivinen
	IT	Inattivo
	NL	Inactief

PLUGIN_HEALTH_STREAMINACTIVE_DESC
	DE	Derzeit existiert keine aktive Verbindung zu diesem Gerät. Eine Verbindung ist notwendig, um eine Datei zum Player übertragen zu können. Squeezebox2/3 können die Streaming-Verbindung gegen Ende eines Liedes schliessen, sobald die Daten im Puffer auf dem Gerät angekommen sind. Das ist kein Grund zur Beunruhigung.<p>Falls Sie Probleme haben, Musikdateien abzuspielen und Sie nie eine aktive Verbindung sehen, dann kann das auf Netzwerkprobleme hindeuten. Bitte verifizieren Sie, dass das Netzwerk und/oder die Firewall Verbindungen auf Port 9000 nicht blockieren.
	EN	There is currently no active connection for streaming to this player.  A connection is required to stream a file to your player.  Squeezebox2/3 may close the streaming connection towards the end of a track once it is transfered to the buffer within the player.  This is not cause for concern.<p>If you experiencing problems playing files and never see an active streaming connection, then this may indicate a network problem.  Please check that your network and/or server firewall do not block connections to TCP port 9000.
	NL	Er is op dit moment geen actieve connectie voor het streamen naar deze speler. Een connectie is altijd nodig om bestanden te spelen vanaf de server (maar niet als je een radiostream op afstand gebruikt bij een Squeezebox2 of 3)  <br>  Als je een lokaal bestand probeert af te spelen dan wijst dit op een netwerkprobleem. Controleer of je netwerk en/of server firewall niet TCP poort 9000 blokkeren.

PLUGIN_HEALTH_CONTROLFAIL_DESC
	DE	Derzeit ist keine aktive Kontroll-Verbindung für diesen Player vorhanden. Bitte stellen Sie sicher, dass das Gerät eingeschaltet ist. Falls der Player keine Netzwerkverbindung aufbauen kann, überprüfen sie bitte die Netzwerkkonfiguration und/oder Firewall. Diese darf TCP und UPD Ports 3483 nicht blockieren.
	EN	There is no currently active control connection to this player.  Please check the player is powered on.  If the player is unable to establish a connection, please check your network and and/or server firewall do not block connections to TCP & UDP port 3483.
	ES	No existe una conexión de control activa a este reproductor. Por favor, verificar que el reproductor esté encendido. Si el reproductor no puede establecer una conexión,  por favor, verificar que la red y/o el firewall del servidor no estén bloqueando las conexiones TCP y UDP  en el puerto 3483.
	HE	הנגן לא מחובר. בדוק אם הוא מחובר לחשמל
	NL	Er is momenteel geen actieve controleconnectie naar deze speler. Controleer of de speler aan staat. Controleer of je netwerk en/of server firewall geen connecties blokkeren naar TCP & UDP poort 3483 als je speler geen connectie kan maken.

PLUGIN_HEALTH_CONTROLCONGEST_DESC
	DE	Die Kontroll-Verbindung zu diesem Player hat Überlastungen erfahren. Dies ist üblicherweise ein Hinweis auf schlechte Netzwerkverbindung, oder dass das Gerät vor kurzem vom Netz genommen wurde.
	EN	The control connection to this player has experienced congestion.  This usually is an indication of poor network connectivity (or the player being recently being disconnected from the network).
	ES	La conexión de control a este reproductor ha experimentado congestión. Esto generalmente es indicador de una mala conectividad en la red (también puede deberse a que el reproductor se desconectó recientemente de la red).
	HE	הקישור בין הנגן לשרת נקטע מספר פעמים. בדוק רשת
	NL	De controleconnectie naar deze speler heeft last gehad van congestie. Dit is meestal een indicatie van een slechte netwerkconnectie (of een speler die recent van het netwerk losgekoppeld is geweest).

PLUGIN_HEALTH_SIGNAL_INTERMIT
	DE	Gut, aber mit vereinzelten Ausfällen
	EN	Good, but Intermittent Drops
	ES	Buena, pero con Cortes Intermitentes
	FI	Hyvä, mutta satunnaisia katkoja
	NL	Goed maar af en toe haperingen

PLUGIN_HEALTH_SIGNAL_INTERMIT_DESC
	DE	Die Signalstärke dieses Players ist im Grossen und Ganzen gut, hatte aber vereinzelte Ausfälle. Dies kann auf andere Wireless Netzwerke, kabellose Telephone oder Mikrowellen-Öfen zurückzuführen sein. Falls Sie vereinzelte Ton-Aussetzer wahrnehmen, so sollten Sie der Ursache des Problems nachgehen.
	EN	The signal strength received by this player is normally good, but occasionally drops.  This may be caused by other wireless networks, cordless phones or microwaves nearby.  If you hear occasional audio dropouts on this player, you should investigate what is causing drops in signal strength.
	ES	La energía de la señal recibida por este reproductor es normalmente buena, pero con cortes ocasionalmente. Esto puede estar causado por otras redes inalámbricas, teléfonos inalámbricos u hornos de microondas cercanos. Si se escuchan interrupciones de audio ocasionales en este reproductor, se debería investigar cuál es la causa de las caídas en la energía de la señal.
	NL	De signaalsterkte ontvangen door de speler is goed met af en toe haperingen. De oorzaak kunnen andere draadloze netwerken zijn, draadloze telefoons of magnetrons die dichtbij zijn. Als je haperingen hoort in de audio moet je de oorzaak onderzoeken van de haperingen in de signaalsterkte.

PLUGIN_HEALTH_SIGNAL_POOR
	DE	Schwach
	EN	Poor
	ES	Pobre
	NL	Matig

PLUGIN_HEALTH_SIGNAL_POOR_DESC
	DE	Die Signalstärke dieses Players ist grösstenteils schwach. Bitte überprüfen Sie das Wireless Netzwerk.
	EN	The signal strength received by this player is poor for significant periods, please check your wireless network.
	ES	La energía de la señal recibida por este reproductor es pobre durante períodos importantes, por favor verificar la red inalámbrica.
	NL	De signaalsterkte ontvangen door de speler is matig over een langere periode. Controleer je draadloze netwerk.

PLUGIN_HEALTH_SIGNAL_BAD
	DE	Schlecht
	EN	Bad
	ES	Mala
	FI	Huono
	NL	Slecht

PLUGIN_HEALTH_SIGNAL_BAD_DESC
	DE	Die Signalstärke dieses Players ist grösstenteils schlecht. Bitte überprüfen Sie das Wireless Netzwerk.
	EN	The signal strength received by this player is bad for significant periods, please check your wireless network.
	ES	La energía de la señal recibida por este reproductor es mala durante períodos importantes, por favor verificar la red inalámbrica.
	NL	De signaalsterkte ontvangen door je speler is slecht over een  aanzienlijke periode. Controleer je draadloze netwerk.

PLUGIN_HEALTH_BUFFER_LOW
	DE	Niedrig
	EN	Low
	ES	Bajo
	FI	Matala
	NL	Laag

PLUGIN_HEALTH_BUFFER_LOW_DESC1
	DE	Der Wiedergabe-Puffer dieses Players ist zeitweise niedriger als wünschenswert. Dies kann zu Tonaussetzern führen, v.a. falls Sie WAV oder AIFF verwenden. Falls Sie solche Aussetzer wahrnehmen, überprüfen Sie bitte die Signalstärke und Server Antwortzeiten.
	EN	The playback buffer for this player is occasionally falling lower than ideal.  This may result in audio dropouts especually if you are streaming as WAV/AIFF.  If you are hearing these, please check your network signal strength and server response times.
	ES	El buffer de reproducción de este reproductor tiene, ocasionalmente, niveles por debajo del ideal. Esto puede producir interrupciones en el audio, especialmente si se está transmitiendo en formato WAV/AIFF. Si se escuchan estos, por favor, controlar la potencia de señal de red y los tiempos de respuesta del servidor.
	HE	לנגן יש בעיות לקבל מידע מהשרת. בדוק רשת
	NL	De afspeelbuffer van deze speler is af en toe minder gevuld dan in de ideale situatie. Dit kan resulteren in audio haperingen, zeker als je WAV/AIFF streamt. Controleer de netwerksignaalsterkte en de snelheid waarmee de server reageert als je haperingen hoort.

PLUGIN_HEALTH_BUFFER_LOW_DESC2
	DE	Der Wiedergabe-Puffer dieses Players ist zeitweise niedriger als wünschenswert. Dies ist eine Squeezebox2/3, es ist daher normal, dass der Puffer am Ende eines Liedes geleert wird. Diese Warnung wird ev. angezeigt, falls Sie viele kurze Lieder wiedergeben. Falls Sie Tonaussetzer feststellen, überprüfen Sie bitte die Signalstärke.
	EN	The playback buffer for this player is occasionally falling lower than ideal.  This is a Squeezebox2/3 and so the buffer fullness is expected to drop at the end of each track.  You may see this warning if you are playing lots of short tracks.  If you are hearing audio dropouts, please check our network signal strength.
	ES	El buffer de reproducción de este reproductor tiene, ocasionalmente, niveles por debajo del ideal. Este es un Squeezebox2/3 y por lo tanto es esperable que el buffer se vacíe al final de cada pista. Se puede recibir esta advertencia si se están reproduciendo muchas pistas de corta duración. Si se escuchan interrupciones de audio, por favor, controlar la potencia de señal de red.
	HE	לנגן יש בעיות לקבל מידע מהשרת. בדוק רשת
	NL	De afspeelbuffer van deze speler is af en toe minder gevuld dan in de ideale situatie. Dit is een Squeezebox2. Daar mag het bufferniveau laag zijn aan het einde van een liedje. Je kunt deze waarschuwing krijgen als je veel korte liedjes afspeelt. Controleer de netwerksignaalsterkte als je haperingen hoort in het geluid.

PLUGIN_HEALTH_RESPONSE_INTERMIT
	DE	Teilweise schlechte Antwortzeiten
	EN	Occasional Poor Response
	ES	Ocasionalmente Respuesta Pobre
	FI	Satunnaista huonoa vastetta
	NL	Af en toe slechte reactietijd

PLUGIN_HEALTH_RESPONSE_INTERMIT_DESC
	DE	Die Antwortzeiten des Servers sind zeitweise länger als wünschenswert. Dies kann zu hörbaren Tonaussetzern führen, v.a. auf SliMP3 und Squeezebox1 Playern. Gründe hierfür können andere laufene Programme im Hintergrund oder komplexe Aufgaben im Slimserver sein.
	EN	Your server response time is occasionally longer than desired.  This may cause audio dropouts, especially on Slimp3 and Squeezebox1 players.  It may be due to background load on your server or a slimserver task taking longer than normal.
	ES	El tiempo de respuesta del servidor es ocasionalmente más alto que el deseado. Esto puede causar interrupciones audio, especialmente en los reproductores Slimp3 y Squeezebox1. Puede deberse a una carga de procesos de fondo, o a que una tarea de Slimserver está tomando más tiempo que el normal.
	HE	זמן התגובה של השרת ארוך מהרצוי, בדוק אם השרת עמוס
	NL	De serverreactietijd is af en toe lager dan gewenst. Dit kan audio haperingen veroorzaken, zeker bij de Slimp3 en Squeezebox1 spelers. De oorzaak kunnen de overige programma's zijn die op je server draaien of een SlimServer taak die langer duurt dan normaal.

PLUGIN_HEALTH_RESPONSE_POOR
	DE	Schlechte Antwortzeiten
	EN	Poor Response
	ES	Respuesta Pobre
	FI	Huono vaste
	NL	Slechte reactietijd

PLUGIN_HEALTH_RESPONSE_POOR_DESC
	DE	Die Antwortzeiten des Servers sind oft länger als wünschenswert. Dies kann zu hörbaren Tonaussetzern führen, v.a. auf SliMP3 und Squeezebox1 Playern. Überprüfen Sie bitte die Leistung ihres Servers. Falls diese ok ist, vergewissern Sie sich, ob SlimServer komplexe Aufgaben (z.B. Durchsuchen der Musiksammlung) durchführt oder ein Plugin die Ursache für das Problem darstellt.
	EN	Your server response time is regularly falling below normal performance levels.  This may lead to audio dropouts, especially on Slimp3 and Squeezebox1 players.  Please check the performance of your server.  If this is OK, then check slimserver is not running intensive tasks (e.g. scanning music library) or a Plugin is not causing this.
	ES	El tiempo de respuesta del servidor es regularmente más bajo que los niveles de perfomance normales. Esto puede causar interrupciones de  audio, especialmente en los reproductores Slimp3 y Squeezebox1. Por favor, verificar la perfomance del servidor. Si esto está OK, entonces verificar que Slimserver no está corriendo tareas intensivas (por ej. recopilando la colección musical) o que algón plugin no está causando esto.
	HE	זמן התגובה של השרת ארוך מהרצוי, בדוק אם השרת עמוס
	NL	De serverreactietijd is regelmatig lager dan gewenst. Dit kan audio haperingen veroorzaken, zeker bij de Slimp3 en Squeezebox1 spelers. Controleer de prestatie van je server. Is die goed, controleer dan of SlimServer geen intensieve taken draait (zoals scannen van de muziekcollectie) of dat een plugin dit veroorzaakt.

PLUGIN_HEALTH_NORMAL
	DE	Dieser Player verhält sich normal.
	EN	This player is performing normally.
	ES	Este reproductor está funcionando normalmente.
	FI	Tämä soitin toimii normaalisti.
	NL	Deze speler functioneert normaal.

PLUGIN_HEALTH_NO_PLAYER_DESC
	DE	SlimServer kann keinen Player finden. Falls einer angeschlossen ist, so kann dies durch eine blockierte Netzwerkverbindung ausgelöst werden. Überprüfen sie bitte die Netzwerkkonfiguration und/oder Firewall. Diese darf TCP und UPD Ports 3483 nicht blockieren.
	EN	Slimserver cannot find a player.  If you own a player this could be due to your network blocking connection between the player and server.  Please check your network and/or server firewall does not block connection to TCP & UDP port 3483.
	ES	Slimserver no puede encontrar ningón reproductor. Si existe un reproductor esto puede deberse a bloqueos de conexión de red entre el servidor y el reproductor. Por favor, verificar que la red y/o el firewall del servidor no estén bloqueando las conexiones TCP y UDP en el puerto 3483.
	HE	השרת לא מוצא נגן, בדוק רשת וחומת אש
	NL	SlimServer kan geen speler vinden. Als je een speler hebt kan dit komen door een netwerk dat connecties blokkeert tussen de speler en server. Controleer of je netwerk en/of server firewall niet TCP & UDP poort 3483 blokkeert.

PLUGIN_HEALTH_SLIMP3_DESC
	DE	Sie verwenden einen SliMP3 Player. Für diesen stehen nicht die vollen Messungen zur Verfügung.
	EN	This is a SLIMP3 player.  Full performance measurements are not available for this player.
	ES	Este es un reproductor SLIMP3. Medidas completas de perfomance no están disponibles para este reproductor.
	NL	Dit is een Slimp3 speler. Volledige prestatiemonitoring is niet beschikbaar voor deze speler.

PLUGIN_HEALTH_NETTEST
	DE	Netzwerktest
	EN	Network Test
	ES	Test de Red
	NL	Netwerk test

PLUGIN_HEALTH_NETTEST_SELECT_RATE
	DE	Bitte mit auf/ab Rate wählen
	EN	Press Up/Down to select rate
	ES	Elegir tasa: pres. Arriba/Abajo
	NL	Selecteer snelheid met op/neer

PLUGIN_HEALTH_NETTEST_NOT_SUPPORTED
	DE	Wird auf diesem Player nicht unterstützt.
	EN	Not Supported on this Player
	ES	No soportado en este Reproductor
	NL	Niet ondersteund op deze speler

PLUGIN_HEALTH_NETTEST_DESC1
	DE	Sie können die Netzwerk-Leistung zwischen dem Server und diesem Player testen. Das erlaubt es ihnen, die höchst mögliche Datenrate zu bestimmen, die ihr Netzwerk übertragen kann. Auch kann es beim Aufspüren von Netzwerkproblemen dienen. Um einen Test zu starten, wählen Sie eine der folgenden Datenraten.<p><b>Achtung:</b> das Durchführen eines Netzwerktests unterbricht alle anderen Aktivitäten auf diesem Gerät.
	EN	You may test the network performance between your server and this player.  This will enable you to confirm the highest data rate that your network will support and identify network problems.  To start a test select one of the data rates below.<p><b>Warning</b> Running a network test will stop all other activity for this player including streaming.
	NL	Je kunt de netwerkprestatie tussen je server en deze speler testen. Hiermee kun je zien wat de hoogste snelheid is die je netwerk ondersteunt en om problemen te identificeren. Om de test te starten kies je een testsnelheid.  <br>  <b>Waarschuwing</b> Tijdens de netwerktest stoppen alle andere activiteiten van de speler, ook het streamen.

PLUGIN_HEALTH_NETTEST_DESC2
	DE	Es läuft derzeit ein Netzwerktest auf diesem Gerät. Dies unterbindet die Erstellung anderer Statistiken. Sie können unten eine neu Testrate definieren. Um den Test zu stoppen und zu den anderen Geräteleistungs-Informationen zu gelangen, wählen Sie "Test anhalten".<p>Die Graphik zeigt den erfolgreich übetragenen Anteil an der Testrate in Prozent an. Sie wird einmal pro Sekunde aktualisiert. Es werden das Resultat für die letzte Sekunde sowie der längerfristige Durchschnitt auch auf dem Display des Players angezeigt. Lassen Sie den Test eine Weile auf einer bestimmten Datenrate laufen. Die Grafik zeigt dann an, wie oft der Datendurchsatz unter 100% der gewünschten Rate gefallen ist.
	EN	You are currently running a network test on this player.  This disables reporting other player statistics.  You may change the test rate by selecting a new rate above.  To stop the test and return to other player performance information select Stop Test above.<p>The graph below records the percentage of the test rate which is sucessfully sent to the player.  It is updated once per second with the performance measured over the last second.  The result for the last second and long term average at this rate are also shown on the player display while a test is running.  Leave the test running for a period of time at a fixed rate.  The graph will record how frequently the network performance drops below 100% at this rate.
	NL	Je laat nu een netwerk test lopen voor deze speler. Andere spelerstatistieken zijn nu uitgeschakeld. Je kunt de testsnelheid wijzigen door hierboven een andere testsnelheid te kiezen. Om de test te stoppen en terug te keren naar de andere spelerstatistieken selecteer je Stop test hierboven.  <br>  De grafiek hieronder toont het percentage van de testsnelheid dat succesvol is verstuurd naar de speler. Elke seconde wordt het resultaat van de laatste seconde bijgewerkt. Het resultaat van de laatste seconde en het resultaat over een langere periode worden ook getoond op het scherm van de speler. Laat de test een tijdje lopen op een gekozen testsnelheid. De grafiek zal registreren hoe frequent de netwerksnelheid onder de 100% komt.

PLUGIN_HEALTH_NETTEST_DESC3
	DE	Die höchste Datenrate, die zu 100% übertragen wird, ist die höchste Rate, die für Streaming zur Verfügung steht. Falls diese geringer ist als die Bitrate ihrer Dateien, so sollten Sie eine Beschränkung der Bitrate in Betracht ziehen.<p>Squeezebox2/3, die per Kabel ans Netzwerk angeschlossen sind, sollten mindestens 3000kbps zu 100% erreichen, die Squeezebox1 ca. 1500kbps. Drahtlos angeschlossene Geräte können ebenfalls solche Werte erreichen, doch hängt das Resultat stark vom Netzwerk ab. Werte, die erheblich niedriger sind, deuten auf Netzwerkprobleme hin. Wireless Netzwerke können durchaus geringere Werte erreichen. Benutzen Sie die Grafik, um die Leistung zu verstehen. Falls die Datenrate häufig absinkt, dann sollten Sie das Netzwerk überprüfen.
	EN	The highest test rate which achieves 100% indicates the maximum rate you can stream at.  If this is below the bitrate of your files you should consider configuring bitrate limiting for this player.<p>A Squeezebox2/3 attached to a wired network should be able to achieve at least 3000 kbps at 100% (Squeezebox1 1500 kbps).  A player attached to a wireless network may also reach up to this rate depending on your wireless network.  Rates significantly below this indicate poor network performance.  Wireless networks may record occasional lower percentages due to interference.  Use the graph above to understand how your network performs.  If the rate drops frequently you should investigate your network.
	NL	De hoogste testsnelheid waar je 100% haalt is de maximale snelheid waarmee je een stream kunt sturen. Als dit onder de bitrate is van je bestanden moet je overwegen om een bitrate limiet in te stellen.  <br> Een Squeezebox2/3 verbonden via een bedraad netwerk moet op zijn minst 3000 kbps op 100% halen (Squeezebox 1 1500 kbps). Een speler gekoppeld aan een draadloos netwerk kan ook deze snelheid halen, afhankelijk van je draadloze netwerk. Snelheden die significant onder de bovenstaande waarden liggen wijzen op een slechte netwerkperformance. Draadloze netwerken kunnen af en toe lagere percentages geven door interferentie. Gebruik de bovenstaande grafiek om na te gaan hoe je netwerkperformance is. Als de snelheid regelmatig laag is moet je het netwerk controleren.

PLUGIN_HEALTH_NETTEST_PLAYERNOTSUPPORTED
	DE	Dieser Player unterstützt keine Netzwerktests.
	EN	Network tests are not supported on this player.
	NL	Netwerk testen zijn niet ondersteund op deze speler.

PLUGIN_HEALTH_NETTEST_CURRENTRATE
	DE	Aktuelle Testrate
	EN	Current Test Rate
	NL	Huidige testsnelheid

PLUGIN_HEALTH_NETTEST_TESTRATE
	DE	Test Datenrate
	EN	Test Rate
	NL	Testsnelheid

PLUGIN_HEALTH_NETTEST_STOPTEST
	DE	Test anhalten
	EN	Stop Test
	NL	Stop test

EOF

}

1;

__END__
