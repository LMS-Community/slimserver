package Slim::Plugin::PreventStandby::Win32;

# Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Win32::API;

use Slim::Plugin::PreventStandby::Plugin;

my $SetThreadExecutionState;

sub new {
	my $class = shift;

	$SetThreadExecutionState = Win32::API->new('kernel32', 'SetThreadExecutionState', 'N', 'N') || return;
	
	return $class;
}

sub isBusy {
	my ($class, $currenttime) = @_;
	return Slim::Plugin::PreventStandby::Plugin->_hasResumed($currenttime) || Slim::Plugin::PreventStandby::Plugin->_playersBusy();
}

sub setBusy {
	$SetThreadExecutionState->Call(1);
}

# some stubs we need for compatibility with the OSX implementation
sub cleanup {};
sub setIdle {};

1;

__END__
