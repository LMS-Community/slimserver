package Slim::Player::Playlist;

# SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use Slim::Control::Command;
use Slim::Player::Source;
use Slim::Player::Sync;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

our %validSubCommands = map { $_ => 1 } qw(play append load_done loadalbum addalbum loadtracks addtracks clear delete move sync);

#
# accessors for playlist information
#
sub count {
	my $client = shift;
	return scalar(@{playList($client)});
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

	if (defined ${shuffleList($client)}[$index]) {
		return ${playList($client)}[${shuffleList($client)}[$index]];
	} else {
		return ${playList($client)}[$index];
	}
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
		Slim::Utils::Prefs::clientSet($client, "shuffle", $shuffle);
	}
	
	return Slim::Utils::Prefs::clientGet($client, "shuffle");
}

sub repeat {
	my $client = shift;
	my $repeat = shift;
	
	$client = Slim::Player::Sync::masterOrSelf($client);

	if (defined($repeat)) {
		Slim::Utils::Prefs::clientSet($client, "repeat", $repeat);
	}
	
	return Slim::Utils::Prefs::clientGet($client, "repeat");
}

# NOTE:
#
# If you are trying to control playback, try to use Slim::Control::Command::execute() instead of 
# calling the functions below.
#

sub copyPlaylist {
	my $toclient   = shift;
	my $fromclient = shift;

	@{$toclient->playlist}    = @{$fromclient->playlist};
	@{$toclient->shufflelist} = @{$fromclient->shufflelist};

	Slim::Player::Source::streamingSongIndex($toclient, Slim::Player::Source::streamingSongIndex($fromclient));

	Slim::Utils::Prefs::clientSet($toclient, "shuffle", Slim::Utils::Prefs::clientGet($fromclient, "shuffle"));
	Slim::Utils::Prefs::clientSet($toclient, "repeat", Slim::Utils::Prefs::clientGet($fromclient, "repeat"));
}

sub removeTrack {
	my $client = shift;
	my $tracknum = shift;
	
	my $playlistIndex = ${shuffleList($client)}[$tracknum];

	my $stopped = 0;
	my $oldmode = Slim::Player::Source::playmode($client);
	
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
			if ($tracknum < $song->{index}) {
				$song->{index}--;
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
		if ($oldmode eq "play") {
			Slim::Player::Source::jumpto($client, $tracknum);
		} else {
			Slim::Player::Source::streamingSongIndex($client, $tracknum, 1);
		}
	}

	refreshPlaylist($client,Slim::Buttons::Playlist::browseplaylistindex($client));
}

sub removeMultipleTracks {
	my $client = shift;
	my $songlist = shift;

	my %songlistentries;
	if (defined($songlist) && ref($songlist) eq 'ARRAY') {

		for my $item (@$songlist) {
			$songlistentries{$item} = 1;
		}
	}

	my $stopped = 0;
	my $oldmode = Slim::Player::Source::playmode($client);
	
	my $playingtrack = ${shuffleList($client)}[Slim::Player::Source::playingSongIndex($client)];
	my $streamingtrack = ${shuffleList($client)}[Slim::Player::Source::streamingSongIndex($client)];

	my $i = 0;
	my $oldcount = 0;
	# going to need to renumber the entries in the shuffled list
	# will need to map the old position numbers to where the track ends
	# up after all the deletes occur
	my %oldToNew = () ;
 
	while ($i <= $#{playList($client)}) {
		#check if this file meets all criteria specified
		my $thistrack=${playList($client)}[$i];
		if (exists($songlistentries{$thistrack})) {
			splice(@{playList($client)}, $i, 1);
			if ($playingtrack == $oldcount) {
				Slim::Player::Source::playmode($client, "stop");
				$stopped = 1;
			}
			elsif ($streamingtrack == $oldcount) {
				Slim::Player::Source::flushStreamingSong($client);
			}
		} else {
			$oldToNew{$oldcount}=$i;
			$i++;
		}
		$oldcount++;
	}
	
	my @reshuffled;
	my $newtrack;
	my $getnext = 0;
	my %oldToNewShuffled = ();
	my $j = 0;
	# renumber all of the entries in the shuffle list with their 
	# new positions, also get an update for the current track, if the 
	# currently playing track was deleted, try to play the next track 
	# in the new list

	while ($j <= $#{shuffleList($client)}) {
		my $oldnum = shuffleList($client)->[$j];
		if ($oldnum == $playingtrack) { $getnext=1; }
		if (exists($oldToNew{$oldnum})) { 
			push(@reshuffled,$oldToNew{$oldnum});
			$oldToNewShuffled{$j} = $#reshuffled;
			if ($getnext) {
				$newtrack=$#reshuffled;
				$getnext=0;
			}
		}
		$j++;
	}

	# if we never found a next, we deleted eveything after the current
	# track, wrap back to the beginning
	if ($getnext) {	$newtrack=0; }

	$client = Slim::Player::Sync::masterOrSelf($client);
	
	@{$client->shufflelist} = @reshuffled;

	if ($stopped && ($oldmode eq "play")) {
		Slim::Player::Source::jumpto($client,$newtrack);
	}
	else {
		my $queue = $client->currentsongqueue();
		for my $song (@{$queue}) {
			$song->{index} = $oldToNewShuffled{$song->{index}} || 0;
		}
	}

	refreshPlaylist($client);
}

sub forgetClient {
	my $client = shift;

	# clear out the playlist
	Slim::Control::Command::execute($client, ["playlist", "clear"]);
	
	# trying to play will close out any open files.
	Slim::Control::Command::execute($client, ["play"]);
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
}

sub moveSong {
	my $client = shift;
	my $src = shift;
	my $dest = shift;
	my $size = shift;
	my $listref;
	
	if (!defined($size)) {
		$size = 1;
	}

	if (defined $dest && $dest =~ /^[\+-]/) {
		$dest = $src + $dest;
	}

	if (defined $src && defined $dest && 
		$src < Slim::Player::Playlist::count($client) && 
		$dest < Slim::Player::Playlist::count($client) && $src >= 0 && $dest >= 0) {

		if (Slim::Player::Playlist::shuffle($client)) {
			$listref = Slim::Player::Playlist::shuffleList($client);
		} else {
			$listref = Slim::Player::Playlist::playList($client);
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

			Slim::Player::Playlist::refreshPlaylist($client);
		}
	}
}

sub clear {
	my $client = shift;

	@{Slim::Player::Playlist::playList($client)} = ();

	Slim::Player::Playlist::reshuffle($client);
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
	my $client = shift;
	my $dontpreservecurrsong = shift;

	my $songcount = count($client);
	my $listRef   = shuffleList($client);

	unless ($songcount) {

		@{$listRef} = ();

		Slim::Player::Source::streamingSongIndex($client, 0);
		refreshPlaylist($client);

		return;
	}

	my $realsong = ${$listRef}[Slim::Player::Source::playingSongIndex($client)];

	if (!defined($realsong) || $dontpreservecurrsong) {
		$realsong = -1;
	} elsif ($realsong > $songcount) {
		$realsong = $songcount;
	}

	my @realqueue;
	my $song;
	my $queue = $client->currentsongqueue();
	for $song (@$queue) {
		push @realqueue, ${$listRef}[$song->{index}];
	}

	@{$listRef} = (0 .. ($songcount - 1));

	if (shuffle($client) == 1) {

		fischer_yates_shuffle($listRef);

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

	} elsif (shuffle($client) == 2) {

		my %albtracks;
		my %trackToNum;
		my $i  = 0;
		my $ds = Slim::Music::Info::getCurrentDataStore();

		for my $track (@{playList($client)}) {

			my $trackObj = $ds->objectForUrl($track);

			if (defined $trackObj && ref($trackObj)) {

				my $album = Slim::Utils::Text::matchCase($trackObj->album()->title()) || $client->string('NO_ALBUM');

				push @{$albtracks{$album}}, $i;

				$trackToNum{$trackObj->url} = $i++;

			} else {

				Slim::Utils::Misc::msg("Couldn't find an object for url: $track\n");
				Slim::Utils::Misc::bt();
			}
		}

		if ($realsong == -1 && !$dontpreservecurrsong) {
			$realsong = $listRef->[Slim::Utils::Prefs::clientGet($client,'currentSong')];
		}

		my $curtrack = $ds->objectForUrl(${playList($client)}[$realsong]);

		my $curalbum = Slim::Utils::Text::matchCase($curtrack->album()) || $client->string('NO_ALBUM');

		my @albums = keys(%albtracks);

		fischer_yates_shuffle(\@albums);

		for (my $i = 0; $i <= $#albums && $realsong != -1; $i++) {

			my $album = shift(@albums);

			if ($album ne $curalbum) {
				push(@albums,$album);
			} else {
				unshift(@albums,$album);
				last;
			}
		}

		my @shufflelist = ();
		my $album = shift(@albums);
		my @albumorder = map { ${playList($client)}[$_] } @{$albtracks{$album}};

		@albumorder = Slim::Music::Info::sortByAlbum(@albumorder);
		$i = 0;

		for my $trackname (@albumorder) {

			push @shufflelist, $trackToNum{$trackname};
			$i++
		}

		for my $album (@albums) {

			my @albumorder = map { ${playList($client)}[$_] } @{$albtracks{$album}};

			@albumorder = Slim::Music::Info::sortByAlbum(@albumorder);

			for my $trackname (@albumorder) {
				push @shufflelist, $trackToNum{$trackname};
			}
		}

		@{$listRef} = @shufflelist;
	} 
	
	for (my $i = 0; $i < $songcount; $i++) {
		for (my $j = 0; $j <= $#$queue; $j++) {
			if (defined($realqueue[$j]) && $realqueue[$j] == $listRef->[$i]) {
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

	refreshPlaylist($client);
}

# DEPRICATED
# for backwards compatibility with plugins and the like, this stuff was moved to Slim::Control::Command
sub executecommand {
	Slim::Control::Command::execute(@_);
}

sub setExecuteCommandCallback {
	Slim::Control::Command::setExecuteCallback(@_);
}

sub clearExecuteCommandCallback {
	Slim::Control::Command::clearExecuteCallback(@_);
}

sub modifyPlaylistCallback {
	my $client = shift;
	my $paramsRef = shift;

	if ($client && Slim::Utils::Prefs::get('playlistdir') && Slim::Utils::Prefs::get('persistPlaylists')) {

		my $command    = $paramsRef->[0];
		my $subCommand = $paramsRef->[1];

		# Did the playlist change?
		my $saveplaylist = $command eq 'playlist' && $validSubCommands{$subCommand};

		# Did the playlist or the current song change?
		my $savecurrsong = $saveplaylist || $command eq 'open' || 
			($command eq 'playlist' && $subCommand =~ /^(jump|index|shuffle)$/);

		return if !$savecurrsong;

		my @syncedclients = Slim::Player::Sync::syncedWith($client);
		push @syncedclients,$client;
		my $playlistref = Slim::Player::Playlist::playList($client);
		my $currsong = (Slim::Player::Playlist::shuffleList($client))->[Slim::Player::Source::playingSongIndex($client)];

		$client->currentPlaylistChangeTime(time());

		for my $eachclient (@syncedclients) {

			if ($saveplaylist) {
				my $playlistname = "__" . $eachclient->id() . ".m3u";
				$playlistname =~ s/\:/_/g;
				$playlistname = catfile(Slim::Utils::Prefs::get('playlistdir'),$playlistname);
				Slim::Formats::Parse::writeM3U($playlistref,$playlistname,$playlistname);
			}

			if ($savecurrsong) {
				Slim::Utils::Prefs::clientSet($eachclient,'currentSong',$currsong);
			}
		}
	}
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
