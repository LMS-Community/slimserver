package Slim::Control::Queries;

# $Id: Command.pm 5121 2005-11-09 17:07:36Z dsully $
#
# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;

use Slim::Utils::Misc;

use Slim::Control::Request;


our %searchMap = (

	'artist' => 'contributor.namesearch',
	'genre'  => 'genre.namesearch',
	'album'  => 'album.titlesearch',
	'track'  => 'track.titlesearch',
);


sub alarmsQuery {
	my $request = shift;

	$d_queries && msg("alarmsQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['alarms']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client   = $request->client();
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');
	my $filter	 = $request->getParam('filter');
	my $alarmDOW = $request->getParam('dow');
	
	
	if ($request->paramNotOneOfIfDefined($filter, ['all', 'defined', 'enabled'])) {
		$request->setStatusBadParams();
		return;
	}
	
	my @results;

	if (defined $alarmDOW) {

		$results[0] = Slim::Utils::Alarms->newLoaded($client, $alarmDOW);

	} else {

		my $i = 0;
		$filter = 'enabled' if !defined $filter;
		for $alarmDOW (0..7) {
			my $alarm = Slim::Utils::Alarms->newLoaded($client, $alarmDOW);
			
			my $wanted = 	( 
								($filter eq 'all') ||
								($filter eq 'defined' && !$alarm->undefined()) ||
								($filter eq 'enabled' && $alarm->enabled())
							);
			$results[$i++] = $alarm if $wanted;
		}
	}

	my $count = scalar @results;

	$request->addResult('fade', $client->prefGet('alarmfadeseconds'));
	$request->addResult('count', $count);

	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

	if ($valid) {

		my $loopname = '@alarms';
		my $cnt = 0;
		
		for my $eachitem (@results[$start..$end]) {
			$request->addResultLoop($loopname, $cnt, 'dow', $eachitem->dow());
			$request->addResultLoop($loopname, $cnt, 'enabled', $eachitem->enabled());
			$request->addResultLoop($loopname, $cnt, 'time', $eachitem->time());
			$request->addResultLoop($loopname, $cnt, 'volume', $eachitem->volume());
			$request->addResultLoop($loopname, $cnt, 'url', $eachitem->playlist());
			$request->addResultLoop($loopname, $cnt, 'playlist_id', $eachitem->playlistid());
			$cnt++;
		}
	}

	$request->setStatusDone();
}

sub browseXQuery {
	my $request = shift;

	$d_queries && msg("browseXQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['artists', 'albums', 'genres']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $label    = $request->getRequest(0);
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');
	my $search   = $request->getParam('search');
	my $genreID  = $request->getParam('genre_id');
	my $artistID = $request->getParam('artist_id');
	my $albumID  = $request->getParam('album_id');
	my $find     = {};

	chop($label);

	# Normalize any search parameters
	if (defined $searchMap{$label} && specified($search)) {

		$find->{ $searchMap{$label} } = Slim::Web::Pages::Search::searchStringSplit($search);
	}

	if (defined $genreID){

		$find->{'genre'} = $genreID;
	}

	if (defined $artistID){
		$find->{'artist'} = $artistID;
	}

	if (defined $albumID){
		$find->{'album'} = $albumID;
	}

	if ($label eq 'artist') {

		# The user may not want to include all the composers/conductors
		if (my $roles = Slim::Schema->artistOnlyRoles) {

			$find->{'contributor.role'} = $roles;
		}
	}

	if (Slim::Music::Import->stillScanning()) {
		$request->addResult('rescan', 1);
	}

	# XXXX - need to convert to Schema
	# Who calls this?
	my $results = Slim::Schema->search($label, {
		'find'   => $find,
		'sortBy' => $label,
#		'limit'  => $cmdRef->{'_p2'},
#		'offset' => $cmdRef->{'_p1'},
	});

	my $count = scalar @$results;

	$request->addResult('count', $count);

	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

	if ($valid) {

		my $loopname = '@' . $label . 's';
		my $cnt = 0;

		for my $eachitem (@$results[$start..$end]) {
			$request->addResultLoop($loopname, $cnt, 'id', $eachitem->id);
			$request->addResultLoop($loopname, $cnt, $label, $eachitem);
			$cnt++;
		}
	}

	$request->setStatusDone();
}

sub cursonginfoQuery {
	my $request = shift;
	
	$d_queries && msg("cursonginfoQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['duration', 'artist', 'album', 'title', 'genre', 'path']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $client = $request->client();

	# get the query
	my $method = $request->getRequest(0);
	my $url = Slim::Player::Playlist::song($client);
	
	if (defined $url) {

		if ($method eq 'path') {
			
			$request->addResult("_$method", $url);

		} else {

			my $track = Slim::Schema->objectForUrl($url);

			if (!blessed($track) || !$track->can('secs')) {

				errorMsg("cursonginfoQuery: Couldn't fetch object for URL: [$url] - skipping track\n");
				bt();

			} else {

				if ($method eq 'duration') {

					$request->addResult("_$method", $track->secs() || 0);

				} else {

					$request->addResult("_$method", $track->$method() || 0);
				}
			}
		}
	}

	$request->setStatusDone();
}


sub connectedQuery {
	my $request = shift;
	
	$d_queries && msg("connectedQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['connected']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $client = $request->client();
	
	$request->addResult('_connected', $client->connected() || 0);
	
	$request->setStatusDone();
}


sub debugQuery {
	my $request = shift;
	
	$d_queries && msg("debugQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['debug']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $debugFlag = $request->getParam('_debugflag');
	
	if ( !defined $debugFlag || !($debugFlag =~ /^d_/) ) {
		$request->setStatusBadParams();
		return;
	}
	
	$debugFlag = "::" . $debugFlag;
	no strict 'refs';
	
	my $isValue = $$debugFlag;
	$isValue ||= 0;
	
	$request->addResult('_value', $isValue);
	
	$request->setStatusDone();
}


sub displayQuery {
	my $request = shift;
	
	$d_queries && msg("displayQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['display']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $client = $request->client();
	
	my $parsed = $client->parseLines(Slim::Display::Display::curLines($client));

	$request->addResult('_line1', $parsed->{line1} || '');
	$request->addResult('_line2', $parsed->{line2} || '');
		
	$request->setStatusDone();
}


sub displaynowQuery {
	my $request = shift;
	
	$d_queries && msg("displaynowQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['displaynow']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $client = $request->client();

	$request->addResult('_line1', $client->prevline1());
	$request->addResult('_line2', $client->prevline2());
		
	$request->setStatusDone();
}


sub infoTotalQuery {
	my $request = shift;
	
	$d_queries && msg("infoTotalQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['info'], ['total'], ['genres', 'artists', 'albums', 'songs']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $entity = $request->getRequest(2);

	if ($entity eq 'albums') {
		$request->addResult("_$entity", Slim::Schema->count('Album'));
	}

	if ($entity eq 'artists') {
		$request->addResult("_$entity", Slim::Schema->count('Contributor'));
	}

	if ($entity eq 'genres') {
		$request->addResult("_$entity", Slim::Schema->count('Genre'));
	}

	if ($entity eq 'songs') {
		$request->addResult("_$entity", Slim::Schema->count('Track'));
	}
	
	$request->setStatusDone();
}


sub linesperscreenQuery {
	my $request = shift;
	
	$d_queries && msg("linesperscreenQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['linesperscreen']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $client = $request->client();

	$request->addResult('_linesperscreen', $client->linesPerScreen());
	
	$request->setStatusDone();
}


sub mixerQuery {
	my $request = shift;
	
	$d_queries && msg("mixerQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['mixer'], ['volume', 'muting', 'treble', 'bass', 'pitch']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client = $request->client();
	my $entity = $request->getRequest(1);

	if ($entity eq 'muting') {
		$request->addResult("_$entity", $client->prefGet("mute"));
	}
	elsif ($entity eq 'volume') {
		$request->addResult("_$entity", $client->prefGet("volume"));
	} else {
		$request->addResult("_$entity", $client->$entity());
	}
	
	$request->setStatusDone();
}


sub modeQuery {
	my $request = shift;
	
	$d_queries && msg("modeQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['mode']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $client = $request->client();

	$request->addResult('_mode', Slim::Player::Source::playmode($client));
	
	$request->setStatusDone();
}


sub playerXQuery {
	my $request = shift;

	$d_queries && msg("playerXQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['player'], ['count', 'name', 'address', 'ip', 'id', 'model', 'displaytype']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $entity      = $request->getRequest(1);
	my $clientparam = $request->getParam('_IDorIndex');
	
	if ($entity eq 'count') {
		$request->addResult("_$entity", Slim::Player::Client::clientCount());

	} else {	
		my $client;
		
		# were we passed an ID?
		if (defined $clientparam && Slim::Player::Client::getClient($clientparam)) {

			$client = Slim::Player::Client::getClient($clientparam);

		} else {
		
			# otherwise, try for an index
			my @clients = Slim::Player::Client::clients();

			if (defined $clientparam && defined $clients[$clientparam]) {
				$client = $clients[$clientparam];
			}
		}
		
		if (defined $client) {

			if ($entity eq "name") {
				$request->addResult("_$entity", $client->name());
			} elsif ($entity eq "address" || $entity eq "id") {
				$request->addResult("_$entity", $client->id());
			} elsif ($entity eq "ip") {
				$request->addResult("_$entity", $client->ipport());
			} elsif ($entity eq "model") {
				$request->addResult("_$entity", $client->model());
			} elsif ($entity eq "displaytype") {
				$request->addResult("_$entity", $client->vfdmodel());
			}
		}
	}
	
	$request->setStatusDone();
}


sub playersQuery {
	my $request = shift;

	$d_queries && msg("playersQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['players']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');
	
	my $count = Slim::Player::Client::clientCount();
	$request->addResult('count', $count);

	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

	if ($valid) {
		my $idx = $start;
		my $cnt = 0;
		my @players = Slim::Player::Client::clients();

		if (scalar(@players) > 0) {

			for my $eachclient (@players[$start..$end]) {
				$request->addResultLoop('@players', $cnt, 
					'playerindex', $idx);
				$request->addResultLoop('@players', $cnt, 
					'playerid', $eachclient->id());
				$request->addResultLoop('@players', $cnt, 
					'ip', $eachclient->ipport());
				$request->addResultLoop('@players', $cnt, 
					'name', $eachclient->name());
				$request->addResultLoop('@players', $cnt, 
					'model', $eachclient->model());
				$request->addResultLoop('@players', $cnt, 
					'displaytype', $eachclient->vfdmodel())
					unless ($eachclient->model() eq 'http');
				$request->addResultLoop('@players', $cnt, 
					'connected', ($eachclient->connected() || 0));
					
				$idx++;
				$cnt++;
			}	
		}
	}
	
	$request->setStatusDone();
}


sub playlistXQuery {
	my $request = shift;
	
	$d_queries && msg("playlistXQuery()\n");

	# check this is the correct query
	if ($request->isNotQuery([['playlist'], ['name', 'url', 'modified', 
			'tracks', 'duration', 'artist', 'album', 'title', 'genre', 'path', 
			'repeat', 'shuffle', 'index', 'jump']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $client = $request->client();
	my $entity = $request->getRequest(1);
	my $index  = $request->getParam('_index');
		
	if ($entity eq 'repeat') {
		$request->addResult("_$entity", Slim::Player::Playlist::repeat($client));

	} elsif ($entity eq 'shuffle') {
		$request->addResult("_$entity", Slim::Player::Playlist::shuffle($client));

	} elsif ($entity eq 'index' || $entity eq 'jump') {
		$request->addResult("_$entity", Slim::Player::Source::playingSongIndex($client));

	} elsif ($entity eq 'name' && defined(my $playlistObj = $client->currentPlaylist())) {
		$request->addResult("_$entity", Slim::Music::Info::standardTitle($client, $playlistObj));

	} elsif ($entity eq 'url') {
		$request->addResult("_$entity", $client->currentPlaylist());

	} elsif ($entity eq 'modified') {
		$request->addResult("_$entity", $client->currentPlaylistModified());

	} elsif ($entity eq 'tracks') {
		$request->addResult("_$entity", Slim::Player::Playlist::count($client));

	} elsif ($entity eq 'path') {
		$request->addResult("_$entity", Slim::Player::Playlist::song($client, $index) || 0);

	} elsif ($entity =~ /(duration|artist|album|title|genre)/) {

		my $track = Slim::Schema->objectForUrl({
			'url'      => Slim::Player::Playlist::song($client, $index),
			'create'   => 1,
			'readTags' => 1,
		});

		if (blessed($track) && $track->can('secs')) {

			# Just call the method on Track
			if ($entity eq 'duration') {
				$request->addResult("_$entity", $track->secs());
			}
			else {
				$request->addResult("_$entity", $track->$entity());
			}
		}
	}
	
	$request->setStatusDone();
}


sub playlisttracksQuery {
	my $request = shift;

	$d_queries && msg("playlisttracksQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['playlisttracks']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $tags       = 'gald';
	my $index      = $request->getParam('_index');
	my $quantity   = $request->getParam('_quantity');
	my $tagsprm    = $request->getParam('tags');
	my $playlistID = $request->getParam('playlist_id');

	if (!defined $playlistID) {
		$request->setStatusBadParams();
		return;
	}

	# did we have override on the defaults?
	$tags = $tagsprm if defined $tagsprm;

	my $iterator;
	my @tracks;

	if (Slim::Music::Import->stillScanning()) {
		$request->addResult("rescan", 1);
	}

	my $playlistObj = Slim::Schema->find('Playlist', $playlistID);

	if (blessed($playlistObj) && $playlistObj->can('tracks')) {
		$iterator = $playlistObj->tracks();
	}

	if (defined $iterator) {

		my $count = $iterator->count();

		$request->addResult("count", $count);
		
		my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

		my $cur = $start;
		my $cnt = 0;

		if ($valid) {

			for my $eachitem ($iterator->slice($start, $end)) {

				_addSong($request, '@playlisttracks', $cnt, $eachitem, $tags, 
						"playlist index", $cur);

				$cur++;
				$cnt++;
			}
		}

	} else {

		$request->addResult("count", 0);
	}

	$request->setStatusDone();	
}


sub playlistsQuery {
	my $request = shift;

	$d_queries && msg("playlistsQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['playlists']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');
	my $search	 = $request->getParam('search');
	my $tags     = $request->getParam('tags') || '';

	# Normalize any search parameters
	if (defined $search) {
		$search = Slim::Web::Pages::Search::searchStringSplit($search);
	}

	if (Slim::Music::Import->stillScanning()) {
		$request->addResult("rescan", 1);
	}

	my $rs = Slim::Schema->rs('Playlist')->getPlaylists('all', $search);

	if (defined $rs) {

		my $numitems = $rs->count;
		
		$request->addResult("count", $numitems);
		
		my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $numitems);

		if ($valid) {
			my $cnt = 0;

			for my $eachitem ($rs->slice($start, $end)) {

				$request->addResultLoop('@playlists', $cnt, "id", $eachitem->id);
				$request->addResultLoop('@playlists', $cnt, "playlist", Slim::Music::Info::standardTitle(undef, $eachitem));
				$request->addResultLoop('@playlists', $cnt, "url", $eachitem->url) if ($tags =~ /u/);

				$cnt++;
			}
		}
	} 
	
	$request->setStatusDone();
}


sub playerprefQuery {
	my $request = shift;
	
	$d_queries && msg("playerprefQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['playerpref']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $client   = $request->client();
	my $prefName = $request->getParam('_prefname');
	
	if (!defined $prefName) {
		$request->setStatusBadParams();
		return;
	}

	$request->addResult('_p2', $client->prefGet($prefName));
	
	$request->setStatusDone();
}


sub powerQuery {
	my $request = shift;
	
	$d_queries && msg("powerQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['power']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $client = $request->client();

	$request->addResult('_power', $client->power());
	
	$request->setStatusDone();
}


sub prefQuery {
	my $request = shift;
	
	# check this is the correct command. Syntax approved by Dean himself!
	if ($request->isNotQuery(['pref'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# use positional parameters as backups
	my $prefName = $request->getParam('prefName') || $request->getParam('_p1');
	
	if (!defined $prefName) {
		$request->setStatusBadParams();
		return;
	}

	my $isValue = Slim::Utils::Prefs::get($prefName);
	
	$request->addResult('isValue', $isValue);
	
	$request->setStatusDone();
}

sub rescanQuery {
	my $request = shift;
	
	if ($request->isNotQuery(['rescan'])) {
		$request->setStatusBadDispatch();
		return;
	}

	# no params for the rescan query

	$request->addResult('_rescan', Slim::Music::Import->stillScanning() ? 1 : 0);
	
	$request->addResult('isValue', $isValue);
	
	$request->setStatusDone();
}

sub versionQuery {
	my $request = shift;
	
	if ($request->isNotQuery(['version'])) {
		$request->setStatusBadDispatch();
		return;
	}

	# no params for the version query

	my $isValue = $::VERSION;
	
	$request->addResult('isValue', $isValue);
	
	$request->setStatusDone();
}

sub debugQuery {
	my $request = shift;
	
	# check this is the correct command. Syntax approved by Dean himself!
	if ($request->isNotQuery(['debug'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# use positional parameters as backups
	my $debugFlag = $request->getParam('debugFlag') || $request->getParam('_p1');
	
	my $SP3  = ($client->model() eq 'slimp3');
	my $SQ   = ($client->model() eq 'softsqueeze');
	my $SB   = ($client->model() eq 'squeezebox');
	my $SB2  = ($client->model() eq 'squeezebox2');
	my $RSC  = ($client->model() eq 'http');
	
	my $connected = $client->connected() || 0;
	my $power     = $client->power();
	my $repeat    = Slim::Player::Playlist::repeat($client);
	my $shuffle   = Slim::Player::Playlist::shuffle($client);
	my $songCount = Slim::Player::Playlist::count($client);
	my $idx = 0;
		
	if (Slim::Music::Import->stillScanning()) {
		$request->addResult('rescan', "1");
	}
	
	# add player info...
	$request->addResult("player_name", $client->name());
	$request->addResult("player_connected", $connected);
	
	if (!$RSC) {
		$request->addResult("power", $power);
	}
	
	if ($SB || $SB2) {
		$request->addResult("signalstrength", ($client->signalStrength() || 0));
	}
	
	# this will be true for http class players
	if ($power) {
	
		$request->addResult('mode', Slim::Player::Source::playmode($client));

		if (my $song = Slim::Player::Playlist::song($client)) {

			$request->addResult('rate', 
				Slim::Player::Source::rate($client));
			$request->addResult('current_title', 
				Slim::Music::Info::getCurrentTitle($client, $song));
			$request->addResult('time', 
				Slim::Player::Source::songTime($client));
			
			my $track = Slim::Schema->objectForUrl($song);

			my $dur   = 0;

			if (blessed($track) && $track->can('secs')) {

				$dur = $track->secs;
			}

			if ($dur) {
				$request->addResult('duration', $dur);
			}
		}
		
		if ($client->currentSleepTime()) {

			my $sleep = $client->sleepTime() - Time::HiRes::time();
			$request->addResult('sleep', $client->currentSleepTime() * 60);
			$request->addResult('will_sleep_in', ($sleep < 0 ? 0 : $sleep));
		}
		
		if (Slim::Player::Sync::isSynced($client)) {

			my $master = Slim::Player::Sync::masterOrSelf($client);

			$request->addResult('sync_master', $master->id());

			my @slaves = Slim::Player::Sync::slaves($master);
			my @sync_slaves = map { $_->id } @slaves;

			$request->addResult('sync_slaves', join(",", @sync_slaves));
		}
	
		if (!$RSC) {
			# undefined for remote streams
			$request->addResult("mixer volume", $client->prefGet("volume"));
		}
		
		if ($SB || $SP3) {
			$request->addResult("mixer treble", $client->treble());
			$request->addResult("mixer bass", $client->bass());
		}

		if ($SB) {
			$request->addResult("mixer pitch", $client->pitch());
		}

		$request->addResult("playlist repeat", $repeat); 
		$request->addResult("playlist shuffle", $shuffle); 
	
		if ($songCount > 0) {
			$idx = Slim::Player::Source::playingSongIndex($client);
			$request->addResult("playlist_cur_index", $idx);
		}

		$request->addResult("playlist_tracks", $songCount);
	}
	
	if ($songCount > 0 && $power) {
	
		# get the other parameters
		my $tags     = $request->getParam('tags');
		my $index    = $request->getParam('_index');
		my $quantity = $request->getParam('_quantity');
	
		$tags = 'gald' if !defined $tags;
		my $loop = '@playlist';

		# we can return playlist data.
		# which mode are we in?
		my $modecurrent = 0;

		if (defined($index) && ($index eq "-")) {
			$modecurrent = 1;
		}
		
		# if repeat is 1 (song) and modecurrent, then show the current song
		if ($modecurrent && ($repeat == 1) && $quantity) {

			_addSong($request, $loop, 0, 
				Slim::Player::Playlist::song($client, $idx), $tags,
				'playlist index', $idx
			);

		} else {

			my ($valid, $start, $end);
			
			if ($modecurrent) {
				($valid, $start, $end) = $request->normalize($idx, scalar($quantity), $songCount);
			} else {
				($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $songCount);
			}

			if ($valid) {
				my $count = 0;

				for ($idx = $start; $idx <= $end; $idx++){
					_addSong(	$request, $loop, $count, 
								Slim::Player::Playlist::song($client, $idx), $tags,
								'playlist index', $idx
							);
					$count++;
					::idleStreams() ;
				}
				
				my $repShuffle = Slim::Utils::Prefs::get('reshuffleOnRepeat');
				my $canPredictFuture = ($repeat == 2)  			# we're repeating all
										&& 						# and
										(	($shuffle == 0)		# either we're not shuffling
											||					# or
											(!$repShuffle));	# we don't reshuffle
				
				if ($modecurrent && $canPredictFuture && ($count < scalar($quantity))) {

					# wrap around the playlist...
					($valid, $start, $end) = $request->normalize(0, (scalar($quantity) - $count), $songCount);		

					if ($valid) {

						for ($idx = $start; $idx <= $end; $idx++){

							_addSong($request, $loop, $count, 
								Slim::Player::Playlist::song($client, $idx), $tags,
								'playlist index', $idx
							);

							$count++;
							::idleStreams() ;
						}
					}
				}
			}
		}
	}
	
	$request->setStatusDone();
}


sub songinfoQuery {
	my $request = shift;

	$d_queries && msg("songinfoQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['songinfo']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $tags  = 'abcdefghijklmnopqrstvwyz'; # all letter EXCEPT u AND x
	my $track;

	if (Slim::Music::Import->stillScanning()) {
		$request->addResult("rescan", 1);
	}

	# get our parameters
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');
	my $url	     = $request->getParam('url');
	my $trackID  = $request->getParam('track_id');
	my $tagsprm  = $request->getParam('tags');

	if (!defined $trackID && !defined $url) {
		$request->setStatusBadParams();
		return;
	}

	# did we have override on the defaults?
	$tags = $tagsprm if defined $tagsprm;

	# find the track
	if (defined $trackID){

		if ($tags !~ /u/) {
			$tags .= 'u';
		}

		$track = Slim::Schema->find('Track', $trackID);

	} else {

		if (defined $url && Slim::Music::Info::isSong($url)){

			if ($tags !~ /x/) {
				$tags .= 'x';
			}

			$track = Slim::Schema->objectForUrl($url)
		}
	}
	
	if (blessed($track) && $track->can('id')) {

		my $hashRef = _songData($track, $tags);
		my $count = scalar (keys %{$hashRef});

		$request->addResult("count", $count);

		my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

		if ($valid) {
			my $idx = 0;

			while (my ($key, $val) = each %{$hashRef}) {

				if ($idx >= $start && $idx <= $end) {
					$request->addResult($key, $val);
				}

				$idx++;
 			}
		}
	}

	$request->setStatusDone();
}


sub syncQuery {
	my $request = shift;
	
	my $isValue = $$debugFlag;
	$isValue ||= 0;
	
	$request->addResult('isValue', $isValue);
	
	$request->setStatusDone();
}

sub timeQuery {
	my $request = shift;
	
	$d_queries && msg("timeQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['time', 'gototime']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $client = $request->client();

	$request->addResult('_time', Slim::Player::Source::songTime($client));
	
	$request->setStatusDone();
}

sub titlesQuery {
	my $request = shift;

	$d_queries && msg("titlesQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['titles', 'tracks', 'songs']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $find  = {};
	my $label = 'track';
	my $sort  = 'title';
	my $tags  = 'gald';

	# get our parameters
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');
	my $tagsprm  = $request->getParam('tags');
	my $sortprm  = $request->getParam('sort');
	my $search   = $request->getParam('search');
	my $genreID  = $request->getParam('genre_id');
	my $artistID = $request->getParam('artist_id');
	my $albumID  = $request->getParam('album_id');

	# did we have override on the defaults?
	# note that this is not equivalent to 
	# $val = $param || $default;
	# since when $default eq '' -> $val eq $param
	$sort = $sortprm if defined $sortprm;
	$tags = $tagsprm if defined $tagsprm;

	# Normalize any search parameters
	if (defined $searchMap{$label} && specified($search)) {
		$find->{ $searchMap{$label} } = Slim::Web::Pages::Search::searchStringSplit($search);
	}

	if (defined $genreID){
		$find->{'genre'} = $genreID;
	}

	if (defined $artistID){
		$find->{'artist'} = $artistID;
	}

	if (defined $albumID){
		$find->{'album'} = $albumID;
	}

	if ($sort eq "tracknum" && !($tags =~ /t/)) {
		$tags = $tags . "t";
	}

	if (Slim::Music::Import->stillScanning()) {
		$request->addResult("rescan", 1);
	}

	# XXXX - need to convert to schema!
	# Who calls this?
	my $results = Slim::Schema->search($label, {
		'find'   => $find,
		'sortBy' => $sort,
#		'limit'  => $cmdRef->{'_p2'},
#		'offset' => $cmdRef->{'_p1'},
	});
	
	my $count = scalar @$results;

	$request->addResult("count", $count);

	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

	if ($valid) {
		
		my $cnt = 0;
	
		for my $item (@$results[$start..$end]) {

			_addSong($request, '@titles', $cnt++, $item, $tags);

			::idleStreams();
		}
	}

	$request->setStatusDone();
}


sub versionQuery {
	my $request = shift;
	
	$d_queries && msg("versionQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['version']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# no params for the version query

	$request->addResult('_version', $::VERSION);
	
	$request->setStatusDone();
}

################################################################################
# Helper functions
################################################################################

sub _addSong {
	my $request   = shift; # request
	my $loop      = shift; # loop
	my $index     = shift; # loop index
	my $pathOrObj = shift; # song path or object
	my $tags      = shift; # tags to use
	my $prefixKey = shift; # prefix key, if any
	my $prefixVal = shift; # prefix value, if any   

	# get the hash with the data	
	my $hashRef = _songData($pathOrObj, $tags);
	
	# add the prefix in the first position, use a fancy feature of
	# Tie::LLHash
	if (defined $prefixKey) {
		(tied %{$hashRef})->first($prefixKey => $prefixVal);
	}
	
	# add it directly to the result loop
	$request->setResultLoopHash($loop, $index, $hashRef);
}


sub _songData {
	my $pathOrObj = shift; # song path or object
	my $tags      = shift; # tags to use

	my $track     = Slim::Schema->objectForUrl($pathOrObj);

#	msg("REMOTE STREAM\n") if Slim::Music::Info::isRemoteURL($pathOrObj);

	if (!blessed($track) || !$track->can('id')) {

		errorMsg("Queries::_songData called with invalid object or path: $pathOrObj!\n");
		
		# For some reason, $pathOrObj may be an id... try that before giving up...
		if ($pathOrObj =~ /^\d+$/) {
			$track = Slim::Schema->find('Track', $pathOrObj);
		}

		if (!blessed($track) || !$track->can('id')) {

			errorMsg("Queries::_songData cannot make track from: $pathOrObj!\n");
			return;
		}
	}
	
	# define an ordered hash for our results
	tie (my %returnHash, "Tie::LLHash", {lazy => 1});

	# add fields present no matter $tags
	$returnHash{'id'}    = $track->id;
	$returnHash{'title'} = $track->title;

	# Allocation map: capital letters are still free:
	#  a b c d e f g h i j k l m n o p q r s t u v X y z

	my %tag2fieldMap = (
		'g' => 'genre',
		'a' => 'artist',
		'l' => 'album',
		't' => 'tracknum',
		'y' => 'year',
		'm' => 'bpm',
		'k' => 'comment',
		'v' => 'tagversion',
		'r' => 'bitrate',
		'z' => 'drm',
		'n' => 'modificationTime',
		'u' => 'url',
		'f' => 'filesize',
# special cased		
#		'c' => 'composer',
#		'b' => 'band',
#		'h' => 'conductor',
# 		'd' => 'duration',
# 		'i' => 'disc',
# 		'j' => 'Cover art',
# 		'o' => 'type',
# 		'q' => 'disc count',
# 		'e' => 'album_id',
# 		'p' => 'genre_id',
# 		's' => 'artist_id',
	);
	
	for my $tag (split //, $tags) {

		if (my $method = $tag2fieldMap{$tag}) {

			my $value = $track->$method();

			if (defined $value && $value !~ /^\s*$/) {

				$returnHash{$method} = $value;
			}

			next;
		}

		if ($tag eq 'b' && (my @bands = $track->band)) {
			$returnHash{'band'} = $bands[0];
			next;
		}

		if ($tag eq 'c' && (my @composers = $track->composer)) {
			$returnHash{'composer'} = $composers[0];
			next;
		}

		if ($tag eq 'd' && defined(my $duration = $track->secs)) {
			$returnHash{'duration'} = $duration;
			next;
		}

		if ($tag eq 'h' && (my @conductors = $track->conductor)) {
			$returnHash{'conductor'} = $conductors[0];
			next;
		}

		if ($tag eq 'i' && defined(my $disc = $track->disc)) {
			$returnHash{'disc'} = $disc;
			next;
		}

		if ($tag eq 'j' && $track->coverArt) {
			$returnHash{'coverart'} = 1;
			next;
		}

		if ($tag eq 'o' && defined(my $ct = $track->content_type)) {
			$returnHash{'type'} = Slim::Utils::Strings::string(uc($ct));
			next;
		}

		if ($tag eq 'p' && defined(my $genre = $track->genre)) {
			if (defined(my $id = $genre->id)) {
				$returnHash{'genre_id'} = $id;
				next;
			}
		}

		if ($tag eq 's' && defined(my $artist = $track->artist)) {

			$returnHash{'artist_id'} = $artist->id;
			next;
		}

		if (defined(my $album = $track->album)) {

			if ($tag eq 'e') {
				$returnHash{'album_id'} = $album->id;
				next;
			}

			if ($tag eq 'q' && defined(my $discc = $album->discc)) {
				$returnHash{'disccount'} = $discc unless $discc eq '';
				next;
			}
		}
	}

	return \%returnHash;
}

1;
