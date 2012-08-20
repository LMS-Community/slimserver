package Slim::Plugin::PreventStandby::OSX;

# Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Utils::Log;

my $log = logger('plugin.preventstandby');

sub new {
	my ($class, $interval) = @_;

	my $self = {
		caffeinate => Slim::Utils::Misc::findbin('caffeinate'), # || '/usr/bin/caffeinate',
		interval   => ($interval || 60) + 5,
	};
	
	if (!$self->{caffeinate}) {
		$log->warn("Didn't find caffeinate tool - standby can't be prevented!");
	}
	
	return bless $self, $class;
}

sub setBusy {
	my $self = shift;
	
	if (my $caffeinate = $self->{caffeinate}) {
		$log->debug("Running caffeinate to keep system alive: $caffeinate");

		my $interval = $self->{interval};
		`$caffeinate -i -t $interval`;
	}
	
}

sub canSetBusy {
	return shift->{caffeinate} ? 1 : 0;
}

1;

__END__
