package Slim::Utils::AutoRescan::Linux;

# Logitech Media Server Copyright 2001-2011 Logitech.
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

use constant PROC_MAX_USER_WATCHES => '/proc/sys/fs/inotify/max_user_watches';

my $log = logger('scan.auto');

my $i;
my $w;

# sth is global to support cancel
my $sth;

# Killing/recreating all inotify watchers is expensive, so 
# we handle stopped mode with a simple flag
my $STOPPED = 0;

# Keep track of max_user_watches and current watchers so we can warn/increase if necessary
my $max_user_watches = 0;
my $current_watches = 0;

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

	# Get max_user_watches value
	if ( !-r PROC_MAX_USER_WATCHES ) {
		logWarning("Unable to read " . PROC_MAX_USER_WATCHES );
		return 0;
	}

	$max_user_watches = File::Slurp::read_file(PROC_MAX_USER_WATCHES);
	chomp $max_user_watches;

	main::DEBUGLOG && $log->is_debug && $log->debug("inotify init, max_user_watches: $max_user_watches");
	
	return 1;
}

sub watch {
	my ( $class, $dir, $cb ) = @_;
	
	if ( $i ) {
		# We are already watching, so simply turn off the stopped flag
		main::DEBUGLOG && $log->is_debug && $log->debug('Enabling inotify watcher');
		$STOPPED = 0;
		return;
	}
	
	$i = Linux::Inotify2->new or die "Unable to start Inotify watcher: $!";
	
	# Watch all directories
	_watch_directory( undef, $cb );
	
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
		if ( $e->IN_DELETE || $e->IN_DELETE_SELF || $e->IN_MOVED_FROM ) {
			# Always check moved_from and delete, they will fail the folderFilter but we want to handle them
		}
		else {
			# Make sure we care about this directory
			return unless Slim::Utils::Misc::folderFilter( $file );
		}
	
		if ( $e->IN_CREATE || $e->IN_MOVED_TO ) {
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
	
	# Don't call callback if we are in stopped mode
	return if $STOPPED;

	$cb->( $file );
}

sub shutdown {
	my $class = shift;
	
	if ( $i && !$STOPPED ) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Disabling inotify watcher');
		$STOPPED = 1;
	}
}

sub _watch_directory {
	my ( $dir, $cb ) = @_;
	
	my $isDebug = main::DEBUGLOG && $log->is_debug;

	my $handler = sub {
		event( shift, $cb );
	};
	
	if ( $dir ) {
		# Watch a single dir

		# Scan new dir in case it has child directories we also need to watch
		my $args = {
			dirs      => 1,
			recursive => 1,
		};

		Slim::Utils::Scanner::Local->find( $dir, $args, sub {
			my $dirs = shift || [];
			push @{$dirs}, $dir;

			for my $d ( @{$dirs} ) {
				main::DEBUGLOG && $isDebug && $log->debug("inotify watching: $d");
				
				my $ok = $i->watch(
					$d,
					IN_MOVE | IN_CREATE | IN_CLOSE_WRITE | IN_DELETE | IN_DELETE_SELF | IN_MOVE_SELF,
					$handler,
				);

				if ( $ok ) {
					_increment_watcher_count();
				} 
				else {
					logWarning("Inotify watch creation failed for $d: $!");
				}
			}
		} );		
	}
	else {
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
	
		my $watch_dirs = sub {
			if ( $sth && $sth->fetch ) {
				my $path = Slim::Utils::Misc::pathFromFileURL($url);
				
				main::DEBUGLOG && $isDebug && $log->debug("inotify watching: $path");
				
				my $ok = $i->watch(
					$path,
					IN_MOVE | IN_CREATE | IN_CLOSE_WRITE | IN_DELETE | IN_DELETE_SELF | IN_MOVE_SELF,
					$handler,
				);

				if ( $ok ) {
					_increment_watcher_count();
				}
				else {
					logWarning("Inotify watch creation failed for $path: $!");
				}
				
				return 1;
			}
			
			$sth && $sth->finish;
			undef $sth;
			
			return 0;
		};
		
		Slim::Utils::Scheduler::add_task( $watch_dirs );
	}
}

sub _increment_watcher_count {
	$current_watches++;

	# If we are close to the max, try to increase it
	if ( $current_watches >= ( $max_user_watches - 100 ) ) {
		logWarning("Current inotify watches ($current_watches) nearing max_user_watches ($max_user_watches), trying to increase to " . ($max_user_watches * 2));

		eval {
			open my $fh, '>', PROC_MAX_USER_WATCHES or die "$!\n";
			print $fh $max_user_watches * 2;
			close $fh;

			$max_user_watches *= 2;
		};

		if ( $@ ) {
			chomp $@;
			logError( "Failed to update " . PROC_MAX_USER_WATCHES . ": $@ - please increase this value manually" );
		}
	}
}

1;
