package Slim::Utils::AutoRescan::Win32;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.


use strict;

use Slim::Utils::Log;
use Slim::Utils::Timers;

use Win32::IPC;
use Win32::ChangeNotify;

use constant INTERVAL => 10; # XXX

my $log = logger('scan.auto');

# One ChangeNotify object per directory
my %dirs;

# sth is global to support cancel
my $sth;

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
	
	my $isDebug = main::DEBUGLOG && $log->is_debug;
	
	# Watch all directories that were found by the scanner
	my $dbh = Slim::Schema->dbh;
	
	$sth = $dbh->prepare_cached("SELECT url FROM scanned_files WHERE filesize = 0");
	$sth->execute;
	
	my $url;
	$sth->bind_columns(\$url);
	
	if ( main::DEBUGLOG && $isDebug ) {
		my ($count) = $dbh->selectrow_array("SELECT COUNT(*) FROM scanned_files WHERE filesize = 0");
		$log->debug( "Setting up ChangeNotify for $count dirs" );
	}
	
	my $watch_dirs = sub {
		if ( $sth && $sth->fetch ) {
			my $dir = Slim::Utils::Misc::pathFromFileURL($url);
			
			main::DEBUGLOG && $isDebug && $log->debug("ChangeNotify watching: $dir");
			
			my $cn = Win32::ChangeNotify->new(
				$dir,
				0,
				  FILE_NOTIFY_CHANGE_DIR_NAME
				| FILE_NOTIFY_CHANGE_FILE_NAME
				| FILE_NOTIFY_CHANGE_SIZE
				| FILE_NOTIFY_CHANGE_LAST_WRITE,
			);
			
			if ( !$cn ) {
				logWarning("Unable to create ChangeNotify object for $dir");
			}
			else {
				$dirs{$dir} = $cn;
			}
			
			return 1;
		}
		
		$sth && $sth->finish;
		undef $sth;
		
		# Setup poll timer
		Slim::Utils::Timers::killTimers( $class, \&_poll );
		Slim::Utils::Timers::setTimer(
			$class,
			Time::HiRes::time() + INTERVAL,
			\&_poll,
			$cb,
		);
		
		return 0;
	};
	
	Slim::Utils::Scheduler::add_task( $watch_dirs );
}

sub _poll {
	my ( $class, $cb ) = @_;
	
	my $isDebug = main::DEBUGLOG && $log->is_debug;
	
	my $start;
	if ( main::DEBUGLOG && $isDebug ) {
		$start = AnyEvent->time;
		$log->debug( 'Polling ChangeNotify...' );
	}
	
	while ( my ($dir, $cn) = each %dirs ) {
		# XXX use wait_any instead?
		my $result = $cn->wait(0);
		if ( $result == 1 ) {
			$cn->reset;
			
			$cb->( $dir );
		}
	}
	
	main::DEBUGLOG && $isDebug && $log->debug( 'Polling ChangeNotify finished in ' . (AnyEvent->time - $start) );
	
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
	
	main::DEBUGLOG && $log->is_debug && $log->debug('ChangeNotify shutting down');
	
	for my $cn ( values %dirs ) {
		$cn->close;
	}
	
	if ( $sth ) {
		# Cancel setting of watches
		$sth->finish;
		undef $sth;
	}
	
	Slim::Utils::Timers::killTimers( $class, \&_poll );
	
	%dirs = ();
}

1;
