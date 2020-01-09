package Slim::Web::Template::Context;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This custom subclass allows for multitasking during template
# processing.  Templates that take too long can interrupt streaming
# to devices with small buffers (i.e. SB1)

use strict;
use base 'Template::Context';

# Following allow timing of template processing excluding time in idleStreams and log4perl
my $depth = 0;   # depth of template being processed
my @start = [0]; # start time for latest execute of this template
my @this  = [0]; # time spent in this template
my @total = [0]; # total time spent in this template + deaper templates

my $last = 0;

sub process {
	my $self = shift;

	my $t1 = Time::HiRes::time();

	if ($t1 - $last > 0.05) {

		main::idleStreams();

		$last = $t1;

	}

	unless (main::PERFMON) {

		return $self->SUPER::process(@_);

	} else {

		my $temp = $_[0];

		$this[$depth] += $t1 - $start[$depth];

		$depth++;

		my $t2 = AnyEvent->time;

		$this[$depth]  = 0;
		$total[$depth] = 0;
		$start[$depth] = $t2;

		my $ret = \$self->SUPER::process(@_);

		my $t3 = AnyEvent->time;

		my $this = $this[$depth] + $t3 - $start[$depth];
		my $total= $total[$depth] += $this;

		Slim::Utils::PerfMon->check('template', $total, 
									sprintf("%-32s (this templ: %7d us)", "  " x $depth . (ref $temp ? $temp->{'name'} : $temp),
											$this * 1000000));

		$depth--;

		$start[$depth] = Time::HiRes::time();
		$total[$depth] += $total;

		return $$ret;
	}
}

1;

