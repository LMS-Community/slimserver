package Slim::Player::Sync;

# $Id$

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Scalar::Util qw(blessed);
use Slim::Utils::Log;
use Slim::Utils::Misc;

my $log = logger('player.sync');

# playlist synchronization routines
sub syncname {
	my $client = shift;
	my $ignore = shift;
	my @buddies = syncedWith($client);
	
	if (isMaster($client)) {
		unshift @buddies , $client;
	} else {
		push @buddies , $client;
	}

	my @newbuddies = ();

	for my $i (@buddies) {

		if ($ignore && $i eq $ignore) {
			next;
		}

		push @newbuddies, $i;
	}
				
	my @names = map {$_->name() || $_->id()} @newbuddies;

	$log->info(sprintf("syncname for %s is %s", $client->id, (join ' & ',@names)));

	my $last = pop @names;

	if (scalar @names) {
		return (join ', ', @names) . ' & ' . $last;
	} else {
		return $last;
	}
}

sub syncwith {
	my $client = shift;

	if (isSynced($client)) {

		my @buddies = syncedWith($client);
		my @names   = map { $_->name || $_->id } @buddies;

		return join(' & ', @names);
	}

	return undef;
}

# unsync a client from its buddies
sub unsync {
	my $client = shift;
	my $temp = shift;

	$log->info($client->id . ": unsyncing");

	# bail if we don't have sync state
	if (!defined($client->syncgroupid)) {
		return;
	}

	my $syncgroupid = $client->syncgroupid;
	my $lastInGroup;
	
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

		} else {

			@{$newmaster->slaves} = ();
			$lastInGroup = $newmaster;
		}
						
		# forget about our slaves & master
		@{$client->slaves} = ();
		$client->master(undef);
		# and copy the playlist to the new master
		Slim::Player::Playlist::copyPlaylist($newmaster, $client);
		
		# copy the song queue from the master
		@{$newmaster->currentsongqueue()} = @{$client->currentsongqueue()};
		
		$newmaster->audioFilehandle($client->audioFilehandle);
		$client->audioFilehandle(undef);	

	} elsif (isSlave($client)) {

		# if we're a slave, remove us from the master's list
		my $i = 0;

		foreach my $c (@{($client->master())->slaves}) {

			if ($c->id eq $client->id) {

				splice @{$client->master->slaves}, $i, 1;
				last;
			}

			$i++;
		}	
	
		# and copy the playlist to the now freed slave
		my $master = $client->master;
		
		$client->master(undef);
		
		Slim::Player::Playlist::copyPlaylist($client, $master);

		$lastInGroup = $master if !scalar(@{$master->slaves});

	} else {

		$lastInGroup = $client;
	}

	# check for any players in group which are off and hence not synced
	my @players = Slim::Player::Client::clients();
	my @inGroup = ();
	
	foreach my $other (@players) {

		next if ($other->power || $other eq $client );

		push @inGroup, $other if (Slim::Utils::Prefs::clientGet($other,'syncgroupid') == $syncgroupid);
	}

	if (scalar @inGroup == 1) {

		if ($lastInGroup && $lastInGroup != $inGroup[0]) {

			# not last in group as other off players exist
			$lastInGroup = undef;

		} else {

			# off player is last in group
			$lastInGroup = $inGroup[0];
		}

	} elsif (scalar @inGroup > 1) {

		# multiple off players in group, remaining player is not last
		$lastInGroup = undef;
	}

	# when we unsync, we stop, but save settings first if we're doing at temporary unsync.
	if ($temp) {

		saveSyncPrefs($client);
		$client->execute(["stop"]);

	} else {

		$client->execute(["stop"]);

		# delete sync prefs for both this client and remaining client if it is last in group
		deleteSyncPrefs($client) unless ($client == $lastInGroup);
		deleteSyncPrefs($lastInGroup, 1) if $lastInGroup;
	}
}

# sync a given client to another client
sub sync {
	my $client = shift;
	my $buddy = shift;
	
	$log->info($client->id .": syncing");

	# we're already synced up!
	if (isSynced($client) && isSynced($buddy) && master($client) eq master($buddy)) {
		return;
	}
	
	unsync($client);
	
	$buddy = masterOrSelf($buddy);

	# if the buddy is silent, switch them, so we don't have any silent masters.
	if ($buddy->prefGet('silent')) {
		($client, $buddy) = ($buddy, $client);
	}

	if ($buddy->prefGet('silent')) {

		$log->warn($buddy->id . " is silent and we're trying to make it a master!");
	}
	
	$client->master($buddy);
	
	push (@{$client->master->slaves}, $client);
	
	if (Slim::Player::Source::playmode($buddy) eq "play") {
		$buddy->execute(["stop"]);
		$client->execute(["playlist", "jump", "+0"]);
	}
	
	# Save Status to Prefs file
	saveSyncPrefs($client);
	
	Slim::Control::Request::notifyFromArray($client, ['playlist', 'sync']);
}

sub saveSyncPrefs {
	my $client = shift;

	if (isSynced($client)) {
	
		if (!defined($client->master->syncgroupid)) {
			$client->master->syncgroupid(int(rand 999999999));
		}

		my $masterID = $client->master->syncgroupid;
		my $clientID = $client->id;

		$client->syncgroupid($masterID);

		# Save Status to Prefs file
		$log->info("Saving $clientID as a slave to $masterID");

		$client->prefSet('syncgroupid', $masterID);
		$client->master->prefSet('syncgroupid', $masterID);
		
	}
}

sub deleteSyncPrefs {
	my $client = shift;
	my $last   = shift;

	my $clientID    = $client->id();
	my $syncgroupid = $client->syncgroupid;

	if ($last) {

		$log->info("Deleting Sync group prefs for group: $syncgroupid");

		Slim::Utils::Prefs::delete("$syncgroupid-Sync");
	}

	$log->info("Clearing Sync master for $clientID");

	$client->syncgroupid(undef);
	$client->prefDelete('syncgroupid');
}

# Restore Sync Operation
sub restoreSync {
	my $client = shift;
	my $masterID = ($client->prefGet('syncgroupid'));

	if ($masterID && ($client->power() || $client->prefGet('syncPower'))) {

		my @players = Slim::Player::Client::clients();

		foreach my $other (@players) {

			next if ($other eq $client);
			next if (!$other->power() && !Slim::Utils::Prefs::clientGet($other,'syncPower'));

			my $othermasterID = Slim::Utils::Prefs::clientGet($other,'syncgroupid');

			if ($othermasterID && ($othermasterID eq $masterID)) {
				$client->syncgroupid($masterID);
				$other->syncgroupid($masterID);
				sync($client, $other);
				last;
			}

		}

	}
}

sub syncedWith {
	my $client = shift || return undef;;

	my @buddies = ();
	
	# get the master and its slaves
	if (isSlave($client)) {

		push @buddies, $client->master;

		for my $otherclient (@{$client->master()->slaves}) {

			# skip ourself.
			if ($client != $otherclient) {

				push @buddies, $otherclient;

				$log->debug($client->id . ": is synced with other slave " . $otherclient->id);
			}
		}
	}
	
	# get our slaves
	for my $otherclient (@{$client->slaves()}) {

		push @buddies, $otherclient;

		$log->debug($client->id . ": is synced with it's slave " . $otherclient->id);
	}

	return @buddies;
}

sub isSyncedWith {
	my $client = shift;
	my $buddy  = shift;
	
	for my $i (syncedWith($client)) {

		if ($buddy == $i) {

			$log->debug($client->id . ": is synced with " . $buddy->id);

			return 1;
		}
	}

	$log->debug($client->id . ": is NOT synced with " . $buddy->id);

	return 0;
}

sub canSyncWith {
	my $client = shift;

	my @buddies = ();

	if (blessed($client) && $client->isPlayer()) {

		for my $otherclient (Slim::Player::Client::clients()) {

			# skip ourself
			next if ($client eq $otherclient);

			# we only sync slimproto devices
			next if (!$otherclient->isPlayer());

			# only include masters and un-sync'ed clients.
			next if (isSlave($otherclient));

			push @buddies, $otherclient;
		}
	}
	
	return @buddies;
}

sub uniqueVirtualPlayers {
	my @players = ();

	for my $player (Slim::Player::Client::clients()) {

		# only include masters and un-sync'ed clients.
		next if (isSlave($player));

		push @players, $player;
	}

	return @players;
}

# checkSync:
#   syncs up the start of playback of synced clients
#   resyncs clients between songs if some clients have multiple outstanding chunks
sub checkSync {
	my $client = shift;

	$log->debug(sprintf("Player %s has %d chunks and %d%% full buffer", 
		$client->id, scalar(@{$client->chunks}), $client->usage
	));

	if (!isSynced($client) || $client->prefGet('silent')) {
		return;
	}

	return if $client->playmode eq 'stop';

	my @group = ($client, syncedWith($client));

	# if we're synced and waiting for the group's buffers to fill,
	# check if our buffer has passed the 64K level. If so, indicate
	# that we're ready to be unpaused.  If everyone else is now ready,
	# unpause all the clients at once.
	if ($client->readytosync == 0) {
		
		# Bug 1869, there is a race condition where the player will keep sending STAT responses
		# from the previous track even though we think it's starting to buffer the current
		# track.  This situation is detected if $client->songElapsedSeconds is not 0
		if ( $client->songElapsedSeconds == 0 ) {
			
			my $threshold = $client->prefGet('syncBufferThreshold');
		
			# Threshold is 128 bytes for local tracks, but it needs to be about 20K for remote streams
			eval {
				my $playlist = Slim::Player::Playlist::playList($client);
				my $track = $playlist->[ Slim::Player::Source::streamingSongIndex($client) ];
				if ( Slim::Music::Info::isRemoteURL( $track->url ) ) {
					$threshold += 20480;
				}
			};

			my $fullness = $client->bufferFullness();
			my $usage = $client->usage();

			$log->info($client->id . " checking buffer fullness: $fullness (threshold: $threshold)");

			if 	((defined($fullness) && $fullness > $threshold) ||
				 (defined($usage) && $usage > 0.90)) {

				$client->readytosync(1);
		
				$log->info($client->id . " is ready to sync " . Time::HiRes::time());

				my $allReady = 1;

				for my $everyclient (@group) {

					if (!$everyclient->readytosync) {
						$allReady = 0;
					}
				}
			
				if ($allReady) {

					$log->info("all clients ready to sync now. unpausing them.");

					for my $everyclient (@group) {
						$everyclient->resume;
					}
				}
			}
		}

	# now check to see if every player has run out of data...
	} elsif ($client->readytosync == -1) {

		$log->info($client->id . " has run out of data, checking to see if we can push on...");

		my $allReady = 1;

		for my $everyclient (@group) {

			if ($everyclient->readytosync != -1) {

				$allReady = 0;
			}
		}

		if ($allReady) {

			$log->info("everybody's run out of data.  Let's start them up...");

			for my $everyclient (@group) {
				$everyclient->readytosync(0);
			}

			if ($client->playmode ne 'playout-stop') {

				Slim::Player::Source::skipahead($client);

			} else {

				$log->info("End of playlist, and players have played out. Going to playmode stop.");

				Slim::Player::Source::playmode($client,'stop');

				$client->update;
			}
		}
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
	my $client = shift || return undef;

	return @{$client->slaves};
}

# returns the master if it's a slave, otherwise returns undef
sub isSlave {
	my $client = shift || return undef;

	return $client->master;
}

sub masterOrSelf {
	my $client = shift;
	
	assert($client);

	return $client->master || $client;
}

sub isSynced {
	my $client = shift;

	return (scalar(@{$client->slaves}) || $client->master);
}

sub syncGroupPref {
	my ($client, $pref, $val) = @_;

	my $syncgroupid = $client->prefGet('syncgroupid') || return undef;

	if ($val) {
		Slim::Utils::Prefs::set("$syncgroupid-Sync", $val, $pref);

		return undef;
	}

	my $ret = Slim::Utils::Prefs::getInd("$syncgroupid-Sync", $pref);

	if (!defined($ret)) {

		$ret = masterOrSelf($client)->prefGet($pref);

		$log->info("Creating Sync group pref for: $pref group: $syncgroupid");

		Slim::Utils::Prefs::set("$syncgroupid-Sync", $ret, $pref);
	}

	return $ret;
}
				
1;

__END__
