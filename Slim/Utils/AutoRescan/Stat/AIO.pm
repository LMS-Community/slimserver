package Slim::Utils::AutoRescan::Stat::AIO;

#
# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, version 2.

# Fully-async parallel stat checker using AIO threads.

use strict;

use File::Basename qw(dirname);
use IO::AIO;
use POSIX qw(ENOENT);

use Slim::Utils::Log;
use Slim::Utils::Misc;

use constant MAX_REQS => 8; # max threads to run

my $log = logger('scan.auto');

# AIO group, global to support cancel
my $grp;

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
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Stat'ing $count files/directories using AIO");
	
	$sth = $dbh->prepare_cached($sql);
	$sth->execute;
	
	my ($url, $timestamp, $filesize);
	$sth->bind_columns(\$url, \$timestamp, \$filesize);
	
	$grp = aio_group($finishcb);
	
	$grp->limit(MAX_REQS);
	
	$grp->feed( sub {
		if ( $sth && $sth->fetch ) {
			my $file = Slim::Utils::Misc::pathFromFileURL($url);
			
			# Copy bound variables as we can't rely on their values in a closure
			my ($mtime, $size) = ($timestamp, $filesize);
			
			$grp->add( aio_lstat( $file, sub {
				if ( $_[0] ) {
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
				if ( $mtime != (stat _)[9] || ( $size && $size != (stat _)[7] ) ) {
					main::DEBUGLOG && $log->is_debug && $log->debug(
						  "Stat change: $file (cur mtime " . (stat _)[9] . ", db $mtime, "
						. "cur size: " . (stat _)[7] . ", db $size)"
					);
					
					# Callback to AutoRescan for the directory or file that changed
					$cb->($file);
				}
			} ) );
		}
	} );
}

sub cancel {
	my $class = shift;
	
	if ( $grp ) {
		$grp->cancel;
		undef $grp;
	}
	
	if ( $sth ) {
		$sth->finish;
		undef $sth;
	}
}

1;