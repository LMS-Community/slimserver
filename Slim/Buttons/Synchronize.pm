package Slim::Buttons::Synchronize;

# $Id: Synchronize.pm,v 1.4 2003/08/09 16:23:43 dean Exp $

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Utils::Strings qw(string);
use Slim::Display::Display;

# Each button on the remote has a function:
my %functions = (
	'up' => sub  {
			my $client = shift;
			$client->syncSelection(Slim::Buttons::Common::scroll($client,-1,scalar(@{$client->syncSelections}),$client->syncSelection));
			$client->update();
	},
	'down' => sub {
		my $client = shift;
		$client->syncSelection(Slim::Buttons::Common::scroll($client,1,scalar(@{$client->syncSelections}),$client->syncSelection));
		$client->update();
	},
	'left' => sub {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
	'right' => sub  {
		my $client = shift;
		
		my $selectedClient = $client->syncSelections($client->syncSelection);
	
		my @oldlines = Slim::Display::Display::curLines($client);
	
		if (Slim::Player::Playlist::isSyncedWith($client, $selectedClient) || ($client eq $selectedClient)) {
			Slim::Player::Playlist::unsync($client);
		} else {
			Slim::Player::Playlist::sync($client, $selectedClient);
		}
		Slim::Display::Animation::pushLeft($client, @oldlines, Slim::Display::Display::curLines($client));
	}
);

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;

	$client->lines(\&lines);
}

sub loadList {
	my $client = shift;
	
	@{$client->syncSelections} = Slim::Player::Playlist::canSyncWith($client);
	
	# add ourselves (for unsyncing) if we're already part of a synced.
	if (Slim::Player::Playlist::isSynced($client)) { push @{$client->syncSelections}, $client };

	if (!defined($client->syncSelection()) || $client->syncSelection >= @{$client->syncSelections}) {
		$client->syncSelection(0);
	}
}

sub lines {
	my $client=shift;
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
			
			if (Slim::Player::Playlist::isSyncedWith($client, $selectedClient) || $selectedClient eq $client) {
				$line1 = Slim::Utils::Strings::string('UNSYNC_WITH');
			} else {
				$line1 = Slim::Utils::Strings::string('SYNC_WITH');
			}
			
			my @buddies = ();
			
			foreach my $buddy (Slim::Player::Playlist::syncedWith($selectedClient)) {
				if ($buddy ne $client) {
					push @buddies, $buddy;	
				}
			}
			
			if ($selectedClient ne $client) {
				push @buddies, $selectedClient;
			}
			
			while (scalar(@buddies) > 2) {
				my $buddy = pop @buddies;
				$line2 .= $buddy->name() . ", ";
			}
			
			if (scalar(@buddies) > 1) {
				my $buddy = pop @buddies;
				$line2 .= $buddy->name() . " " . Slim::Utils::Strings::string('AND') . " ";		
			}
			my $buddy = pop @buddies;
			$line2 .= $buddy->name();
	}
	return ($line1, $line2, undef, Slim::Hardware::VFD::symbol('rightarrow'));
}

1;

__END__
