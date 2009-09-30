package Slim::Utils::AutoRescan::Linux;

# Squeezebox Server Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# $Id$

use strict;

use Slim::Utils::Log;
use Slim::Utils::Scanner::Local;

use Linux::Inotify2;

my $log = logger('scan.auto');

my $i;
my $w;

sub canWatch {
	my ( $class, $dir ) = @_;
	
	# If path is a network share, we will get inotify events for 
	# changes made from the local machine but not from other machines
	# on the network.  Fall back to stat-based monitoring in this case.
	
	eval {
		# not as good as comparing 'df -L' with 'df -Pl' but more portable
		
		my $mounts  = `mount`;
		
		# /dev/mmcblk0p1 on /media/mmcblk0p1 type vfat (roptions)
		# 192.168.1.11:/data1 on /mnt2 type nfs (options)
	
	 	for my $line ( split /\n/, $mounts ) {
			my ($source, undef, $mountpoint, undef, $fstype, undef) = split /\s+/, $line;
			if ($dir =~ /^$mountpoint/ &&  $fstype =~/^(nfs|smb)/) {
				# It's a remote share
				main::DEBUGLOG && $log->is_debug && $log->debug("Remote mountpoint $mountpoint detected, using stat-based monitoring");
				die;
			}
		}
	};

	return 0 if $@;
	
	# Make sure Inotify works
	eval { Linux::Inotify2->new or die "Unable to start Inotify watcher: $!" };
	if ( $@ ) {
		logWarning($@);
		return 0;
	}
	
	return 1;
}

sub watch {
	my ( $class, $dir, $cb ) = @_;
	
	if ( $i ) {
		$class->shutdown();
	}
	
	$i = Linux::Inotify2->new or die "Unable to start Inotify watcher: $!";
	
	_watch_directory( $dir, $cb );
	
	# Can't use fileno's with AnyEvent for some reason
	$w = EV::io (
		$i->fileno,
		EV::READ,
		sub { $i->poll },
	);
}

sub event {
	my ( $e, $cb ) = @_;
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		my @types;
		
		$e->IN_MODIFY      && push @types, 'modify';
		$e->IN_CLOSE_WRITE && push @types, 'close_write';
		$e->IN_ATTRIB      && push @types, 'attrib';
		$e->IN_CREATE      && push @types, 'create';
		$e->IN_DELETE      && push @types, 'delete';
		$e->IN_DELETE_SELF && push @types, 'delete_self';
		$e->IN_MOVED_FROM  && push @types, 'moved_from';
		$e->IN_MOVED_TO    && push @types, 'moved_to';
		$e->IN_MOVE_SELF   && push @types, 'move_self';
		
		$log->debug( 'Inotify event: ' . join( ',', @types ) . ' ' . $e->fullname );
	}
	
	if ( $e->IN_CREATE && $e->IN_ISDIR ) {
		# New directory was created, watch it
		main::DEBUGLOG && $log->is_debug && $log->debug('New directory ' . $e->fullname . ' created, watching it');
		
		_watch_directory( $e->fullname, $cb );
	}

	$cb->( $e->fullname );
}

sub shutdown {
	my $class = shift;
	
	if ( $i ) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Stopping change monitoring');
		
		# Kill watchers
		$w = undef;
		$i = undef;
	}
}

sub _watch_directory {
	my ( $dir, $cb ) = @_;
	
	Slim::Utils::Scanner::Local->find( $dir, { dirs => 1 }, sub {
		my $dirs = shift;
		
		# Also watch the parent directory
		unshift @{$dirs}, $dir;
		
		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug( "Monitoring " . scalar( @{$dirs} ) . " dirs for changes using Inotify:" );
			$log->debug( Data::Dump::dump($dirs) );
		}
		
		my $handler = sub {
			event( shift, $cb );
		};
		
		for my $dir ( @{$dirs} ) {
			$i->watch(
				$dir,
				IN_MOVE | IN_CREATE | IN_CLOSE_WRITE | IN_DELETE | IN_DELETE_SELF | IN_MOVE_SELF,
				$handler,
			) or logWarning("Inotify watch creation failed for $dir: $!");
		}
	} );
}

1;
