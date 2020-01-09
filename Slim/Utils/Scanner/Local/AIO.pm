package Slim::Utils::Scanner::Local::AIO;

#
# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, version 2.

# Fully-async recursive directory scanner.  Does not block on any file operations.
#
# NOTE: if you make changes to the logic here, you may also need to change Scanner::Local::Async
# which is the non-AIO version of this code.

use strict;

use File::Basename;
use IO::AIO;
use Path::Class ();

use Slim::Music::Info;
use Slim::Utils::Misc;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log = logger('scan.scanner');

# 1 thread seems best on Touch
use constant MAX_REQS => 8; # max threads to run

sub find {
	my ( $class, $path, $args, $cb ) = @_;

	main::DEBUGLOG && $log->is_debug && (my $start = AnyEvent->time);

	my $types = Slim::Music::Info::validTypeExtensions( $args->{types} || 'audio' );

	my $progress;
	if ( $args->{progress} ) {
		$progress = Slim::Utils::Progress->new( {
			type  => 'importer',
			name  => $path . '|' . ($args->{scanName} ? 'discovering_' . $args->{scanName} : 'discovering_files'),
		} );
	}

	my $todo   = 1;
	my @items  = ();
	my $count  = 0;
	my $others = [];
	my @dirs   = ();

	my $grp = aio_group($cb);

	# Scanned files are stored in the database, use raw DBI to improve performance here
	my $dbh = Slim::Schema->dbh;

	my $sth = $dbh->prepare_cached( qq{
		INSERT INTO scanned_files
		(url, timestamp, filesize)
		VALUES
		(?, ?, ?)
	} );

	# Add the root directory to the database
	$sth->execute(
		Slim::Utils::Misc::fileURLFromPath($path),
		(stat $path)[9], # mtime
		0,               # size, 0 for dirs
	);
	
	$grp->add( aio_readdirx( $path, IO::AIO::READDIR_STAT_ORDER, sub { 
		my $files = shift;

		push @items, map { "$path/$_" } @{$files};

		$todo--;

		my $childgrp = $grp->add( aio_group( sub {
			if ( main::DEBUGLOG && $log->is_debug ) {
				my $diff = sprintf "%.2f", AnyEvent->time - $start;
				$log->debug( "AIO scanner found $count files/dirs in $diff sec" );
			}

			$progress && $progress->final($count);

			if ( $args->{dirs} ) {
				$grp->result( \@dirs );
			}
			else {
				$grp->result($count, $others);
			}
		} ) );

		$childgrp->limit(MAX_REQS);

		$childgrp->feed( sub {
			my $file = shift @items;

			if ( !$file ) {				
				if ( $todo > 0 ) {
					# We still have outstanding requests, pause feeder
					$childgrp->limit(0);

					# If no items in queue, avoid finishing the group with a nop request
					my $nop;
					$nop = sub {
						if ( $todo > 0 || scalar @items ) {
							$childgrp->add( aio_nop( $nop ) );
						}
					};
					
					$childgrp->add( aio_nop( $nop ) );						
				}

				return;
			}

			$todo++;

			$progress && $progress->update($file);

			$childgrp->add( aio_stat( $file, sub {
				$todo--;

				$_[0] && return;

				if ( -d _ ) {
					if ( Slim::Utils::Misc::folderFilter( $file, 0, $types ) ) {
						$todo++;
						$count++;

						# Save the dir entry in the database
						$sth->execute(
							Slim::Utils::Misc::fileURLFromPath($file),
							(stat _)[9], # mtime
							0,           # size, 0 for dirs
						);

						if ( $args->{dirs} ) {
							push @dirs, $file;
						}
						
						$childgrp->add( aio_readdirx( $file, IO::AIO::READDIR_STAT_ORDER, sub { 
							my $files = shift;

							push @items, map { "$file/$_" } @{$files};

							$todo--;

							$childgrp->limit(MAX_REQS);
						} ) );
					}
				}
				else {
					# Make sure we want this file
					if ( !$args->{dirs} ) {
						if ( Slim::Utils::Misc::fileFilter( dirname($file), basename($file), $types, 0 ) ) {		
							if ( main::ISWINDOWS && $file =~ /\.lnk$/i ) {
								my $orig = $file;

								my $url = Slim::Utils::Misc::fileURLFromPath($file);

								$url  = Slim::Utils::OS::Win32->fileURLFromShortcut($url) || return;

								$file = Slim::Utils::Misc::pathFromFileURL($url);

								if ( Path::Class::dir($file)->subsumes($path) ) {
									$log->error("Found an infinite loop! Breaking out: $file -> $path");
									return;
								}

								if ( !-d $file ) {
									return;
								}

								main::DEBUGLOG && $log->is_debug && $log->debug("Will follow shortcut $orig => $file");

								push @{$others}, $file;

								return;
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
									$log->error("Found an infinite loop! Breaking out: $file -> $path");
									return;
								}

								if ( !-d $file ) {
									return;
								}

								main::DEBUGLOG && $log->is_debug && $log->debug("Will follow alias $orig => $file");

								push @{$others}, $file;

								return;
							}

							# Skip client playlists
							return if $args->{types} && $args->{types} =~ /list/ && $file =~ /clientplaylist.*\.m3u$/;

							$count++;

							$sth->execute(
								Slim::Utils::Misc::fileURLFromPath($file),
								(stat _)[9], # mtime
								(stat _)[7], # size
							);
						}
					}
				}
			} ) );
		} );
	} ) );
}

1;
