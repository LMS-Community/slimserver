package Slim::Schema::Storage;

# $Id$

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Shim to get a backtrace out of throw_exception

use strict;
use base qw(DBIx::Class::Storage::DBI);

use Slim::Utils::Misc;

sub throw_exception {
	my ($self, $msg) = @_;

	errorMsg($msg);
	errorMsg("Backtrace follows:\n");
	bt();
}

1;

__END__
