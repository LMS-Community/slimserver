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
my %genreNameMap = ();

my $htmlTemplate = 'plugins/RandomPlay/randomplay_list.html';

sub getDisplayName {
	return 'PLUGIN_RANDOM';
}

# Find tracks matching parameters and add them to the playlist
sub findAndAdd {
	my ($client, $type, $find, $limit, $addOnly) = @_;

	$::d_plugins && msgf("RandomPlay: Starting random selection of %s items for type: $type\n", defined($limit) ? $limit : 'unlimited');

	my @joins  = ();

	# Pull in the right tables to do our searches
	if ($type eq 'track' || $type eq 'year') {

		if ($find->{'genreTracks.genre'}) {

			push @joins, 'genreTracks';
		}

	} elsif ($type eq 'album') {

		if ($find->{'genreTracks.genre'}) {

			push @joins, { 'tracks' => 'genreTracks' };

		} else {

			push @joins, 'tracks';
		}

	} elsif ($type eq 'contributor') {

		if ($find->{'genreTracks.genre'}) {

			push @joins, { 'contributorTracks' => { 'track' => 'genreTracks' } };

		} else {

			push @joins, { 'contributorTracks' => 'track' };
		}
	}

	# Search the database for the number of track we need. Use MySQL's
	# RAND() function to get back a random list. Restrict by the genre's we've selected.
	my @results = ();
	my $rs      = Slim::Schema->rs($type)->search($find, {

		'order_by' => \'RAND()',
		'join'     => \@joins,
	});

	if ($limit) {

		@results = $rs->slice(0, ($limit-1));

	} else {

		@results = $rs->all;
	}

	$::d_plugins && msgf("RandomPlay: Find returned %i items\n", scalar @results);

	# Pull the first track off to add / play it if needed.
	my $obj = shift @results;

	if (!$obj || !ref($obj)) {

		errorMsg("RandomPlay: Didn't get a valid object for findAndAdd()!\n");
		return undef;
	}

	$::d_plugins && msgf("RandomPlay: %s %s: %s, %d\n",
		$addOnly ? 'Adding' : 'Playing', $type, $obj->name, $obj->id
	);

	# Replace the current playlist with the first item / track or add it to end
	my $request = $client->execute([
		'playlist', $addOnly ? 'addtracks' : 'loadtracks', sprintf('%s.id=%d', $type, $obj->id)
	]);

	# indicate request source
	$request->source('PLUGIN_RANDOM');

	# Add the remaining items to the end
	if ($type eq 'track') {

		if (!defined $limit || $limit > 1) {

			$::d_plugins && msgf("RandomPlay: Adding %i tracks to end of playlist\n", scalar @results);

			$request = $client->execute(['playlist', 'addtracks', 'listRef', \@results ]);

			$request->source('PLUGIN_RANDOM');
		}
	}

	return $obj->name;
}

# Returns a hash whose keys are the genres in the db
sub getGenres {
	my ($client) = @_;

	my $rs = Slim::Schema->search('Genre');

	# Extract each genre name into a hash
	my %clientGenres = ();
	my @exclude      = Slim::Utils::Prefs::getArray('plugin_random_exclude_genres');

	while (my $genre = $rs->next) {

		# Put the name here as well so the hash can be passed to
		# INPUT.Choice as part of listRef later on
		my $name = $genre->name;
		my $id   = $genre->id;
		my $ena  = 1;

		if (grep { $_ eq $name } @exclude) {
			$ena = 0;
		}

		$clientGenres{$name} = {
			'id'      => $id,
			'name'    => $name,
			'enabled' => $ena,
		};
	}

	$genres{$client} = \%clientGenres;

	return $genres{$client};
}

# Returns an array of the non-excluded genres in the db
sub getFilteredGenres {
	my ($client, $returnExcluded, $namesOnly) = @_;

	my @filteredGenres = ();
	my @excludedGenres = ();
	
	# use second arg to set what values we return. we may need list of ids or names
	my $value = $namesOnly ? 'name' : 'id';

	# If $returnExcluded, just return the current state of excluded genres
	my $clientGenres = $returnExcluded ? $genres{$client} : getGenres($client);

	for my $genre (keys %{$clientGenres}) {

		if ($clientGenres->{$genre}->{'enabled'}) {
			push (@filteredGenres, $clientGenres->{$genre}->{$value}) if !$returnExcluded;
		} else {
			push (@excludedGenres, $clientGenres->{$genre}->{$value}) if $returnExcluded;
		}
	}

	return $returnExcluded ? \@excludedGenres : \@filteredGenres;
}

sub getRandomYear {
	my $filteredGenres = shift;

	$::d_plugins && msg("RandomPlay: Starting random year selection\n");

	my %cond = ();
	my %attr = ( 'order_by' => \'RAND()' );

	if (ref($filteredGenres) eq 'ARRAY' && scalar @$filteredGenres > 0) {

		$cond{'genreTracks.genre'} = $filteredGenres;
		$attr{'join'}              = 'genreTracks';
	}

	my $year = Slim::Schema->rs('Track')->search(\%cond, \%attr)->single->year;

	$::d_plugins && msg("RandomPlay: Selected year $year\n");

	return $year;
}

# Add random tracks to playlist if necessary
sub playRandom {
	# If addOnly, then track(s) are appended to end.  Otherwise, a new playlist is created.
	my ($client, $type, $addOnly) = @_;

	$::d_plugins && msg("RandomPlay: playRandom called with type $type\n");

	if (!$mixInfo{$client->masterOrSelf->id}) {
		
		#init hash for each new client
		$mixInfo{$client->masterOrSelf->id}->{'type'} = undef;
	}
	
	$type ||= 'track';
	$type = lc($type);

	# Whether to keep adding tracks after generating the initial playlist
	my $continuousMode = Slim::Utils::Prefs::get('plugin_random_keep_adding_tracks');

	# If this is a new mix, store the start time
	my $startTime = undef;

	if ($continuousMode && $type && (!$mixInfo{$client->masterOrSelf->id}->{'type'} || $mixInfo{$client->masterOrSelf->id}->{'type'} ne $type)) {
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

		} elsif ($songsRemaining < $numRandomTracks) {

			$numItems = $numRandomTracks - $songsRemaining;

		} else {

			$::d_plugins && msgf("RandomPlay: $songsRemaining items remaining so not adding new track\n");
		}

	} elsif ($type ne 'disable' && ($type ne $mixInfo{$client->masterOrSelf->id}->{'type'} || ! $addOnly || $songsRemaining <= 0)) {

		# Old artist/album/year is finished or new random mix started.  Add a new one
		$numItems = 1;
	}

	if ($numItems) {

		if (!$addOnly) {
			$client->execute(['stop']);
			$client->execute(['power', '1']);
		}

		Slim::Player::Playlist::shuffle($client, 0);

		my $find = {};

		# Initialize find to only include user's selected genres.  If they've deselected
		# all genres, this clause will be ignored by find, so all genres will be used.
		my $filteredGenres = getFilteredGenres($client);
		my $excludedGenres = getFilteredGenres($client, 1);

		# Only look for genre tracks if we have some, but not all
		# genres selected. Or no genres selected.
		if ((scalar @$filteredGenres > 0 && scalar @$excludedGenres != 0) || 
		     scalar @$filteredGenres != 0 && scalar @$excludedGenres > 0) {

			$find->{'genreTracks.genre'} = { 'in' => $filteredGenres };
		}

		# Prevent items that have already been played from being played again
		# This fails when multiple clients are playing random mixes. -- Max
		if ($mixInfo{$client->masterOrSelf->id}->{'startTime'}) {

			$find->{'lastPlayed'} = [
				{ '=' => undef },
				{ '<' => $mixInfo{$client->masterOrSelf->id}->{'startTime'} }
			];
		}

		if ($type eq 'track' || $type eq 'year') {

			# Find only tracks, not directories or remote streams etc
			$find->{'audio'} = 1;
		}

		# String to show with showBriefly
		my $string = '';

		if ($type ne 'track') {
			$string = $client->string('PLUGIN_RANDOM_' . uc($type) . '_ITEM') . ': ';
		}

		# If not track mode, add tracks then go round again to check whether the playlist only
		# contains one track (i.e. the artist/album/year only had one track in it).  If so,
		# add another artist/album/year or the plugin would never add more when the first finished in continuous mode.
		for (my $i = 0; $i < 2; $i++) {

			if ($i == 0 || ($type ne 'track' && Slim::Player::Playlist::count($client) == 1 && $continuousMode)) {

				# Genre filters don't apply in year mode as I don't know how to restrict the
				# random year to a genre.
				my $year;

				if ($type eq 'year') {

					$year = getRandomYear($filteredGenres);

					if ($year) {
						$find->{'year'} = $year;
					}
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
					$i == 0 ? $addOnly : 1
				);

				if ($type eq 'year') {
					$string .= $year;
				} else {
					$string .= $findString;
				}
			}
		}

		# Do a show briefly the first time things are added, or every time a new album/artist/year
		# is added
		if (!$addOnly || $type ne $mixInfo{$client->masterOrSelf->id}->{'type'} || $type ne 'track') {

			if ($type eq 'track') {
				$string = $client->string("PLUGIN_RANDOM_TRACK");
			}

			# Don't do showBrieflys if visualiser screensavers are running as the display messes up
			if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {

				$client->showBriefly(
					string($addOnly ? 'ADDING_TO_PLAYLIST' : 'NOW_PLAYING'),
					$string, 2, undef, undef, 1
				);
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

		$mixInfo{$client->masterOrSelf->id} = undef;

	} else {

		$::d_plugins && msgf(
			"RandomPlay: Playing %s %s mode with %i items\n",
			$continuousMode ? 'continuous' : 'static', $type, Slim::Player::Playlist::count($client)
		);

		# $startTime will only be defined if this is a new (or restarted) mix
		if (defined $startTime) {
			# Record current mix type and the time it was started.
			# Do this last to prevent menu items changing too soon
			$::d_plugins && msgf("RandomPlay: New mix started at %i\n", $startTime);
			$mixInfo{$client->masterOrSelf->id}->{'type'} = $type;
			$mixInfo{$client->masterOrSelf->id}->{'startTime'} = $startTime;
		}
	}
}

# Returns the display text for the currently selected item in the menu
sub getDisplayText {
	my ($client, $item) = @_;

	if (!scalar keys %displayText) {

		%displayText = (
			'track'       => 'PLUGIN_RANDOM_TRACK',
			'album'       => 'PLUGIN_RANDOM_ALBUM',
			'contributor' => 'PLUGIN_RANDOM_CONTRIBUTOR',
			'year'        => 'PLUGIN_RANDOM_YEAR',
			'genreFilter' => 'PLUGIN_RANDOM_GENRE_FILTER'
		)
	}

	# if showing the current mode, show altered string
	if (defined $mixInfo{$client->masterOrSelf->id}->{'type'} && $item eq $mixInfo{$client->masterOrSelf->id}->{'type'}) {

		return string($displayText{$item} . '_PLAYING');
		
	# if a mode is active, handle the temporarily added disable option
	} elsif ($item eq 'disable' && $mixInfo{$client->masterOrSelf->id}) {

		return join(' ',
			string('PLUGIN_RANDOM_PRESS_RIGHT'),
			string('PLUGIN_RANDOM_' . uc($mixInfo{$client->masterOrSelf->id}->{'type'}) . '_DISABLE')
		);

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

	my $rv     = 0;
	my $genres = getGenres($client);	

	if ($item->{'selectAll'}) {

		# This item should be ticked if all the genres are selected
		my $genresEnabled = 0;

		for my $genre (keys %{$genres}) {

			if ($genres->{$genre}->{'enabled'}) {
				$genresEnabled++;
			}
		}

		$rv = $genresEnabled == scalar keys %{$genres};
		$item->{'enabled'} = $rv;

	} else {

		$rv = $genres->{$item->{'name'}}->{'enabled'};
	}

	return [undef, Slim::Buttons::Common::checkBoxOverlay($client, $rv)];
}

# Toggle the exclude state of a genre in the select genres mode
sub toggleGenreState {
	my ($client, $item) = @_;
	
	if ($item->{'selectAll'}) {

		$item->{'enabled'} = ! $item->{'enabled'};

		# Enable/disable every genre
		foreach my $genre (keys %{$genres{$client}}) {
			$genres{$client}->{$genre}->{'enabled'} = $item->{'enabled'};
		}

	} else {

		# Toggle the selected state of the current item
		$genres{$client}->{$item->{'name'}}->{'enabled'} = ! $genres{$client}->{$item->{'name'}}->{'enabled'};
	}

	Slim::Utils::Prefs::set('plugin_random_exclude_genres', getFilteredGenres($client, 1, 1));

	$client->update;
}

# Do what's necessary when play or add button is pressed
sub handlePlayOrAdd {
	my ($client, $item, $add) = @_;

	$::d_plugins && msgf("RandomPlay: %s button pushed on type %s\n", $add ? 'Add' : 'Play', $item);

	# reconstruct the list of options, adding and removing the 'disable' option where applicable
	if ($item ne 'genreFilter') {

		my $listRef = $client->modeParam('listRef');

		if ($item eq 'disable') {

			pop @$listRef;

		} elsif (!$mixInfo{$client->masterOrSelf->id}) {

			# only add disable option if starting a mode from idle state
			push @$listRef, 'disable';
		}

		$client->modeParam('listRef', $listRef);

		# Clear any current mix type in case user is restarting an already playing mix
		$mixInfo{$client->masterOrSelf->id}->{'type'} = undef;

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
		listRef    => [qw(track album contributor year genreFilter)],
		name       => \&getDisplayText,
		overlayRef => \&getOverlay,
		modeName   => 'RandomPlay',
		onPlay     => sub { handlePlayOrAdd(@_, 0) },
		onAdd      => sub { handlePlayOrAdd(@_, 1) },
		onRight    => sub {
			my ($client, $item) = @_;

			if ($item eq 'genreFilter') {

				my $genres    = getGenres($client);
				my %genreList = map { $genres->{$_}->{'name'}, $genres->{$_} } keys %{$genres};

				# Insert Select All option at top of genre list
				my @listRef = ({
					name => $client->string('PLUGIN_RANDOM_SELECT_ALL'),
					# Mark the fact that isn't really a genre
					selectAll => 1,
					value     => 1,
				});

				# Add the genres
				foreach my $genre (sort keys %genreList) {
					
					# HACK: add 'value' so that INPUT.Choice won't complain as much. nasty setup there.
					$genreList{$genre}->{'value'} = $genreList{$genre}->{'id'};
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
	if ($mixInfo{$client->masterOrSelf->id} && $mixInfo{$client->masterOrSelf->id}->{'type'}) {
		push @{$params{'listRef'}}, 'disable';
	}

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub commandCallback {
	my $request = shift;
	my $client  = $request->client();

	# Don't respond to callback for ourself.
	if ($request->source && $request->source eq 'PLUGIN_RANDOM') {
		return;
	}

	if (!defined $client || !defined $mixInfo{$client->masterOrSelf->id}->{'type'}) {
		# This is nothing unexpected - some events don't provide $client
		# e.g. rescan
		return;
	}

	if ($::d_plugins) {
		msgf("RandomPlay: received command %s\n", $request->getRequestString);
		msgf("RandomPlay: while in mode: %s, from %s\n", $mixInfo{$client->masterOrSelf->id}->{'type'}, $client->name);
	}
	
	# Bug 3696, If the last track in the playlist failed, restart play
	if ( $request->isCommand([['playlist'], ['cant_open']]) && $client->playmode !~ /play/ ) {
		$::d_plugins && msg("RandomPlay: Last track failed, restarting\n");
		playRandom($client, $mixInfo{$client->masterOrSelf->id}->{'type'});
		return;
	}		

	my $songIndex = Slim::Player::Source::streamingSongIndex($client);

	if ($request->isCommand([['playlist'], ['newsong']]) || 
	    $request->isCommand([['playlist'], ['delete']]) && 
	    $request->getParam('_index') > $songIndex) {

		if ($::d_plugins) {

			if ($request->isCommand([['playlist'], ['newsong']])) {
				msg("RandomPlay: new song detected ($songIndex)\n");
			} else {
				msg("RandomPlay: deletion detected (" . $request->getParam('_index') . ")\n");
			}
		}

		my $songsToKeep = Slim::Utils::Prefs::get('plugin_random_number_of_old_tracks');

		if ($songIndex && $songsToKeep ne '' && $songIndex > $songsToKeep) {

			$::d_plugins && msgf("RandomPlay: Stripping off %i completed track(s)\n", $songIndex - $songsToKeep);

			# Delete tracks before this one on the playlist
			for (my $i = 0; $i < $songIndex - $songsToKeep; $i++) {

				my $request = $client->execute(['playlist', 'delete', 0]);
				$request->source('PLUGIN_RANDOM');
			}
		}

		playRandom($client, $mixInfo{$client->masterOrSelf->id}->{'type'}, 1);

	} elsif ($request->isCommand([['playlist'], [keys %stopcommands]])) {

		$::d_plugins && msgf("RandomPlay: cyclic mode ending due to playlist: %s command\n", $request->getRequestString);
		playRandom($client, 'disable');
	}
}

sub initPlugin {
	# playlist commands that will stop random play
	%stopcommands = (
		'clear'	     => 1,
		'loadtracks' => 1, # multiple play
		'playtracks' => 1, # single play
		'load'       => 1, # old style url load (no play)
		'play'       => 1, # old style url play
		'loadalbum'  => 1, # old style multi-item load
		'playalbum'  => 1, # old style multi-item play
	);
	
	checkDefaults();

	generateGenreNameMap();

	# set up our subscription
	Slim::Control::Request::subscribe(\&commandCallback, 
		[['playlist'], ['newsong', 'delete', 'cant_open', keys %stopcommands]]);

	# Regenerate the genre map after a rescan.
	Slim::Control::Request::subscribe(\&generateGenreNameMap, [['rescan'], ['done']]);

#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F
	Slim::Control::Request::addDispatch(['randomplay', '_mode'],
	[1, 0, 0, \&cliRequest]);
}

sub generateGenreNameMap {
	my $request = shift;

	if ($request && $request->source && $request->source eq 'PLUGIN_RANDOM') {
		return;
	}

	# Clear out the old map.
	%genreNameMap = ();

	# Populate the genreMap, so we can use IDs
	my $rs = Slim::Schema->search('Genre');

	while (my $genre = $rs->next) {

		$genreNameMap{$genre->name} = $genre->id;
	}
}

sub cliRequest {
	my $request = shift;
 
	# get our parameters
	my $mode   = $request->getParam('_mode');
	my $client = $request->client();
	my $functions = getFunctions();

	if (!defined $mode || !defined $$functions{$mode} || !$client) {
		$request->setStatusBadParams();
		return;
	}

	&{$$functions{$mode}}($client);
	
	$request->setStatusDone();
}

sub shutdownPlugin {
	# unsubscribe
	Slim::Control::Request::unsubscribe(\&commandCallback);
}

sub getFunctions {

	# Functions to allow mapping of mixes to keypresses
	return {
		'tracks'       => sub { playRandom(shift, 'track') },
		'albums'       => sub { playRandom(shift, 'album') },
		'contributors' => sub { playRandom(shift, 'contributor') },
		'year'         => sub { playRandom(shift, 'year') },
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

	if ($client) {
		# Pass on the current pref values and now playing info
		$params->{'pluginRandomGenreList'} = getGenres($client);
		$params->{'pluginRandomNumTracks'} = Slim::Utils::Prefs::get('plugin_random_number_of_tracks');
		$params->{'pluginRandomNumOldTracks'} = Slim::Utils::Prefs::get('plugin_random_number_of_old_tracks');
		$params->{'pluginRandomContinuousMode'} = Slim::Utils::Prefs::get('plugin_random_keep_adding_tracks');
		$params->{'pluginRandomNowPlaying'} = $mixInfo{$client->masterOrSelf->id}->{'type'};
	}
	
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

	my $genres = getGenres($client);

	# %$params will contain a key called genre_<genre id> for each ticked checkbox on the page
	for my $genre (keys %{$genres}) {

		if ($params->{'genre_'.$genres->{$genre}->{'id'}}) {
			delete($genres->{$genre});
		}
	}

	Slim::Utils::Prefs::set('plugin_random_exclude_genres', [keys %{$genres}]);	

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
	FI	Satunnainen sekoitus
	FR	Mix aléatoire
	HE	מיקס אקראי
	NL	Willekeurige mix

PLUGIN_RANDOM_DISABLED
	DE	Zufalls Mix angehalten
	EN	Random Mix Stopped
	ES	Mezcla al Azar Detenida
	FR	Mix aléatoire arrêté
	HE	מיקס אקראי מופסק
	NL	Willekeurige mix gestopt

PLUGIN_RANDOM_TRACK
	DE	Zufälliger Lieder Mix
	EN	Random Song Mix
	ES	Mezcla por Canción al Azar
	FR	Morceaux aléatoires
	HE	מיקס שיר אקראי
	NL	Willekeurige liedjes mix

PLUGIN_RANDOM_TRACK_PLAYING
	DE	Spiele zufällige Liederauswahl
	EN	Playing Random Songs
	ES	Reproduciendo Canciones al Azar
	FR	Lecture morceaux aléatoires
	NL	Afspelen willekeurige liedjes

PLUGIN_RANDOM_TRACK_DISABLE
	DE	keine Lieder mehr hinzuzufügen
	EN	stop adding songs
	ES	dejar de añadir canciones
	FR	ne plus ajouter de morceaux
	NL	Stop toevoegen liedjes

PLUGIN_RANDOM_ALBUM
	DE	Zufälliger Album Mix
	EN	Random Album Mix
	ES	Mezcla al azar por Álbum
	FR	Albums aléatoires
	HE	מיקס אלבום אקראי
	NL	Willekeurige album mix

PLUGIN_RANDOM_ALBUM_ITEM
	DE	Zufälliges Album
	EN	Random Album
	ES	Álbum al Azar
	FR	Album aléatoire
	NL	Willekeurig album

PLUGIN_RANDOM_ALBUM_PLAYING
	DE	Spiele zufällige Albenauswahl
	EN	Playing Random Albums
	ES	Reproduciendo Álbumes al Azar
	FR	Lecture albums aléatoires
	NL	Afspelen willekeurige albums

PLUGIN_RANDOM_ALBUM_DISABLE
	DE	keine Alben mehr hinzuzufügen
	EN	stop adding albums
	FR	ne plus ajouter d'albums
	NL	Stoppen toevoegen albums

PLUGIN_RANDOM_CONTRIBUTOR
	DE	Zufälliger Interpreten Mix
	EN	Random Artist Mix
	ES	Mezcla por Artista al Azar
	FR	Artistes aléatoires
	HE	מיקס אמן אקראי
	NL	Willekeurige artiesten mix

PLUGIN_RANDOM_CONTRIBUTOR_ITEM
	DE	Zufälliger Interpret
	EN	Random Artist
	ES	Artista al Azar
	FR	Artiste aléatoire
	NL	Willekeurige artiesten

PLUGIN_RANDOM_CONTRIBUTOR_PLAYING
	DE	Spiele zufälligen Interpreten
	EN	Playing Random Artists
	ES	Reproduciendo Artistas al Azar
	FR	Lecture artistes aléatoires
	NL	Afspelen willekeurige artiesten

PLUGIN_RANDOM_CONTRIBUTOR_DISABLE
	DE	keine Interpreten mehr hinzuzufügen
	EN	stop adding artists
	ES	dejar de añadir artistas
	FR	ne plus ajouter d'artistes
	NL	Stop toevoegen artiesten

PLUGIN_RANDOM_YEAR
	DE	Zufälliger Jahr Mix
	EN	Random Year Mix
	ES	Mezcla por Año al Azar
	FR	Années aléatoires
	NL	Willekeurige jaar mix

PLUGIN_RANDOM_YEAR_ITEM
	DE	Zufälliger Jahrgang
	EN	Random Year
	ES	Año al Azar
	FR	Année aléatoire
	NL	Willekeurig jaar

PLUGIN_RANDOM_YEAR_PLAYING
	DE	Spiele zufälligen Jahrgang
	EN	Playing Random Years
	ES	Reproduciendo Años al Azar
	FR	Lecture années aléatoires
	NL	Afspelen willekeurige jaren

PLUGIN_RANDOM_YEAR_DISABLE
	DE	keine Jahrgänge mehr hinzuzufügen
	EN	stop adding years
	ES	dejar de añadir años
	FR	ne plus ajouter d'années
	NL	Stop toevoegen jaren

PLUGIN_RANDOM_GENRE_FILTER
	DE	Zu berücksichtigende Stile wählen
	EN	Select Genres To Include
	ES	Elegir Géneros A Incluir
	FI	Valitse sisällytettävät tyylilajit
	FR	Sélectionnez les genres à inclure
	NL	Selecteer genres om toe te voegen

PLUGIN_RANDOM_SELECT_ALL
	DE	Alle wählen
	EN	Select All
	ES	Elegir Todo
	FR	Tous les genres
	HE	בחר הכל
	NL	Selecteer alles

PLUGIN_RANDOM_SELECT_NONE
	DE	Alle abwählen
	EN	Select None
	ES	No Elegir Ninguno
	FR	Aucun genre
	NL	Niets selecteren

PLUGIN_RANDOM_CHOOSE_BELOW
	DE	Wählen Sie einen zufälligen Mix von Musik aus Ihrer Sammlung:
	EN	Choose a random mix of music from your library:
	ES	Elegir una mezcla al azar de mósica de tu colección:
	FR	Sélectionnez un mix aléatoire de morceaux tirés de votre collection :
	HE	בחר מיקס אקראי
	NL	Kies een willekeurige mix van je muziekcollectie:

PLUGIN_RANDOM_TRACK_WEB
	DE	Zufällige Lieder
	EN	Random songs
	ES	Canciones al azar
	FR	Morceaux aléatoires
	HE	שירים באקראי
	NL	Willekeurige liedjes

PLUGIN_RANDOM_CONTRIBUTOR_WEB
	DE	Zufällige Interpreten
	EN	Random artists
	ES	Artistas al azar
	FR	Artistes aléatoires
	HE	אמנים באקראי
	NL	Willekeurige artiesten

PLUGIN_RANDOM_ALBUM_WEB
	DE	Zufällige Alben
	EN	Random albums
	FR	Albums aléatoires
	ES	Álbumes al azar
	HE	אלבומים באקראי
	NL	Willekeurige albums

PLUGIN_RANDOM_YEAR_WEB
	DE	Zufällige Jahrgänge
	EN	Random years
	ES	Años al azar
	FR	Années aléatoires
	HE	שנים באקראי
	NL	Willekeurige jaren

PLUGIN_RANDOM_GENRE_FILTER_WEB
	DE	Im Mix zu berücksichtigende Stile:
	EN	Genres to include in your mix:
	ES	Géneros a incluir en tu mezcla:
	FI	Sekoitukseen haluamasi tyylilajit:
	FR	Genres à inclure dans le mix :
	HE	סוגי מוזיקה שיכללו
	NL	Genres om op te nemen in je mix:

PLUGIN_RANDOM_BEFORE_NUM_TRACKS
	DE	Die Wiedergabeliste wird
	EN	Now Playing will show
	ES	Se Está Escuchando mostrará
	FI	"Nyt soi" näyttää
	FR	Lecture en cours affichera
	IT	Riproduzione in corso mostrera'
	NL	Speelt nu zal tonen:

PLUGIN_RANDOM_AFTER_NUM_TRACKS
	DE	noch abzuspielende und
	EN	upcoming songs and
	ES	próximas canciones y
	FI	tulevaa kappaletta ja
	FR	morceau(x) à venir et
	HE	מספר השירים שנוגנו ויוצגו
	NL	komende liedjes en

PLUGIN_RANDOM_AFTER_NUM_OLD_TRACKS
	DE	wiedergegebene Lieder anzeigen.
	EN	recently played songs.
	ES	canciones escuchadas recientemente.
	FI	viimeksi soitettua kappaletta.
	FR	morceau(x) joué(s) précédemment.
	HE	מספר השירים הבאים שיוצגו
	NL	recent gespeelde liedjes.

PLUGIN_RANDOM_CONTINUOUS_MODE
	DE	Neue Objekte ergänzen, wenn alte fertig gespielt sind
	EN	Add new items when old ones finish
	FR	Continuer à ajouter de nouveaux morceaux
	NL	Voeg nieuwe items toe zodra oude eindigen

PLUGIN_RANDOM_GENERAL_HELP
	DE	Sie können jederzeit Lieder aus dem Mix entfernen oder neue hinzufügen. Um den Zufallsmix anzuhalten löschen Sie bitte die Wiedergabeliste oder klicken, um
	EN	You can add or remove songs from your mix at any time. To stop a random mix, clear your playlist or click to
	ES	Se puede añadir o eliminar canciones de la mezcla en cualquier momento. Para detener una mezcla al azar, limpiar la lista o presionar
	FR	Vous pouvez ajouter ou supprimer des morceaux de votre mix à tout moment. Pour arrêter un mix aléatoire, effacez votre liste de lecture ou cliquez  ici pour
	NL	Je kunt op elk moment liedjes toevoegen bij of verwijderen uit je mix. Om de willekeurige mix te stoppen maak je de playlist leeg of klik op

PLUGIN_RANDOM_PRESS_RIGHT
	DE	RECHTS drücken um
	EN	Press RIGHT to
	FR	Appuyez sur DROITE pour
	NL	Druk -> om
EOF

}

1;

__END__
