package Slim::Plugin::PreventStandby::OSX;

# Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Proc::Background;

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log   = logger('plugin.preventstandby');
my $prefs = preferences('plugin.preventstandby');

my $caffeinate;
my $process;

sub new {
	my ($class, $i) = @_;

	$caffeinate = Slim::Utils::Misc::findbin('caffeinate');
	
	if (!$caffeinate) {
		$log->warn("Didn't find caffeinate tool - standby can't be prevented!");
	}
	
	return $class;
}

# shut down caffeinate when the plugin is being shut down
sub cleanup {
	$process->die if $process;
};

sub setBusy {
	if (!$process || !$process->alive) {
		$log->debug("Running caffeinate to keep system alive: $caffeinate");
		
		# run caffeinate for a loooong time - we're going to kill it if needed
		$process = Proc::Background->new("$caffeinate -i -t " . 3600 * 24 * 7);
	}
}

sub setIdle {
	shift->cleanup;
}

sub canSetBusy {
	return $caffeinate ? 1 : 0;
}

1;

__END__
