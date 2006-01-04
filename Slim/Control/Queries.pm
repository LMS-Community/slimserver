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

use Scalar::Util qw(blessed);

use Slim::Control::Request;
use Slim::Music::Import;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

sub cursonginfoQuery {
	my $request = shift;
	
	$::d_command && msg("cursonginfoQuery()\n");

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
			
			my $ds = Slim::Music::Info::getCurrentDataStore();
			my $track  = $ds->objectForUrl(Slim::Player::Playlist::song($client));
			
			if (!blessed($track) || !$track->can('secs')) {
				msg("Couldn't fetch object for URL: [$url] - skipping track\n");
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
	
	$::d_command && msg("connectedQuery()\n");

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
	
	$::d_command && msg("debugQuery()\n");

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
	
	$::d_command && msg("displayQuery()\n");

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
	
	$::d_command && msg("displaynowQuery()\n");

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
	
	$::d_command && msg("infoTotalQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['info'], ['total'], ['genres', 'artists', 'albums', 'songs']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $entity = $request->getRequest(2);
	my $ds = Slim::Music::Info::getCurrentDataStore();
	
	if ($entity eq 'albums') {
		$request->addResult("_$entity", $ds->count('album'));
	}
	if ($entity eq 'artists') {
		$request->addResult("_$entity", $ds->count('contributor'));
	}
	if ($entity eq 'genres') {
		$request->addResult("_$entity", $ds->count('genre'));
	}
	if ($entity eq 'songs') {
		$request->addResult("_$entity", $ds->count('track'));
	}			
	
	$request->setStatusDone();
}

sub linesperscreenQuery {
	my $request = shift;
	
	$::d_command && msg("linesperscreenQuery()\n");

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
	
	$::d_command && msg("mixerQuery()\n");

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
	} else {
		$request->addResult("_$entity", $client->$entity());
	}
	
	$request->setStatusDone();
}

sub modeQuery {
	my $request = shift;
	
	$::d_command && msg("modeQuery()\n");

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

sub playlistinfoQuery {
	my $request = shift;
	
	$::d_command && msg("playlistinfoQuery()\n");

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
	}
	if ($entity eq 'shuffle') {
		$request->addResult("_$entity", Slim::Player::Playlist::shuffle($client));
	}
	if ($entity eq 'index' || $entity eq 'jump') {
		$request->addResult("_$entity", Slim::Player::Source::playingSongIndex($client));
	}
	if ($entity eq 'name') {
		$request->addResult("_$entity", Slim::Music::Info::standardTitle($client, $client->currentPlaylist()));
	}
	if ($entity eq 'url') {
		$request->addResult("_$entity", $client->currentPlaylist());
	}
	if ($entity eq 'modified') {
		$request->addResult("_$entity", $client->currentPlaylistModified());
	}
	if ($entity eq 'tracks') {
		$request->addResult("_$entity", Slim::Player::Playlist::count($client));
	}
	if ($entity eq 'path') {
		$request->addResult("_$entity", Slim::Player::Playlist::song($client, $index) || 0);
	}
	if ($entity =~ /(duration|artist|album|title|genre)/) {

		my $ds = Slim::Music::Info::getCurrentDataStore();
		my $url = Slim::Player::Playlist::song($client, $index);
		my $obj = $ds->objectForUrl($url, 1, 1);

		if (blessed($obj) && $obj->can('secs')) {

			# Just call the method on Track
			if ($entity eq 'duration') {
				$request->addResult("_$entity", $obj->secs());
			}
			else {
				$request->addResult("_$entity", $obj->$entity());
			}
		}
	}
	
	$request->setStatusDone();
}

sub playerprefQuery {
	my $request = shift;
	
	$::d_command && msg("playerprefQuery()\n");

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
	
	$::d_command && msg("powerQuery()\n");

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
	
	$::d_command && msg("prefQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['pref']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $prefName = $request->getParam('_prefname');
	
	if (!defined $prefName) {
		$request->setStatusBadParams();
		return;
	}

	$request->addResult('_p2', Slim::Utils::Prefs::get($prefName));
	
	$request->setStatusDone();
}

sub rateQuery {
	my $request = shift;
	
	$::d_command && msg("rateQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['rate']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $client = $request->client();

	$request->addResult('_rate', Slim::Player::Source::rate($client));
	
	$request->setStatusDone();
}

sub rescanQuery {
	my $request = shift;
	
	$::d_command && msg("rescanQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['rescan']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# no params for the rescan query

	$request->addResult('_rescan', Slim::Music::Import::stillScanning() ? 1 : 0);
	
	$request->setStatusDone();
}

sub signalstrengthQuery {
	my $request = shift;
	
	$::d_command && msg("signalstrengthQuery()\n");

	# check this is the correct query.
	if ($request->isNotQuery([['signalstrength']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $client = $request->client();

	$request->addResult('_signalstrength', $client->signalStrength() || 0);
	
	$request->setStatusDone();
}

sub sleepQuery {
	my $request = shift;
	
	$::d_command && msg("sleepQuery()\n");

	# check this is the correct query
	if ($request->isNotQuery([['sleep']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $client = $request->client();

	my $isValue = $client->sleepTime() - Time::HiRes::time();
	if ($isValue < 0) {
		$isValue = 0;
	}
	
	$request->addResult('_sleep', $isValue);
	
	$request->setStatusDone();
}

sub statusQuery {
	my $request = shift;
	
	$::d_command && msg("statusQuery()\n");

	# check this is the correct query
	if ($request->isNotQuery([['status']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the initial parameters
	my $client = $request->client();
	
	my $ds = Slim::Music::Info::getCurrentDataStore();
	
	my $connected = $client->connected() || 0;
	my $power     = $client->power();
	my $repeat    = Slim::Player::Playlist::repeat($client);
	my $shuffle   = Slim::Player::Playlist::shuffle($client);
	my $songCount = Slim::Player::Playlist::count($client);
	my $idx = 0;
		
	if (Slim::Music::Import::stillScanning()) {
		$request->addResult('rescan', "1");
	}
	
	$request->addResult("player_name", $client->name());
	$request->addResult("player_connected", $connected);
	$request->addResult("power", $power);
	
	if ($client->model() eq "squeezebox" || $client->model() eq "squeezebox2") {
		$request->addResult("signalstrength", ($client->signalStrength() || 0));
	}
	
	if ($power) {
	
		$request->addResult("mode", Slim::Player::Source::playmode($client));

		if (Slim::Player::Playlist::song($client)) { 
			my $track = $ds->objectForUrl(Slim::Player::Playlist::song($client));

			my $dur   = 0;

			if (blessed($track) && $track->can('secs')) {

				$dur = $track->secs;
			}

			if ($dur) {
				$request->addResult("rate", Slim::Player::Source::rate($client));
				$request->addResult("time", Slim::Player::Source::songTime($client));
				$request->addResult("duration", $dur);
			}
		}
		
		if ($client->currentSleepTime()) {

			my $sleep = $client->sleepTime() - Time::HiRes::time();
			$request->addResult("sleep", $client->currentSleepTime() * 60);
			$request->addResult("will_sleep_in", ($sleep < 0 ? 0 : $sleep));
		}
		
		if (Slim::Player::Sync::isSynced($client)) {

			my $master = Slim::Player::Sync::masterOrSelf($client);

			$request->addResult("sync_master", $master->id());

			my @slaves = Slim::Player::Sync::slaves($master);
			my @sync_slaves = map { $_->id } @slaves;

			$request->addResult("sync_slaves", join(" ", @sync_slaves));
		}
	
		$request->addResult("mixer volume", $client->volume());
		$request->addResult("mixer treble", $client->treble());
		$request->addResult("mixer bass", $client->bass());

		if ($client->model() ne "slimp3") {
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

			$request->addResultLoop($loop, 0, 'playlist index', $idx);
			_addSong($request, $loop, 0, Slim::Player::Playlist::song($client, $idx), $tags);

		} else {

			my ($valid, $start, $end);
			
			if ($modecurrent) {
				($valid, $start, $end) = _normalize($idx, scalar($quantity), $songCount);
			} else {
				($valid, $start, $end) = _normalize(scalar($index), scalar($quantity), $songCount);
			}

			if ($valid) {
				my $count = 0;

				for ($idx = $start; $idx <= $end; $idx++){
					$request->addResultLoop($loop, $count, 'playlist index', $idx);
					_addSong($request, $loop, $count, Slim::Player::Playlist::song($client, $idx), $tags);
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
					($valid, $start, $end) = _normalize(0, (scalar($quantity) - $count), $songCount);		

					if ($valid) {

						for ($idx = $start; $idx <= $end; $idx++){
							$request->addResultLoop($loop, $count, 'playlist index', $idx);
							_addSong($request, $loop, $count, Slim::Player::Playlist::song($client, $idx), $tags);
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

sub syncQuery {
	my $request = shift;
	
	$::d_command && msg("syncQuery()\n");

	# check this is the correct query
	if ($request->isNotQuery([['sync']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $client = $request->client();

	if (Slim::Player::Sync::isSynced($client)) {
	
		my @buddies = Slim::Player::Sync::syncedWith($client);
		my $i = 0;
		for my $eachclient (@buddies) {
			$request->addResultLoop('@syncedWith', $i++, '_playerid', $eachclient->id());
		}
	} else {
	
		$request->addResult('_sync', '-');
	}
	
	$request->setStatusDone();
}

sub timeQuery {
	my $request = shift;
	
	$::d_command && msg("timeQuery()\n");

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

sub versionQuery {
	my $request = shift;
	
	$::d_command && msg("versionQuery()\n");

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

sub _normalize {
	my $from = shift;
	my $numofitems = shift;
	my $count = shift;
	
	my $start = 0;
	my $end   = 0;
	my $valid = 0;
	
	if ($numofitems && $count) {

		my $lastidx = $count - 1;

		if ($from > $lastidx) {
			return ($valid, $start, $end);
		}

		if ($from < 0) {
			$from = 0;
		}
	
		$start = $from;
		$end = $start + $numofitems - 1;
	
		if ($end > $lastidx) {
			$end = $lastidx;
		}

		$valid = 1;
	}

	return ($valid, $start, $end);
}

sub _addSong {
	my $request   = shift; # request
	my $loop      = shift; # loop
	my $index     = shift; # loop index
	my $pathOrObj = shift; # song path or object
	my $tags      = shift; # tags to use

	my $ds        = Slim::Music::Info::getCurrentDataStore();
	my $track     = ref $pathOrObj ? $pathOrObj : $ds->objectForUrl($pathOrObj);
	
	if (!blessed($track) || !$track->can('id')) {
		msg("Slim::Control::Command::pushSong called on undefined track!\n");
		return;
	}
	
	$request->addResultLoop($loop, $index, 'id', $track->id());
	$request->addResultLoop($loop, $index, 'title', $track->title());
	
	# Allocation map: capital letters are still free:
	#  a b c d e f g h i j k l m n o p q r s t u v X y z

	my %cliTrackMap = (
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
	);
	
	for my $tag (split //, $tags) {

		if (my $method = $cliTrackMap{$tag}) {

			my $value = $track->$method();

			if (defined $value && $value !~ /^\s*$/) {

				$request->addResultLoop($loop, $index, $method, $value);
			}

			next;
		}

		if ($tag eq 'b' && (my @bands = $track->band())) {
			$request->addResultLoop($loop, $index, 'band', $bands[0]);
			next;
		}
		
		if ($tag eq 'c' && (my @composers = $track->composer())) {
			$request->addResultLoop($loop, $index, 'composer', $composers[0]);
			next;
		}

		if ($tag eq 'd' && defined(my $duration = $track->secs())) {
			$request->addResultLoop($loop, $index, 'duration', $duration);
			next;
		}

		if ($tag eq 'h' && (my @conductors = $track->conductor())) {
			$request->addResultLoop($loop, $index, 'conductor', $conductors[0]);
			next;
		}

		if ($tag eq 'i' && defined(my $disc = $track->disc())) {
			$request->addResultLoop($loop, $index, 'disc', $disc);
			next;
		}

		if ($tag eq 'j' && $track->coverArt()) {
			$request->addResultLoop($loop, $index, 'coverart', 1);
			next;
		}

		if ($tag eq 'o' && defined(my $ct = $track->content_type())) {
			$request->addResultLoop($loop, $index, 'type', Slim::Utils::Strings::string(uc($ct)));
			next;
		}

		if ($tag eq 'p' && defined(my $genre = $track->genre())) {
			if (defined(my $id = $genre->id())) {
				$request->addResultLoop($loop, $index, 'genre_id', $id);
				next;
			}
		}

		if ($tag eq 's' && defined(my $artist = $track->artist())) {
			if (defined(my $id = $artist->id())) {
				$request->addResultLoop($loop, $index, 'artist_id', $id);
				next;
			}
		}
		
		if (defined(my $album = $track->album())) {
		
			if ($tag eq 'e' && defined(my $id = $album->id())) {
				$request->addResultLoop($loop, $index, 'album_id', $id);
				next;
			}
	
			if ($tag eq 'q' && defined(my $discc = $album->discc())) {
				$request->addResultLoop($loop, $index, 'disccount', $discc) unless $discc eq '';
				next;
			}
		}

	}

}

1;

__END__
