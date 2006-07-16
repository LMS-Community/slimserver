package Slim::Utils::Scheduler;

# $Id$
#
# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This module implements a simple scheduler for cooperative multitasking 
#
# XXXXX - The main server does not use this code anymore, since scanning has
# been split into a separate process. 3rd party plugins, such as LazySearch &
# Trackstat, which need to do background processing of the database set tasks
# for the scheduler. XXXX
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

use strict;

use Slim::Utils::Misc;
use Slim::Utils::PerfMon;

my $curtask = 0;            # the next task to run
my @background_tasks = ();  # circular list of references to arrays (sub ptrs with args)
my $lastpass = 0;

our $schedulerTask = Slim::Utils::PerfMon->new('Scheduler Task', [0.002, 0.005, 0.010, 0.015, 0.025, 0.050, 0.1, 0.5, 1, 5]), 1;

sub add_task {
	my @task = @_;

	$::d_scheduler && msg("Adding task: @task\n");

	push @background_tasks, \@task;
}

sub remove_task {
	my ($taskref, @taskargs) = @_;
	
	my $i = 0;

	while ($i < scalar (@background_tasks)) {

		my ($subref, @subargs) = @{$background_tasks[$i]};

		if ($taskref eq $subref) {
			$::d_scheduler && msg("Removing taskptr $i: $taskref\n");
			splice @background_tasks, $i, 1; 
		}

		$i++;
	}

	# loop around when we get to the end of the list
	if ($curtask >= (@background_tasks)) {
		$curtask = 0;
	}			
}

# run one background task
# returns 0 if there is nothing to run
sub run_tasks {
	return 0 if scalar !@background_tasks;

	my $busy = 0;
	my $now  = Time::HiRes::time();
	
	# run tasks at least once half second.
	if (($now - $lastpass) < 0.5) {

		for my $client (Slim::Player::Client::clients()) {

			if (Slim::Player::Source::playmode($client) eq 'play' && 
			    $client->isPlayer() && 
			    $client->usage() < 0.5) {

				$busy = 1;
				last;
			}
		}
	}
	
	if (!$busy) {
		my $taskptr = $background_tasks[$curtask];
		my ($subptr, @subargs) = @$taskptr;

		if (&$subptr(@subargs) == 0) {

			# the task has finished. Remove it from the list.
			$::d_scheduler && msg("Scheduler: task finished: $subptr\n");
			splice(@background_tasks, $curtask, 1);

		} else {

			$curtask++;
		}

		$lastpass = $now;

		# loop around when we get to the end of the list
		if ($curtask >= scalar @background_tasks) {
			$curtask = 0;
		}

		$::perfmon && $schedulerTask->log(Time::HiRes::time() - $now) && 
			msg(sprintf("  %s\n", Slim::Utils::PerlRunTime::realNameForCodeRef($subptr)), undef, 1);
	}

	return 1;
}

1;
