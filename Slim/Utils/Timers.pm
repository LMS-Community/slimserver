package Slim::Utils::Timers;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Scalar::Util qw(blessed);

use Slim::Utils::Misc;
use Slim::Utils::PerfMon;
use Slim::Utils::PerlRunTime;

# Set to enable a list of all timers every 5 seconds
my $d_watch_timers = 0;

# Timers are stored in a list of hashes containing:
# - the time at which the timer should fire, 
# - a reference to an object
# - a reference to the function,
# - and a list of arguments.

# Two classes of timer exist - Normal timers and High Priority timers
# - High priority timers that are due are always execute first, even if a normal timer 
#   is due at an earlier time.
# - Functions assigned for callback on a normal timer may call ::idleStreams
# - Any normal timers which are due will not be executed if another normal timer is
#   currently being executed.
# - High priority timers are only blocked from execution if another High Priority
#   timer is executing (this should not occur).  They are intended for animation
#   routines which should run within ::idleStreams.
#
# Timers are checked whenever we come out of select.

# POE::XS::Queue::Array is a lot faster, but is still new and has some bugs
my $HAS_XS = 0;
use POE::Queue::Array;

our $normal = ( $HAS_XS )
	? POE::XS::Queue::Array->new()
	: POE::Queue::Array->new();
	
our $high = ( $HAS_XS )
	? POE::XS::Queue::Array->new()
	: POE::Queue::Array->new();
  
my $checkingNormalTimers = 0; # Semaphore to avoid normal timer callbacks executing inside each other
my $checkingHighTimers = 0;   # Semaphore for high priority timers

our $timerLate = Slim::Utils::PerfMon->new('Timer Late', [0.002, 0.005, 0.01, 0.015, 0.025, 0.05, 0.1, 0.5, 1, 5]);
our $timerTask = Slim::Utils::PerfMon->new('Timer Task', [0.002, 0.005, 0.01, 0.015, 0.025, 0.05, 0.1, 0.5, 1, 5], 1);

$d_watch_timers && setTimer( undef, time + 5, \&listTimers );

#
# Call any pending timers which have now elapsed.
#
sub checkTimers {

	# check High Priority timers first (animation)
	
	# return if already inside one
	if ($checkingHighTimers) {
	
		$::d_time && msg("[high] blocked checking - already processing a high timer!\n");
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

		if ( $::d_time && $high_subptr ) {
			my $name = Slim::Utils::PerlRunTime::realNameForCodeRef($high_subptr);
			msg("[high] firing $name " . ($now - $high_timer->{'when'}) . " late.\n");
		}
			
		if ( $high_subptr ) {
			no strict 'refs';	
			&$high_subptr($high_objRef, @{$high_args});
		}
		else {
			msg("[high] no subptr: " . Data::Dumper::Dumper($high_timer));
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
		$::d_time && msg("[norm] blocked checking - already processing a normal timer!\n");
		$::d_time && bt();
		return;
	}

	$checkingNormalTimers = 1;
  
	my $nextNormal = $normal->get_next_priority();
	
	if ( defined $nextNormal && $nextNormal <= $now ) {
		
		my (undef, undef, $timer) = $normal->dequeue_next();

		my $subptr = $timer->{'subptr'};
		my $objRef = $timer->{'objRef'};
		my $args   = $timer->{'args'};

		if ( $::d_time && $subptr ) {
			my $name = Slim::Utils::PerlRunTime::realNameForCodeRef($subptr);
			msg("[norm] firing $name " . ($now - $timer->{'when'}) . " late.\n");
		}
		$::perfmon && $timerLate->log($now - $timer->{'when'});
			
		if ( $subptr ) {
			no strict 'refs';
			&$subptr($objRef, @{$args});
		}
		else {
			msg("Normal timer with no subptr: " . Data::Dumper::Dumper($timer));
		}

		$::perfmon && $timerTask->log(Time::HiRes::time() - $now) && 
			msg(sprintf("    %s\n", Slim::Utils::PerlRunTime::realNameForCodeRef($subptr)), undef, 1);

		$nextNormal = $normal->get_next_priority();

	}

	$checkingNormalTimers = 0;
}

#
# Adjust all timers time by a given delta
# Called when time skips backwards and we need to adjust the timers respectively.
#
sub adjustAllTimers {
	my $delta = shift;
	
	$::d_time && msg("adjustAllTimers: time travel!");
	
	for my $item ( $high->peek_items( sub { 1 } ) ) {
		$high->adjust_priority( $item->[ITEM_ID], sub { 1 }, $delta );
	}
	
	for my $item ( $normal->peek_items( sub { 1 } ) ) {
		$normal->adjust_priority( $item->[ITEM_ID], sub { 1 }, $delta );
	}
}

#
# Return the time until the next timer is set to go off, 0 if overdue
# Return nothing if there are no timers
#
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

#
#  For debugging - prints out a list of all pending timers
#
sub listTimers {
	msgf( "High timers: (%d)\n", $high->get_item_count );
	
	my $now = Time::HiRes::time();

	for my $item ( $high->peek_items( sub { 1 } ) ) {
		
		my $timer = $item->[ITEM_PAYLOAD];
		my $name  = Slim::Utils::PerlRunTime::realNameForCodeRef( $timer->{'subptr'} );
		my $diff  = $timer->{'when'} - $now;
		
		my $obj = $timer->{'objRef'};
		if ( blessed $obj && $obj->isa('Slim::Player::Client') ) {
			$obj = $obj->macaddress();
		}

		msgf( "%50.50s %.6s %s\n", $obj, $diff, $name );
	}

	msgf( "Normal timers: (%d)\n", $normal->get_item_count );

	for my $item ( $normal->peek_items( sub { 1 } ) ) {
		
		my $timer = $item->[ITEM_PAYLOAD];
		my $name  = Slim::Utils::PerlRunTime::realNameForCodeRef( $timer->{'subptr'} );
		my $diff  = $timer->{'when'} - $now;
		
		my $obj = $timer->{'objRef'};
		if ( blessed $obj && $obj->isa('Slim::Player::Client') ) {
			$obj = $obj->macaddress();
		}

		msgf( "%50.50s %.6s %s\n", $obj, $diff, $name );
	}
	
	$d_watch_timers && setTimer( undef, time + 5, \&listTimers );
}

#
#  Schedule a High Priority timer to fire after $when, calling $subptr with
#  arguments $objRef and @args.  Returns a reference to the timer so that it can
#  be killed specifically later.
#
sub setHighTimer {
	my ($objRef, $when, $subptr, @args) = @_;

	if ($::d_time) {

		my $now = Time::HiRes::time();

		my $name = Slim::Utils::PerlRunTime::realNameForCodeRef($subptr);
		my $diff = $when - $now;
		msg("[high] set $name, in $diff sec\n");

		if ($when < $now) {
			msg("}{}{}{}{}{}{}{}{}{}  Set a timer in the past!\n");
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

#
#  Schedule a Normal Priority timer to fire after $when, calling $subptr with
#  arguments $objRef and @args.  Returns a reference to the timer so that it can
#  be killed specifically later.
#
sub setTimer {
	my ($objRef, $when, $subptr, @args) = @_;

	if ($::d_time) {
		my $now = Time::HiRes::time();
		my $name = Slim::Utils::PerlRunTime::realNameForCodeRef($subptr);
		my $diff = $when - $now;
		msg("[norm] set $name, in $diff sec\n");
		if ($when < $now) {
			msg("}{}{}{}{}{}{}{}{}{}  Set a timer in the past!\n");
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
				print Slim::Utils::PerlRunTime::deparseCoderef($t->{'subptr'}) . "\n";
			}
		}

		die "Insane number of timers: $numtimers\n";
	}

	return $newtimer;
}

#
# Throw out any pending Normal timers that match the objRef and the subroutine
#
sub killTimers {
	my $objRef = shift || return;
	my $subptr = shift || return;
	
	my @killed = $normal->remove_items( sub {
		my $timer = shift;
		if ( $timer->{subptr} eq $subptr ) {
			if ( $timer->{objRef} eq $objRef ) {
				return 1;
			}
		}
		return 0;	
	} );
	
	return scalar @killed;
}

#
# Throw out any pending High timers that match the objRef and the subroutine
#
sub killHighTimers {
	my $objRef = shift || return;
	my $subptr = shift || return;

	my @killed = $high->remove_items( sub {
		my $timer = shift;
		if ( $timer->{subptr} eq $subptr ) {
			if ( $timer->{objRef} eq $objRef ) {
				return 1;
			}
		}
		return 0;	
	} );

	return scalar @killed;
}

#
# Throw out any pending timers (Normal or High) that match the objRef and the 
# subroutine. Optimized version to use when callers knows a single timer matches.
#
sub killOneTimer {
	my $objRef = shift || return;
	my $subptr = shift || return;
	
	# This method is only used by normal timers, so check those first
	
	my @killed = $normal->remove_items( sub {
		my $timer = shift;
		if ( $timer->{subptr} eq $subptr ) {
			if ( $timer->{objRef} eq $objRef ) {
				return 1;
			}
		}
		return 0;
	}, 1 );
	
	return if @killed;
	
	# If not found, look in high timers
	
	$high->remove_items( sub {
		my $timer = shift;
		if ( $timer->{subptr} eq $subptr ) {
			if ( $timer->{objRef} eq $objRef ) {
				return 1;
			}
		}
		return 0;
	}, 1 );
}

#
# Throw out all pending timers (Normal or High) matching the objRef.
#
sub forgetTimer {
	my $objRef = shift;
	
	$high->remove_items( sub {
		my $timer = shift;
		if ( $timer->{objRef} eq $objRef ) {
			return 1;
		}
		return 0;
	} );
	
	$normal->remove_items( sub {
		my $timer = shift;
		if ( $timer->{objRef} eq $objRef ) {
			return 1;
		}
		return 0;
	} );	
}

#
# Kill a specific timer
#
sub killSpecific {
	my $timer = shift;

	return
		$high->remove_items( sub { $timer == shift } )
		||
		$normal->remove_items( sub { $timer == shift } );
}

#
# Fire the first timer matching a client/subptr
#
sub firePendingTimer {
	my $objRef = shift;
	my $subptr = shift;
	my $foundTimer;

	# find first pending matching timers 
	
	my @normal = $normal->peek_items( sub {
		my $timer = shift;
		if ( $timer->{subptr} eq $subptr ) {
			if ( $timer->{objRef} eq $objRef ) {
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
		return &$subptr($objRef, @{$foundTimer->{'args'}});
	}
}

#
# This method is not used by anything in trunk, but at least one plugin relies
# on it (ShutdownServer)
#
sub pendingTimers {
	my $objRef = shift;
	my $subptr = shift;
	my $count = 0;
	
	$high->peek_items( sub {
		my $timer = shift;
		if ( $timer->{subptr} eq $subptr ) {
			if ( $timer->{objRef} eq $objRef ) {
				$count++;
			}
		}
	} );
	
	$normal->peek_items( sub {
		my $timer = shift;
		if ( $timer->{subptr} eq $subptr ) {
			if ( $timer->{objRef} eq $objRef ) {
				$count++;
			}
		}
	} );
	
	return $count;
}

1;

__END__
