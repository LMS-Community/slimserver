package Slim::Utils::Timers;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use Slim::Utils::Misc;

# Timers are stored in a list of hashes containing:
#  the time after which the timer should fire, 
#  a reference to the function, 
#  and a list of arguments.
#
# Timers are checked whenever we come out of select, or every 10ms,
# whichever is greater.

our @timers = ();
our @secondlines = ();

my $pos = 0;
my $pos2 = 0;
my $string;
my $sline = -1;

my $checkingTimers = 0; # Semaphore to avoid timer callbacks executing inside each other

#
# Call any pending timers which have now elapsed.
#
sub checkTimers {

	return if $checkingTimers;

	$checkingTimers = 1;

	if ($Slim::Player::SLIMP3::SLIMP3Connected && !$::scanOnly) {
		Slim::Networking::Protocol::readUDP();
	}

	my $numtimers = (@timers);
	my $now = Time::HiRes::time();
	
	if ($numtimers > 500) {
		die "Insane number of timers: $numtimers\n";		
	}
	
	my $timer = shift(@timers);
	
	if (defined($timer) && ($timer->{'when'} <= $now)) {

		my $subptr = $timer->{'subptr'};
		my $client = $timer->{'client'};
		my $args =	$timer->{'args'};
	
		$::d_time && msg("firing timer " . ($now - $timer->{'when'}) . " late.\n");
	
		no strict 'refs';
		&$subptr($client, @{$args});
		$::d_perf && ((Time::HiRes::time() - $now) > 0.5) && msg("timer $subptr too long: " . (Time::HiRes::time() - $now) . "seconds!\n");

		$timer = shift(@timers);
	}
	
	if (defined($timer)) {
		unshift @timers, $timer;
	}

	$checkingTimers = 0;
}

#
# Adjust all timers time by a given delta
# Called when time skips backwards and we need to adjust the timers respectively.
#
sub adjustAllTimers {
	my $delta = shift;
	
	$::d_time && msg("adjustAllTimers: time travel!");
	foreach my $timer (@timers) {
		$timer->{'when'} = $timer->{'when'} + $delta;
	}
}

#
# Return the time until the next timer is set to go off, 0 if overdue
# Return nothing if there are no timers
#

sub nextTimer {
	return (undef) if (!scalar(@timers) || $checkingTimers );

	my $delta = $timers[0]{'when'} - Time::HiRes::time();
	
	# return 0 if the timer is overdue
	$delta = 0 if ($delta <=0);
	
	return $delta;
}	

#
#  For debugging - prints out a list of all pending timers
#
sub listTimers {
	msg("timers: \n");

	foreach my $timer (@timers) {
		msg(join("\t", $timer->{'client'}, $timer->{'when'}, $timer->{'subptr'}, "\n"));
	}
}

#
#  Schedule a timer for $client to fire after $when, calling $subptr with
#  arguments @args.  Returns a referen to the timer so that it can be killed specifically later.
#
sub setTimer {
	my ($client, $when, $subptr, @args) = @_;
	if ($::d_time) {
		my $now = Time::HiRes::time();
		msg("settimer: $subptr, now: $now, time: $when \n");
		if ($when < $now) {
			msg("}{}{}{}{}{}{}{}{}{}  Set a timer in the past!");
		}
	}

    # The list of timers is maintained in sorted order, so
    # we only have to check the head.

	# Find the slot where we should insert this new timer
	my $i = 0;
	foreach my $timer (@timers) { 
		last if ($timer->{'when'} > $when);
		$i++;
	}

	my $newtimer = {};

	$newtimer->{'client'} = $client;
	$newtimer->{'when'} = $when;
	$newtimer->{'subptr'} = $subptr;
	$newtimer->{'args'} = \@args;

	splice(@timers, $i, 0, $newtimer);
	return $newtimer;
}

# throw out any pending timers that match the client and the subroutine
sub killTimers {
	my ($client, $subptr) = @_;
	my $i = 0;
	my $killed = 0;
	my $timer;
	
	while ($timer = $timers[$i]) {
		if (($timer->{'client'} eq $client) && ($timer->{'subptr'} eq $subptr)) {
			splice( @timers, $i, 1);
			$killed++;
		} else {
			$i++;
		}
	}
	return $killed;
}

# optimize if we know there's only one outstanding timer that matches
sub killOneTimer {
	my ($client, $subptr) = @_;
	my $i = 0;
	my $timer;
	
	while ($timer = $timers[$i]) {
		if (($timer->{'client'} eq $client) && ($timer->{'subptr'} eq $subptr)) {
			splice( @timers, $i, 1);
			return
		}
		$i++;
	}
}

sub forgetClient {
	my $client = shift;
	my $count = scalar(@timers);
	for (my $i = 0; $i < $count; $i++) {
		my $timer = $timers[$i];
		if (defined($timer) && ($timer->{'client'} eq $client)) {
			splice( @timers, $i, 1);
			redo;
		}
	}
}

# kill a specific timer
sub killSpecific {
	my $timer = shift;
	my $count = scalar(@timers);

	for (my $i = 0; $i < $count; $i++) {
		if ($timers[$i] == $timer) {
			splice( @timers, $i, 1);
			return 1;
		}
	}	
	warn "attempted to delete non-existent timer: $timer\n";
	return 0;
}

# count the matching timers for a given client and subroutine
sub pendingTimers {
	my $client = shift;
	my $subptr = shift;
	my $count = 0;

	# count pending matching timers 
	foreach my $timer (@timers) {
		if (($timer->{'client'} eq $client) && ($timer->{'subptr'} eq $subptr) ) {
			$count++;
		}
	}
	return $count;
}

#fire the first timer matching a client/subptr
sub firePendingTimer {
	my $client = shift;
	my $subptr = shift;
	my $foundTimer;
	my $count = scalar(@timers);
	# find first pending matching timers 
	for (my $i = 0; $i < $count; $i++) {
		my $timer = $timers[$i];
		if (defined($timer) && ($timer->{'client'} eq $client) && ($timer->{'subptr'} eq $subptr) ) {
			$foundTimer = splice( @timers, $i, 1);
			last;
		}
	}
	
	if (defined $foundTimer) {
		my @args =@{$foundTimer->{'args'}};
		return &$subptr($client, @args);
	}
}

1;

__END__
