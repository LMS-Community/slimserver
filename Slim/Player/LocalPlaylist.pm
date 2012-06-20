package Slim::Player::LocalPlaylist;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Spec::Functions qw(catfile);
use Scalar::Util qw(blessed);

use Slim::Formats::Playlists::M3U;
use Slim::Player::Source;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

our %validSubCommands = map { $_ => 1 } qw(play append load_done loadalbum addalbum loadtracks playtracks addtracks inserttracks deletetracks clear delete move sync);

our %shuffleTypes = (
	1 => 'track',
	2 => 'album',
);

my $log = logger('player.playlist');

sub new {
	my ($class, $client) = @_;
	my $self = {
		items       => $client->playlist,
		shuffled    => [],
	};
	
	bless $self, $class;
	return $self;
}

#
# accessors for playlist information
#
sub count {
	return scalar(@{shift->{'items'}});
}

sub shuffleType {
	# my ($self, $client) = @_;

	my $shuffleMode = shuffle(@_);

	if (defined $shuffleTypes{$shuffleMode}) {
		return $shuffleTypes{$shuffleMode};
	}

	return 'none';
}

sub song {
	my ($self, $client, $index, $refresh, $useShuffled) = @_;
	$refresh ||= 0;
	$useShuffled = 1 unless defined $useShuffled;

	if ($self->count() == 0) {
		return;
	}

	if (!defined($index)) {
		$index = Slim::Player::Source::playingSongIndex($client);
	}

	my $objOrUrl;

	if ($useShuffled && defined $self->{'shuffled'}->[$index]) {

		$objOrUrl = $self->{'items'}->[$self->{'shuffled'}->[$index]];

	} else {

		$objOrUrl = $self->{'items'}->[$index];
	}

	if ( $objOrUrl && ($refresh || !blessed($objOrUrl)) ) {

		$objOrUrl = Slim::Schema->objectForUrl({
			'url'      => $objOrUrl,
			'create'   => 1,
			'readTags' => 1,
		});
		
		if ($refresh) {
			$objOrUrl = $self->refreshTrack($client, $objOrUrl->url);
		}
	}

	return $objOrUrl;
}

sub songs {
	my ($self, $client, $start, $end) = @_;

	if ($self->count() == 0) {
		return;
	}

	my @tracks;

	foreach (defined $self->{'shuffled'}->[$start]
				? (@{$self->{'items'}}[ @{$self->{'shuffled'}} ])[$start .. $end]
				: @{$self->{'items'}}[$start .. $end])
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
	my ( $self, $client, $url ) = @_;
	
	my $track = Slim::Schema->objectForUrl( {
		url      => $url,
		create   => 1,
		readTags => 1,
	} );
	
	my $i = 0;
	for my $item ( @{ $self->{'items'} } ) {
		my $itemUrl = blessed($item) ? $item->url : $item;
		if ( $itemUrl eq $url ) {
			$self->{'items'}->[$i] = $track;
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
	return shift->{'shuffled'};
}

sub playList {
	return shift->{'items'};
}

sub addTracks {
	my ($self, $client, $tracksRef, $position, undef, undef, $infoText, $icon) = @_;
	
	$position = -3 if !defined $position;
		
	my $playlist = $self->{'items'};
	
	@$playlist = () if $position == -2;
	
	my $maxPlaylistLength = $prefs->get('maxPlaylistLength');
	
	# How many tracks might we need to remove to make space?
	my $need = $maxPlaylistLength ? (scalar @{$playlist} + scalar @{$tracksRef}) - $maxPlaylistLength : 0;
	
	if ($need > 0) {
		# 1. If we have already-played stuff at the start of the playlist that we can remove, then remove that first
		my $canRemove = Slim::Player::Source::playingSongIndex($client) || 0;
		$canRemove = $need if $canRemove > $need;
		
		$canRemove = $position if ($position >= 0 && $position < $canRemove);

		if ($canRemove) {
			main::INFOLOG && $log->info("Removing $canRemove tracks from start of playlist");
			my $removed = $self->removeTrack($client, 0, $canRemove);
			$need -= $removed;
			$position -= $removed if $position > 0;
		}
	}
		
	if ($need > 0 && $position == -2) {
		# 2. If inserting, then try to remove stuff from the end of the playlist
		my $streamingSongIndex = Slim::Player::Source::streamingSongIndex($client) || 0;
		my $canRemove = $#{$playlist} - $streamingSongIndex;
		$canRemove = $need if $canRemove > $need;

		if ($canRemove) {
			main::INFOLOG && $log->info("Removing $canRemove tracks from end of playlist");
			$need -= $self->removeTrack($client, scalar @{$playlist} - $canRemove, $canRemove);
		}
	}
	
	if ($need > 0 && $position > (Slim::Player::Source::streamingSongIndex($client) || 0)) {
		my $canRemove = $#{$playlist} - $position;
		$canRemove = $need if $canRemove > $need;

		if ($canRemove) {
			main::INFOLOG && $log->info("Removing $canRemove tracks from end of playlist");
			$need -= $self->removeTrack($client, scalar @{$playlist} - $canRemove, $canRemove);
		}
	}
	
	$position = -3 if $position > scalar @{$playlist} - 1;
	
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
	} elsif ($infoText && ($position == -1 || $position == -3)) {
		if ($icon) {
			my @line = ($client->string(
				$position == -1
					? 'JIVE_POPUP_TO_PLAY_NEXT'
					: 'JIVE_POPUP_ADDING'),
				$infoText);
			$client->showBriefly({
					'line' => \@line,
					'jive' => {
						'type'    => 'mixed',
						'style'   => 'add',
						'text'    => \@line,
						'icon'    => $icon,
					}
				});
		} else {
			my $msg = $client->string(
				$position == -1
					? 'JIVE_POPUP_ADDING_TO_PLAY_NEXT'
					: 'JIVE_POPUP_ADDING_TO_PLAYLIST',
				$infoText);
			my @line = split("\n", $msg);
			$client->showBriefly({
					'line' => [ @line ],
					'jive' => { 'type' => 'popupplay', text => [ $msg ] },
				});
			
		}
	}
	
	if ($position > -2) {
		_insert_done($self, $client, $canAdd, $position);
	}
	
	return $canAdd;
}

sub _insert_done {
	my ($self, $client, $size, $to) = @_;

	$to = Slim::Player::Source::streamingSongIndex($client)+1 if $to == -1;
	my $moveFrom = $self->count() - $size;

	if ($self->shuffle($client)) {
		my @reshuffled = ($moveFrom .. ($moveFrom + $size - 1));
		if ($self->count() != $size) {	
			splice @{$self->{'shuffled'}}, $to, 0, @reshuffled;
		} else {
			push @{$self->{'shuffled'}}, @reshuffled;
		}
	} else {
		if ($self->count() != $size) {
			$self->moveSong($client, $moveFrom, $to, $size);
		}
		$self->reshuffle($client);
	}

	$self->refreshPlaylist($client);
}

sub shuffle {
	my ($self, $client, $shuffle) = @_;
	
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
	my ($self, $client, $repeat) = @_;
	
	if (defined($repeat)) {
		$prefs->client($client)->set('repeat', $repeat);
	}
	
	return $prefs->client($client)->get('repeat');
}

sub copyPlaylist {
	my ($self, $toClient, $fromClient, $noQueueReset) = @_;

	my $from = $fromClient->getPlaylist();
	
	@{$self->{'items'}}    = @{$from->{'items'}};
	@{$self->{'shuffled'}} = @{$from->{'shuffled'}};

	$toClient->controller()->resetSongqueue(Slim::Player::Source::streamingSongIndex($fromClient)) unless $noQueueReset;

	$self->shuffle($toClient, $prefs->client($fromClient)->get('shuffle'));
	$self->repeat($toClient, $prefs->client($fromClient)->get('repeat'));
}

sub removeTrack {
	my ($self, $client, $tracknum, $nTracks) = @_;
	$nTracks ||= 1;
	
	my $log     = logger('player.source');

	if ($tracknum > $self->count() - 1) {
		$log->warn("Attempting to remove track(s) $tracknum beyond end of playlist");
		return 0;
	}	
	if ($tracknum + $nTracks > $self->count()) {
		$log->warn("Arrempting to remove too many tracks ($nTracks)");
		$nTracks = $self->count() - $tracknum;
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
	my $playlist = $self->{'items'};
	my $shufflelist = $self->{'shuffled'};
	if ($self->shuffle($client)) {
		
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
	$self->refreshPlaylist($client,
		Slim::Buttons::Playlist::showingNowPlaying($client) ?
			undef : 
			Slim::Buttons::Playlist::browseplaylistindex($client)
	) if main::IP3K;
	
	return $nTracks;
}

sub removeMultipleTracks {
	my ($self, $client, $tracks) = @_;

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

	my $playingTrackPos   = ${$self->{'shuffled'}}[Slim::Player::Source::playingSongIndex($client)];
	my $streamingTrackPos = ${$self->{'shuffled'}}[Slim::Player::Source::streamingSongIndex($client)];

	# going to need to renumber the entries in the shuffled list
	# will need to map the old position numbers to where the track ends
	# up after all the deletes occur
	my %oldToNew = ();
	my $i        = 0;
	my $oldCount = 0;
 
	while ($i <= $#{$self->{'items'}}) {

		#check if this file meets all criteria specified
		my $thisTrack = ${$self->{'items'}}[$i];

		if ($trackEntries{$thisTrack->url}) {

			splice(@{$self->{'items'}}, $i, 1);

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
	while ($j <= $#{$self->{'shuffled'}}) {

		my $oldNum = $self->{'shuffled'}->[$j];

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

	$self->{'shuffled'} = \@reshuffled;

	if ($stopped && ($oldMode eq "play")) {

		$client->execute([ 'playlist', 'jump', $newTrack ]);

	} else {

		my $queue = $client->currentsongqueue();

		for my $song (@{$queue}) {
			$song->index($oldToNewShuffled{$song->index()} || 0);
		}
	}

	$self->refreshPlaylist($client);
}

sub refreshPlaylist {
	my $self = shift;
	my $client = shift;
	my $index = shift;

	if (main::IP3K) {
		# make sure we're displaying the new current song in the playlist view.
		for my $everybuddy ($client->syncGroupActiveMembers()) {
			if ($everybuddy->isPlayer()) {
				Slim::Buttons::Playlist::jump($everybuddy,$index);
			}
		}
	}
}

sub moveSong {
	my ($self, $client, $src, $dest, $size) = @_;
	my $listref;
	
	if (!defined($size)) {
		$size = 1;
	}

	if (defined $dest && $dest =~ /^[\+-]/) {
		$dest = $src + $dest;
	}

	if (defined $src && defined $dest && 
		$src < $self->count() && 
		$dest < $self->count() && $src >= 0 && $dest >= 0) {

		if ($self->shuffle($client)) {
			$listref = $self->{'shuffled'};
		} else {
			$listref = $self->{'items'};
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

			$self->refreshPlaylist($client);
		}
	}
}

sub stopAndClear {
	my $self = shift;
	my $client = shift;
	
	# Bug 11447 - Have to stop player and clear song queue
	$client->controller->stop();
	$client->controller()->resetSongqueue();

	@{$self->{'items'}} = ();
	$client->currentPlaylist(undef);
	
	# Remove saved playlist if available
	my $playlistUrl = _playlistUrlForClient($client);
	unlink(Slim::Utils::Misc::pathFromFileURL($playlistUrl)) if $playlistUrl;

	$self->reshuffle($client);
}

#reshuffle - every time the playlist is modified, the shufflelist should be updated
#		We also invalidate the htmlplaylist at this point
sub reshuffle {
	my ($self, $client, $dontpreservecurrsong) = @_;
  
	my $songcount = $self->count();
	my $listRef   = $self->{'shuffled'};

	if (!$songcount) {

		@{$listRef} = ();

		$self->refreshPlaylist($client);

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
	if ($self->shuffle($client) == 1) {

		Slim::Player::Playlist::fischer_yates_shuffle($listRef);

		# If we're preserving the current song
		# this places it at the top of the playlist
		if ( $realsong > -1 ) {
			for (my $i = 0; $i < $songcount; $i++) {

				if ($listRef->[$i] == $realsong) {

					if ($self->shuffle($client)) {
					
						my $temp = $listRef->[$i];
						$listRef->[$i] = $listRef->[0];
						$listRef->[0] = $temp;
						$i = 0;
					}

					last;
				}
			}
		}

	} elsif ($self->shuffle($client) == 2) {

		my %albumTracks     = ();
		my %trackToPosition = ();
		my $i  = 0;

		my $defaultAlbumTitle = Slim::Utils::Text::matchCase($client->string('NO_ALBUM'));

		# Because the playList might consist of objects - we can avoid doing an extra objectForUrl call.
		for my $track (@{$self->{'items'}}) {

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

		my $currentTrack = ${$self->{'items'}}[$realsong];
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

		Slim::Player::Playlist::fischer_yates_shuffle(\@albums);

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
	if ($self->shuffle($client) && 
		Slim::Player::Source::playingSongIndex($client) != Slim::Player::Source::streamingSongIndex($client)) {

		Slim::Player::Source::flushStreamingSong($client);
	}

	$self->refreshPlaylist($client);
}

sub newSongPlaylist {
	my ($self, $client) = @_;
	
	main::DEBUGLOG && logger('player.playlist')->debug("Begin function");

	return if $self->shuffle($client);
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
		Slim::Player::Source::playingSongIndex($client)
	);
}


sub modifyPlaylistCallback {
	my ($self, $client, $request) = @_;
	
	main::INFOLOG && $log->info("Checking if persistPlaylists is set..");

	if ( !$prefs->get('persistPlaylists') ) {
		main::DEBUGLOG && $log->debug("persistPlaylists not set, not saving playlist");
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

	my $playlist = $self->{'items'};
	my $currsong = ($self->{'shuffled'})->[Slim::Player::Source::playingSongIndex($client)];

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
	my ($self, $client, $callback) = @_;
	
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
