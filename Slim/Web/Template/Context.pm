package Slim::Web::Template::Context;

# $Id$

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This custom subclass allows for multitasking during template
# processing.  Templates that take too long can interrupt streaming
# to devices with small buffers (i.e. SB1)

use strict;
use base 'Template::Context';

our $procTemplate = Slim::Utils::PerfMon->new('Process Template', [0.002, 0.005, 0.010, 0.015, 0.025, 0.050, 0.1, 0.5, 1, 5]);
my $depth = 0;

my $last = 0;

my (@start, @elapsed) = ([0], [0]);

sub process {
	my $self = shift;

	my $t1 = Time::HiRes::time();

	if ($t1 - $last > 0.05) {

		main::idleStreams();

		$last = $t1;

	}

	unless ($::perfmon) {

		return $self->SUPER::process(@_);

	} else {

		my $temp = $_[0];

		$elapsed[$depth] += $t1 - $start[$depth];

		$depth++;

		my $t2 = Time::HiRes::time();

		$elapsed[$depth] = 0;
		$start[$depth]   = $t2;

		my $ret = \$self->SUPER::process(@_);

		my $t3 = Time::HiRes::time();

		$procTemplate->log($t3 - $t2,
			sub {
				my $us = ($elapsed[$depth] + $t3 - $start[$depth]) * 1000000;
				sprintf ("%-32s (this templ: %7d us)", "  " x $depth . (ref $temp ? $temp->{'name'} : $temp), $us);
			}
		);

		$depth--;

		$start[$depth] = Time::HiRes::time();

		return $$ret;

	}
}

1;

