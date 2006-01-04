package Slim::Control::Commands;

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

use Slim::Utils::Misc qw(msg errorMsg);

#use Slim::Control::Request;
#use Slim::Music::Import;
#use Slim::Music::Info;
#use Slim::Player::Client;
#use Slim::Utils::Prefs;

sub buttonCommand {
	my $request = shift;
	
	$::d_command && msg("buttonCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['button']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $client     = $request->client();
	my $button     = $request->getParam('_buttoncode');
	my $time       = $request->getParam('_time');
	my $orFunction = $request->getParam('_orFunction');
	
	if (!defined $button ) {
		$request->setStatusBadParams();
		return;
	}
	
	Slim::Hardware::IR::executeButton($client, $button, $time, undef, defined($orFunction) ? $orFunction : 1);
	
	$request->setStatusDone();
}

sub debugCommand {
	my $request = shift;
	
	$::d_command && msg("debugCommand()\n");

	# check this is the correct command. Syntax approved by Dean himself!
	if ($request->isNotCommand([['debug']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $debugFlag = $request->getParam('_debugflag');
	my $newValue = $request->getParam('_newvalue');
	
	if ( !defined $debugFlag || !($debugFlag =~ /^d_/) ) {
		$request->setStatusBadParams();
		return;
	}
	
	$debugFlag = "::" . $debugFlag;
	no strict 'refs';
	
	if (defined($newValue)) {
		$$debugFlag = $newValue;
	} else {
		# toggle if we don't have a new value
		$$debugFlag = ($$debugFlag ? 0 : 1);
	}
	
	$request->setStatusDone();
}

sub displayCommand {
	my $request = shift;
	
	$::d_command && msg("displayCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['display']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client   = $request->client();
	my $line1    = $request->getParam('_line1');
	my $line2    = $request->getParam('_line2');
	my $duration = $request->getParam('_duration');
	my $p4       = $request->getParam('_p4');
	
	if (!defined $line1) {
		$request->setStatusBadParams();
		return;
	}
	
	Slim::Buttons::ScreenSaver::wakeup($client);
	$client->showBriefly($line1, $line2, $duration, $p4);
	
	$request->setStatusDone();
}

sub irCommand {
	my $request = shift;
	
	$::d_command && msg("irCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['ir']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client      = $request->client();
	my $irCodeBytes = $request->getParam('_ircode');
	my $irTime      = $request->getParam('_time');	
	
	if (!defined $irCodeBytes || !defined $irTime ) {
		$request->setStatusBadParams();
		return;
	}
	
	Slim::Hardware::IR::processIR($client, $irCodeBytes, $irTime);
	
	$request->setStatusDone();
}

sub mixerCommand {
	my $request = shift;
	
	$::d_command && msg("mixerCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['mixer'], ['volume', 'muting', 'treble', 'bass', 'pitch']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client   = $request->client();
	my $entity   = $request->getRequest(1);
	my $newvalue = $request->getParam('_newvalue');

	my @buddies;

	# if we're sync'd, get our buddies
	if (Slim::Player::Sync::isSynced($client)) {
		@buddies = Slim::Player::Sync::syncedWith($client);
	}
	
	if ($entity eq 'muting') {
		my $vol = $client->volume();
		my $fade;
		
		if ($vol < 0) {
			# need to un-mute volume
			$::d_command && msg("Unmuting, volume is $vol.\n");
			$client->prefSet("mute", 0);
			$fade = 0.3125;
		} else {
			# need to mute volume
			$::d_command && msg("Muting, volume is $vol.\n");
			$client->prefSet("mute", 1);
			$fade = -0.3125;
		}

		$client->fade_volume($fade, \&_mixer_mute, [$client]);

		for my $eachclient (@buddies) {
			if ($eachclient->prefGet('syncVolume')) {
				$eachclient->fade_volume($fade, \&_mixer_mute, [$eachclient]);
			}
		}
	} else {
		my $newval;
		my $oldval = $client->$entity();

		if ($newvalue =~ /^[\+\-]/) {
			$newval = $oldval + $newvalue;
		} else {
			$newval = $newvalue;
		}

		$newval = $client->$entity($newval);

		for my $eachclient (@buddies) {
			if ($eachclient->prefGet('syncVolume')) {
				$eachclient->prefSet($entity, $newval);
				$eachclient->$entity($newval);
				Slim::Display::Display::volumeDisplay($eachclient) if $entity eq 'volume';
			}
		}
	}
		
	$request->setStatusDone();
}

sub playcontrolCommand {
	my $request = shift;
	
	$::d_command && msg("playcontrolCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['play', 'stop', 'pause']]) &&
		$request->isNotCommand([['mode'], ['play', 'pause', 'stop']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client = $request->client();
	my $cmd    = $request->getRequest(0);
	my $param  = $request->getRequest(1);
	
	# which state are we in?
	my $curmode = Slim::Player::Source::playmode($client);
	
	# which state do we want to go to?
	my $wantmode = $cmd;
	
	if ($cmd eq 'mode') {
		
		# we want to go to $param if the command is mode
		$wantmode = $param;
	}
	
	if ($cmd eq 'pause') {
		
		# pause 1, pause 0 and pause (toggle) are all supported, figure out which
		# one we want...
		if (defined $param) {
			$wantmode = $param ? 'pause' : 'play';
		} else {
			$wantmode = ($curmode eq 'pause') ? 'play' : 'pause';
		}
	}

	# Adjust for resume: if we're paused and asked to play, we resume
	$wantmode = 'resume' if ($curmode eq 'pause' && $wantmode eq 'play');

	# Adjust for pause: can only do it from play
	if ($wantmode eq 'pause') {

		# default to doing nothing...
		$wantmode = $curmode;
		
		# pause only from play
		$wantmode = 'pause' if $curmode eq 'play';
	}			
	
	# do we need to do anything?
	if ($curmode ne $wantmode) {
		
		# set new playmode
		Slim::Player::Source::playmode($client, $wantmode);

		# reset rate in all cases
		Slim::Player::Source::rate($client, 1);
		
		# update the display
		$client->update();
	}
		
	$request->setStatusDone();
}

sub playlistClearCommand {
	my $request = shift;
	
	$::d_command && msg("playlistClearCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['clear']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client = $request->client();

	Slim::Player::Playlist::clear($client);
	Slim::Player::Source::playmode($client, "stop");
	$client->currentPlaylist(undef);
	$client->currentPlaylistChangeTime(time());
	
	# The above changes the playlist but I am not sure this is ever
	# executed, or even if it should be
	Slim::Player::Playlist::refreshPlaylist($client) if $client->currentPlaylistModified();
	
	$request->setStatusDone();
}

sub playlistDeleteCommand {
	my $request = shift;
	
	$::d_command && msg("playlistDeleteCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['delete']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client = $request->client();
	my $index  = $request->getParam('_index');;
	
	if (!defined $index) {
		$request->setStatusBadParams();
		return;
	}

	Slim::Player::Playlist::removeTrack($client, $index);

	$client->currentPlaylistModified(1);
	$client->currentPlaylistChangeTime(time());
	Slim::Player::Playlist::refreshPlaylist($client);
	
	$request->setStatusDone();
}

sub playlistDeleteitemCommand {
	my $request = shift;
	
	$::d_command && msg("playlistDeleteitemCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['deleteitem']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client      = $request->client();
	my $item        = $request->getParam('_item');;
	
	if (!defined $item || $item eq '') {
		$request->setStatusBadParams();
		return;
	}

	# This used to update $p2; anybody depending on this behaviour needs
	# to be changed to used the returned result (commented below)
	my $absitem = Slim::Utils::Misc::virtualToAbsolute($item);
	#$request->addResult('__absitem', $absitem);

	my $contents;

	if (!Slim::Music::Info::isList($absitem)) {

		Slim::Player::Playlist::removeMultipleTracks($client, [$absitem]);

	} elsif (Slim::Music::Info::isDir($absitem)) {

		Slim::Utils::Scan::addToList({
			'listRef' 	=> \@{$contents},
			'url'		=> $absitem,
			'recursive' => 1
		});

		Slim::Player::Playlist::removeMultipleTracks($client, \@{$contents});

	} else {

		$contents = Slim::Music::Info::cachedPlaylist($absitem);

		if (!defined $contents) {

			my $playlist_filehandle;

			if (!open($playlist_filehandle, Slim::Utils::Misc::pathFromFileURL($absitem))) {

				errorMsg("Couldn't open playlist file $absitem : $!\n");

				$playlist_filehandle = undef;

			} else {

				$contents = [Slim::Formats::Parse::parseList($absitem, $playlist_filehandle, dirname($absitem))];
			}
		}

		if (defined($contents)) {
			Slim::Player::Playlist::removeMultipleTracks($client, $contents);
		}
	}

	$client->currentPlaylistModified(1);
	$client->currentPlaylistChangeTime(time());
	Slim::Player::Playlist::refreshPlaylist($client);
	
	$request->setStatusDone();
}

sub playlistJumpCommand {
	my $request = shift;
	
	$::d_command && msg("playlistJumpCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['jump', 'index']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client = $request->client();
	my $index  = $request->getParam('_index');;
	my $noplay = $request->getParam('_noplay');;
	
	Slim::Player::Source::jumpto($client, $index, $noplay);

	# Does the above change the playlist?
	Slim::Player::Playlist::refreshPlaylist($client) if $client->currentPlaylistModified();
	
	$request->setStatusDone();
}

sub playlistMoveCommand {
	my $request = shift;
	
	$::d_command && msg("playlistMoveCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['move']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client     = $request->client();
	my $fromindex  = $request->getParam('_fromindex');;
	my $toindex    = $request->getParam('_toindex');;
	
	if (!defined $fromindex || !defined $toindex) {
		$request->setStatusBadParams();
		return;
	}

	Slim::Player::Playlist::moveSong($client, $fromindex, $toindex);
	$client->currentPlaylistModified(1);
	$client->currentPlaylistChangeTime(time());
	
	Slim::Player::Playlist::refreshPlaylist($client);
	
	$request->setStatusDone();
}

sub playlistRepeatCommand {
	my $request = shift;
	
	$::d_command && msg("playlistRepeatCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['repeat']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client   = $request->client();
	my $newvalue = $request->getParam('_newvalue');
	
	if (!defined $newvalue) {
		# original code: (Slim::Player::Playlist::repeat($client) + 1) % 3
		$newvalue = (1,2,0)[Slim::Player::Playlist::repeat($client)];
	}
	
	Slim::Player::Playlist::repeat($client, $newvalue);
	
	$request->setStatusDone();
}

sub playlistShuffleCommand {
	my $request = shift;
	
	$::d_command && msg("playlistShuffleCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['shuffle']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client   = $request->client();
	my $newvalue = $request->getParam('_newvalue');
	
	if (!defined $newvalue) {
		$newvalue = (1,2,0)[Slim::Player::Playlist::shuffle($client)];
	}
	
	Slim::Player::Playlist::shuffle($client, $newvalue);
	Slim::Player::Playlist::reshuffle($client);
	$client->currentPlaylistChangeTime(time());
	
	# Does the above change the playlist?
	Slim::Player::Playlist::refreshPlaylist($client) if $client->currentPlaylistModified();
	
	$request->setStatusDone();
}

sub playlistXalbumCommand {
	my $request = shift;
	
	$::d_command && msg("playlistXalbumCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['playalbum', 'loadalbum', 'addalbum', 'insertalbum', 'deletealbum']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client   = $request->client();
	my $cmd      = $request->getRequest(1);
	my $genre    = $request->getParam('_genre'); #p2
	my $artist   = $request->getParam('_artist');#p3
	my $album    = $request->getParam('_album'); #p4
	my $title    = $request->getParam('_title'); #p5

	my $ds = Slim::Music::Info::getCurrentDataStore();
	my $find = {};

	# Find the songs for the passed params
	my $sort = 'track';

	if (_playlistXalbum_specified($genre)) {
		$find->{'genre.name'} = _playlistXalbum_singletonRef($genre);
	}
	if (_playlistXalbum_specified($artist)) {
		$find->{'contributor.name'} = _playlistXalbum_singletonRef($artist);
	}
	if (_playlistXalbum_specified($album)) {
		$find->{'album.title'} = _playlistXalbum_singletonRef($album);
		$sort = 'tracknum';
	}
	if (_playlistXalbum_specified($title)) {
		$find->{'track.title'} = _playlistXalbum_singletonRef($title);
	}
	
	msg("$sort\n");

	my $results = $ds->find({
		'field'  => 'lightweighttrack',
		'find'   => $find,
		'sortBy' => $sort,
		});

	my $load   = ($cmd eq 'loadalbum' || $cmd eq 'playalbum');
	my $insert = ($cmd eq 'insertalbum');
	my $add    = ($cmd eq 'addalbum');
	my $delete = ($cmd eq 'deletealbum');

	my $playListSize = Slim::Player::Playlist::count($client);
	my $size = scalar(@$results);

	Slim::Player::Source::playmode($client, 'stop') 				if $load;
	Slim::Player::Playlist::clear($client) 							if $load;

	push(@{Slim::Player::Playlist::playList($client)}, @$results) 	if $load || $add || $insert;
	_insert_done($client, $playListSize, $size)						if                  $insert;
	Slim::Player::Playlist::removeMultipleTracks($client, $results)	if                             $delete;

	Slim::Player::Playlist::reshuffle($client, $load?1:undef)		if $load || $add;
	Slim::Player::Source::jumpto($client, 0) 						if $load;

	$client->currentPlaylist(undef) 								if $load;
	$client->currentPlaylistModified(1)								if          $add || $insert || $delete;	
	$client->currentPlaylistChangeTime(time()) 						if $load || $add || $insert || $delete;			

	Slim::Player::Playlist::refreshPlaylist($client) if $client->currentPlaylistModified();

	$request->setStatusDone();
}

sub playlistZapCommand {
	my $request = shift;
	
	$::d_command && msg("playlistZapCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['zap']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client = $request->client();
	my $index  = $request->getParam('_index');;
	
	my $ds = Slim::Music::Info::getCurrentDataStore();

	my $zapped   = Slim::Utils::Strings::string('ZAPPED_SONGS');
	my $zapindex = defined $index ? $index : Slim::Player::Source::playingSongIndex($client);
	my $zapsong  = Slim::Player::Playlist::song($client, $zapindex);

	#  Remove from current playlist
	if (Slim::Player::Playlist::count($client) > 0) {

		# Callo ourselves.
		Slim::Control::Command::execute($client, ["playlist", "delete", $zapindex]);
	}

	my $playlistObj = $ds->updateOrCreate({
		'url'        => "playlist://$zapped",
		'attributes' => {
			'TITLE' => $zapped,
			'CT'    => 'ssp',
		},
	});

	my @list = $playlistObj->tracks();
	push @list, $zapsong;

	$playlistObj->setTracks(\@list);
	$playlistObj->update();

	$client->currentPlaylistModified(1);
	$client->currentPlaylistChangeTime(time());
	Slim::Player::Playlist::refreshPlaylist($client);
	
	$request->setStatusDone();
}

sub playlistcontrolCommand {
	my $request = shift;
	
	$::d_command && msg("playlistcontrolCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['playlistcontrol']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client = $request->client();
	my $cmd    = $request->getParam('cmd');;
	
	if (Slim::Music::Import::stillScanning()) {
		$request->addResult('rescan', "1");
	}

	if ($request->paramUndefinedOrNotOneOf($cmd, ['load', 'insert', 'add', 'delete'])) {
		$request->setStatusBadParams();
		return;
	}

	my $load = ($cmd eq 'load');
	my $insert = ($cmd eq 'insert');
	my $add = ($cmd eq 'add');
	my $delete = ($cmd eq 'delete');

	my $ds = Slim::Music::Info::getCurrentDataStore();
 			

	# find the songs
	my $find = {};
	my @songs;
 	my $playlist;

	if (defined(my $playlist_id = $request->getParam('playlist_id'))){
		# Special case...

		my $playlist = $ds->objectForId('track', $playlist_id);

		if (blessed($playlist) && $playlist->can('tracks')) {

			# We want to add the playlist name to the client object.
			$client->currentPlaylist($playlist) if $load && defined $playlist;

			@songs = $playlist->tracks();
		}
	}
	else {
		if (defined(my $genre_id = $request->getParam('genre_id'))){
			$find->{'genre'} = $genre_id;
		}
		if (defined(my $artist_id = $request->getParam('artist_id'))){
			$find->{'artist'} = $artist_id;
		}
		if (defined(my $album_id = $request->getParam('album_id'))){
			$find->{'album'} = $album_id;
		}
		if (defined(my $track_id = $request->getParam('track_id'))){
			$find->{'id'} = $track_id;
		}
		if (defined(my $year_id = $request->getParam('year_id'))){
			$find->{'year'} = $year_id;
		}
			
		my $sort = exists $find->{'album'} ? 'tracknum' : 'track';

		@songs = @{ $ds->find({
			'field'  => 'lightweighttrack',
			'find'   => $find,
			'sortBy' => $sort,
		}) };
	}
	my $size  = scalar(@songs);

	# start the show...

	Slim::Player::Source::playmode($client, "stop") if $load;
	Slim::Player::Playlist::clear($client) if $load;
				
	my $playListSize = Slim::Player::Playlist::count($client);
	
	push(@{Slim::Player::Playlist::playList($client)}, @songs) if ($load || $add || $insert);
	Slim::Player::Playlist::removeMultipleTracks($client, \@songs) if $delete;
	
	_insert_done($client, $playListSize, $size) if $insert;
	
	Slim::Player::Playlist::reshuffle($client, $load?1:0) if ($load || $add);
	Slim::Player::Source::jumpto($client, 0) if $load;

	$client->currentPlaylistModified(1) if ($add || $insert || $delete);
	$client->currentPlaylistChangeTime(time()) if ($load || $add || $insert || $delete);

	$request->addResult('count', $size);

	$request->setStatusDone();
}

sub playerprefCommand {
	my $request = shift;
	
	$::d_command && msg("playerprefCommand()\n");

	if ($request->isNotCommand([['playerpref']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $client   = $request->client();
	my $prefName = $request->getParam('_prefname');
	my $newValue = $request->getParam('_newvalue');

	if (!defined $prefName || !defined $newValue) {
		$request->setStatusBadParams();
		return;
	}	

	$client->prefSet($prefName, $newValue);
	
	$request->setStatusDone();
}

sub powerCommand {
	my $request = shift;
	
	$::d_command && msg("powerCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['power']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client   = $request->client();
	my $newpower = $request->getParam('_newvalue');
	
	# handle toggle
	if (!defined $newpower) {
		$newpower = $client->power() ? 0 : 1;
	}

	# handle sync'd players
	if (Slim::Player::Sync::isSynced($client)) {

		my @buddies = Slim::Player::Sync::syncedWith($client);
		
		for my $eachclient (@buddies) {
			$eachclient->power($newpower) if $eachclient->prefGet('syncPower');
		}
	}

	$client->power($newpower);

	# Powering off cancels sleep...
	if ($newpower eq "0") {
		Slim::Utils::Timers::killTimers($client, \&_sleepStartFade);
		Slim::Utils::Timers::killTimers($client, \&_sleepPowerOff);
		$client->sleepTime(0);
		$client->currentSleepTime(0);
	}
		
	$request->setStatusDone();
}

sub prefCommand {
	my $request = shift;
	
	$::d_command && msg("prefCommand()\n");

	if ($request->isNotCommand([['pref']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $prefName = $request->getParam('_prefname');
	my $newValue = $request->getParam('_newvalue');

	if (!defined $prefName || !defined $newValue) {
		$request->setStatusBadParams();
		return;
	}	

	Slim::Utils::Prefs::set($prefName, $newValue);
	
	$request->setStatusDone();
}

sub rateCommand {
	my $request = shift;
	
	$::d_command && msg("rateCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['rate']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client  = $request->client();
	my $newrate = $request->getParam('_newvalue');
	
	if (!defined $newrate) {
		$request->setStatusBadParams();
		return;
	}
	
	if ($client->directURL() || $client->audioFilehandleIsSocket) {
		Slim::Player::Source::rate($client, 1);
		# shouldn't we return an error here ???
	} else {
		Slim::Player::Source::rate($client, $newrate);
	}
	
	$request->setStatusDone();
}

sub rescanCommand {
	my $request = shift;
	
	$::d_command && msg("rescanCommand()\n");

	if ($request->isNotCommand([['rescan']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $playlistsOnly = $request->getParam('_playlists') || 0;
	
	# if we're scanning allready, don't do it twice
	if (!Slim::Music::Import::stillScanning()) {

		if ($playlistsOnly) {

			Slim::Music::Import::scanPlaylistsOnly(1);

		} else {

			Slim::Music::Import::cleanupDatabase(1);
		}

		# rescan should not reset importers. currently iTunes # is the
		# only scanner that defines a reset function, # and that's for
		# the wipedb case only.
		Slim::Music::Info::clearPlaylists();
		Slim::Music::Import::startScan();
	}

	$request->setStatusDone();
}

sub sleepCommand {
	my $request = shift;
	
	$::d_command && msg("sleepCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['sleep']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client        = $request->client();
	my $will_sleep_in = $request->getParam('_newvalue');
	
	if (!defined $will_sleep_in) {
		$request->setStatusBadParams();
		return;
	}
	
	# Cancel the timers, we'll set them back if needed
	Slim::Utils::Timers::killTimers($client, \&_sleepStartFade);
	Slim::Utils::Timers::killTimers($client, \&_sleepPowerOff);
		
	# if we have a sleep duration
	if ($will_sleep_in > 0) {
		my $now = Time::HiRes::time();
		my $offTime = $now + $will_sleep_in;
		
		# do a nice fade if time allows. The duration of the fade is 60 seconds
		my $fadeTime = $offTime;
		if ($will_sleep_in > 60) {
			$fadeTime -= 60;
		}
			
		# set our timers
		Slim::Utils::Timers::setTimer($client, $offTime, \&_sleepPowerOff);
		Slim::Utils::Timers::setTimer($client, $fadeTime, \&_sleepStartFade) if $fadeTime != $offTime;

		$client->sleepTime($offTime);
		$client->currentSleepTime($will_sleep_in / 60); # for some reason this is minutes...
	} else {
		# finish canceling any sleep in progress
		$client->sleepTime(0);
		$client->currentSleepTime(0);
	}
	
	$request->setStatusDone();
}

sub syncCommand {
	my $request = shift;
	
	$::d_command && msg("syncCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['sync']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client   = $request->client();
	my $newbuddy = $request->getParam('_indexid-');
	
	if (!defined $newbuddy) {
		$request->setStatusBadParams();
		return;
	}
	
	if ($newbuddy eq '-') {
	
		Slim::Player::Sync::unsync($client);
		
	} else {

		# try an ID
		my $buddy = Slim::Player::Client::getClient($newbuddy);

		# try a player index
		if (!defined $buddy) {
			my @clients = Slim::Player::Client::clients();
			if (defined $clients[$newbuddy]) {
				$buddy = $clients[$newbuddy];
			}
		}
		
		Slim::Player::Sync::sync($buddy, $client) if defined $buddy;
	}
	
	$request->setStatusDone();
}

sub timeCommand {
	my $request = shift;
	
	$::d_command && msg("timeCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['time', 'gototime']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client  = $request->client();
	my $newtime = $request->getParam('_newvalue');
	
	if (!defined $newtime) {
		$request->setStatusBadParams();
		return;
	}
	
	Slim::Player::Source::gototime($client, $newtime);
	
	$request->setStatusDone();
}

sub wipecacheCommand {
	my $request = shift;
	
	$::d_command && msg("wipecacheCommand()\n");

	if ($request->isNotCommand([['wipecache']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# no parameters
	
	# if we're scanning allready, don't do it twice
	if (!Slim::Music::Import::stillScanning()) {

		# Clear all the active clients's playlists
		for my $client (Slim::Player::Client::clients()) {

			$client->execute([qw(playlist clear)]);
		}

		Slim::Music::Info::clearPlaylists();
		Slim::Music::Info::wipeDBCache();
		Slim::Music::Import::resetImporters();
		Slim::Music::Import::startScan();
	}

	$request->setStatusDone();
}

################################################################################
# Helper functions
################################################################################

sub _sleepStartFade {
	my $client = shift;

	$::d_command && msg("_sleepStartFade()\n");
	
	if ($client->isPlayer()) {
		$client->fade_volume(-60);
	}
}

sub _sleepPowerOff {
	my $client = shift;
	
	$::d_command && msg("_sleepPowerOff()\n");

	$client->sleepTime(0);
	$client->currentSleepTime(0);
	
	Slim::Control::Command::execute($client, ['stop', 0]);
	Slim::Control::Command::execute($client, ['power', 0]);
}

sub _mixer_mute {
	my $client = shift;

	$::d_command && msg("_mixer_mute()\n");

	$client->mute();
}

sub _insert_done {
	my ($client, $listsize, $size, $callbackf, $callbackargs) = @_;

	$::d_command && msg("_insert_done()\n");

	my $playlistIndex = Slim::Player::Source::streamingSongIndex($client)+1;
	my @reshuffled;

	if (Slim::Player::Playlist::shuffle($client)) {

		for (my $i = 0; $i < $size; $i++) {
			push @reshuffled, ($listsize + $i);
		};
			
		$client = Slim::Player::Sync::masterOrSelf($client);
		
		if (Slim::Player::Playlist::count($client) != $size) {	
			splice @{$client->shufflelist}, $playlistIndex, 0, @reshuffled;
		}
		else {
			push @{$client->shufflelist}, @reshuffled;
		}
	} else {

		if (Slim::Player::Playlist::count($client) != $size) {
			Slim::Player::Playlist::moveSong($client, $listsize, $playlistIndex, $size);
		}

		Slim::Player::Playlist::reshuffle($client);
	}

	Slim::Player::Playlist::refreshPlaylist($client);

	$callbackf && (&$callbackf(@$callbackargs));

	Slim::Control::Command::executeCallback($client, ['playlist','load_done']);
}

# defined, but does not contain a *
sub _playlistXalbum_specified {
	my $i = shift;

	return 0 if ref($i) eq 'ARRAY';
	return 0 unless defined $i;
	return $i !~ /\*/;
}

sub _playlistXalbum_singletonRef {
	my $arg = shift;

	if (!defined($arg)) {
		return [];
	} elsif ($arg eq '*') {
		return [];
	} elsif ($arg) {
		# force stringification of a possible object.
		return ["" . $arg];
	} else {
		return [];
	}
}



1;

__END__
