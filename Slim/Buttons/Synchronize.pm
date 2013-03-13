package Slim::Buttons::Synchronize;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Buttons::Synchronize

=head1 DESCRIPTION

L<Slim::Buttons::Synchronize> is the Logitech Media Server module to handle a player UI 
for synchronizing groups of players, and reporting the current status of sync groups

=cut

use strict;

our %functions = ();

sub init {
	Slim::Buttons::Common::addMode('synchronize', {}, \&setMode);
}

sub loadList {
	my $client = shift;
	
	@{$client->syncSelections} = Slim::Player::Sync::canSyncWith($client);
	
	# add ourselves (for unsyncing) if we're the master of a sync-group.
	if (Slim::Player::Sync::isMaster($client)) { push @{$client->syncSelections}, $client };

	if (!defined($client->syncSelection()) || $client->syncSelection >= @{$client->syncSelections}) {
		$client->syncSelection(0);
	}
}

sub lines {
	my $client = shift;

	my $line1;

	loadList($client);
	
	if (scalar @{$client->syncSelections} < 1) {

		warn "Can't sync without somebody to sync with!";
		Slim::Buttons::Common::popMode($client);

	} else {
			# get the currently selected client
			my $selectedClient = $client->syncSelections->[ $client->syncSelection ];
			
			if ($client->isSyncedWith($selectedClient)) {
				$line1 = $client->string('UNSYNC_WITH');
			} else {
				$line1 = $client->string('SYNC_WITH');
			}
	}

	return $line1;
}

sub buddies {
	my $client = shift;
	my $selectedClient = shift || $client->syncSelections->[ $client->syncSelection ];

	my @buddies = ();
	my $list = '';
	
	push @buddies, $selectedClient unless $selectedClient == $client;
	
	push @buddies, $selectedClient->syncedWith($client);
	
	while (scalar(@buddies) > 2) {
		my $buddy = shift @buddies;
		$list .= $buddy->name() . ", ";
	}
	
	if (scalar(@buddies) > 1) {
		my $buddy = shift @buddies;
		$list .= $buddy->name() . " " . $client->string('AND') . " ";		
	}

	my $buddy = shift @buddies;
	$list .= $buddy->name();
	
	return $list;
}

sub setMode {
	my $client = shift;
	my $method = shift;
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	
	loadList($client);
	
	my %params = (
		'header'         => \&lines,
		'headerArgs'     => 'C',
		'listRef'        => \@{$client->syncSelections},
		'externRef'      => sub {
								return buddies($_[0]);
							},
		'externRefArgs'  => 'CV',
		'overlayRef'     => sub { return (undef, shift->symbols('rightarrow')) },
		'overlayRefArgs' => 'C',
		'callback'       => \&syncExitHandler,
		'onChange'       => sub { $_[0]->syncSelection($_[1]); },
		'onChangeArgs'   => 'CI'
	);
	
	Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);
}

sub syncExitHandler {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);
	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
		
	} elsif ($exittype eq 'RIGHT') {
		my $selectedClient = $client->syncSelections->[ $client->syncSelection ];
	
		my @oldlines = $client->curLines();
		
		if ($client->isSyncedWith($selectedClient)) {
			$client->execute( [ 'sync', '-' ] );
		} else {
			
			# bug 9722: Tell user if their sync operation has also resulted in an unsync
			if ($client->isSynced) {
				my $lines;
				if ($client->linesPerScreen() == 1) {
					$lines = [ $client->string( 'UNSYNCING_FROM', buddies($client, $client))
								. ' ' . $client->string( 'AND' ) . ' '
								. $client->string( 'SYNCING_WITH', buddies($client))];
				} else {
					$lines = [ $client->string( 'UNSYNCING_FROM', buddies($client, $client)),
								$client->string( 'SYNCING_WITH', buddies($client))];
				}
				
				# Do this on a timer so that the mode animation can complete first
				Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + .1,
					sub {
						$client->showBriefly( {'line' => $lines}, 
							{'block' => 1, 'scroll' => 1, 'duration' => 2} );
					});
			}
			
			$selectedClient->execute( [ 'sync', $client->id ] );
		}

		$client->pushLeft(\@oldlines, $client->curLines());
	} else {
		return;
	}
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

L<Slim::Player::Sync>

=cut

1;

__END__
