package Slim::Utils::AutoRescan;

# Squeezebox Server Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# $Id$

# This class handles file system change detection and auto-rescan on
# Mac 10.5+, Linux with inotify, and Windows.

use strict;

use Path::Class ();

use Slim::Utils::Log;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::Scanner::Local;
use Slim::Utils::Timers;

use constant BATCH_DELAY => 15; # how long to wait for events to settle before handling them

my $log = logger('scan.auto');

my $prefs = preferences('server');

my %queue = ();
my $osclass;

sub init {
	my $class = shift;
	
	my $audiodir = $prefs->get('audiodir') || return;
	
	Slim::Schema->init();
	
	# Try to load a filesystem watch module
	if ( main::ISMAC ) {
		eval { require Slim::Utils::AutoRescan::OSX };
		if ( $@ ) {
			$log->error( "FSEvents is not supported on your version of OSX, falling back to stat-based monitoring ($@)" );
		}
		else {
			$osclass = 'Slim::Utils::AutoRescan::OSX';
		}
	}
	elsif ( main::ISWINDOWS ) {
		eval { require Slim::Utils::AutoRescan::Win32 };
		if ( $@ ) {
			$log->error( "Error loading Win32 auto-rescan module, falling back to stat-based monitoring ($@)" );
		}
		else {
			# XXX needs improved
			$osclass = 'Slim::Utils::AutoRescan::Win32';
		}
	}
	elsif ( Slim::Utils::OSDetect::isLinux() ) {
		eval { require Slim::Utils::AutoRescan::Linux };
		if ( $@ ) {
			$log->error( "Error loading Linux auto-rescan module, falling back to stat-based monitoring ($@)" );
		}
		else {
			$osclass = 'Slim::Utils::AutoRescan::Linux';
		}
	}
	
	# XXX maybe add a kqueue watcher for BSD, see File::ChangeNotify::Watcher::KQueue
	
	# Verify the dir can be monitored using the OS-specific method
	if ( $osclass && !$osclass->canWatch( $audiodir ) ) {
		$osclass = undef;
	}
	
	if ( !$osclass ) {
		# XXX: needs a pref to disable stat-based monitoring
		eval { require Slim::Utils::AutoRescan::Stat };
		if ( $@ ) {
			$log->error( "Unable to use stat-based monitoring ($@)" );
		}
		else {
			$osclass = 'Slim::Utils::AutoRescan::Stat';
		}
	}
	
	if ( $osclass ) {
		# Stop watcher if currently running
		$osclass->shutdown;
		
		my $rewatch = sub {
			my $audiodir = $prefs->get('audiodir');
			
			if ( defined $audiodir ) {
				$osclass->shutdown;
				$osclass->watch( $audiodir, \&fsevent );
			}
		};
		
		# Re-watch if directory changes
		$prefs->setChange( $rewatch, 'audiodir');
		
		# Re-watch upon scanner finish
		Slim::Control::Request::subscribe( $rewatch, [[ 'rescan', 'done' ]] );
	}

	# Perform a rescan in case any files have changed while server was off
	# Only do this if we have files in the database
	my $rescanning = 0;
	if ( my ($count) = Slim::Schema->dbh->selectrow_array("SELECT COUNT(*) FROM tracks") ) {
		if ( !Slim::Music::Import->stillScanning ) {
			# Clear progress info
			Slim::Utils::Progress->clear;
			
			# Start async rescan
			Slim::Utils::Scanner::Local->rescan( $audiodir, {
				types    => qr/(?:list|audio)/,
				scanName => 'directory',
				progress => 1,
			} );
	
			$rescanning = 1;
		}
	}

	if ( !$rescanning ) {
		# Start change watcher now, if a rescan is run, it will start after it's finished
		$osclass && $osclass->watch( $audiodir, \&fsevent );
	}
}

sub fsevent {
	my $path = shift;
	
	main::DEBUGLOG && $log->is_debug && $log->debug("File system event(s) detected: $path");
	
	$queue{ $path } = 1;
			
	# Wait until no events are received for a bit before dealing with the changed queue
	Slim::Utils::Timers::killTimers( undef, \&handleQueue );
	Slim::Utils::Timers::setTimer( undef, AnyEvent->now + BATCH_DELAY, \&handleQueue );
}

sub handleQueue {
	my $audiodir = $prefs->get('audiodir') || return;
	
	# We need to ignore the top-level dir (unless it's the only event),
	# or else we will have to do a full rescan
	if ( scalar( keys %queue ) > 1 ) {
		delete $queue{ $audiodir };
		delete $queue{ "$audiodir/" };
	}
	
	# Check each path, if another path in the queue contains it, remove it
	my @todo;
	
	my @list = map { Path::Class::dir($_) } sort keys %queue;
	
	OUTER:
	for my $next ( @list ) {
		for my $check ( @list ) {
			next if $next eq $check;
			
			if ( $check->subsumes($next) ) {
				# scanning $check will cover $next, so remove it
				main::DEBUGLOG && $log->is_debug && $log->debug("Removing child path $next");
				
				delete $queue{$next};
				delete $queue{ "$next/" };
				next OUTER;
			}
		}
	}
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( "Auto-rescanning: " . Data::Dump::dump(\%queue) );
	}
	
	# Wait if scanner is currently running
	if ( Slim::Music::Import->stillScanning ) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Main scanner is running, ignoring auto-rescan event");
		return;
	}
	
	# Stop watcher
	$osclass->shutdown();
	
	# Rescan tree
	Slim::Utils::Scanner::Local->rescan( [ sort keys %queue ], {
		types    => qr/(?:list|audio)/,
		scanName => 'directory',
		progress => 1,
	} );
	
	%queue = ();
	
	# Watcher will be restarted via 'rescan done' subscription above
}

sub shutdown {
	my $class = shift;
	
	if ( $osclass ) {
		$osclass->shutdown();
	}
}

1;
