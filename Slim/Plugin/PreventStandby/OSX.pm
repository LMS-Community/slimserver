package Slim::Plugin::PreventStandby::OSX;

# Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Proc::Background;

use Slim::Utils::Log;

my $log   = logger('plugin.preventstandby');

my $command;
my $process;

sub new {
	my ($class, $i) = @_;

	$command = Slim::Utils::Misc::findbin('pmset');
	
	if ($command) {
		$command .= ' noidle';
	}
	else {
		$log->warn("Didn't find pmset tool - standby can't be prevented!");
	}
	
	return $class;
}

# shut down caffeinate when the plugin is being shut down
sub cleanup {
	$process->die if $process;
};

sub setBusy {
	if (!$process || !$process->alive) {
		$log->debug("Injecting some caffein to keep system alive: '$command'");
		$process = Proc::Background->new($command);
	}
}

sub setIdle {
	shift->cleanup;
}

1;

__END__
