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

sub process {
	my $self = shift;
	
	main::idleStreams();
	
	return $self->SUPER::process(@_);
}

1;
	
