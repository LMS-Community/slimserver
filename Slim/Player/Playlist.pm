package Slim::Player::Playlist;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Spec::Functions qw(catfile);
use Scalar::Util qw(blessed);

use Slim::Formats::Playlists::M3U;
use Slim::Player::Source;
use Slim::Player::Sync;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

if (!main::SCANNER) {
	require Slim::Control::Jive;
}

my $prefs = preferences('server');

our %validSubCommands = map { $_ => 1 } qw(play append load_done loadalbum addalbum loadtracks playtracks addtracks inserttracks deletetracks clear delete move sync);

our %shuffleTypes = (
	1 => 'track',
	2 => 'album',
);

my $log = logger('player.playlist');

#
# accessors for playlist information
#
sub count {
	my $client = shift;
	return scalar(@{playList($client)});
}

sub shuffleType {
	my $client = shift;

	my $shuffleMode = shuffle($client);

	if (defined $shuffleTypes{$shuffleMode}) {
		return $shuffleTypes{$shuffleMode};
	}

	return 'none';
}

sub song {

	my ($client, $index, $refresh, $useShuffled) = @_;
	$refresh ||= 0;
	$useShuffled = 1 unless defined $useShuffled;

	if (count($client) == 0) {
		return;
	}

	if (!defined($index)) {
		$index = Slim::Player::Source::playingSongIndex($client);
	}

	my $objOrUrl;

	if ($useShuffled && defined ${shuffleList($client)}[$index]) {

		$objOrUrl = ${playList($client)}[${shuffleList($client)}[$index]];

	} else {

		$objOrUrl = ${playList($client)}[$index];
	}

	if ( $objOrUrl && ($refresh || !blessed($objOrUrl)) ) {

		$objOrUrl = Slim::Schema->objectForUrl({
			'url'      => $objOrUrl,
			'create'   => 1,
			'readTags' => 1,
		});
		
		if ($refresh) {
			$objOrUrl = refreshTrack($client, $objOrUrl->url);
		}
	}

	return $objOrUrl;
}

sub songs {

	my ($client, $start, $end) = @_;

	if (count($client) == 0) {
		return;
	}

	my @tracks;

	foreach (defined ${shuffleList($client)}[$start]
				? (@{ playList($client) }[ @{shuffleList($client)} ])[$start .. $end]
				: @{playList($client)}[$start .. $end])
	{
		# Use $_ here to use perl's inline replace semantics
		
		if ( $_ && !blessed($_) ) {
						
			# If we instantiate a Track from a URL then 
			# back-patch the playlist item with the Track. This could be common
			# for remote tracks.

			my $track = Slim::Schema->objectForUrl({
					'url'      => $_,
					'create'   => 1,
					'readTags' => 1,
				});

			if (defined $track) {
				$_ = $track;
			} else {
				$log->warn('Cannot get Track object for: ', $_);
			}
		}
		
		push @tracks, $_ if $_ && blessed($_);
	}

	return @tracks;
}

# Refresh track(s) in a client playlist from the database
sub refreshTrack {
	my ( $client, $url ) = @_;
	
	my $track = Slim::Schema->objectForUrl( {
		url      => $url,
		create   => 1,
		readTags => 1,
	} );
	
	my $i = 0;
	for my $item ( @{ playList($client) } ) {
		my $itemUrl = blessed($item) ? $item->url : $item;
		if ( $itemUrl eq $url ) {
			playList($client)->[$i] = $track;
		}
		$i++;
	}
	
	return $track;
}

sub url {
	my $objOrUrl = song( @_ );

	return ( blessed $objOrUrl ) ? $objOrUrl->url : $objOrUrl;
}

sub shuffleList {
	my ($client) = shift;
	
	$client = $client->master();
	
	return $client->shufflelist;
}

sub playList {
	my ($client) = shift;

	$client = $client->master();
	
	return $client->playlist;
}

sub addTracks {
	my ($client, $tracksRef, $insert) = @_;
	
	my $playlist = playList($client);
	
	my $maxPlaylistLength = $prefs->get('maxPlaylistLength');
	
	# How many tracks might we need to remove to make space?
	my $need = $maxPlaylistLength ? (scalar @{$playlist} + scalar @{$tracksRef}) - $maxPlaylistLength : 0;
	
	if ($need > 0) {
		# 1. If we have already-played stuff at the start of the playlist that we can remove, then remove that first
		my $canRemove = Slim::Player::Source::playingSongIndex($client) || 0;
		$canRemove = $need if $canRemove > $need;

		if ($canRemove) {
			main::INFOLOG && $log->info("Removing $canRemove tracks from start of playlist");
			$need -= removeTrack($client, 0, $canRemove);
		}
	}
		
	if ($need > 0 && $insert) {
		# 2. If inserting, then try to remove stuff from the end of the playlist
		my $streamingSongIndex =Slim::Player::Source::streamingSongIndex($client) || 0;
		my $canRemove = $#{$playlist} - $streamingSongIndex;
		$canRemove = $need if $canRemove > $need;

		if ($canRemove) {
			main::INFOLOG && $log->info("Removing $canRemove tracks from end of playlist");
			$need -= removeTrack($client, scalar @{$playlist} - $canRemove, $canRemove);
		}
	}
	
	my $canAdd;
	my $errorMsg;
	if ($need >= scalar @{$tracksRef}) {
		# no space to add any tracks
		$canAdd = 0;
		$errorMsg = $client->string('ERROR_PLAYLIST_FULL');
	} elsif ($need > 0) {
		# can add some tracks
		$canAdd = scalar @{$tracksRef} - $need;
		push (@{$playlist}, @{$tracksRef}[ ( 0 .. ($canAdd - 1) ) ]);
		$errorMsg = $client->string('ERROR_PLAYLIST_ALMOST_FULL', $canAdd, scalar @{$tracksRef});
	} else {
		# can simply add all tracks
		$canAdd = scalar @{$tracksRef};
		push (@{$playlist}, @{$tracksRef});
	}
	
	if ($errorMsg) {
		$client->showBriefly({
			line => [ undef, $errorMsg ],
			jive => {type => 'popupplay', text => [ $errorMsg ], style => 'add', duration => 5_000},
		}, {
			scroll    => 1,
			firstline => 0,
			duration  => 5,
		});
	}
	
	if ($insert) {
		_insert_done($client, $canAdd);
	}
	
	return $canAdd;
}

sub _insert_done {
	my ($client, $size, $callbackf, $callbackargs) = @_;

	my $playlistIndex = Slim::Player::Source::streamingSongIndex($client)+1;
	my $moveFrom = count($client) - $size;

	if (shuffle($client)) {
		my @reshuffled = ($moveFrom .. ($moveFrom + $size - 1));
		$client = $client->master();
		if (count($client) != $size) {	
			splice @{$client->shufflelist}, $playlistIndex, 0, @reshuffled;
		} else {
			push @{$client->shufflelist}, @reshuffled;
		}
	} else {
		if (count($client) != $size) {
			moveSong($client, $moveFrom, $playlistIndex, $size);
		}
		reshuffle($client);
	}

	refreshPlaylist($client);
}

sub shuffle {
	my $client = shift;
	my $shuffle = shift;
	
	$client = $client->master();

	if (defined($shuffle)) {
		$prefs->client($client)->set('shuffle', $shuffle);
	}
	
	# If Random Play mode is active, return 0
	if (   exists $INC{'Slim/Plugin/RandomPlay/Plugin.pm'} 
		&& Slim::Plugin::RandomPlay::Plugin::active($client)
	) {
		return 0;
	}

	# Allow plugins to inhibit shuffle mode
	if ($client->shuffleInhibit) {
		return 0;
	}
	
	return $prefs->client($client)->get('shuffle');
}

sub repeat {
	my $client = shift;
	my $repeat = shift;
	
	$client = $client->master();

	if (defined($repeat)) {
		$prefs->client($client)->set('repeat', $repeat);
	}
	
	return $prefs->client($client)->get('repeat');
}

sub copyPlaylist {
	my $toClient   = shift;
	my $fromClient = shift;
	my $noQueueReset = shift;

	@{$toClient->playlist}    = @{$fromClient->playlist};
	@{$toClient->shufflelist} = @{$fromClient->shufflelist};

	$toClient->controller()->resetSongqueue(Slim::Player::Source::streamingSongIndex($fromClient)) unless $noQueueReset;

	$prefs->client($toClient)->set('shuffle', $prefs->client($fromClient)->get('shuffle'));
	$prefs->client($toClient)->set('repeat',  $prefs->client($fromClient)->get('repeat'));
}

sub removeTrack {
	my $client = shift->master();
	my $tracknum = shift;
	my $nTracks = shift || 1;
	
	my $log     = logger('player.source');

	if ($tracknum > count($client) - 1) {
		$log->warn("Attempting to remove track(s) $tracknum beyond end of playlist");
		return 0;
	}	
	if ($tracknum + $nTracks > count($client)) {
		$log->warn("Arrempting to remove too many tracks ($nTracks)");
		$nTracks = count($client) - $tracknum;
	}
	
	my $stopped = 0;
	my $oldMode = Slim::Player::Source::playmode($client);
	
	# Stop playing track, if necessary, before cuting old track(s) out of playlist
	# in case Playlist::song() is called while stopping
	my $playingSongIndex = Slim::Player::Source::playingSongIndex($client);
	if ($playingSongIndex >= $tracknum  && $playingSongIndex < $tracknum + $nTracks) {

		main::INFOLOG && $log->info("Removing currently playing track.");

		Slim::Player::Source::playmode($client, "stop");
		$stopped = 1;
	} 

	# Remove old tracks from playlist
	my $playlist = playList($client);
	my $shufflelist = shuffleList($client);
	if (shuffle($client)) {
		
		# We make a copy of the set of playlist-index values to remove here,
		# so that they are stable while the inner loop may change the values in place.
		my @playlistIndexes = @{$shufflelist}[$tracknum .. ($tracknum + $nTracks - 1)];
		
		foreach my $playlistindex (@playlistIndexes) {
			splice(@$playlist, $playlistindex, 1);
			foreach (@$shufflelist) {
				if ($_ > $playlistindex) {
					$_ -= 1;	# Modifies element of shufflelist array in place
				}
			}
		}
		splice(@$shufflelist, $tracknum, $nTracks);
	} else {
		splice(@$playlist, $tracknum, $nTracks);
		@$shufflelist = ( 0 .. $#{$playlist} );
	}
	
	if (!$stopped) {
		if (Slim::Player::Source::streamingSongIndex($client) >= $tracknum  && Slim::Player::Source::streamingSongIndex($client) < $tracknum + $nTracks) {
			# If we're removing the streaming song (which is different from
			# the playing song), get the client to flush out the current song
			# from its audio pipeline.
			main::INFOLOG && $log->info("Removing currently streaming track.");
	
			Slim::Player::Source::flushStreamingSong($client);
	
		} else {
	
			my $queue = $client->currentsongqueue();
	
			for my $song (@$queue) {
	
				if ($tracknum < $song->index()) {
					$song->index($song->index() - $nTracks);
				}
			}
		}
	}
	
	if ($stopped) {

		my $songcount = scalar(@$playlist);

		if ($playingSongIndex >= $songcount) {
			$playingSongIndex = $songcount - 1;
		}
		
		$client->execute([ 'playlist', 'jump', $playingSongIndex, undef, $oldMode ne "play" ]);
	}

	# browseplaylistindex could return a non-sensical number if we are not in playlist mode
	# this is due to it being a wrapper around $client->modeParam('listIndex')
	refreshPlaylist($client,
		Slim::Buttons::Playlist::showingNowPlaying($client) ?
			undef : 
			Slim::Buttons::Playlist::browseplaylistindex($client)
	);
	
	return $nTracks;
}

sub removeMultipleTracks {
	my $client = shift;
	my $tracks = shift;

	my %trackEntries = ();

	if (defined($tracks) && ref($tracks) eq 'ARRAY') {

		for my $track (@$tracks) {
	
			# Handle raw file urls (from BMF, of course)
			if (ref $track) {
				$track = $track->url;
			};
			
			$trackEntries{$track} = 1;
		}
	}

	my $stopped = 0;
	my $oldMode = Slim::Player::Source::playmode($client);

	my $playingTrackPos   = ${shuffleList($client)}[Slim::Player::Source::playingSongIndex($client)];
	my $streamingTrackPos = ${shuffleList($client)}[Slim::Player::Source::streamingSongIndex($client)];

	# going to need to renumber the entries in the shuffled list
	# will need to map the old position numbers to where the track ends
	# up after all the deletes occur
	my %oldToNew = ();
	my $i        = 0;
	my $oldCount = 0;
 
	while ($i <= $#{playList($client)}) {

		#check if this file meets all criteria specified
		my $thisTrack = ${playList($client)}[$i];

		if (blessed($thisTrack) ? $trackEntries{$thisTrack->url} : $trackEntries{$thisTrack}) {

			splice(@{playList($client)}, $i, 1);

			if ($playingTrackPos == $oldCount) {

				Slim::Player::Source::playmode($client, "stop");
				$stopped = 1;

			} elsif ($streamingTrackPos == $oldCount) {

				Slim::Player::Source::flushStreamingSong($client);
			}

		} else {

			$oldToNew{$oldCount} = $i;
			$i++;
		}

		$oldCount++;
	}
	
	my @reshuffled = ();
	my $newTrack;
	my $getNext = 0;
	my %oldToNewShuffled = ();
	my $j = 0;

	# renumber all of the entries in the shuffle list with their new
	# positions, also get an update for the current track, if the
	# currently playing track was deleted, try to play the next track in
	# the new list
	while ($j <= $#{shuffleList($client)}) {

		my $oldNum = shuffleList($client)->[$j];

		if ($oldNum == $playingTrackPos) {
			$getNext = 1;
		}

		if (exists($oldToNew{$oldNum})) { 

			push(@reshuffled,$oldToNew{$oldNum});

			$oldToNewShuffled{$j} = $#reshuffled;

			if ($getNext) {
				$newTrack = $#reshuffled;
				$getNext  = 0;
			}
		}

		$j++;
	}

	# if we never found a next, we deleted eveything after the current
	# track, wrap back to the beginning
	if ($getNext) {
		$newTrack = 0;
	}

	$client = $client->master();
	
	@{$client->shufflelist} = @reshuffled;

	if ($stopped && ($oldMode eq "play")) {

		$client->execute([ 'playlist', 'jump', $newTrack ]);

	} else {

		my $queue = $client->currentsongqueue();

		for my $song (@{$queue}) {
			$song->index($oldToNewShuffled{$song->index()} || 0);
		}
	}

	refreshPlaylist($client);
}

sub refreshPlaylist {
	my $client = shift;
	my $index = shift;

	# make sure we're displaying the new current song in the playlist view.
	for my $everybuddy ($client->syncGroupActiveMembers()) {
		if ($everybuddy->isPlayer()) {
			Slim::Buttons::Playlist::jump($everybuddy,$index);
		}
	}
}

sub moveSong {
	my $client = shift;
	my $src = shift;
	my $dest = shift;
	my $size = shift;
	my $listref;
	
	$client = $client->master();
	
	if (!defined($size)) {
		$size = 1;
	}

	if (defined $dest && $dest =~ /^[\+-]/) {
		$dest = $src + $dest;
	}

	if (defined $src && defined $dest && 
		$src < count($client) && 
		$dest < count($client) && $src >= 0 && $dest >= 0) {

		if (shuffle($client)) {
			$listref = shuffleList($client);
		} else {
			$listref = playList($client);
		}

		if (defined $listref) {		

			my @item = splice @{$listref},$src, $size;

			splice @{$listref},$dest, 0, @item;	

			my $playingIndex = Slim::Player::Source::playingSongIndex($client);
			my $streamingIndex = Slim::Player::Source::streamingSongIndex($client);
			# If we're streaming a different song than we're playing and
			# moving either to or from the streaming song position, flush
			# the streaming song, because it's no longer relevant.
			if (($playingIndex != $streamingIndex) &&
				(($streamingIndex == $src) || ($streamingIndex == $dest) ||
				 ($playingIndex == $src) || ($playingIndex == $dest))) {
				Slim::Player::Source::flushStreamingSong($client);
			}

			my $queue = $client->currentsongqueue();

			for my $song (@$queue) {
				my $index = $song->index();
				if ($src == $index) {
					$song->index($dest);
				}
				elsif (($dest == $index) || (($src < $index) != ($dest < $index))) {
					$song->index(($dest>$src)? $index - 1 : $index + 1);
				}
			}

			refreshPlaylist($client);
		}
	}
}

# iterate over the current playlist to replace local file:// urls with volatile tmp:// versions
sub makeVolatile {
	my $client = shift;

	require Slim::Player::Protocols::Volatile;
	
	$client = $client->master;
		
	# When shuffle is on, we'll have to deal with it separately. Track order won't be retained, 
	# but at least the same track should play after the update:
	#    1. set shuffle off
	#    2. remember the position
	#    3. add new tracks
	#    4. restore position
	#    5. shuffle again, preserving the currently playing track
	my $shuffle = shuffle($client);
	$client->execute([ 'playlist', 'shuffle', 0 ]) if $shuffle;
	
	my $needRestart;
	
	my @urls = map {
		my $url = blessed($_) ? $_->url : $_;
		
		if ( $url =~ s/^file/tmp/ ) {
			Slim::Schema->objectForUrl({
				'url'      => $url,
				'create'   => 1,
				'readTags' => 1,
			});
			
			Slim::Player::Protocols::Volatile->getMetadataFor($client, $url);
			
			$needRestart++;
		}
		
		$url;
	} @{playList($client)};
	
	# don't restart playback unless we've been playing local tracks
	if ($needRestart) {
		my $position = Slim::Player::Source::playingSongIndex($client);
		my $cmd      = 'addtracks';
		my $playtime;
		my $restoreStateWhenShuffled = ['power', 0];
		
		if ($client->isPlaying()) {
			$playtime = Slim::Player::Source::songTime($client);
			
			if ($shuffle) {
				$restoreStateWhenShuffled = ['play', 0.2];
			}
			else {
				$cmd = 'loadtracks';
			}
		}
		elsif ($shuffle && $client->power) {
			if ($client->isPaused) {
				# XXX - pause somehow doesn't work...
#				$restoreStateWhenShuffled = ['pause', 1];
				$restoreStateWhenShuffled = ['stop'];
			}
			elsif ($client->isStopped) {
				$restoreStateWhenShuffled = ['stop'];
			}
		}

		Slim::Player::Playlist::stopAndClear($client);

		$client->execute([ 'playlist', $cmd, 'listRef', \@urls, 0.2, $position ]);
		
		# restore shuffle state
		if ($shuffle) {
			# playlist addtracks wouldn't jump - need to do it here
			$client->execute([ 'playlist', 'jump', $position ]);
			$client->execute([ 'playlist', 'shuffle', $shuffle ]);
			$client->execute($restoreStateWhenShuffled);
		}
		
		Slim::Player::Source::gototime($client, $playtime) if $playtime;
	}
}

sub stopAndClear {
	my $client = shift;
	
	# Bug 11447 - Have to stop player and clear song queue
	$client->controller->stop();
	$client->controller()->resetSongqueue();

	@{playList($client)} = ();
	$client->currentPlaylist(undef);
	
	# Remove saved playlist if available
	my $playlistUrl = _playlistUrlForClient($client);
	unlink(Slim::Utils::Misc::pathFromFileURL($playlistUrl)) if $playlistUrl;

	reshuffle($client);
}

sub fischer_yates_shuffle {
	my ($listRef) = @_;

	if ($#$listRef == -1 || $#$listRef == 0) {
		return;
	}

	for (my $i = ($#$listRef + 1); --$i;) {
		# swap each item with a random item;
		my $a = int(rand($i + 1));
		@$listRef[$i,$a] = @$listRef[$a,$i];
	}
}

#reshuffle - every time the playlist is modified, the shufflelist should be updated
#		We also invalidate the htmlplaylist at this point
sub reshuffle {
	my $client = shift->master();

	my $dontpreservecurrsong = shift;
  
	my $songcount = count($client);
	my $listRef   = shuffleList($client);

	if (!$songcount) {

		@{$listRef} = ();

		refreshPlaylist($client);

		return;
	}

	my $realsong = ${$listRef}[Slim::Player::Source::playingSongIndex($client)];

	if (!defined($realsong) || $dontpreservecurrsong) {
		$realsong = -1;
	} elsif ($realsong > $songcount) {
		$realsong = $songcount;
	}
	
	if ( main::INFOLOG && $log->is_info ) {
		$log->info(sprintf("Reshuffling, current song index: %d, preserve song? %s",
			$realsong,
			$dontpreservecurrsong ? 'no' : 'yes',
		));
	}

	my @realqueue = ();
	my $queue     = $client->currentsongqueue();

	for my $song (@$queue) {

		push @realqueue, $listRef->[$song->index()];
	}

	@{$listRef} = (0 .. ($songcount - 1));

	# 1 is shuffle by song
	# 2 is shuffle by album
	if (shuffle($client) == 1) {

		fischer_yates_shuffle($listRef);

		# If we're preserving the current song
		# this places it at the top of the playlist
		if ( $realsong > -1 ) {
			for (my $i = 0; $i < $songcount; $i++) {

				if ($listRef->[$i] == $realsong) {

					if (shuffle($client)) {
					
						my $temp = $listRef->[$i];
						$listRef->[$i] = $listRef->[0];
						$listRef->[0] = $temp;
						$i = 0;
					}

					last;
				}
			}
		}

	} elsif (shuffle($client) == 2) {

		my %albumTracks     = ();
		my %trackToPosition = ();
		my $i  = 0;

		my $defaultAlbumTitle = Slim::Utils::Text::matchCase($client->string('NO_ALBUM'));

		# Because the playList might consist of objects - we can avoid doing an extra objectForUrl call.
		for my $track (@{playList($client)}) {

			# Can't shuffle remote URLs - as they most likely
			# won't have distinct album names.
			next if Slim::Music::Info::isRemoteURL($track);

			my $trackObj = $track;

			if (!blessed($trackObj) || !$trackObj->can('albumid')) {

				main::INFOLOG && $log->info("Track: $track isn't an object - fetching");

				$trackObj = Slim::Schema->objectForUrl($track);
			}

			# Pull out the album id, and accumulate all of the
			# tracks for that album into a hash. Also map that
			# object to a poisition in the playlist.
			if (blessed($trackObj) && $trackObj->can('albumid')) {

				my $albumid = $trackObj->albumid() || 0;

				push @{$albumTracks{$albumid}}, $trackObj;

				$trackToPosition{$trackObj} = $i++;

			} else {

				logBacktrace("Couldn't find an object for url: $track");
			}
		}

		# Not quite sure what this is doing - not changing the current song?
		if ($realsong == -1 && !$dontpreservecurrsong) {

			my $index = $prefs->client($client)->get('currentSong');

			if (defined $index && defined $listRef->[$index]) {
				$realsong = $listRef->[$index];
			}
		}

		my $currentTrack = ${playList($client)}[$realsong];
		my $currentAlbum = 0;

		# This shouldn't happen - but just in case.
		if (!blessed($currentTrack) || !$currentTrack->can('albumid')) {
			$currentTrack = Slim::Schema->objectForUrl($currentTrack);
		}

		if (blessed($currentTrack) && $currentTrack->can('albumid')) {
			$currentAlbum = $currentTrack->albumid() || 0;
		}

		# @albums is now a list of Album names. Shuffle that list.
		my @albums = keys %albumTracks;

		fischer_yates_shuffle(\@albums);

		# Put the album for the currently playing track at the beginning of the list.
		for (my $i = 0; $i <= $#albums && $realsong != -1; $i++) {

			if ($albums[$i] eq $currentAlbum) {

				my $album = splice(@albums, $i, 1);

				unshift(@albums, $album);

				last;
			}
		}

		# Clear out the list ref - we'll be reordering it.
		@{$listRef} = ();

		for my $album (@albums) {

			for my $track (@{$albumTracks{$album}}) {
				push @{$listRef}, $trackToPosition{$track};
			}
		}
	}

	for (my $i = 0; $i < $songcount; $i++) {

		for (my $j = 0; $j <= $#$queue; $j++) {

			if (defined($realqueue[$j]) && defined $listRef->[$i] && $realqueue[$j] == $listRef->[$i]) {

				$queue->[$j]->index($i);
			}
		}
	}

	for my $song (@$queue) {
		if ($song->index() >= $songcount) {
			$song->index(0);
		}
	}

	# If we just changed order in the reshuffle and we're already streaming
	# the next song, flush the streaming song since it's probably not next.
	if (shuffle($client) && 
		Slim::Player::Source::playingSongIndex($client) != Slim::Player::Source::streamingSongIndex($client)) {

		Slim::Player::Source::flushStreamingSong($client);
	}

	refreshPlaylist($client);
}

sub scheduleWriteOfPlaylist {
	my ($client, $playlistObj) = @_;

	# This should proably be more configurable / have writeM3U or a
	# wrapper know about the scheduler, so we can write out a file at a time.
	#
	# Need to fork!
	#
	# This can happen if the user removes the
	# playlist - because this is a closure, we get
	# a bogus object back)
	if (!blessed($playlistObj) || !$playlistObj->can('tracks') || !Slim::Utils::Misc::getPlaylistDir()) {

		return 0;
	}

	if ($playlistObj->title eq Slim::Utils::Strings::string('UNTITLED')) {

		logger('player.playlist')->warn("Not writing out untitled playlist.");

		return 0;
	}

	Slim::Formats::Playlists::M3U->write( 
		[ $playlistObj->tracks ],
		undef,
		$playlistObj->path,
		1,
		defined($client) ? Slim::Player::Source::playingSongIndex($client) : 0,
	);
}

sub removePlaylistFromDisk {
	my $playlistObj = shift;

	if (!$playlistObj->can('path')) {
		return;
	}

	my $path = $playlistObj->path;

	if (-e $path) {

		unlink $path;

	} else {

		unlink catfile(Slim::Utils::Misc::getPlaylistDir(), $playlistObj->title . '.m3u');
	}
}


sub newSongPlaylist {
	my $client = shift || return;
	my $reset = shift;
	
	main::DEBUGLOG && logger('player.playlist')->debug("Begin function - reset: " . ($reset || 'false'));

	return if Slim::Player::Playlist::shuffle($client);
	return if !Slim::Utils::Misc::getPlaylistDir();
	
	my $playlist = '';

	if ($client->currentPlaylist && blessed($client->currentPlaylist)) {

		$playlist = $client->currentPlaylist->path;

	} else {

		$playlist = $client->currentPlaylist;
	}

	return if Slim::Music::Info::isRemoteURL($playlist);

	main::INFOLOG && logger('player.playlist')->info("Calling writeCurTrackForM3U()");

	Slim::Formats::Playlists::M3U->writeCurTrackForM3U(
		$playlist,
		$reset ? 0 : Slim::Player::Source::playingSongIndex($client)
	);
}


sub newSongPlaylistCallback {
	my $request = shift;

	main::DEBUGLOG && logger('player.playlist')->debug("Begin function");

	my $client = $request->client() || return;
	
	newSongPlaylist($client)
}


sub modifyPlaylistCallback {
	my $request = shift;
	
	my $client  = $request->client();

	main::INFOLOG && $log->info("Checking if persistPlaylists is set..");

	if ( !$client || !$prefs->get('persistPlaylists') ) {
		main::DEBUGLOG && $log->debug("no client or persistPlaylists not set, not saving playlist");
		return;
	}
	
	# If Random Play mode is active, we don't save the playlist
	if (   exists $INC{'Slim/Plugin/RandomPlay/Plugin.pm'} 
		&& Slim::Plugin::RandomPlay::Plugin::active($client)
	) {
		main::DEBUGLOG && $log->debug("Random play mode active, not saving playlist");
		return;
	}

	my $savePlaylist = $request->isCommand([['playlist'], [keys %validSubCommands]]);

	# Did the playlist or the current song change?
	my $saveCurrentSong = 
		$savePlaylist || 
		$request->isCommand([['playlist'], ['open']]) || 
		($request->isCommand([['playlist'], ['jump', 'index', 'shuffle']]));

	if (!$saveCurrentSong) {
		main::INFOLOG && $log->info("saveCurrentSong not set. returing.");
		return;
	}

	main::INFOLOG && $log->info("saveCurrentSong is: [$saveCurrentSong]");

	my @syncedclients = ($client->controller()->allPlayers());

	my $playlist = Slim::Player::Playlist::playList($client);
	my $currsong = (Slim::Player::Playlist::shuffleList($client))->[Slim::Player::Source::playingSongIndex($client)];

	$client->currentPlaylistChangeTime(Time::HiRes::time());

	for my $eachclient (@syncedclients) {

		# Don't save all the tracks again if we're just starting up!
		if (!$eachclient->startupPlaylistLoading && $savePlaylist) {

			if ( main::INFOLOG && $log->is_info ) {
				$log->info("Saving client playlist for: ", $eachclient->id);
			}

			# Create a virtual track that is our pointer
			# to the list of tracks that make up this playlist.
			my $playlistTitle = sprintf('%s - %s', 
						Slim::Utils::Unicode::utf8encode($eachclient->string('NOW_PLAYING')),
						Slim::Utils::Unicode::utf8encode($eachclient->name ||  $eachclient->ip),
					);

			my $playlistUrl = _playlistUrlForClient($client) or next;
			
			Slim::Formats::Playlists::M3U->write( 
				$playlist,
				$playlistTitle,
				Slim::Utils::Misc::pathFromFileURL($playlistUrl),
				1,
				defined($client) ? Slim::Player::Source::playingSongIndex($client) : 0,
			);
		}

		if ($saveCurrentSong) {
			$prefs->client($eachclient)->set('currentSong', $currsong);
		}
	}

	# Because this callback is asyncronous, reset the flag here.
	# there's only one place that sets it - in Client::startup()
	if ($client->startupPlaylistLoading) {

		main::INFOLOG && $log->info("Resetting startupPlaylistLoading flag.");

		$client->startupPlaylistLoading(0);
	}
}

# restore the old playlist if we aren't already synced with somebody (that has a playlist)
sub loadClientPlaylist {
	my ($client, $callback) = @_;
	
	return if ($client->isSynced() || !$prefs->get('persistPlaylists'));

	my $url = _playlistUrlForClient($client) or return;
	my @tracks = Slim::Formats::Playlists::M3U->read(Slim::Utils::Misc::pathFromFileURL($url), undef, $url);
	my $currsong = $prefs->client($client)->get('currentSong');

	# Only add on to the playlist if there are tracks.
	if (scalar @tracks && defined $tracks[0] && blessed($tracks[0]) && $tracks[0]->id) {

		$client->debug("found nowPlayingPlaylist - will loadtracks");

		# We don't want to re-setTracks on load - so mark a flag.
		$client->startupPlaylistLoading(1);

		$client->execute(
			['playlist', 'addtracks', 'listref', \@tracks ],
			$callback, [$client, $currsong],
		);
	}
}

sub _playlistUrlForClient {
	my $client = shift;
	
	my $id = $client->id();
	$id =~ s/://g;

	return Slim::Utils::Misc::fileURLFromPath(
		catfile(Slim::Utils::OSDetect::dirsFor('prefs'), "clientplaylist_$id.m3u")
	);
}


1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
