package Slim::Utils::Scheduler;

# $Id$
#
# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.


=head1 NAME

Slim::Utils::Scheduler

=head1 SYNOPSIS

Slim::Utils::Scheduler::add_task(\&scanFunction);

Slim::Utils::Scheduler::remove_task(\&scanFunction);

=head1 DESCRIPTION

 This module implements a simple scheduler for cooperative multitasking 

 If you need to do something that will run for more than a few milliseconds,
 write it as a function which works on the task incrementally, returning 1 when
 it has more work to do, 0 when finished.

 Then add it to the list of background tasks using add_task, giving a pointer to
 your function and a list of arguments. 

 Background tasks should be run whenever the server has extra time on its hands, ie,
 when we'd otherwise be sitting in select.

=cut

use strict;

use Slim::Utils::Log;
use Slim::Utils::Misc;

my $curtask = 0;            # the next task to run
my @background_tasks = ();  # circular list of references to arrays (sub ptrs with args)
my $lastpass = 0;
my $paused = 0;

my $log = logger('server.scheduler');

use constant BLOCK_LIMIT => 0.01; # how long we are allowed to block the server

=head1 METHODS

=head2 add_task( @task )

 Add a new task to the scheduler. Takes an array for task identifier.  First element is a 
 code reference to the sheduled subroutine.  Subsequent elements are the args required by 
 the newly scheduled task.

=cut

sub add_task {
	my @task = @_;

	main::INFOLOG && $log->is_info && $log->info("Adding task: @task");

	push @background_tasks, \@task;
}

=head2 add_ordered_task( @task )

Same as add_task, but this task will run to completion before any other tasks are executed.

=cut

sub add_ordered_task {
	my @task = @_;
	
	main::INFOLOG && $log->is_info && $log->info("Adding ordered task: @task");
	
	# Ordered tasks are stored differently so they can be identified in run_tasks
	push @background_tasks, [ \@task ];
}

=head2 remove_task( $taskref, [ @taskargs ])

 Remove a task from teh scheduler.  The first argument is the 
 reference to the scheduled function
 
 Optionally, the arguments required when starting the scheduled task are
 included for identifying the correct task.

=cut

sub remove_task {
	my ($taskref, @taskargs) = @_;
	
	my $i = 0;

	while ($i < scalar (@background_tasks)) {

		my ($subref, @subargs) = @{$background_tasks[$i]};
		
		# check for ordered task
		if ( ref $subref eq 'ARRAY' ) {
			$subref = $subref->[0];
		}

		if ($taskref eq $subref) {

			main::INFOLOG && $log->is_info && $log->info("Removing taskptr $i: $taskref");

			splice @background_tasks, $i, 1; 
		}

		$i++;
	}

	# loop around when we get to the end of the list
	if ($curtask >= (@background_tasks)) {
		$curtask = 0;
	}			
}


=head2 run_tasks( )

 run one background task
 returns 0 if there is nothing to run

=cut

sub run_tasks {
	my $task_count = scalar @background_tasks || return 0;
	
	# Do not run if paused, return 0 to avoid spinning the main loop
	if ($paused) {
		return 0;
	}
	
	my $isDebug = main::DEBUGLOG && $log->is_debug;
	
	my $now = AnyEvent->now;
	my $ordered = 0;
	
	while (1) {
		my $taskptr = $background_tasks[$curtask];
		
		# Check for ordered task
		if ( ref $taskptr->[0] eq 'ARRAY' ) {
			$taskptr = $taskptr->[0];
			$ordered = 1;
		}
		
		my ($subptr, @subargs) = @$taskptr;

		my $cont = eval { &$subptr(@subargs) };

		if ( main::DEBUGLOG && $isDebug ) {
			my $subname = Slim::Utils::PerlRunTime::realNameForCodeRef($subptr);
			$log->debug("Scheduler ran task: $subname (ordered: $ordered)");
		}

		if ($@) {
			logError("Scheduler task failed: $@");
		}

		if ( $@ || !$cont ) {
			# the task has finished. Remove it from the list.
			main::INFOLOG && $log->is_info && $log->info("Task finished: $subptr");

			splice @background_tasks, $curtask, 1;
			$task_count--;
		}
		else {
			# Don't cycle through tasks if this one is ordered
			if ( !$ordered ) {
				$curtask++;
			}
		}

		$lastpass = $now;

		# loop around when we get to the end of the list
		if ( $curtask >= $task_count ) {
			$curtask = 0;
		}

		main::PERFMON && Slim::Utils::PerfMon->check('scheduler', AnyEvent->time - $now, undef, $subptr);
	
		# Break out if we've reached the block limit or have no more tasks
		# Note $now will remain the same across multiple calls
		if ( !$task_count || $paused || ( AnyEvent->time - $now >= BLOCK_LIMIT ) ) {
		    main::DEBUGLOG && $isDebug && $log->debug("Scheduler block limit reached (" . (AnyEvent->time - $now) . ") or scheduler was paused");
			last;
		}
		
		main::idleStreams();
	}

	return $task_count;
}

=head2 pause()

Pause any additional tasks from being called.

=cut

sub pause {
	$paused = 1;
}

=head2 unpause()

Continue running the active task(s).

=cut

sub unpause {
	$paused = 0;
}

1;
