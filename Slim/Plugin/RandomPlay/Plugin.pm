package Slim::Plugin::RandomPlay::Plugin;

# $Id$
#
# Originally written by Kevin Deane-Freeman (slim-mail (A_t) deane-freeman.com).
#
# New world order by Dan Sully - <dan | at | slimdevices.com>
# Fairly substantial rewrite by Max Spicer

# This code is derived from code with the following copyright message:
#
# SqueezeCenter Copyright (C) 2005-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::Base);

use Slim::Buttons::Home;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;
use Slim::Player::Sync;

my %stopcommands = ();

# Information on each clients random mix
my %mixInfo      = ();

# Display text for each mix type
my %displayText  = ();

# Genres for each client (don't access this directly - use getGenres())
my %genres       = ();
my %genreNameMap = ();

my $htmlTemplate = 'plugins/RandomPlay/list.html';

my $log          = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.randomplay',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

my $prefs = preferences('plugin.randomplay');

$prefs->migrate( 1, sub {
	my $newtracks = Slim::Utils::Prefs::OldPrefs->get('plugin_random_number_of_tracks');
	if ( !defined $newtracks ) {
		$newtracks = 10;
	}
	
	my $continuous = Slim::Utils::Prefs::OldPrefs->get('plugin_random_keep_adding_tracks');
	if ( !defined $continuous ) {
		$continuous = 1;
	}
	
	$prefs->set( 'newtracks', $newtracks );
	$prefs->set( 'oldtracks', Slim::Utils::Prefs::OldPrefs->get('plugin_random_number_of_old_tracks') );
	$prefs->set( 'continuous', $continuous );
	$prefs->set( 'exclude_genres', Slim::Utils::Prefs::OldPrefs->get('plugin_random_exclude_genres') || [] );
	
	1;
} );

$prefs->migrateClient(1, sub {
	my ($clientprefs, $client) = @_;
	$clientprefs->set('type', Slim::Utils::Prefs::OldPrefs->clientGet($client, 'plugin_random_type'));
	1;
});

$prefs->setValidate('int', 'newtracks' );

sub getDisplayName {
	return 'PLUGIN_RANDOMPLAY';
}

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin();

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
	Slim::Control::Request::addDispatch(['randomplaygenrelist'],
	[1, 1, 0, \&chooseGenresMenu]);
	Slim::Control::Request::addDispatch(['randomplaychoosegenre', '_genre', '_value'],
	[1, 0, 0, \&chooseGenre]);
	
	Slim::Buttons::AlarmClock->addSpecialPlaylist('PLUGIN_RANDOM_TRACK','track');
	Slim::Buttons::AlarmClock->addSpecialPlaylist('PLUGIN_RANDOM_ALBUM','album');
	Slim::Buttons::AlarmClock->addSpecialPlaylist('PLUGIN_RANDOM_CONTRIBUTOR','contributor');

	# register handler for starting mix of last type on remote button press [Default is press and hold shuffle]
	Slim::Buttons::Common::setFunction('randomPlay', \&buttonStart);

	my $menu = {
		text   => Slim::Utils::Strings::string(getDisplayName()),
		count  => 5,
		offset => 0,
		weight => 60,
		window => { titleStyle => 'mymusic' },
		item_loop => [
			{
				text    => Slim::Utils::Strings::string('PLUGIN_RANDOM_TRACK'),
				actions => {
					do => {
						player => 0,
						cmd    => [ 'randomplay', 'tracks' ],
						params => {
							menu => 'nowhere',
						},
					}
				},
			},
			{
				text    => Slim::Utils::Strings::string('PLUGIN_RANDOM_ALBUM'),
				actions => {
					do => {
						player => 0,
						cmd    => [ 'randomplay', 'albums' ],
						params => {
							menu => 'nowhere',
						},
					}
				},
			},
			{
				text    => Slim::Utils::Strings::string('PLUGIN_RANDOM_CONTRIBUTOR'),
				actions => {
					do => {
						player => 0,
						cmd    => [ 'randomplay', 'contributors' ],
						params => {
							menu => 'nowhere',
						},
					}
				},
			},
			{
				text    => Slim::Utils::Strings::string('PLUGIN_RANDOM_YEAR'),
				actions => {
					do => {
						player => 0,
						cmd    => [ 'randomplay', 'year' ],
						params => {
							menu => 'nowhere',
						},
					}
				},
			},
			{
				text    => Slim::Utils::Strings::string('PLUGIN_CHOOSE_GENRES'),
				actions => {
					go => {
						player => 0,
						cmd    => [ 'randomplaygenrelist' ],
					},
				},
			},
		],
	};

	Slim::Control::Jive::registerPluginMenu($menu, 'mymusic');
}

sub chooseGenre {
	my $request   = shift;
	my $client    = $request->client();
	my $genre     = $request->getParam('_genre');
	my $value     = $request->getParam('_value');
	my $genres    = getGenres($client);

	# in $genres, an enabled genre returns true for $genres->{'enabled'}
	# so we set enabled to 0 for this genre, then
	$genres->{$genre}->{'enabled'} = $value;
	my @excluded = ();
	for my $genre (keys %$genres) {
		push @excluded, $genre if $genres->{$genre}->{'enabled'} == 0;
	}
	# set the exclude_genres pref to all disabled genres 
	$prefs->set('exclude_genres', [@excluded]);

	$request->setStatusDone();
}

# create the Choose Genres menu for a given player
sub chooseGenresMenu {
	my $request = shift;
	my $client = $request->client();
	my $genres = getGenres($client);	
	my $filteredGenres = getFilteredGenres($client);
	my @menu = ();
	for my $genre (sort keys %$genres) {
		my $val = $genres->{$genre}->{'enabled'};
		push @menu, {
			text => $genre,
			checkbox => ($val == 1) + 0,
                        actions  => {
                                on  => {
                                        player => 0,
                                        cmd    => ['randomplaychoosegenre', $genre, 1],
                                },
                                off => {
                                        player => 0,
                                        cmd    => ['randomplaychoosegenre', $genre, 0],
                                },
                        },
		};
	}
	my $numitems = scalar(@menu);
	$request->addResult("count", $numitems);
	$request->addResult("offset", 0);
	my $cnt = 0;
	for my $eachGenreMenu (@menu[0..$#menu]) {
		$request->setResultLoopHash('item_loop', $cnt, $eachGenreMenu);
		$cnt++;
	}
	$request->setStatusDone();
}

# Find tracks matching parameters and add them to the playlist
sub findAndAdd {
	my ($client, $type, $find, $limit, $idList, $addOnly) = @_;

	if ( $log->is_info ) {
		$log->info(sprintf("Starting random selection of %s items for type: $type", defined($limit) ? $limit : 'unlimited'));
	}

	my @results;

	if ($limit && scalar @$idList) {

		# use previous id list as same find criteria as last call, select a random set of them
		my @randomIds;

		for (my $i = 0; $i < $limit && scalar @$idList; ++$i) {

			push @randomIds, (splice @$idList, rand @$idList, 1);
		}

		# Turn ids into tracks, note this will reorder ids so needs use of RAND() in SQL statement to maintain randomness
		@results = Slim::Schema->rs($type)->search({ 'id' => { 'in' => \@randomIds } }, { 'order_by' => \'RAND()' })->all;

	} else {

		# Search the database for all items of $type which match find criteria

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

		my $rs = Slim::Schema->rs($type)->search($find, { 'join' => \@joins });

		if ($limit) {

			# Get ids for all results from find and store in @$idList so they can be used in repeat calls
			@$idList = $rs->distinct->get_column('me.id')->all;

			# Get a random selection for this call
			my @randomIds;

			for (my $i = 0; $i < $limit && scalar @$idList; ++$i) {

				push @randomIds, (splice @$idList, rand @$idList, 1);
			}

			# Turn ids into tracks, note this will reorder ids so needs use of RAND() in SQL statement to maintain randomness
			@results = Slim::Schema->rs($type)->search({ 'id' => { 'in' => \@randomIds } }, { 'order_by' => \'RAND()' })->all;

		} else {

			# We want all results from the result set, but need to randomise them
			my @all = $rs->all;

			while (@all) {

				push @results, (splice @all, rand @all, 1);
			}
		}
	}

	if ( $log->is_info ) {
		$log->info(sprintf("Find returned %i items", scalar @results));
	}

	# Pull the first track off to add / play it if needed.
	my $obj = shift @results;

	if (!$obj || !ref($obj)) {

		logWarning("Didn't get a valid object for findAndAdd()!");

		return undef;
	}

	if ( $log->is_info ) {
		$log->info(sprintf("%s %s: %s, %d",
			$addOnly ? 'Adding' : 'Playing', $type, $obj->name, $obj->id
		));
	}

	# temporarily turn off shuffle while we add new stuff
	my $oldshuffle = Slim::Player::Playlist::shuffle($client);
	Slim::Player::Playlist::shuffle($client, 0);

	# Replace the current playlist with the first item / track or add it to end
	my $request = $client->execute([
		'playlist', $addOnly ? 'addtracks' : 'loadtracks', sprintf('%s.id=%d', $type, $obj->id)
	]);

	# indicate request source
	$request->source('PLUGIN_RANDOMPLAY');

	# Add the remaining items to the end
	if ($type eq 'track') {

		if (!defined $limit || $limit > 1) {

			if ( $log->is_info ) {
				$log->info(sprintf("Adding %i tracks to end of playlist", scalar @results));
			}

			$request = $client->execute(['playlist', 'addtracks', 'listRef', \@results ]);

			$request->source('PLUGIN_RANDOMPLAY');
		}
	}

	Slim::Player::Playlist::shuffle($client, $oldshuffle);
	return $obj->name;
}

# Returns a hash whose keys are the genres in the db
sub getGenres {
	my ($client) = @_;

	my $rs = Slim::Schema->search('Genre');

	# Extract each genre name into a hash
	my %clientGenres = ();
	my @exclude      = @{$prefs->get('exclude_genres')};

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

	$log->debug("Starting random year selection");

	my %cond = ();
	my %attr = ( 'order_by' => \'RAND()' );

	if (ref($filteredGenres) eq 'ARRAY' && scalar @$filteredGenres > 0) {

		$cond{'genreTracks.genre'} = $filteredGenres;
		$attr{'join'}              = 'genreTracks';
	}

	my $year = Slim::Schema->rs('Track')->search(\%cond, \%attr)->single->year;

	$log->debug("Selected year $year");

	return $year;
}

# Add random tracks to playlist if necessary
sub playRandom {
	# If addOnly, then track(s) are appended to end.  Otherwise, a new playlist is created.
	my ($client, $type, $addOnly) = @_;

	$log->debug("Called with type $type");

	$mixInfo{$client->masterOrSelf->id}->{'type'} ||= '';
	
	$type ||= 'track';
	$type = lc($type);

	# Whether to keep adding tracks after generating the initial playlist
	my $continuousMode = $prefs->get('continuous');

	# If this is a new mix, store the start time
	my $startTime = undef;

	if ($type ne $mixInfo{$client->masterOrSelf->id}->{'type'}) {

		$mixInfo{$client->masterOrSelf->id}->{'idList'} = undef;

		$prefs->client($client)->set('type', $type) unless ($type eq 'disable');

		$startTime = time() if $continuousMode;
	}

	my $songIndex = Slim::Player::Source::streamingSongIndex($client);
	my $songsRemaining = Slim::Player::Playlist::count($client) - $songIndex - 1;

	$log->debug("$songsRemaining songs remaining, songIndex = $songIndex");

	# Work out how many items need adding
	my $numItems = 0;

	if ($type eq 'track') {

		# Add new tracks if there aren't enough after the current track
		my $numRandomTracks = $prefs->get('newtracks');

		if (!$addOnly) {

			$numItems = $numRandomTracks;

		} elsif ($songsRemaining < $numRandomTracks) {

			$numItems = $numRandomTracks - $songsRemaining;

		} else {

			$log->debug("$songsRemaining items remaining so not adding new track");
		}

	} elsif ($type ne 'disable' && ($type ne $mixInfo{$client->masterOrSelf->id}->{'type'} || !$addOnly || $songsRemaining <= 0)) {

		# Old artist/album/year is finished or new random mix started.  Add a new one
		$numItems = 1;
	}

	if ($numItems) {

		if (!$addOnly) {
			$client->execute(['stop']);
			$client->execute(['power', '1']);
		}

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
					$mixInfo{$client->masterOrSelf->id}->{'idList'} ||= [],
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

		# Do a show briefly the first time things are added, or every time a new album/artist/year is added
		if (!$addOnly || $type ne $mixInfo{$client->masterOrSelf->id}->{'type'} || $type ne 'track') {

			if ($type eq 'track') {
				$string = $client->string("PLUGIN_RANDOM_TRACK");
			}

			# Don't do showBrieflys if visualiser screensavers are running as the display messes up
			if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {

				$client->showBriefly( {
					'line' => [ string($addOnly ? 'ADDING_TO_PLAYLIST' : 'NOW_PLAYING'), $string ]
				}, 2, undef, undef, 1);
			}
		}

		# Set the Now Playing title.
		#$client->currentPlaylist($string);
		
		# Never show random as modified, since its a living playlist
		$client->currentPlaylistModified(0);
	}

	if ($type eq 'disable') {

		$log->info("Cyclic mode ended");

		# Don't do showBrieflys if visualiser screensavers are running as 
		# the display messes up
		if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {

			$client->showBriefly( {
				'line' => [ string('PLUGIN_RANDOMPLAY'), string('PLUGIN_RANDOM_DISABLED') ]
			} );
		}

		$mixInfo{$client->masterOrSelf->id} = undef;
		$client->blockShuffle = 0;

	} else {

		if ( $log->is_info ) {
			$log->info(sprintf(
				"Playing %s %s mode with %i items",
				$continuousMode ? 'continuous' : 'static', $type, Slim::Player::Playlist::count($client)
			));
		}

		#BUG 5444: store the status so that users re-visiting the random mix 
		#will see a continuous mode state.
		if ($continuousMode) {
			$mixInfo{$client->masterOrSelf->id}->{'type'} = $type;
			$client->blockShuffle(1);
		}

		# $startTime will only be defined if this is a new (or restarted) mix
		if (defined $startTime) {

			# Record current mix type and the time it was started.
			# Do this last to prevent menu items changing too soon
			$log->info("New mix started at $startTime");

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
		return [undef, $client->symbols('rightarrow')];
	
	} elsif ($item ne 'disable') {
		return [undef, $client->symbols('notesymbol')];
	
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

	$prefs->set('exclude_genres', getFilteredGenres($client, 1, 1) );

	$client->update;
}

# Do what's necessary when play or add button is pressed
sub handlePlayOrAdd {
	my ($client, $item, $add) = @_;

	if ( $log->is_debug ) {
		$log->debug(sprintf("RandomPlay: %s button pushed on type %s", $add ? 'Add' : 'Play', $item));
	}

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
	my $class  = shift;
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header     => '{PLUGIN_RANDOMPLAY} {count}',
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
	if ($request->source && $request->source eq 'PLUGIN_RANDOMPLAY') {
		return;
	}

	if (!defined $client || !defined $mixInfo{$client->masterOrSelf->id}->{'type'} || !$prefs->get('continuous')) {
		return;
	}

	if ( $log->is_debug ) {
		$log->debug(sprintf("Received command %s", $request->getRequestString));
		$log->debug(sprintf("While in mode: %s, from %s", $mixInfo{$client->masterOrSelf->id}->{'type'}, $client->name));
	}
	
	# Bug 3696, If the last track in the playlist failed, restart play
	if ( $request->isCommand([['playlist'], ['cant_open']]) && $client->playmode !~ /play/ ) {

		$log->warn("Warning: Last track failed, restarting.");

		playRandom($client, $mixInfo{$client->masterOrSelf->id}->{'type'});

		return;
	}		

	my $songIndex = Slim::Player::Source::streamingSongIndex($client);

	if ($request->isCommand([['playlist'], ['newsong']]) || 
	    $request->isCommand([['playlist'], ['delete']]) && 
	    $request->getParam('_index') > $songIndex) {

		if ($log->is_info) {

			if ($request->isCommand([['playlist'], ['newsong']])) {

				if (Slim::Player::Sync::isSlave($client)) {
					$log->debug(sprintf("Ignoring new song notification for slave player"));
					return;
				} else {
					$log->info(sprintf("New song detected ($songIndex)"));
				}
				
			} else {

				$log->info(sprintf("Deletion detected (%s)", $request->getParam('_index')));
			}
		}

		my $songsToKeep = $prefs->get('oldtracks');

		if ($songIndex && $songsToKeep ne '' && $songIndex > $songsToKeep) {

			if ( $log->is_info ) {
				$log->info(sprintf("Stripping off %i completed track(s)", $songIndex - $songsToKeep));
			}

			# Delete tracks before this one on the playlist
			for (my $i = 0; $i < $songIndex - $songsToKeep; $i++) {

				my $request = $client->execute(['playlist', 'delete', 0]);
				$request->source('PLUGIN_RANDOMPLAY');
			}
		}

		playRandom($client, $mixInfo{$client->masterOrSelf->id}->{'type'}, 1);

	} elsif ($request->isCommand([['playlist'], [keys %stopcommands]])) {

		if ( $log->is_info ) {
			$log->info(sprintf("Cyclic mode ending due to playlist: %s command", $request->getRequestString));
		}

		playRandom($client, 'disable');
	}
}

sub generateGenreNameMap {
	my $request = shift;

	if ($request && $request->source && $request->source eq 'PLUGIN_RANDOMPLAY') {
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
	my $class = shift;

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

sub buttonStart {
	my $client = shift;

	playRandom($client, $prefs->client($client)->get('type') || 'track');
}

sub webPages {
	my $class = shift;

	my $urlBase = 'plugins/RandomPlay';

	Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_RANDOMPLAY' => $htmlTemplate });

	Slim::Web::HTTP::addPageFunction("$urlBase/list.html", \&handleWebList);
	Slim::Web::HTTP::addPageFunction("$urlBase/mix.html", \&handleWebMix);
	Slim::Web::HTTP::addPageFunction("$urlBase/settings.html", \&handleWebSettings);

	Slim::Web::HTTP::protectURI("$urlBase/list.html");
	Slim::Web::HTTP::protectURI("$urlBase/mix.html");
	Slim::Web::HTTP::protectURI("$urlBase/settings.html");
}

# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;

	if ($client) {
		# Pass on the current pref values and now playing info
		$params->{'pluginRandomGenreList'}     = getGenres($client);
		$params->{'pluginRandomNumTracks'}     = $prefs->get('newtracks');
		$params->{'pluginRandomNumOldTracks'}  = $prefs->get('oldtracks');
		$params->{'pluginRandomContinuousMode'}= $prefs->get('continuous');
		$params->{'pluginRandomNowPlaying'}    = $mixInfo{$client->masterOrSelf->id}->{'type'};
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

	$prefs->set('exclude_genres', [keys %{$genres}]);
 	$prefs->set('newtracks', $params->{'numTracks'});
 	$prefs->set('oldtracks', $params->{'numOldTracks'});
	$prefs->set('continuous', $params->{'continuousMode'} ? 1 : 0);

	# Pass on to check if the user requested a new mix as well
	handleWebMix($client, $params);
}

sub active {
	my $client = shift;
	
	my $id = $client->masterOrSelf->id;
	
	if ( exists $mixInfo{$id} && exists $mixInfo{$id}->{'type'} ) {
		return 1;
	}
	
	return 0;
}

1;

__END__


