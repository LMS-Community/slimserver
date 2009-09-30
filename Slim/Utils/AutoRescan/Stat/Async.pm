package Slim::Utils::AutoRescan::Stat::Async;

# $Id$
#
# Squeezebox Server Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, version 2.

# Async stat checker, TODO

use strict;

sub check {
	my ( $class, $dir, $cb, $finishcb ) = @_;
	
	# XXX
	
	$finishcb->();
}

sub cancel {
	my $class = shift;
	
}

1;