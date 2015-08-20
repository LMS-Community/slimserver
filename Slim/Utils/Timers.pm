package Slim::Utils::Timers;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
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

use EV;

use Slim::Utils::Log;
use Slim::Utils::Misc;

use constant CLEANUP_INTERVAL => 30;
use constant EV_KILL          => 0xDEADBEEF;

my %TIMERS = ();
my $CLEANUP;

my $log = logger('server.timers');

=head2 setHighTimer( $obj, $when, $coderef, @args )

Schedule a high priority timer.  See setTimer for documentation.

=cut

sub setHighTimer {
	my $w = _makeTimer(@_);
	
	$w->priority(2);
	
	return $w;
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

*setTimer = \&_makeTimer;

=head2 killTimers ( $obj, $coderef )

Remove all normal timers that match the $obj and $coderef.  Returns the number
of timers removed.

=cut

sub killTimers {
	my $objRef = shift;
	my $subptr = shift || return;
	
	if ( !defined $objRef ) {
		$objRef = '';
	}
	
	if ( exists $TIMERS{$subptr}->{$objRef} ) {
		for my $timer ( @{ $TIMERS{$subptr}->{$objRef} } ) {
			$timer->cb->(EV_KILL) if $timer;
		}
		
		delete $TIMERS{$subptr}->{$objRef};
		
		return 1;
	}
	
	return;
}

=head2 killHighTimers ( $obj, $coderef )

Remove all high timers that match the $obj and $coderef.  Returns the number
of timers removed.

=cut

*killHighTimers = \&killTimers;

=head2 killOneTimer( $obj, $coderef )

Remove at most one normal or high timer.  If you know there is only one timer
that will match, this method is slightly faster than killTimers.  Returns 1 if
the timer was removed, 0 if the timer could not be found.

=cut

*killOneTimer = \&killTimers;

=head2 forgetTimer( $obj )

Remove all timers that match $obj.  Can be used to quickly clear all timers
for a specific $client, for example.

=cut

sub forgetTimer {
	my $objRef = shift;
	
	my @subs = keys %TIMERS;
	
	for my $sub ( @subs ) {
		if ( exists $TIMERS{$sub}->{$objRef} ) {
			for my $timer ( @{ $TIMERS{$sub}->{$objRef} } ) {
				$timer->cb->(EV_KILL) if $timer;
			}
			
			delete $TIMERS{$sub}->{$objRef};
		}
	}
	
	return;
}

=head2 killSpecific( $timer )

Takes the $timer returned by setTimer or setHighTimer
and removes that specific timer.  Returns 1 if the timer was
removed, 0 if the timer could not be found.

=cut

sub killSpecific {
	my $w = shift;
	
	my @subs = keys %TIMERS;
	
	for my $sub ( @subs ) {
		for my $objRef ( keys %{ $TIMERS{$sub} } ) {
			my $i = 0;
			for my $timer ( @{ $TIMERS{$sub}->{$objRef} } ) {
				if ( defined $timer && $timer == $w ) {
					$timer->cb->(EV_KILL);
					
					splice @{ $TIMERS{$sub}->{$objRef} }, $i, 1;
					
					return;
				}
				
				$i++;
			}
		}
	}
	
	return;
}

=head2 firePendingTimer( $obj, $coderef )

Immediately run the specified timer, if it exists.  The timer is then removed
so it will not run at it's previously scheduled time.  Returns 1 if the timer
was run, or undef if the timer does not exist.

=cut

sub firePendingTimer {
	my $objRef = shift;
	my $subptr = shift;
	
	if ( !defined $objRef ) {
		$objRef = '';
	}
	
	if ( my $timers = $TIMERS{$subptr}->{$objRef} ) {
		# Run the first timer and remove it
		for my $t ( @{$timers} ) {
			if ( defined $t ) {
				$t->invoke;
				return 1;
			}
		}
	}
	
	return;
}

=head2 timeChanged()

Notify this subsystem that the system clock has been changed

=cut

sub timeChanged {
	EV::now_update;
	
	# We could possibly consider going through the list of times adjusting
	# when they should fire but it is probably not worth it.
}

sub _makeTimer {
	my ($objRef, $when, $subptr, @args) = @_;
	
	if ( !defined $objRef ) {
		$objRef = '';
	}
	
	my $now = EV::now;
	
	# We could use AnyEvent->timer here but paying the overhead
	# cost of proxying the method is silly
	my $w;
	$w = EV::timer( $when - $now, 0, sub {
		if ( $_[0] && $_[0] == EV_KILL ) {
			# Nasty hack to destroy the EV::Timer object properly
			defined $w && $w->stop;
			undef $w;
			return;
		}

		main::PERFMON && ($now = AnyEvent->time);
		
		eval { $subptr->( $objRef, @args ) };
		
		main::PERFMON && Slim::Utils::PerfMon->check('timers', AnyEvent->time - $now, undef, $subptr);

		if ( $@ ) {
			my $name = main::DEBUGLOG ? Slim::Utils::PerlRunTime::realNameForCodeRef($subptr) : 'unk';

			logError("Timer $name failed: $@");
		}
		
		# Destroy the timer after it's been run
		undef $w;
	} );
	
	_storeTimer( $subptr, $objRef, $w );
	
	if ( !$CLEANUP ) {
		# start periodic cleanup timer
		$CLEANUP = 1;
		
		setTimer( undef, $now + CLEANUP_INTERVAL, \&cleanupTimers );
	}
	
	return $w;
}

# Periodically go through and clean out empty timers
sub cleanupTimers {
	my @subs = keys %TIMERS;
	
	for my $sub ( @subs ) {
		my @objs = keys %{ $TIMERS{$sub} };
		for my $obj ( @objs ) {
			my $timers = $TIMERS{$sub}->{$obj};
			while ( @{$timers} ) {
				if ( !defined $timers->[0] ) {
					splice @{$timers}, 0, 1;
				}
				else {
					last;
				}
			}
			
			if ( !scalar @{$timers} ) {
				# No timers left for this obj, remove it
				delete $TIMERS{$sub}->{$obj};
			}
		}
		
		if ( !scalar keys %{ $TIMERS{$sub} } ) {
			# No objs left for this coderef, remove it
			delete $TIMERS{$sub};
		}
	}
	
	setTimer( undef, EV::now + CLEANUP_INTERVAL, \&cleanupTimers );
}

sub _storeTimer {
	my ( $subptr, $objRef, $w ) = @_;
	
	$TIMERS{$subptr} ||= {};
	my $slot = $TIMERS{$subptr}->{$objRef} ||= [];
	push @{$slot}, $w;
	
	# Ensure the timer is destroyed after it fires (by undef $w above)
	Scalar::Util::weaken( $slot->[-1] );
}

1;

__END__
