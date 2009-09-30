package Slim::Utils::AutoRescan::Stat::AIO;

# $Id$
#
# Squeezebox Server Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, version 2.

# Fully-async parallel stat checker using AIO threads.

use strict;

use File::Basename qw(dirname);
use IO::AIO;

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
	
	my $dbh = Slim::Schema->storage->dbh;
	
	my ($count) = $dbh->selectrow_array( qq{
		SELECT COUNT(*) FROM ( $sql )
	} );
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Stat'ing $count files using AIO");
	
	$sth = $dbh->prepare_cached($sql);
	$sth->execute;
	
	my ($url, $timestamp, $filesize);
	$sth->bind_columns(\$url, \$timestamp, \$filesize);
	
	$grp = aio_group($finishcb);
	
	$grp->limit(MAX_REQS);
	
	$grp->feed( sub {
		if ( $sth->fetch ) {
			my $file = Slim::Utils::Misc::pathFromFileURL($url);
			my $bfile = $file;
			
			# IO::AIO needs byte-encoded paths
			if ( utf8::is_utf8($bfile) ) {
				utf8::encode($bfile);
			}
			
			# Copy bound variables as we can't rely on their values in a closure
			my ($mtime, $size) = ($timestamp, $filesize);
			
			$grp->add( aio_lstat( $bfile, sub {
				$_[0] && die "stat of $file failed: $!";
				
				# XXX: Doesn't handle deleted files well, or find new files
				
				if ( $mtime != (stat _)[9] || $size != (stat _)[7] ) {
					# Callback to AutoRescan for directory containing this file
					$cb->( dirname($file) );
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