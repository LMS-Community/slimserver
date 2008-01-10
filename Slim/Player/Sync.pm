package Slim::Player::Sync;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Scalar::Util qw(blessed);
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $log = logger('player.sync');

my $prefs = preferences('server');

my %nextCheckSyncTime;	# kept for each sync-group master player
use constant CHECK_SYNC_INTERVAL        => 0.950;
use constant MIN_DEVIATION_ADJUST       => 0.010;
use constant MAX_DEVIATION_ADJUST       => 10.000;
use constant PLAYPOINT_RECENT_THRESHOLD => 3.0;

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

	if ( $log->is_info ) {
		$log->info(sprintf("syncname for %s is %s", $client->id, (join ' & ',@names)));
	}

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

	# bail if we don't have sync state
	if (!defined($client->syncgroupid)) {
		return;
	}
	
	if ( $log->is_info ) {
		$log->info($client->id . ": unsyncing");
	}

	my $syncgroupid = $client->syncgroupid;
	my $lastInGroup;
	my $master = $client->master;
	
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

		$newmaster->audioFilehandleIsSocket($client->audioFilehandleIsSocket);
		$client->audioFilehandleIsSocket(0);	

		$newmaster->frameData($client->frameData);
		$client->frameData(undef);	

		$newmaster->initialStreamBuffer($client->initialStreamBuffer);
		$client->initialStreamBuffer(undef);	

		$newmaster->streamformat($client->streamformat);
		$client->streamformat(undef);	

		$newmaster->resumePlaymode($client->resumePlaymode);
		$client->resumePlaymode(undef);	

		$master = $newmaster;

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
		
		$client->master(undef);
		
		Slim::Player::Playlist::copyPlaylist($client, $master);

		$lastInGroup = $master if !scalar(@{$master->slaves});

	} else {

		$lastInGroup = $client;
	}
	
	if ($lastInGroup) {
		Slim::Player::Source::resetFrameData($lastInGroup);
	}
	else {
	    # do we still need to save frame data?
	    my $needFrameData = 0;
	    foreach ( $master, Slim::Player::Sync::slaves($master) ) {
		    my $model = $_->model();
		    last if $needFrameData = ($model eq 'slimp3' || $model eq 'squeezebox');
	    }
	    Slim::Player::Source::resetFrameData($master) unless ($needFrameData);
	}

	# check for any players in group which are off and hence not synced
	my @players = Slim::Player::Client::clients();
	my @inGroup = ();
	
	foreach my $other (@players) {

		next if ($other->power || $other eq $client );
		
		my $syncpref = $prefs->client($other)->get('syncgroupid');
		next if !defined $syncpref;
		
		push @inGroup, $other if ($syncpref == $syncgroupid);
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
	
	if ( $log->is_info ) {
		$log->info($client->id .": syncing");
	}

	# we're already synced up!
	if (isSynced($client) && isSynced($buddy) && master($client) eq master($buddy)) {
		return;
	}
	
	unsync($client);
	
	$buddy = masterOrSelf($buddy);

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

		$prefs->client($client)->set('syncgroupid', $masterID);
		$prefs->client($client->master)->set('syncgroupid', $masterID);
		
	}
}

sub deleteSyncPrefs {
	my $client = shift;
	my $last   = shift;

	my $clientID    = $client->id();
	my $syncgroupid = $client->syncgroupid;

	if ($last) {

		$log->info("Deleting Sync group prefs for group: $syncgroupid");

		$prefs->remove('$syncgroupid-Sync');
	}

	$log->info("Clearing Sync master for $clientID");

	$client->syncgroupid(undef);
	$prefs->client($client)->remove('syncgroupid');
}

# Restore Sync Operation
sub restoreSync {
	my $client = shift;
	my $masterID = ($prefs->client($client)->get('syncgroupid'));

	if ($masterID && ($client->power() || $prefs->client($client)->get('syncPower'))) {

		my @players = Slim::Player::Client::clients();

		foreach my $other (@players) {

			next if ($other eq $client);
			next if (!$other->power() && !$prefs->client($other)->get('syncPower'));

			my $othermasterID = $prefs->client($other)->get('syncgroupid');

			if ($othermasterID && ($othermasterID eq $masterID)) {
				$client->syncgroupid($masterID);
				$other->syncgroupid($masterID);
				$other->execute( [ 'sync', $client->id ] );
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

				# $log->debug($client->id . ": is synced with other slave " . $otherclient->id);
			}
		}
	}
	
	# get our slaves
	for my $otherclient (@{$client->slaves()}) {

		push @buddies, $otherclient;

		# $log->debug($client->id . ": is synced with it's slave " . $otherclient->id);
	}

	return @buddies;
}

sub isSyncedWith {
	my $client = shift;
	my $buddy  = shift;
	
	for my $i (syncedWith($client)) {

		if ($buddy == $i) {

			if ( $log->is_debug ) {
				$log->debug($client->id . ": is synced with " . $buddy->id);
			}

			return 1;
		}
	}

	if ( $log->is_debug ) {
		$log->debug($client->id . ": is NOT synced with " . $buddy->id);
	}

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

	if (!isSynced($client)) {
		return;
	}

	return if $client->playmode eq 'stop';

	if ( 0 && $log->is_debug && isSynced($client) ) {
		$log->debug(sprintf("Player %s has %d chunks and %d%% full buffer, readyToSync=%s", 
			$client->id, scalar(@{$client->chunks}), $client->usage, $client->readytosync()
		));
	}

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
			
			my $threshold = $prefs->client($client)->get('syncBufferThreshold') * 1024;
		
			# Threshold is usually 128 kbytes for local tracks, but it needs to be about 20K for remote streams
			eval {
				my $playlist = Slim::Player::Playlist::playList($client);
				my $track = $playlist->[ Slim::Player::Source::streamingSongIndex($client) ];
				if ( Slim::Music::Info::isRemoteURL( $track->url ) ) {
					if ($threshold < 20480) {
						$threshold = 20480;
					}
				}
			};

			my $fullness = $client->bufferFullness();
			my $usage = $client->usage();

			if ( $log->is_info ) {
				$log->info($client->id . " checking buffer fullness: $fullness (threshold: $threshold)");
			}

			if 	((defined($fullness) && $fullness > $threshold) ||
				 (defined($usage) && $usage > 0.90)) {

				$client->readytosync(1);
		
				if ( $log->is_info ) {
					$log->info($client->id . " is ready to sync");
				}

				my $allReady = 1;
				my $playerStartDelay = 0;	# ms

				for my $everyclient (@group) {

					if ( !$everyclient->readytosync ) {
						$allReady = 0;
					}
					else {
						my $delay;	# ms
						if (($delay = $prefs->client($everyclient)->get('startDelay')
									+ $prefs->client($everyclient)->get('playDelay'))
							 > $playerStartDelay )
						{
							$playerStartDelay = $delay;
						}
					}
				}
			
				if ($allReady) {

					$log->info("all clients ready to sync now. unpausing them.");
					
					my $startAt = Time::HiRes::time() 
						+ ($playerStartDelay + ( $prefs->get('syncStartDelay') || 100 )) / 1000;

					for my $everyclient (@group) {
						$everyclient->startAt( $startAt -
							($prefs->client($everyclient)->get('startDelay')
							+ $prefs->client($everyclient)->get('playDelay')) / 1000
							);
					}
				}
			}
		}

	# now check to see if every player has run out of data...
	}
	elsif ($client->readytosync == -1) {

		if ( $log->is_info ) {
			$log->info($client->id . " has run out of data, checking to see if we can push on...");
		}

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

				my $nextsong = Slim::Player::Source::nextsong($client);
				if ( defined $nextsong ) {
					$client->execute( [ 'playlist', 'jump', $nextsong ] );
				}

			} else {

				$log->info("End of playlist, and players have played out. Going to playmode stop.");

				Slim::Player::Source::playmode($client,'stop');

				$client->update;
			}
		}
	}
	elsif ( isMaster($client) ) {
		# check to see if resynchronization is necessary

		my $now = Time::HiRes::time();

		return if $now < $nextCheckSyncTime{$client};

		$nextCheckSyncTime{$client} = $now + CHECK_SYNC_INTERVAL;

		# $log->debug("checksync: checking for resync");

		# need a recent play-point from all players in the group, otherwise give up
		my $recentThreshold = $now - PLAYPOINT_RECENT_THRESHOLD;
		my @playerPlayPoints;
		foreach my $player (@group) {
			next unless $prefs->client($player)->get('maintainSync');
			my $playPoint = $player->playPoint();
			if ( !defined $playPoint ) {
				if ( $log->is_debug ) {
					$log->debug($player->id() ." bailing as no playPoint");
				}
				return;
			}
			if ($playPoint->[0] > $recentThreshold) {
				push(@playerPlayPoints, [$player,
										$playPoint->[1] + $prefs->client($player)->get('playDelay')/1000]
					);
			}
			else {
				if ( $log->is_debug ) {
					$log->debug(
						$player->id() ." bailing as playPoint too old: ".
						($now - $playPoint->[0]) . "s"
					);
				}
				return;
			}
		}
		return unless scalar(@playerPlayPoints);

		if ( $log->is_debug ) {
			my $first = $playerPlayPoints[0][1];
			my $str = sprintf("%s: %.3f", $playerPlayPoints[0][0]->id(), $first);
			foreach ( @playerPlayPoints[1 .. $#playerPlayPoints] ) {
				$str .= sprintf(", %s: %+5d", $_->[0]->id(), ($_->[1] - $first) * 1000);
			}
			$log->debug("playPoints: $str");
		}

		# sort the play-points by decreasing apparent-start-time
		@playerPlayPoints = sort {$b->[1] <=> $a->[1]} @playerPlayPoints;

		# clean up the list of stored frame data
		# (do this now, so that it does not delay critial timers when using pauseFor())
		Slim::Player::Source::purgeOldFrames( $client, $recentThreshold - $playerPlayPoints[0][1] );

		# find the reference player - the most-behind that does not support skipAhead
		my $reference;
		for ( $reference = 0; $reference < $#playerPlayPoints; $reference++ ) {
			last unless $playerPlayPoints[$reference][0]->can('skipAhead');
		}
		my $referenceTime = $playerPlayPoints[$reference][1];
		# my $referenceMinAdjust = $prefs->client($playerPlayPoints[$reference][0])->get('minSyncAdjust')/1000;

		# tell each player that is out-of-sync with the reference to adjust
		for ( my $i = 0; $i < @playerPlayPoints; $i++ ) {
			next if ($i == $reference);
			my $player = $playerPlayPoints[$i][0];
			my $delta = abs($playerPlayPoints[$i][1] - $referenceTime);
			next if ($delta > MAX_DEVIATION_ADJUST
				|| $delta < MIN_DEVIATION_ADJUST
				|| $delta < $prefs->client($player)->get('minSyncAdjust')/1000
				# || $delta < $referenceMinAdjust
				);
			if ($i < $reference) {
				if ( $log->is_debug ) {
					$log->debug( sprintf("%s resync: skipAhead %dms", $player->id(), $delta * 1000) );
				}
				
				$player->skipAhead($delta);
				$nextCheckSyncTime{$client} += 1;
			}
			else {
				if ( $log->is_debug ) {
					$log->debug( sprintf("%s resync: pauseFor %dms", $player->id(), $delta * 1000) );
				}
				
				$player->pauseForInterval($delta);
				$nextCheckSyncTime{$client} += $delta;
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

	my $syncgroupid = $prefs->client($client)->get('syncgroupid') || return undef;

	if (defined $val) {

		my $hash = $prefs->get("$syncgroupid-Sync");

		$hash->{$pref} = $val;

		$prefs->set("$syncgroupid-Sync", $hash);

		return undef;
	}

	my $ret = ($prefs->get("$syncgroupid-Sync") || {})->{ $pref };

	if (!defined($ret)) {

		my $hash = $prefs->get("$syncgroupid-Sync") || {};

		$ret = $hash->{$pref} = $prefs->client(masterOrSelf($client))->get($pref);

		$log->info("Creating Sync group pref for: $pref group: $syncgroupid");

		$prefs->set("$syncgroupid-Sync", $hash);
	}

	return $ret;
}

1;

__END__
