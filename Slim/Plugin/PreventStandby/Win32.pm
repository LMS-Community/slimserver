package Slim::Plugin::PreventStandby::Win32;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use base qw(Slim::Plugin::PreventStandby::OS);

use strict;
use Win32::API;

# # https://docs.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setthreadexecutionstate
# "Calling SetThreadExecutionState without ES_CONTINUOUS simply resets the idle timer; to keep the
# display or system in the working state, the thread must call SetThreadExecutionState periodically."
# "To run properly on a power-managed computer, applications such as fax servers, answering machines,
# backup agents, and network management applications must use both ES_SYSTEM_REQUIRED and ES_CONTINUOUS
# when they process events."
use constant ES_SYSTEM_REQUIRED   => 0x00000001;
use constant ES_AWAYMODE_REQUIRED => 0x00000040;
use constant ES_CONTINUOUS        => 0x80000000;

my $SetThreadExecutionState;

sub new {
	my $class = shift;

	$SetThreadExecutionState = Win32::API->new('kernel32', 'SetThreadExecutionState', 'N', 'N') || return;

	return $class;
}

sub setBusy {
	$SetThreadExecutionState->Call(ES_SYSTEM_REQUIRED + ES_CONTINUOUS);
}

sub setIdle {
	$SetThreadExecutionState->Call(ES_CONTINUOUS);
}

1;

__END__
