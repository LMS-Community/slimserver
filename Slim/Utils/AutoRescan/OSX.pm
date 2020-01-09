package Slim::Utils::AutoRescan::OSX;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.


use strict;

use Slim::Utils::Log;

use File::Basename;
use Mac::FSEvents;

my $log = logger('scan.auto');

my $fs;
my $w;

sub canWatch {
	my ( $class, $dir ) = @_;
	
	# If path is a network share, we will get fsevents for 
	# changes made from the local machine but not from other machines
	# on the network.  Fall back to stat-based monitoring in this case.
	
	if ( $dir =~ m{^(/Volumes/[^/]+)} ) {
		# Check if mounted drive is a local disk (/dev/...)
		my $mount = $1;
		my $df = `df -l`; # list local drives only
		if ( $df !~ /$mount/ ) {
			# It's a remote share
			main::DEBUGLOG && $log->is_debug && $log->debug("Remote mountpoint $mount detected, using stat-based monitoring");
			return;
		}
	}
	
	return 1;
}

sub watch {
	my ( $class, $dir, $cb ) = @_;
	
	if ( $fs ) {
		$class->shutdown();
	}
	
	main::DEBUGLOG && $log->is_debug && $log->debug( "Monitoring $dir for changes using FSEvents" );
	
	$fs = Mac::FSEvents->new( {
		path    => $dir,
		latency => 2.0,
	} );
	
	$w = AnyEvent->io(
		fh   => $fs->watch,
		poll => 'r',
		cb   => sub {
			for my $event ( $fs->read_events ) {
				my $file = $event->path;
				
				stat $file;
				
				if ( -d _ ) {
					# Make sure we care about this directory
					return unless Slim::Utils::Misc::folderFilter($file);
				}
				else {
					# Make sure we care about this file
					return unless Slim::Utils::Misc::fileFilter( dirname($file), basename($file) );
				}
				
				$cb->( $file );
			}
		},
	);
}

sub shutdown {
	my $class = shift;
	
	if ( $fs ) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Stopping FSEvents change monitoring');
		
		$fs->stop;
		
		# Kill watchers
		$w  = undef;
		$fs = undef;
	}
}

1;