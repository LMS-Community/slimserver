package Slim::Player::Playlist;

# Slim Server Copyright (C) 2001,2002,2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use FileHandle;
use IO::Socket qw(:DEFAULT :crlf);
use Time::HiRes;
use Slim::Control::Command;
use Slim::Display::Display;
use Slim::Utils::Misc;
use Slim::Utils::Scan;
use Slim::Utils::Strings qw(string);

my $CLIENTBUFFERLEN = (128 * 1024);

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
		$index = currentSongIndex($client);
	}
	return ${playList($client)}[${shuffleList($client)}[$index]];
}

sub shuffleList {
	my ($client) = shift;
	
	$client = masterOrSelf($client);
	
	return $client->shufflelist;
}

sub playList {
	my ($client) = shift;

	$client = masterOrSelf($client);
	
	return $client->playlist;
}

sub currentSongIndex {
	my $client = shift;
	my $newindex = shift;

	$client = masterOrSelf($client);
	
	if (defined($newindex)) {
		$client->currentsong($newindex);
	}
	
	return $client->currentsong;
}

sub shuffle {
	my $client = shift;
	my $shuffle = shift;
	
	$client = masterOrSelf($client);

	if (defined($shuffle)) {
		Slim::Utils::Prefs::clientSet($client, "shuffle", $shuffle);
	}
	
	return Slim::Utils::Prefs::clientGet($client, "shuffle");
}

sub repeat {
	my $client = shift;
	my $repeat = shift;
	
	$client = masterOrSelf($client);

	if (defined($repeat)) {
		Slim::Utils::Prefs::clientSet($client, "repeat", $repeat);
	}
	
	return Slim::Utils::Prefs::clientGet($client, "repeat");
}

sub songTime {
	my ($client) = shift;

	$client = masterOrSelf($client);

	if ($client->mp3filehandleIsSocket) {
		my $startTime = $client->remoteStreamStartTime;
		if ($startTime) {
			return Time::HiRes::time() - $startTime;
		} else {
			return 0;
		}
	}

	my $size = $client->songtotalbytes;
	my $duration = $client->songduration;
	my $byterate;
	if (!$duration) {
		$byterate = 0;
	} else {
		$byterate = $size / $duration;
	}

	my $songtime;
	if (!$size) {
		$songtime = 0;
	} else {
		$songtime = (songRealPos($client) / $size * $duration);
	}

	$::d_playlist && msg( "byterate = $byterate, size = $size, songpos = ".songRealPos($client)." songtime = $songtime\n");

	return($songtime);

}	

# the "real" position in the track, accounting for client and server-side buffering
# TODO include server-side buffering
# TODO this won't work when scanning in reverse
#
sub songRealPos {
	my ($client) = shift;

	$client = masterOrSelf($client);

	my $realpos = 0;
	if (defined($client->songpos) && defined(Slim::Networking::Stream::fullness($client))) {
		$realpos = $client->songpos - Slim::Networking::Stream::fullness($client);
	}

	if ($realpos<0) {
#		warn("came up with a negative position in the stream: ".
#		     "songpos = ".$client->songpos.", fullness = ".Slim::Networking::Stream::fullness($client)."\n");
		$realpos = 0;
	}
#	$::d_playlist && msg("songRealPos songPos: ". $client->songpos . " realpos: $realpos\n");
	return $realpos;	
}

# playmode - start playing, pause or stop
sub playmode {
	my($client, $newmode) = @_;

	assert($client);

	if (!defined($newmode)) {
		return $client->playmode;
	}
	
	$::d_playlist && $newmode && msg(Slim::Player::Client::id($client) . ": Switching to mode $newmode\n");

	my $prevmode = $client->playmode;

	if ($newmode eq $prevmode) {
		$::d_playlist && msg(" Already in playmode $newmode : ignoring mode change\n");
	} else {

		# if we're playing, then open the new song the master.		
		if ($newmode eq "play") {
			my $opened;
			
			# if the player is off, we automatically power on when we start to play
			if (!Slim::Player::Client::power($client)) {
				Slim::Player::Client::power($client, 1);
			}
			
			$opened = openSong(masterOrSelf($client));

			# if we couldn't open the song, then stop...
			if (!$opened) {
				$::d_playlist && msg("Couldn't open song.  Stopping.\n");
				$newmode = "stop";
			}
		}
		
		# when we change modes, make sure we do it to all the synced clients.
		foreach my $everyclient ($client, syncedWith($client)) {
			$::d_playlist && msg(" New play mode: " . $newmode . "\n");
			
			# wake up the display if we've switched modes.
			if (Slim::Player::Client::isPlayer($everyclient)) { Slim::Buttons::ScreenSaver::wakeup($everyclient); };
			
			# when you resume, you go back to play mode
			if (($newmode eq "resume") ||($newmode eq "resumenow")) {
				$everyclient->playmode("play");
				rate($everyclient, 1);
				
			} elsif ($newmode eq "pausenow") {
				$everyclient->playmode("pause");
				rate($everyclient, 0);
				
			} elsif ($newmode eq "playout") {
				$everyclient->playmode("stop");
				
			} else {
				$everyclient->playmode($newmode);
			}
	
			if ($newmode eq "stop") {
				$everyclient->currentplayingsong("");
			#	$everyclient->songpos(0);
				$::d_playlist && msg("Stopping and clearing out old chunks for client " . Slim::Player::Client::id($everyclient) . "\n");
				@{$everyclient->chunks} = ();

				Slim::Player::Control::stop($everyclient);
				closeSong($everyclient);
			} elsif ($newmode eq "play") {
				$everyclient->readytosync(0);
				rate($everyclient, 1);
				Slim::Player::Control::play($everyclient, Slim::Player::Playlist::isSynced($everyclient));				
			} elsif ($newmode eq "pause") {
				# since we can't count on the accuracy of the fade timers, we unfade them all, but the master calls back to unpause everybody
				if ($everyclient eq $client) {
					Slim::Player::Control::fade_volume($everyclient, -0.3125, \&pauseSynced, [$client]);
				} else {
					Slim::Player::Control::fade_volume($everyclient, -0.3125);
				}				
				
			} elsif ($newmode eq "pausenow") {
				Slim::Player::Control::pause($everyclient);
				rate($everyclient,0);
			} elsif ($newmode eq "resumenow") {
				Slim::Player::Control::resume($everyclient);
				rate($everyclient, 1);
				
			} elsif ($newmode eq "resume") {
				# set volume to 0 to make sure fade works properly
				Slim::Player::Control::volume($everyclient,0);
				Slim::Player::Control::resume($everyclient);
				Slim::Player::Control::fade_volume($everyclient, .3125);
				
			} elsif ($newmode eq "playout") {
				Slim::Player::Control::playout($everyclient);
				
			} else {
				$::d_playlist && msg(" Unknown play mode: " . $everyclient->playmode . "\n");
				return $everyclient->playmode();
			}
			
			refreshPlaylist($everyclient);
		}
	}
	$::d_playlist && msg(Slim::Player::Client::id($client) . ": Current playmode: " . $client->playmode() . "\n");

	return $client->playmode();
}

sub lastChunk {
	my $client = shift;
	return $client->lastchunk;
}

# NOTE:
#
# If you are trying to control playback, try to use Slim::Control::Command::execute() instead of 
# calling the functions below.
#

sub copyPlaylist {
	my $toclient = shift;
	my $fromclient = shift;

	@{$toclient->playlist} = @{$fromclient->playlist};
	@{$toclient->shufflelist} = @{$fromclient->shufflelist};
	$toclient->currentsong(	$fromclient->currentsong);	
	Slim::Utils::Prefs::clientSet($toclient, "shuffle", Slim::Utils::Prefs::clientGet($fromclient, "shuffle"));
	Slim::Utils::Prefs::clientSet($toclient, "repeat", Slim::Utils::Prefs::clientGet($fromclient, "repeat"));
}

sub removeTrack {
	my $client = shift;
	my $tracknum = shift;
	
	my $playlistIndex = ${shuffleList($client)}[$tracknum];

	my $stopped = 0;
	my $oldmode = playmode($client);
	
	if ($tracknum == currentSongIndex($client)) {
		playmode($client, "stop");
		$stopped = 1;
	} elsif ($tracknum < currentSongIndex($client)) {
		currentSongIndex($client,currentSongIndex($client) - 1);
	}
	
	splice(@{playList($client)}, $playlistIndex, 1);

	my @reshuffled;
	my $counter = 0;
	foreach my $i (@{shuffleList($client)}) {
		if ($i < $playlistIndex) {
			push @reshuffled, $i;
		} elsif ($i > $playlistIndex) {
			push @reshuffled, ($i - 1);
		} else {
		}
	}
	
	$client = masterOrSelf($client);
	
	@{$client->shufflelist} = @reshuffled;

	if ($stopped && ($oldmode eq "play")) {
		jumpto($client, $tracknum);
	}
	
	refreshPlaylist($client);

}

sub removeMultipleTracks {
	my $client = shift;
	my $songlist = shift;

	my %songlistentries;
	if (defined($songlist) && ref($songlist) eq 'ARRAY') {
		foreach my $item (@$songlist) {
			$songlistentries{$item}=1;
		}
	}

	my $stopped = 0;
	my $oldmode = playmode($client);
	
	my $curtrack = ${shuffleList($client)}[currentSongIndex($client)];

	my $i=0;
	my $oldcount=0;
	# going to need to renumber the entries in the shuffled list
	# will need to map the old position numbers to where the track ends
	# up after all the deletes occur
	my %oldToNew;
	while ($i <= $#{playList($client)}) {
		#check if this file meets all criteria specified
		my $thistrack=${playList($client)}[$i];
		if (exists($songlistentries{$thistrack})) {
			splice(@{playList($client)}, $i, 1);
			if ($curtrack == $oldcount) {
				playmode($client, "stop");
				$stopped = 1;
			}
		} else {
			$oldToNew{$oldcount}=$i;
			$i++;
		}
		$oldcount++;
	}
	
	my @reshuffled;
	my $newtrack;
	my $getnext=0;
	# renumber all of the entries in the shuffle list with their 
	# new positions, also get an update for the current track, if the 
	# currently playing track was deleted, try to play the next track 
	# in the new list
	foreach my $oldnum (@{shuffleList($client)}) {
		if ($oldnum == $curtrack) { $getnext=1; }
		if (exists($oldToNew{$oldnum})) { 
			push(@reshuffled,$oldToNew{$oldnum});
			if ($getnext) {
				$newtrack=$#reshuffled;
				$getnext=0;
			}
		}
	}

	# if we never found a next, we deleted eveything after the current
	# track, wrap back to the beginning
	if ($getnext) {	$newtrack=0; }

	$client = masterOrSelf($client);
	
	@{$client->shufflelist} = @reshuffled;

	if ($stopped && ($oldmode eq "play")) {
		jumpto($client,$newtrack);
	} else {
		currentSongIndex($client,$newtrack);
	}

	refreshPlaylist($client);
}

#
# playlist synchronization routines
#
sub syncname {
	my $client = shift;
	my $ignore = shift;
	my @buddies = syncedWith($client);
	
	if (isMaster($client)) {
		unshift @buddies , $client;
	} else {
		push @buddies , $client;
	}

	my @newbuddies;
	foreach my $i (@buddies) {
		if ($ignore && $i eq $ignore) { next; }
		push @newbuddies, $i;
	}
				
	my @names = map {Slim::Player::Client::name($_) || Slim::Player::Client::id($_)} @newbuddies;
	$::d_playlist && msg("syncname for " . Slim::Player::Client::id($client) . " is " . (join ' & ',@names) . "\n");
	my $last = pop @names;
	if (scalar @names) {
		return (join ', ', @names) . ' & ' . $last;
	} else {
		return $last;
	}
}

sub syncwith {
	my $client = shift;
	if (Slim::Player::Playlist::isSynced($client)) {
		my @buddies = Slim::Player::Playlist::syncedWith($client);
		my @names = map {Slim::Player::Client::name($_) || Slim::Player::Client::id($_)} @buddies;
		return join ' & ',@names;
	} else { return undef;}
}

# unsync a client from its buddies
sub unsync {
	my $client = shift;
	
	$::d_sync && msg( Slim::Player::Client::id($client) . ": unsyncing\n");
	
	# bail if we aren't synced already
	if (!isSynced($client)) {
		return;
	}
	
	# if we're the master...
	if (isMaster($client)) {
		my $slave;
		my $newmaster;
		
		# make a new master
		$newmaster = splice @{$client->slaves}, 0, 1;

		# you are your own master now
		$newmaster->master(undef);

		# if there are any slaves left
		if (scalar(@{$client->slaves}) > 0) {
		
			# make the slaves know about the new master
			foreach $slave (@{$client->slaves}) {
				$slave->master($newmaster);
			}		
			
			# copy over the slave list to the new master
			@{$newmaster->slaves} = @{$client->slaves};
			
		}
						
		# forget about our slaves
		@{$client->slaves} = ();

		# and copy the playlist to the new master
		copyPlaylist($newmaster, $client);	
		$newmaster->mp3filehandle($client->mp3filehandle);
		$client->mp3filehandle(undef);	
	} elsif (isSlave($client)) {
		# if we're a slave, remove us from the master's list
		my $i = 0;
		foreach my $c (@{($client->master())->slaves}) {
			if (Slim::Player::Client::id($c) eq Slim::Player::Client::id($client)) {
				splice @{$client->master->slaves}, $i, 1;
				last;
			}
			$i++;
		}	
	
		# and copy the playlist to the now freed slave
		my $master = $client->master;
		copyPlaylist($client, $master);
	
		$client->master(undef);
	}
	# when we unsync, we stop.
	Slim::Control::Command::execute($client, ["stop"]);
	saveSyncPrefs($client);
}

# sync a given client to another client
sub sync {
	my $client = shift;
	my $buddy = shift;
	
	$::d_sync && msg(Slim::Player::Client::id($client) .": syncing\n");

	if (isSynced($client) && isSynced($buddy) && master($client) eq master($buddy)) {
		return;  # we're already synced up!
	}
	
	unsync($client);
	
	if (isSynced($buddy)) {
		$buddy = master($buddy);
	}
	
	$client->master($buddy);
	
	push (@{$client->master->slaves}, $client);
	
	if (playmode($buddy) eq "play") {
		Slim::Control::Command::execute($client, ["playlist", "jump", "+0"]);
	}
	
	# Save Status to Prefs file
	saveSyncPrefs($client,$buddy);
	
	Slim::Control::Command::executeCallback($client, ['playlist','sync']);

}

sub saveSyncPrefs {
	
	my $client = shift;
	my $clientID = Slim::Player::Client::id($client);
	if (isSynced($client)) {
	
		if (!defined($client->master->syncgroupid)) {
			$client->master->syncgroupid(int(rand 999999999));
		}
		
		my $masterID = $client->master->syncgroupid;
		# Save Status to Prefs file
		$::d_sync && msg("Saving $clientID as a slave to $masterID\n");
		Slim::Utils::Prefs::clientSet($client,'syncgroupid',$masterID);
		Slim::Utils::Prefs::clientSet($client->master,'syncgroupid',$masterID);
		
	} else {
		Slim::Utils::Prefs::clientSet($client,'syncgroupid','');
		$::d_sync && msg("Clearing Sync master for $clientID\n");
	}
}

# Restore Sync Operation
sub restoreSync {
	my $client = shift;
	my $masterID = (Slim::Utils::Prefs::clientGet($client,'syncgroupid'));
	if ($masterID) {
		my @players = Slim::Player::Client::clients();
		foreach my $other (@players) {
			next if ($other eq $client);
			my $othermasterID = Slim::Utils::Prefs::clientGet($other,'syncgroupid');
			if ($othermasterID && ($othermasterID eq $masterID)) {
			  	$client->syncgroupid($masterID);
			  	$other->syncgroupid($masterID);
			   	Slim::Player::Playlist::sync($client, $other);
			   	last;
			}
		}
	}
}


sub syncedWith {
	my $client = shift;
	my @buddies = ();
	my $otherclient;
	
	# get the master and its slaves
	if (isSlave($client)) {
		push @buddies, $client->master;
		foreach $otherclient (@{$client->master()->slaves}) {
			next if ($client == $otherclient);	# skip ourself
			push @buddies, $otherclient;
			$::d_sync && msg(Slim::Player::Client::id($client) .": is synced with other slave " . Slim::Player::Client::id($otherclient) . "\n");
		}
	}
	
	# get our slaves
	foreach $otherclient (@{$client->slaves()}) {
		push @buddies, $otherclient;
		$::d_sync && msg(Slim::Player::Client::id($client) . " : is synced with its slave " . Slim::Player::Client::id($otherclient) . "\n");
	}
	
	return @buddies;
}

sub isSyncedWith {
	my $client = shift;
	my $buddy = shift;
	
	foreach my $i (syncedWith($client)) {
		if ($buddy == $i) {
			$::d_sync && msg(Slim::Player::Client::id($client) . " : is synced with " . Slim::Player::Client::id($buddy) . "\n");
			return 1;
		}
	}
	$::d_sync && msg(Slim::Player::Client::id($client) . " : is synced NOT with " . Slim::Player::Client::id($buddy) . "\n");
	return 0;
}

sub canSyncWith {
	my $client = shift;
	my @buddies = ();
	if (Slim::Player::Client::isPlayer($client)) {
		foreach my $otherclient (Slim::Player::Client::clients()) {
			next if ($client eq $otherclient);					# skip ourself
			next if (!Slim::Player::Client::isPlayer($otherclient));  # we only sync hardware devices
			next if (isSlave($otherclient)); 					# only include masters and un-sync'ed clients.
			push @buddies, $otherclient;
		}
	}
	
	return @buddies;
}

sub uniqueVirtualPlayers {
	my @players = ();

	foreach my $player (Slim::Player::Client::clients()) {
		next if (isSlave($player)); 					# only include masters and un-sync'ed clients.
		push @players, $player;
	}
	return @players;
}

# checkSync:
#   syncs up the start of playback of synced clients
#   resyncs clients between songs if some clients have multiple outstanding chunks
#
sub checkSync {
	my $client = shift;
	
	$::d_playlist_v && msg("checkSync: Player " . Slim::Player::Client::id($client) . " has " . scalar(@{$client->chunks}) . " chunks, and " . $client->usage() . "% full buffer \n");

	if (!Slim::Player::Playlist::isSynced($client)) {
		return;
	}
	
	# if we're synced and waiting for the group's buffers to fill,
	# check if our buffer has passed the 95% level. If so, indicate
	# that we're ready to be unpaused.  If everyone else is now ready,
	# unpause all the clients at once.
	if ($client->readytosync == 0) {

		my $usage = $client->usage();
		$::d_playlist && msg("checking buffer usage: $usage on client $client\n");

		if 	($usage > 0.90) {
			$client->readytosync(1);
		
			$::d_playlist && msg(Slim::Player::Client::id($client)." is ready to sync ".Time::HiRes::time()."\n");
			my $allReady=1;
			my $everyclient;
			foreach $everyclient ($client, Slim::Player::Playlist::syncedWith($client)) {
				if (!($everyclient->readytosync)) {
					$allReady=0;
				}
			}
			
			if ($allReady) {
				$::d_playlist && msg("all clients ready to sync now. unpausing them.\n");
				foreach $everyclient ($client, Slim::Player::Playlist::syncedWith($client)) {
					Slim::Player::Control::resume($everyclient);
				}
			}
		}
	}
	
	my $everyclient;
	my @group = ($client, Slim::Player::Playlist::syncedWith($client));
	
	# if we are ready to resync, then check to see if we've run out of packets.
	# when we have, stop and restart the clients on the current song, which 
	# has already been opened.
	
	if (master($client)->resync) {
		my $readyToContinue = 0;
		# we restart the song as soon as the first player has run out of chunks.
		foreach $everyclient (@group) {
			$::d_playlist && msg("Resync: Player " . Slim::Player::Client::id($everyclient) . " has " . scalar(@{$everyclient->chunks}) . " chunks \n");
			if (scalar(@{$everyclient->chunks}) == 0) { 
				$readyToContinue = 1; 
				last; 
			}
		}

		if ($readyToContinue) {
			master($client)->resync(0);
			Slim::Control::Command::execute($client, ["playlist", "jump", "+0"]);
			$::d_playlist && msg("Resync restarting players on current song\n");
		}
	}
	
	# sanity check on queued chunks
	foreach my $everyclient (@group) {
		if (scalar(@{$everyclient->chunks}) > 200) { 
			$::d_playlist && msg("Player " . Slim::Player::Client::id($everyclient) . " isn't keeping up with the rest of the synced group.");
			@{$everyclient->chunks} = ();
			last; 
		}
	}
}

sub forgetClient {
	my $client = shift;
	# clear out the playlist
	Slim::Control::Command::execute($client, ["playlist", "clear"]);
	
	# trying to play will close out any open files.
	Slim::Control::Command::execute($client, ["play"]);
}

sub nextChunk {
	my $client = shift;
	my $maxChunkSize = shift;
	my $chunkRef;
	my $i;
		
	# if there's a chunk in the queue, then use it.
	if (scalar(@{$client->chunks})) {
		$chunkRef = shift @{$client->chunks};
	} else {
		#otherwise, read a new chunk
		my $readfrom = masterOrSelf($client);

		# if we're at a non-regular rate (not 0 or 1), play for one second 
		# then skip a calculated amount to play back at the apparent rate.
		my $rate = rate($client);
		my $lastskip = $client->lastskip();
		my $now = Time::HiRes::time();
		if (($rate != 0 && $rate != 1) && (($now - $lastskip) > 1.0)) { 
			my $skip = $rate - 1.0;
			if ($skip > 0) { $skip = "+" . $skip; }
			$::d_playlist && msg("non regular play rate ($rate), skipping $skip seconds\n");
			$client->lastskip($now);
			gototime($readfrom, $skip, 1);
			# the gototime above will reload the data, so we should just return;
			return undef;
		}
			
		$chunkRef = readNextChunk($readfrom, $maxChunkSize);
			
		if (defined($chunkRef)) {	
			# let everybody I'm synced with use this chunk
			foreach my $buddy (syncedWith($client)) {
				push @{$buddy->chunks}, $chunkRef;
			}
		}
	}
	if (defined($chunkRef)) {
		my $len = length($$chunkRef);
		
		if ($len > $maxChunkSize) {
			push @{$client->chunks}, \substr($$chunkRef, $maxChunkSize - $len, $len - $maxChunkSize);
			$chunkRef = \substr($$chunkRef, 0, $maxChunkSize);
		}
		
		# remember the last chunk we sent
		if (defined($chunkRef)) {
			$client->lastchunk($chunkRef);
		}
	}
	
	return $chunkRef;
}

sub refreshPlaylist {
	my $client = shift;
	# make sure we're displaying the new current song in the playlist view.
	foreach my $everybuddy ($client, syncedWith($client)) {
		if (Slim::Player::Client::isPlayer($everybuddy)) {
			Slim::Buttons::Playlist::jump($everybuddy);
		}
		$client->htmlstatusvalid(0); #invalidate cached htmlplaylist
	}
	
}

sub moveSong {
	my $client = shift;
	my $src = shift;
	my $dest = shift;
	my $size = shift;
	my $listref;
	
	if (!defined($size)) { $size = 1;};
	if (defined $dest && $dest =~ /^[\+-]/) {
		$dest = $src + $dest;
	}
	if (defined $src && defined $dest && $src < Slim::Player::Playlist::count($client) && $dest < Slim::Player::Playlist::count($client) && $src >= 0 && $dest >=0) {
		if (Slim::Player::Playlist::shuffle($client)) {
			$listref = Slim::Player::Playlist::shuffleList($client);
		} else {
			$listref = Slim::Player::Playlist::playList($client);
		}
		if (defined $listref) {
			my @item = splice @{$listref},$src, $size;
			splice @{$listref},$dest, 0, @item;
			my $currentSong = Slim::Player::Playlist::currentSongIndex($client);
			if ($src == $currentSong) {
				Slim::Player::Playlist::currentSongIndex($client,$dest);
			} elsif ($dest == $currentSong) {
				Slim::Player::Playlist::currentSongIndex($client,($dest>$src)? $currentSong - 1 : $currentSong + 1);
			}
			Slim::Player::Playlist::refreshPlaylist($client);
		}
	}
}

# rate can be negative for rew, zero for pause, 1 for playback and greater than one for ffwd
sub rate {
	my ($client, $newrate) = @_;
	if (!defined($newrate)) {
		return $client->rate;
	}
	my $oldrate = $client->rate();
	$client->rate($newrate);
	
	$::d_playlist && msg("switching rate from $oldrate to $newrate\n");
	# restart playback if we've changed and we're not pausing or unpauseing
	if ($oldrate != $newrate) {  		
	 	if ($oldrate != 0 && $newrate != 0) {
	 		$::d_playlist && msg("gototime, jumping to here in order to restart the stream\n");
			gototime($client, "+0", 1);
		}
	}
}

sub clear {
	my $client = shift;
	@{Slim::Player::Playlist::playList($client)} = ();
	Slim::Player::Playlist::reshuffle($client);
}

# jumpto - set the current song to a given offset
sub jumpto {
	my($client, $offset) = @_;
	my($songcount) = count($client);
	if ($songcount == 0) {
		return;
	}

	playmode($client,"stop");
	if ($songcount != 1) {
		if ($offset =~ /[\+\-]\d+/) {
			currentSongIndex($client, currentSongIndex($client) + $offset);
			$::d_playlist && msgf("jumping by %s\n", $offset);
		} else {
			currentSongIndex($client, $offset);
			$::d_playlist && msgf("jumping to %s\n", $offset);
		}
	
		if ($songcount && currentSongIndex($client) >= $songcount) {
			currentSongIndex($client, currentSongIndex($client) % $songcount);
		}
		if ($songcount && currentSongIndex($client) < 0) {
			currentSongIndex($client, $songcount - ((0 - currentSongIndex($client)) % $songcount));
		}
	} else {
		currentSongIndex($client, 0);
	}
	playmode($client,"play");
}

sub fischer_yates_shuffle {
	my ($listRef)=@_;
	if ($#$listRef == -1 || $#$listRef == 0) {
		return;
	}
	for (my $i = $#$listRef; --$i; ) {
		# swap each item with a random item;
		my $a = int(rand($i + 1));
		@$listRef[$i,$a] = @$listRef[$a,$i];
	}
}

#reshuffle - every time the playlist is modified, the shufflelist should be updated
#		We also invalidate the htmlplaylist at this point
sub reshuffle {
	my($client) = shift;
	my($realsong);
	my($i);
	my($temp);
	my($songcount) = count($client);
	my $listRef = shuffleList($client);

	$client->htmlstatusvalid(0); #invalidate cached htmlplaylist

	if ($songcount) {
		$realsong = ${$listRef}[currentSongIndex($client)];

		if (!defined($realsong)) {
			$realsong = -1;
		} elsif ($realsong > $songcount) {
			$realsong = $songcount;
		}

		@{$listRef} = (0 .. ($songcount - 1));

		if (shuffle($client) == 1) {
			fischer_yates_shuffle($listRef);
			for ($i = 0; $i < $songcount; $i++) {
				if (${$listRef}[$i] == $realsong) {
					if (shuffle($client)) {
						$temp = ${$listRef}[$i];
						${$listRef}[$i] = ${$listRef}[0];
						${$listRef}[0] = $temp;
						$i = 0;
					}
					last;
				}
			}
		} elsif (shuffle($client) == 2) {
			my %albtracks;
			my %trackToNum;
			my $i = 0;			
			foreach my $track (@{playList($client)}) {
				my $album=Slim::Music::Info::matchCase(Slim::Music::Info::album($track));
				if (!defined($album)) {
					$album=string('NO_ALBUM');
				}
				push @{$albtracks{$album}},$i;
				$trackToNum{$track}=$i;
				$i++;
			}
			if ($realsong == -1) {
				$realsong=${$listRef}[Slim::Utils::Prefs::clientGet($client,'currentSong')];
			}
			my $curalbum=Slim::Music::Info::matchCase(Slim::Music::Info::album(${playList($client)}[$realsong]));
			if (!defined($curalbum)) {
				$curalbum = string('NO_ALBUM');
			}
			my @albums = keys(%albtracks);

			fischer_yates_shuffle(\@albums);

			for ($i = 0; $i <= $#albums && $realsong != -1; $i++) {
				my $album=shift(@albums);
				if ($album ne $curalbum) {
					push(@albums,$album);
				} else {
					unshift(@albums,$album);
					last;
				}
			}
			my @shufflelist;
			$i=0;
			my $album=shift(@albums);
			my @albumorder=map {${playList($client)}[$_]} @{$albtracks{$album}};
			@albumorder=Slim::Music::Info::sortByTrack(@albumorder);
			foreach my $trackname (@albumorder) {
				my $track=$trackToNum{$trackname};
				push @shufflelist,$track;
				$i++
			}
			foreach my $album (@albums) {
				my @albumorder=map {${playList($client)}[$_]} @{$albtracks{$album}};
				@albumorder=Slim::Music::Info::sortByTrack(@albumorder);
				foreach my $trackname (@albumorder) {
					push @shufflelist,$trackToNum{$trackname};
				}
			}
			@{$listRef}=@shufflelist;
		} 
		
		for ($i = 0; $i < $songcount; $i++) {
			if (${$listRef}[$i] == $realsong) {
				currentSongIndex($client,$i);
				last;
			}
		}
	
		if (currentSongIndex($client) >= $songcount) { currentSongIndex($client, 0); };
	} else {
		@{$listRef} = ();
		currentSongIndex($client, 0);
	}
	refreshPlaylist($client);
}

#
# jump to a particular time in the current song
#  should be dead-on for CBR, approximate for VBR
#  third argument determines whether this is an instant jump or wait until the
#   buffer gets around to it
#
sub gototime {
	my($client, $newtime, $doitnow) = @_;
	my $newoffset;
	my $oldoffset;
	my $oldtime;

	if (isSynced($client)) {
		$client = master($client);
	}

	return if (!song($client));
	return if !defined($client->mp3filehandle);

	my $size = $client->songtotalbytes;
	my $duration = $client->songduration;

#	$oldoffset = $client->songpos;
	$oldoffset = songRealPos($client);
	
	if ($oldoffset > $size) {
		 warn ("song position > size\n") 
	}

	$oldtime = songTime($client);

	if ($newtime =~ /^[\+\-]/) {
		$newoffset = int($oldoffset + ($newtime / $duration * $size));
		$::d_playlist && msgf("going to time %s, offset %s from old offset %s\n", $newtime, $newoffset, $oldoffset);
		# skip to the previous or next track as necessary
		if ($newoffset > $size) {
			my $rate = rate($client);
			jumpto($client, "+1");
			rate($client, $rate);
			$newtime = ($newoffset - $size) * $duration / $size;
			$::d_playlist && msg("skipping forward to the next track to time $newtime\n");
			gototime($client, $newtime, $doitnow);
			return;
		} elsif ($newoffset < 0) {
			my $rate = rate($client);
			while ($newtime < 0) {
				jumpto($client, "-1");
				rate($client, $rate);
				$newtime = $client->songduration - ((-$newoffset) * $duration / $size);
				$::d_playlist && msg("skipping backwards to the previous track to time $newtime\n");
			}
			gototime($client, $newtime, $doitnow);
			return;
		}
	} else {
		$::d_playlist && msgf("going to time %s\n", $newtime);
		$newoffset = int($newtime / $duration * ($size));
		if ($newoffset > $size) {
			$newoffset = $size;
		} elsif ($newoffset < 0) {
			$newoffset = 0;
		}
	}
	
	$::d_playlist && msgf("oldoffset $oldoffset, old time = %d, newoffset: %d new time = %d\n", $oldtime, $newoffset, $newoffset / $size * $duration);

	if ($doitnow) {
		foreach my $everybuddy ($client, slaves($client)) {
			$::d_playlist && msg("gototime: stopping playback\n");
			Slim::Player::Control::stop($everybuddy);
			@{$everybuddy->chunks} = ();
		}
	}
	my $dataoffset =  $client->songoffset;
	$client->songpos($newoffset);
	$client->mp3filehandle->seek($newoffset+$dataoffset, 0);

	if ($doitnow) {
		foreach my $everybuddy ($client, slaves($client)) {
			$::d_playlist && msg("gototime: restarting playback\n");
			$everybuddy->readytosync(0);
			Slim::Player::Control::play($everybuddy, Slim::Player::Playlist::isSynced($client));
		}
	}	
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


################################################################################
# Private functions below. Do not call from outside this module.
################################################################################

# openNext returns 1 if it succeeded opening a new song, 
#                  0 if it stopped at the end of the list or failed to open the current song 
# note: Only call this with a master or solo client
sub openNext {
	$::d_playlist && msg("opening next song...\n"); 
	my $client = shift;
	my $result = 1;
		
	closeSong($client);

	# we're at the end of a song, let's figure out which song to open up.
	# if we can't open a song, skip over it until we hit the end or a good song...
	do {
	
		if (repeat($client) == 2  && $result) {
			# play the next song and start over if necessary
			skipsong($client);
		} elsif (repeat($client) == 1 && $result) {
			#play the same song again
		} else {
			#stop at the end of the list
			if (currentSongIndex($client) == (count($client) - 1)) {
				playmode($client, $result ? 'playout' : 'stop');
				currentSongIndex($client, 0);
				return 0;
			} else {
				skipsong($client);
			}
		}
		
		$result = openSong($client);
		
	} while (!$result);
	
	# this is
	if ($result && isSynced($client)) {
		my $silence = Slim::Web::HTTP::getStaticContent("html/silentpacket.mp3");
		my $count = int($CLIENTBUFFERLEN / length($silence)) + 1;
		my @fullbufferofsilence =  (\$silence) x $count;
		$::d_playlist && msg("stuffing " . scalar(@fullbufferofsilence) . " of silence into the buffers to sync.\n"); 
		# stuff silent packets to fill the buffers for each player
		foreach my $buddy ($client, syncedWith($client)) {
			push @{$buddy->chunks}, (@fullbufferofsilence);
		}
		$client->resync(1); 
	}
	
	return $result;
}

sub closeSong {
	my $client = shift;

	# close the previous handle to prevent leakage.
	if (defined $client->mp3filehandle()) {
		$client->mp3filehandle->close();
		$client->mp3filehandle(undef);
		$client->mp3filehandleIsSocket(0);
	}	
}

sub openSong {
	my $client = shift;

	# at the end of a song, reset the song time
	$client->songtotalbytes(0);
	$client->songduration(0);
	$client->songpos(0);

	# reset shoutcast variables
	$client->shoutMetaInterval(0);
	$client->shoutMetaPointer(0);

	# mark htmlplaylist invalid so the current song changes
	$client->htmlstatusvalid(0);
	my $fullpath = '';

	# We are starting a new song, lets kill any animation so we see the correct new song.
	foreach my $everyclient ($client, syncedWith($client)) { 
		Slim::Display::Animation::killAnimation($everyclient);
	}
	
	closeSong($client);
	
	$fullpath = song($client);

	unless ($fullpath) {
		return undef;
	}


	$::d_playlist && msg("openSong on: $fullpath\n");
	####################
	# parse the filetype

	if (Slim::Music::Info::isHTTPURL($fullpath)) {
		my $line1 = string('CONNECTING_FOR');
		my $line2 = Slim::Music::Info::standardTitle($client, song($client));			
		Slim::Display::Animation::showBriefly($client, $line1, $line2, undef,1);

		# we don't get the content type until after the stream is opened
		my $sock = Slim::Web::RemoteStream::openRemoteStream($fullpath, $client);
		if ($sock) {
			# if it's an mp3 stream, then let's stream it.
			if (Slim::Music::Info::isSong($fullpath)) {
				$client->mp3filehandle($sock);
				$client->mp3filehandleIsSocket(1);
				$client->remoteStreamStartTime(time());
			# if it's one of our playlists, parse it...
			} elsif (Slim::Music::Info::isList($fullpath)) {
				$::d_playlist && msg("openSong on a remote list!\n");
				my @items;
				# handle the case that we've actually got a playlist in the list,
				# rather than a stream.

				# parse out the list
				@items = Slim::Formats::Parse::parseList($fullpath, $sock);
				
				# hack to preserve the title of a song redirected through a playlist
				if ( scalar(@items) == 1 && defined(Slim::Music::Info::title($fullpath))) {
				    Slim::Music::Info::setTitle($items[0], Slim::Music::Info::title($fullpath));
				} 
				
				# close the socket
				$sock->close();
				$sock = undef;
				$client->mp3filehandle(undef);

				# insert the list onto the playlist
				splice @{playList($client)}, currentSongIndex($client), 1, @items;

				# update the shuffle list
				reshuffle($client);

				# try to open the first item in the list, if there is one.
				return openSong($client);
			} else {
				$::d_playlist && msg("don't know how to handle content for $fullpath\n");
				$sock->close();
				$sock = undef;
				$client->mp3filehandle(undef);
			}
		} 
		
		if (!$sock) {
			$::d_playlist && msg("Remote stream failed to open, showing message.\n");
			$client->mp3filehandle(undef);
			
			my $line1 = string('PROBLEM_CONNECTING');
			my $line2 = Slim::Music::Info::standardTitle($client, song($client));			
			Slim::Display::Animation::showBriefly($client, $line1, $line2, 5, 1);
			return undef;
		}
	} elsif (Slim::Music::Info::isSong($fullpath)) {
	
		my $filepath;
		if (Slim::Music::Info::isFileURL($fullpath)) {
			$filepath = Slim::Utils::Misc::pathFromFileURL($fullpath);
		} else {
			$filepath = $fullpath;
		}
		
		my $size = Slim::Music::Info::size($fullpath);
		my $duration = Slim::Music::Info::durationSeconds($fullpath);
		my $offset = Slim::Music::Info::offset($fullpath);
		$::d_playlist && msg("openSong: getting duration  $duration, size $size, and offset $offset for $fullpath\n");

		if (!$size || !$duration)  {
			$::d_playlist && msg("openSong: not bothering opening file with zero size or duration\n");
			return undef;
		}

		if (Slim::Music::Info::isMP3($fullpath)) {
			$::d_playlist && msg("openSong: this is an MP3 file: $fullpath\n");
			
			
			$client->mp3filehandle( FileHandle->new() );
	
			$::d_playlist && msg("openSong: opening file $filepath\n");
			if ($client->mp3filehandle->open($filepath)) {
				
				$::d_playlist && msg(" seeking in $offset into $filepath\n");
				if ($offset) {
					if (!seek ($client->mp3filehandle, $offset, 0) ) {
						msg("couldn't seek to $offset for $filepath");
					};
				}
							
			} else { 
				$client->mp3filehandle(undef);
			}
		} elsif(Slim::Music::Info::isMOV($fullpath)) {
			$::d_playlist && msg("openSong: this is an MOV file: $fullpath\n");
			my $samplerate = Slim::Utils::Prefs::get("wavmp3samplerate");
			my $movbin = Slim::Utils::Misc::findbin('mov123');
			my $lamebin = Slim::Utils::Misc::findbin('lame');
			if (!$movbin || !$lamebin) { return undef; }

			my $mov_cmd = "\"$movbin\" \"$filepath\"";

			my $lame_cmd = "\"$lamebin\" --silent -r - - &";
	
			$client->mp3filehandle( FileHandle->new() );
	
			$client->mp3filehandle->open("$mov_cmd | $lame_cmd |");
			$client->mp3filehandleIsSocket(1);
			$client->remoteStreamStartTime(time());
		} elsif (Slim::Music::Info::isOgg($fullpath) && Slim::Utils::Prefs::get("transcode-ogg")) {
			# Note we have to put the path in double quotes so that
			# spaces in file names are handled properly.
			my $oggbin = Slim::Utils::Misc::findbin('ogg123');
			my $lamebin = Slim::Utils::Misc::findbin('lame');
			if (!$oggbin || !$lamebin) { return undef; }

			my $rate = Slim::Music::Info::samplerate($fullpath);
			if ($rate) {
				$rate = "-s $rate";
			} else {
				$rate = '';
			}
			
			my $ogg_cmd = "\"$oggbin\" -q -p 5 -d raw -f - \"$filepath\"";
			# Added -x option to fix ogg output problem reported by users
			my $lame_cmd = "\"$lamebin\" -r $rate -v -x --quiet - - &";
			$client->mp3filehandle( FileHandle->new() );
	
			$client->mp3filehandle->open("$ogg_cmd | $lame_cmd |");
			$client->mp3filehandleIsSocket(1);
			$client->remoteStreamStartTime(time());
		} elsif((Slim::Music::Info::isWav($fullpath) || Slim::Music::Info::isAIFF($fullpath)) && Slim::Utils::Prefs::get("transcode-wav")) {
			$::d_playlist && msg("openSong: this is an WAV or AIFF file: $fullpath\n");
			my $samplerate = Slim::Utils::Prefs::get("wavmp3samplerate");
			my $lamebin = Slim::Utils::Misc::findbin('lame');
			if (!$lamebin) { return undef; }

			my $lame_cmd = qq("$lamebin" --silent -h -b $samplerate "$filepath" -) . (Slim::Utils::OSDetect::OS() eq 'win' ? "" : " &");
	
			$client->mp3filehandle( FileHandle->new() );
			$client->mp3filehandle->open( "$lame_cmd |");
			$client->mp3filehandleIsSocket(1);
			$client->remoteStreamStartTime(time());
		} else {
			$::d_playlist && msg("Song is of unrecognized type " . Slim::Music::Info::contentType($fullpath) . "! Stopping! $fullpath\n");
			return undef;
		}
		$client->songtotalbytes($size);
		$client->songduration($duration);
		$client->songoffset($offset);

	} else {
		$::d_playlist && msg("Next item is of unrecognized type! Stopping! $fullpath\n");
		return undef;
	}

	######################
	# make sure the filehandle was actually set
	if ($client->mp3filehandle()) {
		binmode($client->mp3filehandle());
		Slim::Web::History::record(song($client));
	} else {
		$::d_playlist && msg("Can't open [$fullpath] : $!");

		my $line1 = string('PROBLEM_OPENING');
		my $line2 = Slim::Music::Info::standardTitle($client, song($client));		
		Slim::Display::Animation::showBriefly($client, $line1, $line2, 5,1);
		return undef;
	}

	refreshPlaylist($client);
	
	Slim::Control::Command::executeCallback($client,  ['open', $fullpath]);

	return 1;
}

# skipsong is just for playing the next song when the current one ends
sub skipsong {
	my ($client) = @_;
	# mark htmlplaylist invalid so the current song changes
	$client->htmlstatusvalid(0);

	currentSongIndex($client, currentSongIndex($client) + 1);

	if (currentSongIndex($client) >= count($client)) {
		if (shuffle($client) && Slim::Utils::Prefs::get('reshuffleOnRepeat')) {
			my $playmode = playmode($client);
			playmode($client,'stop');
			reshuffle($client);
			playmode($client,$playmode);
		}
		currentSongIndex($client, 0);
	}
}

sub readNextChunk {
	my $client = shift;
	my $givenChunkSize = shift;
	
	if (!defined($givenChunkSize)) {
		$givenChunkSize = Slim::Utils::Prefs::get('udpChunkSize') * 10;
	} 
	
	my $chunksize = $givenChunkSize;
	
	my $chunk  = 0;

	if ($client->mp3filehandle()) {
	
		my $isRemoteStream = $client->mp3filehandleIsSocket && Slim::Music::Info::isHTTPURL(song($client));
		
		if ($isRemoteStream) {
			# If the MP3 file handle is a remote stream and it's not readable,
			# just return instead of blocking here. The client will repeat the
			# request.
			#
			my $selRead = IO::Select->new();
			$selRead->add($client->mp3filehandle);
			my ($selCanRead,$selCanWrite)=IO::Select->select($selRead,undef,undef,0);
			if (!$selCanRead) {
				#$::d_playlist && msg("remote stream not readable\n");
				return undef;
			} else {
				#$::d_playlist && msg("remote stream readable.\n");
			}

			# adjust chunksize to lie on metadata boundary (for shoutcast/icecast)
			if ($client->shoutMetaInterval() &&
				($client->shoutMetaPointer() + $chunksize) > $client->shoutMetaInterval()) {
	
				$chunksize = $client->shoutMetaInterval() - $client->shoutMetaPointer();
			}
		} else {
			# don't send extraneous ID3 data at the end of the file
			my $size = $client->songtotalbytes();
			my $pos = $client->songpos();
			
			if ($pos + $chunksize > $size) {
				$chunksize = $size - $pos;
				$::d_playlist && msg( "Reduced chunksize to $chunksize at end of file");
			}
		}

		$client->mp3filehandle()->read($chunk, $chunksize);
		
		if ($isRemoteStream) {
			$client->shoutMetaPointer($client->shoutMetaPointer() + length($chunk));
	
			# handle instream metadata for shoutcast/icecast
			if ($client->shoutMetaPointer() == $client->shoutMetaInterval()) {
	
				Slim::Web::RemoteStream::readMetaData($client);
				$client->shoutMetaPointer(0);
			}
		}
	} else {
		$::d_playlist && msg(Slim::Player::Client::id($client) . ": No filehandle to read from, returning no chunk.\n");
		$::d_playlist && bt();
		return undef;
	}

	# if nothing was read from the filehandle, then we're done with it,
	# so open the next filehandle.
	if (length($chunk) == 0 ||
		(!$client->mp3filehandleIsSocket && $client->songtotalbytes() != 0 && ($client->songpos()) > $client->songtotalbytes())) {
		$::d_playlist && msg("opening next song: chunk length" . length($chunk) . ", song pos: " .
				$client->songpos() . "(tell says: . " . tell($client->mp3filehandle()). "), totalbytes: " . $client->songtotalbytes() . "\n");
		if (!openNext($client)) {
			$::d_playlist && msg("Can't opennext, returning no chunk.");
			return undef;
		}
		
		$client->mp3filehandle()->read($chunk, $givenChunkSize);
		
		if ($client->mp3filehandleIsSocket) {
			$client->shoutMetaPointer(length($chunk));
		}
	}
	
	$client->songpos($client->songpos + length($chunk));
	
	$::d_playlist_verbose && msg("read a chunk of " . length($chunk) . " length\n");
	
	return \$chunk;
}

sub pauseSynced {
	my $client = shift;
	foreach my $everyclient ($client, syncedWith($client)) {
		Slim::Player::Control::pause($everyclient);
		rate($everyclient, 0);
	}
}

sub isMaster {
	my $client = shift;
	if (scalar(@{$client->slaves}) > 0) {
		return 1;
	} else {
		return 0;
	}
}

sub master {
	my $client = shift;
	if (isMaster($client)) {
		return $client;
	} 
	return $client->master;
}

sub slaves {
	my $client = shift;
	
	return @{$client->slaves};
}

# returns the master if it's a slave, otherwise returns undef
sub isSlave {
	my $client = shift;
	return $client->master;
}

sub masterOrSelf {
	my $client = shift;
	return $client->master || $client;
}

sub isSynced {
	my $client = shift;
	return (scalar(@{$client->slaves}) || $client->master);
}


sub modifyPlaylistCallback {
	my $client = shift;
	my $paramsRef = shift;
	if (Slim::Utils::Prefs::get('playlistdir') && Slim::Utils::Prefs::get('persistPlaylists')) {
		#Did the playlist change?
		my $saveplaylist = $paramsRef->[0] eq 'playlist' && ($paramsRef->[1] eq 'play' 
					|| $paramsRef->[1] eq 'append' || $paramsRef->[1] eq 'load_done'
					|| $paramsRef->[1] eq 'loadalbum'
					|| $paramsRef->[1] eq 'addalbum' || $paramsRef->[1] eq 'clear'
					|| $paramsRef->[1] eq 'delete' || $paramsRef->[1] eq 'move'
					|| $paramsRef->[1] eq 'sync');
		#Did the playlist or the current song change?
		my$savecurrsong = $saveplaylist || $paramsRef->[0] eq 'open' 
					|| ($paramsRef->[0] eq 'playlist' 
						&& ($paramsRef->[1] eq 'jump' || $paramsRef->[1] eq 'index' || $paramsRef->[1] eq 'shuffle'));
		return if !$savecurrsong;
		my @syncedclients = Slim::Player::Playlist::syncedWith($client);
		push @syncedclients,$client;
		my $playlistref = Slim::Player::Playlist::playList($client);
		my $currsong = (Slim::Player::Playlist::shuffleList($client))->[Slim::Player::Playlist::currentSongIndex($client)];
		foreach my $eachclient (@syncedclients) {
			if ($saveplaylist) {
				my $playlistname = "__" . Slim::Player::Client::id($eachclient) . ".m3u";
				$playlistname =~ s/\:/_/g;
				$playlistname = catfile(Slim::Utils::Prefs::get('playlistdir'),$playlistname);
				Slim::Formats::Parse::writeM3U($playlistref,$playlistname);
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
