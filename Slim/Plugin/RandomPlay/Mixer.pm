package Slim::Plugin::RandomPlay::Mixer;

# Originally written by Kevin Deane-Freeman (slim-mail (A_t) deane-freeman.com).
# New world order by Dan Sully - <dan | at | slimdevices.com>
# Fairly substantial rewrite by Max Spicer

# This code is derived from code with the following copyright message:
#
# Logitech Media Server Copyright 2005-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

my $cache = Slim::Utils::Cache->new();
my $log   = logger('plugin.randomplay');
my $prefs = preferences('plugin.randomplay');

# Find tracks matching parameters and add them to the playlist
sub findAndAdd {
	my ($client, $type, $limit, $addOnly) = @_;

	my $idList = $cache->get('rnd_idList_' . $client->id) || [];

	if ( main::INFOLOG && $log->is_info ) {
		$log->info(sprintf("Starting random selection of %s items for type: $type", defined($limit) ? $limit : 'unlimited'));
	}

	if ( !scalar @$idList ) {
		$idList = getIdList($client, $type);
	}

	if ($type eq 'year') {
		$type = 'track';
	}

	# get first ID from our randomized list
	my @randomIds = splice @$idList, 0, $limit;

	$cache->set('rnd_idList_' . $client->id, $idList, 'never');

	if (!scalar @randomIds) {

		logWarning("Didn't get a valid object for findAndAdd()!");

		return undef;
	}

	my $queryLibrary = $prefs->get('library') || Slim::Music::VirtualLibraries->getLibraryIdForClient($client);
	my $libraryParam = '&library_id=' . $queryLibrary if $queryLibrary;

	# Add the items to the end
	foreach my $id (@randomIds) {

		if ( main::INFOLOG && $log->is_info ) {
			$log->info(sprintf("%s %s: #%d",
				$addOnly ? 'Adding' : 'Playing', $type, $id
			));
		}

		# Replace the current playlist with the first item / track or add it to end
		my $request = $client->execute([
			'playlist', $addOnly ? 'addtracks' : 'loadtracks', sprintf('%s.id=%d%s', $type, $id, $libraryParam)
		]);

		# indicate request source
		$request->source('PLUGIN_RANDOMPLAY');

		$addOnly++;
	}
}

sub getIdList {
	my ($client, $type) = @_;

	main::DEBUGLOG && $log->debug('Initialize ID list to be randomized: ' . $type);

	# Search the database for all items of $type which match find criteria
	my @joins = ();

	# Initialize find to only include user's selected genres.  If they've deselected
	# all genres, this clause will be ignored by find, so all genres will be used.
	my $filteredGenres = Slim::Plugin::RandomPlay::Plugin::getFilteredGenres($client, 0, 0, 1);
	my $excludedGenres = Slim::Plugin::RandomPlay::Plugin::getFilteredGenres($client, 1, 0, 1);
	my $queryGenres;
	my $queryLibrary;
	my $idList;

	# Only look for genre tracks if we have some, but not all
	# genres selected. Or no genres selected.
	if ( (scalar @$filteredGenres > 0 && scalar @$excludedGenres != 0) ||
			scalar @$filteredGenres != 0 && scalar @$excludedGenres > 0 ) {

		$queryGenres = join(',', @$filteredGenres);
	}

	$queryLibrary = $prefs->get('library') || Slim::Music::VirtualLibraries->getLibraryIdForClient($client);

	if ($type =~ /track|year/) {
		# it's messy reaching that far in to Slim::Control::Queries, but it's >5x faster on a Raspberry Pi2 with 100k tracks than running the full "titles" query
		my $results;
		($results, $idList) = Slim::Control::Queries::_getTagDataForTracks( 'II', {
			where     => '(tracks.content_type != "cpl" AND tracks.content_type != "src" AND tracks.content_type != "ssp" AND tracks.content_type != "dir")',
			year      => $type eq 'year' && getRandomYear($client, $filteredGenres),
			genreId   => $queryGenres,
			libraryId => $queryLibrary,
		} );

		if (preferences('server')->get('useBalancedShuffle')) {
			main::DEBUGLOG && $log->is_debug && $log->debug("Using balanced shuffle");
			$idList = Slim::Player::Playlist::balancedShuffle([ map { [$_, $results->{$_}->{'tracks.primary_artist'}] } keys %$results ]);
		}
		else {
			# shuffle ID list
			Slim::Player::Playlist::fischer_yates_shuffle($idList);
		}

		$type = 'track';
	}
	else {
		my %categories = (
			album       => ['albums', 0, 999_999, 'tags:t'],
			contributor => ['artists', 0, 999_999],
			track       => []
		);
		$categories{year}    = $categories{track};
		$categories{artist} = $categories{contributor};

		my $query = $categories{$type};

		push @$query, 'genre_id:' . $queryGenres if $queryGenres;
		push @$query, 'library_id:' . $queryLibrary if $queryLibrary;

		my $request = Slim::Control::Request::executeRequest($client, $query);

		my $loop = "${type}s_loop";
		$loop = 'artists_loop' if $type eq 'contributor';

		$idList = [ map { $_->{id} } @{ $request->getResult($loop) || [] } ];

		# shuffle ID list
		Slim::Player::Playlist::fischer_yates_shuffle($idList);
	}

	return $idList;
}

sub getRandomYear {
	my $client = shift;
	my $filteredGenres = shift;

	main::DEBUGLOG && $log->debug("Starting random year selection");

	my $years = $cache->get('rnd_years_' . $client->id) || [];

	if (!scalar @$years) {
		my %cond = ();
		my %attr = (
			'order_by' => Slim::Utils::OSDetect->getOS()->sqlHelperClass()->randomFunction(),
			'group_by' => 'me.year',
		);

		if (ref($filteredGenres) eq 'ARRAY' && scalar @$filteredGenres > 0) {

			$cond{'genreTracks.genre'} = $filteredGenres;
			$attr{'join'}              = ['genreTracks'];
		}

		if ( my $library_id = $prefs->get('library') || Slim::Music::VirtualLibraries->getLibraryIdForClient($client) ) {

			$cond{'libraryTracks.library'} = $library_id;
			$attr{'join'}                ||= [];
			push @{$attr{'join'}}, 'libraryTracks';

		}

		$years = [ Slim::Schema->rs('Track')->search(\%cond, \%attr)->get_column('me.year')->all ];
	}

	my $year = shift @$years;

	$cache->set('rnd_years_' . $client->id, $years, 'never');

	main::DEBUGLOG && $log->debug("Selected year $year");

	return $year;
}

# Add random tracks to playlist if necessary
sub playRandom {
	# If addOnly, then track(s) are appended to end.  Otherwise, a new playlist is created.
	my ($client, $type, $addOnly) = @_;

	$client = $client->master;

	main::DEBUGLOG && $log->debug("Called with type $type");

	$client->pluginData('type', '') unless $client->pluginData('type');

	$type ||= 'track';
	$type = lc($type);

	# Whether to keep adding tracks after generating the initial playlist
	my $continuousMode = $prefs->get('continuous');

	if ($type ne $client->pluginData('type')) {
		$cache->remove('rnd_idList_' . $client->id);
	}

	if (my $idList = $cache->get('dstm_idList_' . $client->id)) {
		$cache->set('rnd_idList_' . $client->id, $idList, 'never');
		$cache->remove('dstm_idList_' . $client->id);
	}

	my $songIndex = Slim::Player::Source::streamingSongIndex($client);
	my $songsRemaining = Slim::Player::Playlist::count($client) - $songIndex - 1;

	main::DEBUGLOG && $log->debug("$songsRemaining songs remaining, songIndex = $songIndex");

	# Work out how many items need adding
	my $numItems = 0;

	if ($type =~ /track|year/) {

		# Add new tracks if there aren't enough after the current track
		my $numRandomTracks = $prefs->get('newtracks');

		if (!$addOnly) {

			$numItems = $numRandomTracks;

		} elsif ($songsRemaining < $numRandomTracks) {

			$numItems = $numRandomTracks - $songsRemaining;

		} else {

			main::DEBUGLOG && $log->debug("$songsRemaining items remaining so not adding new track");
		}

	} elsif ($type ne 'disable' && ($type ne $client->pluginData('type') || !$addOnly || $songsRemaining <= 0)) {

		# Old artist/album/year is finished or new random mix started.  Add a new one
		$numItems = 1;
	}

	if ($numItems) {

		# String to show with showBriefly
		my $string = '';

		if ($type ne 'track') {
			$string = $client->string('PLUGIN_RANDOM_' . uc($type) . '_ITEM') . ': ';
		}

		# If not track mode, add tracks then go round again to check whether the playlist only
		# contains one track (i.e. the artist/album/year only had one track in it).  If so,
		# add another artist/album/year or the plugin would never add more when the first finished in continuous mode.
		for (my $i = 0; $i < 2; $i++) {

			if ($i == 0 || ($type =~ /track|year/ && Slim::Player::Playlist::count($client) == 1 && $continuousMode)) {

				if ($i == 1) {
					$string .= ' // ';
				}

				# Get the tracks.  year is a special case as we do a find for all tracks that match
				# the previously selected year
				findAndAdd($client,
				    $type,
				    $numItems,
					# 2nd time round just add tracks to end
					$i == 0 ? $addOnly : 1
				);
			}
		}

		# Do a show briefly the first time things are added, or every time a new album/artist/year is added
		if (!$addOnly || $type ne $client->pluginData('type') || $type !~ /track|year/) {

			if ($type eq 'track') {
				$string = $client->string("PLUGIN_RANDOM_TRACK");
			}

			# Don't do showBrieflys if visualiser screensavers are running as the display messes up
			if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {

				$client->showBriefly( {
					jive   => undef,
					'line' => [ string($addOnly ? 'ADDING_TO_PLAYLIST' : 'NOW_PLAYING'), $string ]
				}, 2, undef, undef, 1);
			}
		}

		# Never show random as modified, since its a living playlist
		$client->currentPlaylistModified(0);
	}

	if ($type eq 'disable') {

		main::INFOLOG && $log->info("Cyclic mode ended");

		# Don't do showBrieflys if visualiser screensavers are running as
		# the display messes up
		if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./ && !$client->pluginData('disableMix')) {

			$client->showBriefly( {
				jive => string('PLUGIN_RANDOM_DISABLED'),
				'line' => [ string('PLUGIN_RANDOMPLAY'), string('PLUGIN_RANDOM_DISABLED') ]
			} );

		}

		$client->pluginData('disableMix', 0);
		$client->pluginData('type', '');

	} else {

		if ( main::INFOLOG && $log->is_info ) {
			$log->info(sprintf(
				"Playing %s %s mode with %i items",
				$continuousMode ? 'continuous' : 'static', $type, Slim::Player::Playlist::count($client)
			));
		}

		#BUG 5444: store the status so that users re-visiting the random mix
		#          will see a continuous mode state.
		if ($continuousMode) {
			$client->pluginData('type', $type);
		}
	}
}

1;