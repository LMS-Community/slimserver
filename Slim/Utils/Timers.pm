package Slim::Utils::Timers;

# $Id$

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Utils::Timers

=head1 SYNOPSIS

    # Run someCode( $client, @args ) in 20 seconds
    Slim::Utils::Timers::setTimer( $client, Time::HiRes::time() + 20, \&someCode, @args );

    # On second thought, don't run it
    Slim::Utils::Timers::killTimers( $client, \&someCode );

=head1 DESCRIPTION

Schedule functions to run at some point in the future.

Two classes of timers exist - Normal timers and High Priority timers.  High timers are used by
animation routines to ensure smooth animation even when other normal timers may be
scheduled to run.

High timers are also allowed to run any time main::idleStreams() is called, so long-running
tasks should call main::idleStreams() to yield time to animation and audio streaming.

=head1 METHODS

=cut

use strict;
use warnings;

use Scalar::Util qw(blessed);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::PerfMon;
use Slim::Utils::PerlRunTime;

# Set to enable a list of all timers every 5 seconds
our $d_watch_timers = 0;

# Use POE::XS::Queue::Array >= 0.002 if available
BEGIN {
	my $hasXS;

	sub hasXS {
		return $hasXS if defined $hasXS;
	
		$hasXS = 0;
		eval {
			require POE::XS::Queue::Array;
			die if $POE::XS::Queue::Array::VERSION eq '0.001'; # 0.001 has memory leaks
			$hasXS = 1;
		};
		if ($@) {
			require POE::Queue::Array;
		}
	
		return $hasXS;
	}

	# alias PQA's ITEM methods
	if ( hasXS() ) {
		*ITEM_ID      = \&POE::XS::Queue::Array::ITEM_ID;
		*ITEM_PAYLOAD = \&POE::XS::Queue::Array::ITEM_PAYLOAD;
	}
	else {
		*ITEM_ID      = \&POE::Queue::Array::ITEM_ID;
		*ITEM_PAYLOAD = \&POE::Queue::Array::ITEM_PAYLOAD;
	}
}

our $normal = ( hasXS() )
	? POE::XS::Queue::Array->new()
	: POE::Queue::Array->new();
	
our $high = ( hasXS() )
	? POE::XS::Queue::Array->new()
	: POE::Queue::Array->new();
  
my $checkingNormalTimers = 0; # Semaphore to avoid normal timer callbacks executing inside each other
my $checkingHighTimers = 0;   # Semaphore for high priority timers

our $timerLate = Slim::Utils::PerfMon->new('Timer Late', [0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.5, 1, 5]);
our $timerTask = Slim::Utils::PerfMon->new('Timer Task', [0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.5, 1, 5]);

my $log = logger('server.timers');

$d_watch_timers && setTimer( undef, time + 5, \&listTimers );

=head2 checkTimers()

Called from the main idle loop, checkTimers runs all high priority timers 
or at most one normal timer.

=cut

sub checkTimers {

	# check High Priority timers first (animation)
	# return if already inside one
	if ($checkingHighTimers) {
	
		$log->debug("[high] blocked checking - already processing a high timer!");

		return;
	}

	$checkingHighTimers = 1;

	my $now = Time::HiRes::time();
	my $fired = 0;
	
	my $nextHigh = $high->get_next_priority();

	while ( defined $nextHigh && $nextHigh <= $now ) {

		my (undef, undef, $high_timer) = $high->dequeue_next();
		
		$fired++;
		
		my $high_subptr = $high_timer->{'subptr'};
		my $high_objRef = $high_timer->{'objRef'};
		my $high_args   = $high_timer->{'args'};

		if ($log->is_info && $high_subptr) {

			my $name = Slim::Utils::PerlRunTime::realNameForCodeRef($high_subptr);

			$log->info("[high] firing $name " . ($now - $high_timer->{'when'}) . " late.");
		}

		if ( $high_subptr ) {	

			$high_subptr->($high_objRef, @{$high_args});

		} else {

			$log->warn("[high] no subptr: " . Data::Dump::dump($high_timer));
		}

		$nextHigh = $high->get_next_priority();
	}

	$checkingHighTimers = 0;

	return if $fired;

	# completed check of High Priority timers

	if ($Slim::Player::SLIMP3::SLIMP3Connected) {
		Slim::Networking::UDP::readUDP();
	}
	
	# Check Normal timers - return if already inside one
	if ($checkingNormalTimers) {

		if ($log->is_debug) {

			$log->debug("[norm] blocked checking - already processing a normal timer!");
		}

		return;
	}

	$checkingNormalTimers = 1;
  
	my $nextNormal = $normal->get_next_priority();
	
	if ( defined $nextNormal && $nextNormal <= $now ) {
		
		my (undef, undef, $timer) = $normal->dequeue_next();

		my $subptr = $timer->{'subptr'};
		my $objRef = $timer->{'objRef'};
		my $args   = $timer->{'args'};

		if ($log->is_info && $subptr) {
			my $name = Slim::Utils::PerlRunTime::realNameForCodeRef($subptr);

			$log->info("[norm] firing $name " . ($now - $timer->{'when'}) . " late.");
		}

		$::perfmon && $timerLate->log($now - $timer->{'when'});

		if ( $subptr ) {

			eval { $subptr->($objRef, @{$args}) };

			if ($@) {
				logError("Timer failed: $@");
			}

		} else {

			$log->warn("Normal timer with no subptr: " . Data::Dump::dump($timer));
		}

		$::perfmon && $timerTask->log(Time::HiRes::time() - $now, undef, $subptr);
	}

	$checkingNormalTimers = 0;
}

=head2 adjustAllTimers( $delta )

If the server's clock goes backwards (DST, NTP drift adjustments, etc)
this function is called to adjust all timers by the amount the clock was
changed by.

=cut

sub adjustAllTimers {
	my $delta = shift;

	$log->warn("adjustAllTimers: time travel!");

	for my $item ( $high->peek_items( sub { 1 } ) ) {
		$high->adjust_priority( $item->[ITEM_ID], sub { 1 }, $delta );
	}
	
	for my $item ( $normal->peek_items( sub { 1 } ) ) {
		$normal->adjust_priority( $item->[ITEM_ID], sub { 1 }, $delta );
	}
}

=head2 nextTimer()

Returns the time until the next scheduled timer, 0 if overdue, or
undef if there are no timers.  This is used by the
main loop to determine how long to wait in select().

=cut

sub nextTimer {
	
	my $nextHigh   = $high->get_next_priority();
	my $nextNormal = $normal->get_next_priority();

	my $next = (defined($nextNormal) && !$checkingNormalTimers) ? $nextNormal : undef;
	
	if (defined($nextHigh) && (!defined($next) || $nextHigh < $next) && !$checkingHighTimers ) {
		$next = $nextHigh;
	}

	return undef if !defined $next;

	my $delta = $next - Time::HiRes::time();
	
	# return 0 if the timer is overdue
	$delta = 0 if ($delta <=0);
	
	return $delta;
}	

=head2 listTimers()

Lists all pending timers in an easy-to-read format for debugging.

=cut

sub listTimers {
	my $now = Time::HiRes::time();

	$log->debug(sprintf("High timers: (%d)", $high->get_item_count));

	for my $item ( $high->peek_items( sub { 1 } ) ) {
		
		my $timer = $item->[ITEM_PAYLOAD];
		my $name  = Slim::Utils::PerlRunTime::realNameForCodeRef( $timer->{'subptr'} );
		my $diff  = $timer->{'when'} - $now;
		
		my $obj = $timer->{'objRef'};
		if ( blessed $obj && $obj->isa('Slim::Player::Client') ) {
			$obj = $obj->macaddress();
		}

		$log->debug(sprintf("%50.50s %.6s %s", $obj, $diff, $name));
	}

	$log->debug(sprintf("Normal timers: (%d)", $normal->get_item_count));

	for my $item ( $normal->peek_items( sub { 1 } ) ) {
		
		my $timer = $item->[ITEM_PAYLOAD];
		my $name  = Slim::Utils::PerlRunTime::realNameForCodeRef( $timer->{'subptr'} );
		my $diff  = $timer->{'when'} - $now;
		my $obj   = $timer->{'objRef'} || '';

		if ( blessed $obj && $obj->isa('Slim::Player::Client') ) {
			$obj = $obj->macaddress();
		}

		$log->debug(sprintf("%50.50s %.6s %s", $obj, $diff, $name));
	}
	
	$d_watch_timers && setTimer( undef, time + 5, \&listTimers );
}

=head2 setHighTimer( $obj, $when, $coderef, @args )

Schedule a high priority timer.  See setTimer for documentation.

=cut

sub setHighTimer {
	my ($objRef, $when, $subptr, @args) = @_;

	if ($log->is_debug) {

		my $now  = Time::HiRes::time();
		my $name = Slim::Utils::PerlRunTime::realNameForCodeRef($subptr);
		my $diff = $when - $now;

		$log->debug("[high] Set $name, in $diff seconds");

		if ($when < $now) {
			$log->debug("Set a timer in the past for [$name]!");
		}
	}

	my $newtimer = {
		'objRef' => $objRef,
		'when'   => $when,
		'subptr' => $subptr,
		'args'   => \@args,
	};
	
	$high->enqueue( $when, $newtimer );

	return $newtimer;
}

=head2 setTimer( $obj, $when, $coderef, @args )

Schedule a normal priority timer.  Returns a reference to the internal timer
object.  This can be passed to killSpecific to remove this specific timer.

=over 4

=item obj

$obj can be any value you would like passed to $coderef as the first argument.

=item when

A hi-res epoch time value for when the timer should fire.  Typically, this is set
with Time::HiRes::time() + $seconds.

=item coderef

A code reference that will be run when the timer fires.  It is passed $obj as the first
argument, followed by any other arguments specified.

=item args

An array of any other arguments to be passed to $coderef.

=back

=cut

sub setTimer {
	my ($objRef, $when, $subptr, @args) = @_;

	if ($log->is_debug) {

		my $now  = Time::HiRes::time();
		my $name = Slim::Utils::PerlRunTime::realNameForCodeRef($subptr);
		my $diff = $when - $now;

		$log->debug("[norm] Set $name, in $diff seconds");

		if ($when < $now) {
			$log->debug("Set a timer in the past for [$name]!");
		}
	}

	my $newtimer = {
		'objRef' => $objRef,
		'when'   => $when,
		'subptr' => $subptr,
		'args'   => \@args,
	};
	
	$normal->enqueue( $when, $newtimer );
	
	my $numtimers = $normal->get_item_count();

	if ($numtimers > 500) {
		
		for my $item ( $normal->peek_items( sub { 1 } ) ) {
			
			my $t = $item->[ITEM_PAYLOAD];
		
			if ( ref($t->{'subptr'}) eq 'CODE' ) {

				logError(Slim::Utils::PerlRunTime::deparseCoderef($t->{'subptr'}));
			}
		}

		logger('')->logdie("FATAL: Insane number of timers: [$numtimers]");
	}

	return $newtimer;
}

=head2 killTimers ( $obj, $coderef )

Remove all normal timers that match the $obj and $coderef.  Returns the number
of timers removed.

=cut

sub killTimers {
	my $objRef = shift;
	my $subptr = shift || return;

	my @killed = $normal->remove_items( sub {

		my $timer = shift;

		if ( $timer->{subptr} eq $subptr ) {
			if ( !defined $objRef && !defined $timer->{objRef} ) {
				return 1;
			}
			elsif ( $timer->{objRef} && $timer->{objRef} eq $objRef ) {
				return 1;
			}
		}
		return 0;	
	} );

	if ($log->is_info && @killed) {

		my $name = Slim::Utils::PerlRunTime::realNameForCodeRef( $subptr );

		$log->info("[norm] Killed " . scalar @killed . " timer(s) for $objRef / $name");
	}
	
	return scalar @killed;
}

=head2 killHighTimers ( $obj, $coderef )

Remove all high timers that match the $obj and $coderef.  Returns the number
of timers removed.

=cut

sub killHighTimers {
	my $objRef = shift;
	my $subptr = shift || return;

	my @killed = $high->remove_items( sub {

		my $timer = shift;

		if ( $timer->{subptr} eq $subptr ) {
			if ( !defined $objRef && !defined $timer->{objRef} ) {
				return 1;
			}
			elsif ( $timer->{objRef} && $timer->{objRef} eq $objRef ) {
				return 1;
			}
		}

		return 0;	
	} );
	
	if ($log->is_info && @killed) {

		my $name = Slim::Utils::PerlRunTime::realNameForCodeRef( $subptr );

		$log->info("[high] Killed " . scalar @killed . " timer(s) for $objRef / $name");
	}

	return scalar @killed;
}

=head2 killOneTimer( $obj, $coderef )

Remove at most one normal or high timer.  If you know there is only one timer
that will match, this method is slightly faster than killTimers.  Returns 1 if
the timer was removed, 0 if the timer could not be found.

=cut

sub killOneTimer {
	my $objRef = shift;
	my $subptr = shift || return;
	
	# This method is only used by normal timers, so check those first
	
	my @killed = $normal->remove_items( sub {
		my $timer = shift;
		if ( $timer->{subptr} eq $subptr ) {
			if ( !defined $objRef && !defined $timer->{objRef} ) {
				return 1;
			}
			elsif ( $timer->{objRef} && $timer->{objRef} eq $objRef ) {
				return 1;
			}
		}
		return 0;
	}, 1 );
	
	return 1 if @killed;
	
	# If not found, look in high timers
	
	@killed = $high->remove_items( sub {
		my $timer = shift;
		if ( $timer->{subptr} eq $subptr ) {
			if ( !defined $objRef && !defined $timer->{objRef} ) {
				return 1;
			}
			elsif ( $timer->{objRef} && $timer->{objRef} eq $objRef ) {
				return 1;
			}
		}
		return 0;
	}, 1 );
	
	return @killed ? 1 : 0;
}

=head2 forgetTimer( $obj )

Remove all timers that match $obj.  Can be used to quickly clear all timers
for a specific $client, for example.  Returns the number of timers killed.

=cut

sub forgetTimer {
	my $objRef = shift;
	
	my @killed = $high->remove_items( sub {
		my $timer = shift;
		if ( !defined $objRef && !defined $timer->{objRef} ) {
			return 1;
		}
		elsif ( $timer->{objRef} && $timer->{objRef} eq $objRef ) {
			return 1;
		}
		return 0;
	} );
	
	my @killed2 = $normal->remove_items( sub {
		my $timer = shift;
		if ( !defined $objRef && !defined $timer->{objRef} ) {
			return 1;
		}
		elsif ( $timer->{objRef} && $timer->{objRef} eq $objRef ) {
			return 1;
		}
		return 0;
	} );
	
	my $total = 0 + scalar @killed + scalar @killed2;
	
	return $total;
}

=head2 killSpecific( $timer )

Takes the $timer returned by setTimer or setHighTimer
and removes that specific timer.  Returns 1 if the timer was
removed, 0 if the timer could not be found.

=cut

sub killSpecific {
	my $timer = shift;
	
	my @killed = $high->remove_items( sub {
		my $t = shift;
		return 1 if $timer eq $t;
	}, 1 );
	
	if ($log->is_info && @killed) {

		my $name = Slim::Utils::PerlRunTime::realNameForCodeRef( $timer->{subptr} );

		$log->info("killSpecific: Removed high timer $name");
	}

	return 1 if @killed;
	
	@killed = $normal->remove_items( sub {
		my $t = shift;
		return 1 if $timer eq $t;
	}, 1 );
	
	if ($log->is_info && @killed) {

		my $name = Slim::Utils::PerlRunTime::realNameForCodeRef( $timer->{subptr} );

		$log->info("killSpecific: Removed normal timer $name");
	}
	
	return @killed ? 1 : 0;
}

=head2 firePendingTimer( $obj, $coderef )

Immediately run the specified timer, if it exists.  The timer is then removed
so it will not run at it's previously scheduled time. Returns the return value
of $coderef or undef if the timer does not exist.

=cut

sub firePendingTimer {
	my $objRef = shift;
	my $subptr = shift;
	my $foundTimer;

	# find first pending matching timers 
	my @normal = $normal->peek_items( sub {
		my $timer = shift;
		if ( $timer->{subptr} eq $subptr ) {
			if ( !defined $objRef && !defined $timer->{objRef} ) {
				return 1;
			}
			elsif ( $timer->{objRef} && $timer->{objRef} eq $objRef ) {
				return 1;
			}
		}
		return 0;	
	}, 1 );
	
	if ( @normal ) {
		$foundTimer = $normal[0]->[ITEM_PAYLOAD];
		$normal->remove_item( $normal[0]->[ITEM_ID], sub { 1 } );
	}
	
	if (defined $foundTimer) {
		return $subptr->( $objRef, @{ $foundTimer->{args} } );
	}
	
	return;
}

=head2 pendingTimers( $obj, $coderef )

Returns the total number of pending timers matching $obj and $coderef.

=cut

#
# Note: This method is not used by anything in trunk, but at least one plugin relies
# on it (ShutdownServer)
#
sub pendingTimers {
	my $objRef = shift;
	my $subptr = shift || return 0;
	my $count = 0;
	
	$high->peek_items( sub {
		my $timer = shift;
		if ( $timer->{subptr} eq $subptr ) {
			if ( !defined $objRef && !defined $timer->{objRef} ) {
				$count++;
			}
			elsif ( $timer->{objRef} && $timer->{objRef} eq $objRef ) {
				$count++;
			}
		}
	} );
	
	$normal->peek_items( sub {
		my $timer = shift;
		if ( $timer->{subptr} eq $subptr ) {
			if ( !defined $objRef && !defined $timer->{objRef} ) {
				$count++;
			}
			elsif ( $timer->{objRef} && $timer->{objRef} eq $objRef ) {
				$count++;
			}
		}
	} );
	
	return $count;
}

1;

__END__

=head1 SEE ALSO

This module uses L<POE::XS::Queue::Array> as the underlying timer data structure.

See L<POE::Queue> for documentation.

=cut
