package Slim::Player::Sync;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
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
	my @buddies = $client->syncedWith();
	
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

	if ( main::INFOLOG && $log->is_info ) {
		$log->info(sprintf("syncname for %s is %s", $client->id, (join ' & ',@names)));
	}

	my $last = pop @names;

	if (scalar @names) {
		return (join ', ', @names) . ' & ' . $last;
	} else {
		return $last;
	}
}


# Restore Sync Operation
sub restoreSync {
	my $client = shift;
	my $syncgroupid = shift;
	my $noRestart = shift;
	
	if ($client->controller()->allPlayers() > 1) {
		# already synced (this can get called more than once when a player first connects)
		return;
	}
	
	if ($syncgroupid) {
		$prefs->client($client)->set('syncgroupid', $syncgroupid);
	} else {
		$syncgroupid = ($prefs->client($client)->get('syncgroupid'));
	}
	
	if ($syncgroupid) {
		foreach my $other (Slim::Player::Client::clients()) {

			next if ($other eq $client);

			my $othermasterID = $prefs->client($other)->get('syncgroupid');

			if ($othermasterID && ($othermasterID eq $syncgroupid)) {
				$other->execute( [ 'sync', $client->id, 'noRestart:' . ($noRestart ? '1' : '0') ] );
				last;
			}
		}
	}
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
			next if $otherclient->controller()->master() != $otherclient;
			
			push @buddies, $otherclient;
		}
	}
	
	return @buddies;
}

sub isMaster {
	my $client = shift;
	
	my $controller = $client->controller();
	return scalar $controller->allPlayers() > 1 && $client == $controller->master();

}

sub isSlave {
	my $client = shift || return undef;
	
	my $controller = $client->controller();
	return scalar $controller->allPlayers() > 1 && $client != $controller->master();
}


sub slaves {
	my $client = shift || return undef;
	my $controller = $client->controller();
	my $master = $controller->master();
	my @slaves;
	foreach my $player ($controller->allPlayers()) {
		if ($player != $master) {
			push @slaves, $player
		}
	}

	return @slaves;
}


1;

__END__
