package Slim::Utils::AutoRescan::Win32;

# Squeezebox Server Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# $Id$

use strict;

use Slim::Utils::Log;
use Slim::Utils::Timers;

use Win32::IPC;
use Win32::ChangeNotify;

use constant INTERVAL => 10; # XXX

my $log = logger('scan.auto');

# One ChangeNotify object per directory
my %dirs;

sub canWatch {
	my ( $class, $dir ) = @_;
	
	# XXX: If path is a network share, fall back to stat-based monitoring

	return 1;
}

sub watch {
	my ( $class, $dir, $cb ) = @_;
	
	if ( scalar keys %dirs ) {
		$class->shutdown();
	}
	
	main::DEBUGLOG && $log->is_debug && $log->debug( "Monitoring $dir for changes using Win32::ChangeNotify" );
	
	# XXX store directories in scanned_files table?
	# XXX: Use Slim::Utils::Scanner::Local->find
	$class->recurse( $dir, sub {
		my $subdir = shift;
		
		$dirs{$subdir} = undef;
	} );
	
	# XXX: process via Scheduler
	for my $dir ( keys %dirs ) {
		$dirs{$dir} = Win32::ChangeNotify->new(
			$dir,
			0,
			  FILE_NOTIFY_CHANGE_DIR_NAME
			| FILE_NOTIFY_CHANGE_FILE_NAME
			| FILE_NOTIFY_CHANGE_SIZE
			| FILE_NOTIFY_CHANGE_LAST_WRITE,
		);
	}
	
	Slim::Utils::Timers::killTimers( $class, \&_poll );
	Slim::Utils::Timers::setTimer(
		$class,
		Time::HiRes::time() + INTERVAL,
		\&_poll,
		$cb,
	);
}

sub _poll {
	my ( $class, $cb ) = @_;
	
	main::DEBUGLOG && $log->is_debug && $log->debug( 'Polling ChangeNotify...' );
	
	while ( my ($dir, $cn) = each %dirs ) {
		my $result = $cn->wait(0);
		if ( $result == 1 ) {
			$cn->reset;
			
			$cb->( $dir );
		}
	}
	
	# Schedule next check
	Slim::Utils::Timers::setTimer(
		$class,
		Time::HiRes::time() + INTERVAL,
		\&_poll,
		$cb,
	);
}

sub shutdown {
	my $class = shift;
	
	for my $cn ( values %dirs ) {
		$cn->close;
	}
	
	Slim::Utils::Timers::killTimers( $class, \&_poll );		
}

1;