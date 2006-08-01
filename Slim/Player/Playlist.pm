package Slim::Player::Playlist;

# SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use Scalar::Util qw(blessed);

use Slim::Control::Command;
use Slim::Formats::Playlists::M3U;
use Slim::Player::Source;
use Slim::Player::Sync;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

our %validSubCommands = map { $_ => 1 } qw(play append load_done loadalbum addalbum loadtracks addtracks clear delete move sync);

our %shuffleTypes = (
	1 => 'track',
	2 => 'album',
);

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
	my $client = shift;
	my $index = shift;

	if (count($client) == 0) {
		return;
	}

	if (!defined($index)) {
		$index = Slim::Player::Source::playingSongIndex($client);
	}

	my $objOrUrl;

	if (defined ${shuffleList($client)}[$index]) {

		$objOrUrl = ${playList($client)}[${shuffleList($client)}[$index]];

	} else {

		$objOrUrl = ${playList($client)}[$index];
	}

	if ($objOrUrl && !blessed($objOrUrl)) {

		 $objOrUrl = Slim::Schema->rs('Track')->objectForUrl({
			'url'      => $objOrUrl,
			'create'   => 1,
			'readTags' => 1,
		});
	}

	return $objOrUrl;
}

sub url {
	my $objOrUrl = song( @_ );

	return ( blessed $objOrUrl ) ? $objOrUrl->url : $objOrUrl;
}

sub shuffleList {
	my ($client) = shift;
	
	$client = Slim::Player::Sync::masterOrSelf($client);
	
	return $client->shufflelist;
}

sub playList {
	my ($client) = shift;

	$client = Slim::Player::Sync::masterOrSelf($client);
	
	return $client->playlist;
}

sub shuffle {
	my $client = shift;
	my $shuffle = shift;
	
	$client = Slim::Player::Sync::masterOrSelf($client);

	if (defined($shuffle)) {
		$client->prefSet("shuffle", $shuffle);
	}
	
	return $client->prefGet("shuffle");
}

sub repeat {
	my $client = shift;
	my $repeat = shift;
	
	$client = Slim::Player::Sync::masterOrSelf($client);

	if (defined($repeat)) {
		$client->prefSet("repeat", $repeat);
	}
	
	return $client->prefGet("repeat");
}

# NOTE:
#
# If you are trying to control playback, try to use Slim::Control::Command::execute() instead of 
# calling the functions below.
#

sub copyPlaylist {
	my $toClient   = shift;
	my $fromClient = shift;

	@{$toClient->playlist}    = @{$fromClient->playlist};
	@{$toClient->shufflelist} = @{$fromClient->shufflelist};

	Slim::Player::Source::streamingSongIndex($toClient, Slim::Player::Source::streamingSongIndex($fromClient), 1);

	$toClient->prefSet("shuffle", $fromClient->prefGet("shuffle"));
	$toClient->prefSet("repeat", $fromClient->prefGet("repeat"));
}

sub removeTrack {
	my $client = shift;
	my $tracknum = shift;
	
	my $playlistIndex = ${shuffleList($client)}[$tracknum];

	my $stopped = 0;
	my $oldMode = Slim::Player::Source::playmode($client);
	
	if (Slim::Player::Source::playingSongIndex($client) == $tracknum) {
		$::d_source && msg("Removing currently playing track.\n");

		Slim::Player::Source::playmode($client, "stop");
		$stopped = 1;

	} elsif (Slim::Player::Source::streamingSongIndex($client) == $tracknum) {
		# If we're removing the streaming song (which is different from
		# the playing song), get the client to flush out the current song
		# from its audio pipeline.
		$::d_source && msg("Removing currently streaming track.\n");
		Slim::Player::Source::flushStreamingSong($client);

	} else {

		my $queue = $client->currentsongqueue();

		for my $song (@$queue) {

			if ($tracknum < $song->{'index'}) {
				$song->{'index'}--;
			}
		}
	}
	
	splice(@{playList($client)}, $playlistIndex, 1);

	my @reshuffled;
	my $counter = 0;
	for my $i (@{shuffleList($client)}) {
		if ($i < $playlistIndex) {
			push @reshuffled, $i;
		} elsif ($i > $playlistIndex) {
			push @reshuffled, ($i - 1);
		}
	}
	
	$client = Slim::Player::Sync::masterOrSelf($client);
	
	@{$client->shufflelist} = @reshuffled;

	if ($stopped) {
		my $songcount = scalar(@{playList($client)});
		if ($tracknum >= $songcount) {
			$tracknum = $songcount - 1;
		}
		if ($oldMode eq "play") {
			Slim::Player::Source::jumpto($client, $tracknum);
		} else {
			Slim::Player::Source::streamingSongIndex($client, $tracknum, 1);
		}
	}

	refreshPlaylist($client,Slim::Buttons::Playlist::showingNowPlaying($client) ?
		undef : 
		Slim::Buttons::Playlist::browseplaylistindex($client));
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

		if ($trackEntries{$thisTrack->url}) {

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

	$client = Slim::Player::Sync::masterOrSelf($client);
	
	@{$client->shufflelist} = @reshuffled;

	if ($stopped && ($oldMode eq "play")) {

		Slim::Player::Source::jumpto($client,$newTrack);

	} else {

		my $queue = $client->currentsongqueue();

		for my $song (@{$queue}) {
			$song->{'index'} = $oldToNewShuffled{$song->{'index'}} || 0;
		}
	}

	refreshPlaylist($client);
}

sub refreshPlaylist {
	my $client = shift;
	my $index = shift;

	# make sure we're displaying the new current song in the playlist view.
	for my $everybuddy ($client, Slim::Player::Sync::syncedWith($client)) {
		if ($everybuddy->isPlayer()) {
			Slim::Buttons::Playlist::jump($everybuddy,$index);
		}
	}
	
	$client->sendParent( {
		command => 'refreshPlaylist',
		index   => $index,
	} );
}

sub moveSong {
	my $client = shift;
	my $src = shift;
	my $dest = shift;
	my $size = shift;
	my $listref;
	
	$client = Slim::Player::Sync::masterOrSelf($client);
	
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
				my $index = $song->{index};
				if ($src == $index) {
					$song->{index} = $dest;
				}
				elsif (($dest == $index) || (($src < $index) != ($dest < $index))) {
					$song->{index} = ($dest>$src)? $index - 1 : $index + 1;
				}
			}

			refreshPlaylist($client);
		}
	}
}

sub clear {
	my $client = shift;

	@{playList($client)} = ();
	$client->currentPlaylist(undef);

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
	my $client = Slim::Player::Sync::masterOrSelf(shift);
	my $dontpreservecurrsong = shift;
  
	my $songcount = count($client);
	my $listRef   = shuffleList($client);

	unless ($songcount) {

		@{$listRef} = ();

		Slim::Player::Source::streamingSongIndex($client, 0, 1);
		refreshPlaylist($client);

		return;
	}

	my $realsong = ${$listRef}[Slim::Player::Source::playingSongIndex($client)];

	if (!defined($realsong) || $dontpreservecurrsong) {
		$realsong = -1;
	} elsif ($realsong > $songcount) {
		$realsong = $songcount;
	}
	
	$::d_playlist && msgf("Reshuffling, current song index: %d, preserve song? %s\n",
		$realsong,
		( $dontpreservecurrsong ) ? 'no' : 'yes',
	);

	my @realqueue;
	my $song;
	my $queue = $client->currentsongqueue();
	for $song (@$queue) {
		push @realqueue, ${$listRef}[$song->{index}];
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

				$::d_playlist && msg("Track: $track isn't an object - fetching\n");

				$trackObj = Slim::Schema->rs('Track')->objectForUrl($track);
			}

			# Pull out the album id, and accumulate all of the
			# tracks for that album into a hash. Also map that
			# object to a poisition in the playlist.
			if (blessed($trackObj) && $trackObj->can('albumid')) {

				my $albumid = $trackObj->albumid() || 0;

				push @{$albumTracks{$albumid}}, $trackObj;

				$trackToPosition{$trackObj} = $i++;

			} else {

				msg("Couldn't find an object for url: $track\n");
				bt();
			}
		}

		# Not quite sure what this is doing - not changing the current song?
		if ($realsong == -1 && !$dontpreservecurrsong) {

			my $index = $client->prefGet('currentSong');

			if (defined $index && defined $listRef->[$index]) {
				$realsong = $listRef->[$index];
			}
		}

		my $currentTrack = ${playList($client)}[$realsong];
		my $currentAlbum = 0;

		# This shouldn't happen - but just in case.
		if (!blessed($currentTrack) || !$currentTrack->can('albumid')) {
			$currentTrack = Slim::Schema->rs('Track')->objectForUrl($currentTrack);
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
				$queue->[$j]->{index} = $i;
			}
		}
	}

	for $song (@$queue) {
		if ($song->{index} >= $songcount) {
			$song->{index} = 0;
		}
	}

	# If we just changed order in the reshuffle and we're already streaming
	# the next song, flush the streaming song since it's probably not next.
	if (shuffle($client) && 
		Slim::Player::Source::playingSongIndex($client) != Slim::Player::Source::streamingSongIndex($client)) {
		Slim::Player::Source::flushStreamingSong($client);
	}
	elsif ($client->playmode() eq 'playout-stop' &&
		   Slim::Player::Source::playingSongIndex($client) != (count($client) - 1)) {
		Slim::Player::Source::playmode($client, 'playout-play');
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
	if (!blessed($playlistObj) || !$playlistObj->can('tracks') || !Slim::Utils::Prefs::get('playlistdir')) {

		return 0;
	}

	if ($playlistObj->title eq $client->string('UNTITLED')) {

		$::d_playlist && msg("scheduleWriteOfPlaylist: Not writing out untitled playlist.\n");

		return 0;
	}

	Slim::Formats::Playlists::M3U->write( 
		[ $playlistObj->tracks ],
		undef,
		$playlistObj->path,
		1,
		Slim::Player::Source::playingSongIndex($client),
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

		unlink catfile(Slim::Utils::Prefs::get('playlistdir'), $playlistObj->title . '.m3u');
	}
}

sub newSongPlaylistCallback {
	my $request = shift;
	
	my $client = $request->client();

	my $playlist = '';

	if ($client->currentPlaylist && blessed($client->currentPlaylist)) {

		$playlist = $client->currentPlaylist->path;

	} else {

		$playlist = $client->currentPlaylist;
	}

	return if Slim::Music::Info::isRemoteURL($playlist) || Slim::Player::Playlist::shuffle($client);

	if (Slim::Utils::Prefs::get('playlistdir')) {

		$::d_playlist && msg("newSongPlaylistCallback() writeCurTrackForM3U()\n");

		Slim::Formats::Playlists::M3U->writeCurTrackForM3U(
			$playlist,
			$request->getParam('reset') ? 0 : Slim::Player::Source::playingSongIndex($client)
		);
	}
}

sub modifyPlaylistCallback {
	my $request = shift;
	
	my $client = $request->client();
	
	if ($client && Slim::Utils::Prefs::get('persistPlaylists')) {

		my $saveplaylist = $request->isCommand([['playlist'], [keys %validSubCommands]]);

		# Did the playlist or the current song change?
		my $savecurrsong = 
			$saveplaylist || 
			$request->isCommand([['playlist'], ['open']]) || 
			($request->isCommand([['playlist'], ['jump', 'index', 'shuffle']]));

		$::d_playlist && msg("modifyPlaylistCallback: savecurrsong is $savecurrsong\n");

		return if !$savecurrsong;

		my @syncedclients = (Slim::Player::Sync::syncedWith($client), $client);

		my $playlist = Slim::Player::Playlist::playList($client);
		my $currsong = (Slim::Player::Playlist::shuffleList($client))->[Slim::Player::Source::playingSongIndex($client)];

		$client->currentPlaylistChangeTime(time());

		for my $eachclient (@syncedclients) {

			# Don't save all the tracks again if we're just starting up!
			if (!$eachclient->startupPlaylistLoading && $saveplaylist) {

				$::d_playlist && msgf("modifyPlaylistCallback: finding client playlist for: [%s]\n", $eachclient->id);

				# Create a virtual track that is our pointer
				# to the list of tracks that make up this playlist.
				my $playlistObj = Slim::Schema->rs('Playlist')->updateOrCreate({

					'url'        => sprintf('clientplaylist://%s', $eachclient->id),
					'attributes' => {
						'TITLE' => sprintf('%s - %s', 
							Slim::Utils::Unicode::utf8encode($eachclient->string('NOW_PLAYING')),
							Slim::Utils::Unicode::utf8encode($eachclient->name ||  $eachclient->ip),
						),

						'CT'    => 'cpl',
					},
				});

				if (defined $playlistObj) {

					$::d_playlist && msg("modifyPlaylistCallback: calling setTracks()\n");

					$playlistObj->setTracks($playlist);
				}
			}

			if ($savecurrsong) {
				Slim::Utils::Prefs::clientSet($eachclient, 'currentSong', $currsong);
			}
		}

		# Because this callback is asyncronous, reset the flag here.
		# there's only one place that sets it - in Client::startup()
		if ($client->startupPlaylistLoading) {

			$::d_playlist && msg("modifyPlaylistCallback: resetting startupPlaylistLoading flag.\n");

			$client->startupPlaylistLoading(0);
		}
	}
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
