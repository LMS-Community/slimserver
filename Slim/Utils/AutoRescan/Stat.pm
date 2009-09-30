package Slim::Utils::AutoRescan::Stat;

# Squeezebox Server Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# $Id$

use strict;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

use constant INTERVAL => 60; # XXX: needs to be configurable

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
print "$statclass\n";
eval "use $statclass";
die $@ if $@;

sub canWatch { 1 }

sub watch {
	my ( $class, $dir, $cb ) = @_;
	
	if ( $active ) {
		$class->shutdown();
	}
	
	$active = 1;
	
	my $interval = $prefs->get('autorescan_stat_interval') || INTERVAL;

	main::DEBUGLOG && $log->is_debug && $log->debug( "Starting stat monitoring for $dir, interval $interval" );

	Slim::Utils::Timers::killTimers( $class, \&_stat );
	Slim::Utils::Timers::setTimer(
		$class,
		Time::HiRes::time() + $interval,
		\&_stat,
		$dir,
		$interval,
		$cb,
	);
}

sub _stat {
	my ( $class, $dir, $interval, $cb ) = @_;
	
	my $isDebug = $log->is_debug;
	
	main::DEBUGLOG && $log->is_debug && (my $start = AnyEvent->now);
	
	$statclass->check( $dir, $cb, sub {
		if ( main::DEBUGLOG && $log->is_debug ) {
			my $diff = sprintf "%.2f", AnyEvent->now - $start;
			$log->debug("Stat check finished in $diff seconds");
		}
		
		Slim::Utils::Timers::setTimer(
			$class,
			Time::HiRes::time() + $interval,
			\&_stat,
			$dir,
			$interval,
			$cb,
		);
	} );
}

sub shutdown {
	my $class = shift;
	
	main::DEBUGLOG && $log->is_debug && $log->debug('Stopping stat monitoring');
	
	Slim::Utils::Timers::killTimers( $class, \&_stat );
	
	$statclass->cancel;
	
	$active = 0;
}

1;