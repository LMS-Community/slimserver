package Slim::Utils::AutoRescan::Linux;

# Squeezebox Server Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# $Id$

use strict;

use Slim::Utils::Log;
use Slim::Utils::Scanner::Local;

use File::Basename;
use File::Slurp;
use Linux::Inotify2;

my $log = logger('scan.auto');

my $i;
my $w;

# sth is global to support cancel
my $sth;

sub canWatch {
	my ( $class, $dir ) = @_;
	
	# If path is a network share, we will get inotify events for 
	# changes made from the local machine but not from other machines
	# on the network.  Fall back to stat-based monitoring in this case.
	
	# not as good as comparing 'df -L' with 'df -Pl' but more portable	
	my $mounts = File::Slurp::read_file('/proc/mounts');
		
	# /dev/mmcblk0p1 on /media/mmcblk0p1 type vfat (roptions)
	# 192.168.1.11:/data1 on /mnt2 type nfs (options)

 	for my $line ( split /\n/, $mounts ) {
		my ($source, $mountpoint, $fstype) = split /\s+/, $line;
		if ( $dir =~ /^$mountpoint/ &&  $fstype =~ /^(nfs|smb)/ ) {
			# It's a remote share
			main::DEBUGLOG && $log->is_debug && $log->debug("Remote mountpoint $mountpoint detected, using stat-based monitoring");
			return 0;
		}
	}
	
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
	
	my $file = $e->fullname;
	
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
		
		$log->debug( 'Inotify event: ' . join( ',', @types ) . ' ' . $file );
	}
	
	if ( $e->IN_ISDIR ) {
		# Make sure we care about this directory
		return unless Slim::Utils::Misc::folderFilter( $file );
	
		if ( $e->IN_CREATE ) {
			# New directory was created, watch it
			# This is done so that copying in a new directory structure won't trigger rescan
			# too soon because we only got one event for the directory
			main::DEBUGLOG && $log->is_debug && $log->debug("New directory $file created, watching it");
		
			_watch_directory( $file, $cb );
		}
	}
	else {
		# Make sure we care about this file
		return unless Slim::Utils::Misc::fileFilter( dirname($file), basename($file) );
	}

	$cb->( $file );
}

sub shutdown {
	my $class = shift;
	
	if ( $i ) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Stopping change monitoring');
		
		# Kill watchers
		$w = undef;
		$i = undef;
	}
	
	if ( $sth ) {
		# Cancel setting of watches
		$sth->finish;
		undef $sth;
	}
}

sub _watch_directory {
	my ( $dir, $cb ) = @_;
	
	my $isDebug = main::DEBUGLOG && $log->is_debug;
	
	# Watch all directories that were found by the scanner
	my $dbh = Slim::Schema->dbh;
	
	$sth = $dbh->prepare_cached("SELECT url FROM scanned_files WHERE filesize = 0");
	$sth->execute;
	
	my $url;
	$sth->bind_columns(\$url);
	
	if ( main::DEBUGLOG && $isDebug ) {
		my ($count) = $dbh->selectrow_array("SELECT COUNT(*) FROM scanned_files WHERE filesize = 0");
		$log->debug( "Setting up inotify for $count dirs" );
	}
	
	my $handler = sub {
		event( shift, $cb );
	};
	
	my $watch_dirs = sub {
		if ( $sth && $sth->fetch ) {
			my $dir = Slim::Utils::Misc::pathFromFileURL($url);
			
			main::DEBUGLOG && $isDebug && $log->debug("inotify watching: $dir");
			
			$i->watch(
				$dir,
				IN_MOVE | IN_CREATE | IN_CLOSE_WRITE | IN_DELETE | IN_DELETE_SELF | IN_MOVE_SELF,
				$handler,
			) or logWarning("Inotify watch creation failed for $dir: $!");
			
			return 1;
		}
		
		$sth && $sth->finish;
		undef $sth;
		
		return 0;
	};
	
	Slim::Utils::Scheduler::add_task( $watch_dirs );
}

1;
