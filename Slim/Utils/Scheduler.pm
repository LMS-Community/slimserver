package Slim::Utils::Scheduler;

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

#---------------------------------------

#
# This module implements a simple scheduler for cooperative multitasking 
#
# If you need to do something that will run for more than a few milliseconds,
# write it as a function which works on the task incrementally, returning 1 when
# it has more work to do, 0 when finished.
#
# Then add it to the list of background tasks using add_task, giving a pointer to
# your function and a list of arguments. 
#
# Background tasks should be run whenever the server has extra time on its hands, ie,
# when we'd otherwise be sitting in select. To run background tasks, call run_tasks,
# passing as the argument the amount of time (in seconds; 0.1 or less is
# recommended) that you want to spend on them.
#
#

use strict;

use Slim::Utils::Misc;

my $curtask = 0;            # the next task to run
my @background_tasks = ();  # circular list of references to arrays (sub ptrs with args)
my $lastpass = 0;

#
# add a task
#
sub add_task {
	my @task = @_;
	$::d_scheduler && msg("Adding task: @task\n");
	my $taskptr = \@task;
	$::d_scheduler && msg("Adding taskptr: $taskptr\n");
	push @background_tasks, $taskptr;
}

sub remove_task {
	my @task = @_;
	my $taskref = \@task;
	my $i = 0;
	while ($i < scalar (@background_tasks)) {
		if (@{$taskref} eq @{$background_tasks[$i]}) {
			splice @background_tasks, $i, 1; 
		} else {
			$i++;
		}
	}
	# loop around when we get to the end of the list
	if ($curtask >= (@background_tasks)) {
		$curtask = 0;
	}			
}

# run one background task
# returns 0 if there is nothing to run

sub run_tasks {

	return 0 if (scalar(@background_tasks) == 0);

	my $subptr;
	my @subargs;
	my $taskptr;
	my $busy = 0;
	my $to;
	my $now = Time::HiRes::time();
	
	#run tasks at least once a second.
	if (($now - $lastpass) < 1.0) {
		foreach my $client (Slim::Player::Client::clients()) {
			if (Slim::Player::Playlist::playmode($client) eq 'play' && 
			    $client->isPlayer() && 
			    $client->model eq 'slimp3' && 
			    $client->usage() < 0.5) {
				$busy = 1;
				$::d_perf && msg(Slim::Player::Client::id($client) . " Usage low, not running tasks.\n");
				last;
			}
		}
	}
	
	if (!$busy) {
		$taskptr = $background_tasks[$curtask];
		
		($subptr, @subargs) = @$taskptr;
		if ($::d_perf) { $to = watchDog(); }
		if (&$subptr(@subargs) == 0) {
			# the task has finished. Remove it from the list.
			$::d_scheduler && msg("TASK FINISHED: $subptr\n");
			splice(@background_tasks, $curtask, 1);
		} else {
			$curtask++;
		}
		$::d_perf && watchDog($to, "run task: $subptr");
	}
	
	# loop around when we get to the end of the list
	if ($curtask >= (@background_tasks)) {
		$curtask = 0;
	}
				
	$::d_perf && msg("Ran tasks..\n");
	
	$lastpass = $now;
	
	return scalar(@background_tasks);
}


1;
