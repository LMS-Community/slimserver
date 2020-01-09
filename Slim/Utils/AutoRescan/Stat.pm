package Slim::Utils::AutoRescan::Stat;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.


use strict;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

use constant INTERVAL_MINUTES => 10;

my $log = logger('scan.auto');

my $prefs = preferences('server');

my $active = 0;

my $statclass;
if ( main::HAS_AIO ) {
	$statclass = 'Slim::Utils::AutoRescan::Stat::AIO';
}
else {
	$statclass = 'Slim::Utils::AutoRescan::Stat::Async';
}
eval "use $statclass";
die $@ if $@;

sub canWatch { 1 }

sub watch {
	my ( $class, $dir, $cb ) = @_;
	
	if ( $active ) {
		$class->shutdown();
	}
	
	$active = 1;
	
	my $interval = ( $prefs->get('autorescan_stat_interval') || INTERVAL_MINUTES ) * 60;

	main::DEBUGLOG && $log->is_debug && $log->debug( "Starting stat monitoring for $dir, interval $interval" );

	Slim::Utils::Timers::killTimers( $class, \&_stat );
	Slim::Utils::Timers::setTimer(
		$class,
		Time::HiRes::time() + $interval,
		\&_stat,
		$dir,
		$cb,
	);
}

sub _stat {
	my ( $class, $dir, $cb ) = @_;
	
	my $isDebug = $log->is_debug;
	
	main::DEBUGLOG && $log->is_debug && (my $start = AnyEvent->now);
	
	my $interval = ( $prefs->get('autorescan_stat_interval') || INTERVAL_MINUTES ) * 60;
	
	my $setTimer = sub {
		Slim::Utils::Timers::setTimer(
			$class,
			Time::HiRes::time() + $interval,
			\&_stat,
			$dir,
			$cb,
		);
	};
	
	# If a scan is running (i.e. wipe and rescan with scanner.pl), don't trigger a stat check
	if ( Slim::Music::Import->stillScanning ) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Not running stat check, other scan is currently running");
		
		$setTimer->();
	}
	else {	
		$statclass->check( $dir, $cb, sub {
			if ( main::DEBUGLOG && $log->is_debug ) {
				my $diff = sprintf "%.2f", AnyEvent->now - $start;
				$log->debug("Stat check finished in $diff seconds");
			}
		
			$setTimer->();
		} );
	}
}

sub shutdown {
	my $class = shift;
	
	main::DEBUGLOG && $log->is_debug && $log->debug('Stopping stat monitoring');
	
	Slim::Utils::Timers::killTimers( $class, \&_stat );
	
	$statclass->cancel;
	
	$active = 0;
}

1;