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
my $indent = 0;

my $last = 0;


sub process {
	my $self = shift;

	my $now = Time::HiRes::time();

	if ($now - $last > 0.05) {

		main::idleStreams();

		$last = $now = Time::HiRes::time();

	}

	unless ($::perfmon) {

		return $self->SUPER::process(@_);

	} else {

		my $temp = $_[0];

		$indent++;

		my $ret = \$self->SUPER::process(@_);

		$indent--;

		$procTemplate->log(Time::HiRes::time() - $now, sub { "  " x $indent . (ref $temp ? $temp->{'name'} : $temp) } );

		return $$ret;

	}
}

1;
	
