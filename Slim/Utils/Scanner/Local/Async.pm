package Slim::Utils::Scanner::Local::Async;

# $Id$
#
# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, version 2.
#
# Async recursive directory scanner for Win32 and other systems without AIO support,
# this can still block on file operations.
#
# NOTE: if you make changes to the logic here, you may also need to change Scanner::Local::AIO
# which is the AIO version of this code.

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
	
	main::DEBUGLOG && $log->is_debug && (my $start = Time::HiRes::time);
	
	my $count = 0;
	
	# Other paths we need to scan later
	my $others = [];
	
	# Scanned files are stored in the database, use raw DBI to improve performance here
	my $dbh = Slim::Schema->dbh;
	
	my $sth = $dbh->prepare_cached( qq{
		INSERT INTO scanned_files
		(url, timestamp, filesize)
		VALUES
		(?, ?, ?)
	} );
	
	my $types = Slim::Music::Info::validTypeExtensions( $args->{types} || 'audio' );
	
	my $progress;
	if ( $args->{progress} ) {
		$progress = Slim::Utils::Progress->new( {
			type  => 'importer',
			name  => $path . '|' . ($args->{scanName} ? 'discovering_' . $args->{scanName} : 'discovering_files'),
		} );
	}
	
	# Find all files and directories.
	# We save directories for use in various auto-rescan modules
	my $iter = File::Next::everything( {
		file_filter    => sub { 
			-f _ && $_ ? Slim::Utils::Misc::fileFilter($File::Next::dir, $_, $types)
			           : Slim::Utils::Misc::folderFilter($File::Next::dir, 0, $types)
		},
		descend_filter => sub {
			$args->{recursive} ? Slim::Utils::Misc::folderFilter($File::Next::dir, 0, $types)
			                   : 0
		},
		error_handler => sub { 
			$log->error('Error scanning file or folder: ', shift)
		},
	}, $path );
	
	my $walk = sub {
		my $file = $iter->();
		
		if ( !defined $file ) {
			# We've reached the end
			if ( main::DEBUGLOG && $log->is_debug ) {
				my $diff = sprintf "%.2f", Time::HiRes::time - $start;
				$log->debug( "Async scanner found $count files/dirs in $diff sec" );
			}
			
			$progress && $progress->final($count);
			
			$cb->($count, $others);
			return 0;
		}
		
		# Skip client playlists
		return 1 if $args->{types} && $args->{types} =~ /list/ && $file =~ /clientplaylist.*\.m3u$/;
		
		$progress && $progress->update($file);
		
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
		
		main::DEBUGLOG && $log->is_debug && $log->debug("Found $file");
		
		$count++;
		
		# XXX Not sure why, but sometimes there is no cached stat data available?!
		if ( !(stat _)[9] ) {
			stat $file;
		}
		
		$sth->execute(
			Slim::Utils::Misc::fileURLFromPath($file),
			(stat _)[9], # mtime
			-d _ ? 0 : (stat _)[7], # size, 0 for directories
		);
		
		return 1;
	};
	
	if ( $args->{no_async} ) {
		my $i = 0;
		while ( $walk->() ) {
			main::SCANNER && ++$i % 200 == 0 && Slim::Schema->forceCommit;
		}
	}
	else {	
		Slim::Utils::Scheduler::add_task( $walk );
	}
}

1;
