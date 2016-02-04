package Slim::Plugin::PreventStandby::OSX;

# Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use base qw(Slim::Plugin::PreventStandby::OS);

use strict;
use Proc::Background;

use Slim::Plugin::PreventStandby::Plugin;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

my $log   = logger('plugin.preventstandby');
my $prefs = preferences('plugin.preventstandby');

my $command;
my $process;

sub new {
	my ($class, $i) = @_;

	if ( $command = Slim::Utils::Misc::findbin('caffeinate') ) {
		$command .= ' -i';
	}
	elsif ( $command = Slim::Utils::Misc::findbin('pmset') ) {
		$command .= ' noidle';
	}
	else {
		$log->warn("Didn't find pmset tool - standby can't be prevented!");
		return;
	}
	
	main::DEBUGLOG && $log->debug("Going to use '$command' to prevent standby");
	
	return $class;
}

# shut down pmset when the plugin is being shut down
sub cleanup {
	$process->die if $process;
};

sub setBusy {
	my ($class, $currenttime) = @_;

	# Bug 8141: when coming out of standby, we don't want to keep the system alive for the full defined idle time
	# OSX 10.8+ often resumes for some clean up work etc. In those cases only keep LMS awake for a few minutes
	# before we can determine that we are really busy. Then either go back to sleep or to business as usual.
	if ( Slim::Plugin::PreventStandby::Plugin->_hasResumed($currenttime) ) {
		my $idletime = $prefs->get('idletime');

		Slim::Utils::Timers::killTimers( undef, \&_setShortIdleTime );
		if ($idletime && $idletime > 2) {
			Slim::Utils::Timers::setTimer(
				undef, 
				time + 60, 
				\&_setShortIdleTime
			);
		}
	}
	
	if (!$process || !$process->alive) {
		main::DEBUGLOG && $log->debug("Injecting some caffeine to keep system alive: '$command'");
		$process = Proc::Background->new($command);
	}
}

sub _setShortIdleTime {
	my $idletime = $prefs->get('idletime');

	main::DEBUGLOG && $log->debug("System came out of standby - keep alive for only a few minutes");

	Slim::Plugin::PreventStandby::Plugin->hasBeenIdle($idletime - 2) if $idletime && $idletime > 2;
}

sub setIdle {
	shift->cleanup;
}

# use short polling interval, or we might miss some activity after resume
sub pollInterval {
	return 10;
}

1;

__END__
