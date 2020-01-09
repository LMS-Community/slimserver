package Slim::Plugin::PreventStandby::Win32;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use base qw(Slim::Plugin::PreventStandby::OS);

use strict;
use Win32::API;

my $SetThreadExecutionState;

sub new {
	my $class = shift;

	$SetThreadExecutionState = Win32::API->new('kernel32', 'SetThreadExecutionState', 'N', 'N') || return;
	
	return $class;
}

sub setBusy {
	$SetThreadExecutionState->Call(1);
}

1;

__END__
