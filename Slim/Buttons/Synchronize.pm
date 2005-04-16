package Slim::Buttons::Synchronize;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Display::Display;

our %functions = ();

sub init {

	Slim::Buttons::Common::addMode('synchronize', getFunctions(), \&setMode);

	# Each button on the remote has a function:
	%functions = (
		'up' => sub  {
			my $client = shift;
			my $newpos = Slim::Buttons::Common::scroll($client,-1,scalar(@{$client->syncSelections}),$client->syncSelection);
			if (scalar(@{$client->syncSelections}) < 2) {
				$client->bumpUp();
			} elsif ($newpos != $client->syncSelection) {
				$client->syncSelection($newpos);
				$client->pushUp();
			}
		},

		'down' => sub {
			my $client = shift;
			my $newpos = Slim::Buttons::Common::scroll($client,1,scalar(@{$client->syncSelections}),$client->syncSelection);
			if (scalar(@{$client->syncSelections}) < 2) {
				$client->bumpDown();
			} elsif ($newpos != $client->syncSelection) {
				$client->syncSelection($newpos);
				$client->pushDown();
			}
		},

		'left' => sub {
			my $client = shift;
			Slim::Buttons::Common::popModeRight($client);
		},

		'right' => sub  {
			my $client = shift;
			
			my $selectedClient = $client->syncSelections($client->syncSelection);
		
			my @oldlines = Slim::Display::Display::curLines($client);
		
			if (Slim::Player::Sync::isSyncedWith($client, $selectedClient) || ($client eq $selectedClient)) {
				Slim::Player::Sync::unsync($client);
			} else {
				Slim::Player::Sync::sync($client, $selectedClient);
			}

			$client->pushLeft(\@oldlines, [Slim::Display::Display::curLines($client)]);
		},
	);
}

sub getFunctions {
	return \%functions;
}

sub loadList {
	my $client = shift;
	
	@{$client->syncSelections} = Slim::Player::Sync::canSyncWith($client);
	
	# add ourselves (for unsyncing) if we're already part of a synced.
	if (Slim::Player::Sync::isSynced($client)) { push @{$client->syncSelections}, $client };

	if (!defined($client->syncSelection()) || $client->syncSelection >= @{$client->syncSelections}) {
		$client->syncSelection(0);
	}
}

sub lines {
	my $client = shift;

	my $line1;
	my $line2;
	my $symbol = undef;

	loadList($client);
	
	if (scalar @{$client->syncSelections} < 1) {

		warn "Can't sync without somebody to sync with!";
		Slim::Buttons::Common::popMode($client);

	} else {
			# get the currently selected client
			my $selectedClient = $client->syncSelections($client->syncSelection);
			
			if (Slim::Player::Sync::isSyncedWith($client, $selectedClient) || $selectedClient eq $client) {
				$line1 = $client->string('UNSYNC_WITH');
			} else {
				$line1 = $client->string('SYNC_WITH');
			}

			$line2 = buddies($client, $selectedClient);			
	}

	return ($line1, $line2, undef, Slim::Display::Display::symbol('rightarrow'));
}

sub buddies {
	my $client = shift;
	my $selectedClient = shift;

	my @buddies = ();
	my $list = '';
	
	foreach my $buddy (Slim::Player::Sync::syncedWith($selectedClient)) {
		if ($buddy ne $client) {
			push @buddies, $buddy;	
		}
	}
	
	if ($selectedClient ne $client) {
		push @buddies, $selectedClient;
	}
	
	while (scalar(@buddies) > 2) {
		my $buddy = pop @buddies;
		$list .= $buddy->name() . ", ";
	}
	
	if (scalar(@buddies) > 1) {
		my $buddy = pop @buddies;
		$list .= $buddy->name() . " " . $client->string('AND') . " ";		
	}

	my $buddy = pop @buddies;
	$list .= $buddy->name();
	
	return $list;
}

sub setMode {
	my $client = shift;
	$client->lines(\&lines);
}

1;

__END__
