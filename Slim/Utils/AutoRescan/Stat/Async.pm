package Slim::Utils::AutoRescan::Stat::Async;

#
# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, version 2.

# Async stat checker, for Windows or other systems that can't run AIO

use strict;

use File::Basename qw(dirname);
use POSIX qw(ENOENT);

use Slim::Utils::Log;
use Slim::Utils::Misc;

my $log = logger('scan.auto');

# sth is global to support cancel
my $sth;

sub check {
	my ( $class, $dir, $cb, $finishcb ) = @_;
	
	# Stat every file in the scanned_files table that matches $dir
	my $basedir = Slim::Utils::Misc::fileURLFromPath($dir);
	
	my $sql = qq{
		SELECT url, timestamp, filesize
		FROM   scanned_files
		WHERE  url LIKE '$basedir%'
	};
	
	my $dbh = Slim::Schema->dbh;
	
	my ($count) = $dbh->selectrow_array( qq{
		SELECT COUNT(*) FROM ( $sql )
	} );
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Stat'ing $count files/directories using async");
	
	$sth = $dbh->prepare_cached($sql);
	$sth->execute;
	
	my ($url, $timestamp, $filesize);
	$sth->bind_columns(\$url, \$timestamp, \$filesize);
	
	my $work = sub {
		if ( $sth && $sth->fetch ) {
			my $file = Slim::Utils::Misc::pathFromFileURL($url);
			
			my @stat = stat $file;
			
			if ( !@stat ) {
				# stat failed
				if ( $! == ENOENT ) {
					# File/dir was deleted
					main::DEBUGLOG && $log->is_debug && $log->debug("Stat failed (item was deleted): $file");
					
					$cb->($file);
					return;
				}
				die "stat of $file failed: $!\n";
			}
			
			# If mtime has changed, or if filesize has changed (unless it's a dir where size=0)
			if ( $timestamp != $stat[9] || ( $filesize && $filesize != $stat[7] ) ) {
				main::DEBUGLOG && $log->is_debug && $log->debug(
					  "Stat change: $file (cur mtime " . $stat[9] . ", db $timestamp, "
					. "cur size: " . $stat[7] . ", db $filesize)"
				);
				
				# Callback to AutoRescan for the directory or file that changed
				$cb->($file);
			}
			
			return 1;
		}
		
		if ( $sth ) {
			# Only call finish callback if we weren't cancelled
			$finishcb->();
		}
		
		return 0;
	};
	
	Slim::Utils::Scheduler::add_task($work);
}

sub cancel {
	my $class = shift;
	
	if ( $sth ) {
		$sth->finish;
		undef $sth;
	}
}

1;