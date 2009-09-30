package Slim::Utils::Scanner::Local::Async;

# $Id$
#
# Squeezebox Server Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, version 2.
#
# Async recursive directory scanner for Win32 and other systems without AIO support,
# this can still block on file operations.

use strict;

use File::Next;
use File::Spec ();
use Path::Class ();

use Slim::Music::Info;
use Slim::Utils::Misc;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Scheduler;

my $log = logger('scan.scanner');

sub find {
	my ( $class, $path, $args, $cb ) = @_;
	
	main::DEBUGLOG && $log->is_debug && (my $start = AnyEvent->time);
	
	my $basedir = Slim::Utils::Misc::fileURLFromPath($path);
	
	my $count = 0;
	
	# Other paths we need to scan later
	my $others = [];
	
	# Scanned files are stored in the database, use raw DBI to improve performance here
	my $dbh = Slim::Schema->storage->dbh;
	
	unless ( $args->{no_trunc} ) {
		$dbh->do("DELETE FROM scanned_files WHERE url LIKE '$basedir%'");
	}
	
	my $sth = $dbh->prepare_cached( qq{
		INSERT INTO scanned_files
		(url, timestamp, filesize)
		VALUES
		(?, ?, ?)
	} );
	
	my $types = Slim::Music::Info::validTypeExtensions( $args->{types} || 'audio' );
	
	my $iter = File::Next::files( {
		file_filter     => sub { Slim::Utils::Misc::fileFilter($File::Next::dir, $_, $types) },
		descend_filter  => sub { Slim::Utils::Misc::folderFilter($File::Next::dir) },
	}, $path );
	
	my $walk = sub {
		my $file = $iter->();
		
		if ( !defined $file ) {
			# We've reached the end
			if ( main::DEBUGLOG && $log->is_debug ) {
				my $diff = sprintf "%.2f", AnyEvent->time - $start;
				$log->debug( "Async scanner found $count files in $diff sec" );
			}
			
			$cb->($count, $others);
			return 0;
		}
		
		if ( main::ISWINDOWS && $file =~ /\.lnk$/i ) {
			my $orig = $file;
			
			my $url = Slim::Utils::Misc::fileURLFromPath($file);

			$url  = Slim::Utils::OS::Win32->fileURLFromShortcut($url) || return 1;
			
			$file = Slim::Utils::Misc::pathFromFileURL($url);
			
			if ( Path::Class::dir($file)->subsumes($path) ) {
				$log->error("Found an infinite loop shortcut! Breaking out: $file -> $path");
				return 1;
			}
			
			if ( !-d $file ) {
				return 1;
			}
			
			main::DEBUGLOG && $log->is_debug && $log->debug("Will follow shortcut $orig => $file");
			
			push @{$others}, $file;
			
			return 1;
		}
		elsif (
			main::ISMAC
			&&
			(stat _)[7] == 0 # aliases have a 0 size
			&&
			(my $alias = Slim::Utils::Misc::pathFromMacAlias($file))
		) {
			my $orig = $file;
			
			$file = $alias;
			
			if ( Path::Class::dir($file)->subsumes($path) ) {
				$log->error("Found an infinite loop alias! Breaking out: $file -> $path");
				return 1;
			}
			
			if ( !-d $file ) {
				return 1;
			}
			
			main::DEBUGLOG && $log->is_debug && $log->debug("Will follow alias $orig => $file");
			
			push @{$others}, $file;
			
			return 1;
		}
		
		$file = File::Spec->canonpath($file);
		
		$count++;
		
		$sth->execute(
			Slim::Utils::Misc::fileURLFromPath($file),
			(stat _)[9], # mtime
			(stat _)[7], # size
		);
		
		return 1;
	};
	
	if ( $args->{no_async} ) {
		while ( $walk->() ) {}
	}
	else {	
		Slim::Utils::Scheduler::add_task( $walk );
	}
}

1;
