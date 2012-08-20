package Slim::Plugin::PreventStandby::Win32;

# Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Win32::API;

sub new {
	my $class = shift;

	my $self = {
		SetThreadExecutionState => Win32::API->new('kernel32', 'SetThreadExecutionState', 'N', 'N')
	};
	
	return bless $self, $class;
}

sub setBusy {
	my $self = shift;
	
	if ($self->{SetThreadExecutionState}) {
		$self->{SetThreadExecutionState}->Call(1);
	}
}

sub canSetBusy {
	return shift->{SetThreadExecutionState} ? 1 : 0;
}


1;

__END__
