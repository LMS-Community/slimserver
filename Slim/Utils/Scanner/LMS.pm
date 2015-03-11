package Slim::Utils::Scanner::LMS;

# $Id: /sd/slim/7.6/branches/lms/server/Slim/Utils/Scanner/LMS.pm 78886 2011-07-26T15:15:45.375510Z andy  $
#
# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, version 2.
#
# This file is to migrate from Scanner::Local to Media::Scan-based scanning,
# where the module handles the file discovery, reporting progress, and so on.
# Eventually ::Local will be replaced with this module, when it supports audio formats.

use strict;

use File::Basename qw(basename dirname);
use File::Next;
use FileHandle;
use Media::Scan;
use Path::Class ();
use Scalar::Util qw(blessed);

use Slim::Schema::Video;
use Slim::Schema::Image;
use Slim::Utils::ArtworkCache;
use Slim::Utils::Misc ();
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Progress;
use Slim::Utils::Scheduler;

use constant PENDING_DELETE  => 0x01;
use constant PENDING_NEW     => 0x02;
use constant PENDING_CHANGED => 0x04;

# If more than this many items are changed during a scan, the database is optimized
use constant OPTIMIZE_THRESHOLD => 100;

my $log   = logger('scan.scanner');
my $prefs = preferences('server');

my %pending = ();

# Coderefs to plugin handler functions
my $pluginHandlers = {};

sub hasAborted {
	my ($progress, $no_async) = @_;

	if ( Slim::Music::Import->hasAborted() ) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Scan aborted");

		if ( !main::SCANNER && !$no_async ) {
			Slim::Music::Import->setAborted(0);
			Slim::Music::Import->clearProgressInfo();
			Slim::Music::Import->setIsScanning(0);
			Slim::Control::Request::notifyFromArray( undef, [ 'rescan', 'done' ] );
		}

		$progress && $progress->final;
		return 1;	
	}
}

sub rescan {
	my ( $class, $in_paths, $args ) = @_;
	
	# don't continue if image and video processing have been disabled
	if ( !main::MEDIASUPPORT ) {
		if ( $args->{onFinished}) {
			$args->{onFinished}->();
		}
		
		return;
	}
	
	if ( ref $in_paths ne 'ARRAY' ) {
		$in_paths = [ $in_paths ];
	}
	
	# bug 17674 - don't continue if there's no path defined
	return unless @$in_paths;

	my $dbh = Slim::Schema->dbh;
	
	my $paths = [];
	for my $p ( @{$in_paths} ) {
		# Strip trailing slashes
		$p =~ s{/$}{};
		
		# Must make sure all scanned paths are raw bytes
		push @{$paths}, Slim::Utils::Unicode::encode_locale($p);
	}
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Rescanning " . join(", ", @{$paths}) );
	
	if ( !main::SCANNER ) {
		my $type = 'SETUP_STANDARDRESCAN';
		if ( $args->{wipe} ) {
			$type = 'SETUP_WIPEDB';
		}
		elsif ( $args->{types} eq 'list' ) {
			$type = 'SETUP_PLAYLISTRESCAN';
		}
		
		Slim::Music::Import->setIsScanning($type);
	}
	
	#$pending{$next} = 0;
	
	# Initialize plugin hooks if any plugins want scan events.
	# The API module is only loaded if a plugin uses it.
	$pluginHandlers = {};
	
	if ( Slim::Utils::Scanner::API->can('getHandlers') ) {
		$pluginHandlers = Slim::Utils::Scanner::API->getHandlers();
	}
	
	# Keep track of the number of changes we've made so we can decide
	# if we should optimize the database or not, and also so we know if
	# we need to udpate lastRescanTime
	my $changes = 0;
	
	my $ignore = [
		keys %{ Slim::Music::Info::disabledExtensions('image') },
		keys %{ Slim::Music::Info::disabledExtensions('video') },
	];
	
	# if we're dealing with one folder only, filter out unwanted media types
	# XXX - unfortunately we can only do this for single folders, as Media::Scan would apply the filter to all folders
	if ( scalar @$paths == 1 ) {
		my $mediafolder = $paths->[0];
		
		push @{$ignore}, 'VIDEO' if ( grep { $_ eq $mediafolder } @{ $prefs->get('ignoreInVideoScan') } );
		push @{$ignore}, 'IMAGE' if ( grep { $_ eq $mediafolder } @{ $prefs->get('ignoreInImageScan') } );
	}
	
	if ( !main::IMAGE ) {
		push @{$ignore}, 'IMAGE';
	}
	elsif ( !main::VIDEO ) {
		push @{$ignore}, 'VIDEO'
	}
	
	# some of these are duplicates of the Slim::Utils::OS->ignoreItems
	# but we can't use those values, as they're supposed to be exact matches
	# whereas ignore_dirs can be substring matches too
	my $ignore_dirs = [
		# OSX
		'.ite',       # iTunes Extras (purchased movies)
		'.itlp',      # iTunes LP data (purchased music)
		'.aplibrary', # Aperture data file
		'.apvault',   # Aperture backup file
		'.rcproject', # iMovie project
		'.noindex',   # iPhoto
		'.eyetv',     # EyeTV recording
		'TheVolumeSettingsFolder',
		'TheFindByContentFolder',
		'Network Trash Folder',
		'iPod Photo Cache',
		'iPhoto Library/Thumbnails',
		# various versions of the Windows trash - http://en.wikipedia.org/wiki/Trash_(computing)#Microsoft_Windows
		'$RECYCLE.BIN', # Windows Vista+
		'$Recycle.Bin',
		'RECYCLER',   # NT/2000/XP
		#'Recycled',   # Windows 9x, too generic a term to be enabled
		'System Volume Information',
		# Synology/QNAP
		'@eaDir',	
	];
	
	my $progress;
	if ( $args->{progress} ) {
		$progress = Slim::Utils::Progress->new( {
			type  => 'importer',
			name  => join(', ', @$paths) . '|' . $args->{scanName} . '_media',
			bar	  => 1,
		} );
	}
	
	# AnyEvent watcher for async scans
	my $watcher;
	
	# Media::Scan object
	my $s;
	
	# Flag set when a scan has been aborted
	my $aborted = 0;
	
	# This callback checks if the user has aborted the scan
	my $abortCheck = sub {
		if ( !$aborted && hasAborted($progress, $args->{no_async}) ) {
			$s->abort;
			$aborted = 1;
		}
	};
	
	# Scan options
	my $flags = MS_USE_EXTENSION; # Scan by extension only, no guessing
	if ( $args->{wipe} ) {
		$flags |= MS_CLEARDB | MS_FULL_SCAN; # Scan everything and clear the internal libmediascan database
	}
	else {
		$flags |= MS_RESCAN | MS_INCLUDE_DELETED; # Only scan files that have changed size or timestamp,
		                                          # and notify us of files that have been deleted
	}
	
	my $thumbnails = [
		# DLNA
		{ format => 'JPEG', width => 160, height => 160 }, # for JPEG_TN
		{ format => 'PNG', width => 160, height => 160 },  # for PNG_TN
	];
	
	if ( $prefs->get('precacheArtwork') == 2 ) {
		push @$thumbnails, (
			# SP
			{ format => 'PNG', width => 41, height => 41 },    # jive/baby
			{ format => 'PNG', width => 40, height => 40 },    # fab4 touch
			# Web UI large thumbnails
			{ format => 'PNG', width => $prefs->get('thumbSize') || 100, height => $prefs->get('thumbSize') || 100 },
		);
	}
	
	# Begin scan
	$s = Media::Scan->new( $paths, {
		loglevel => $log->is_debug ? MS_LOG_DEBUG : MS_LOG_ERR, # Set to MS_LOG_MEMORY for very verbose logging
		async => $args->{no_async} ? 0 : 1,
		flags => $flags,
		cachedir => $prefs->get('librarycachedir'),
		ignore => $ignore,
		ignore_dirs => $ignore_dirs,
		thumbnails => $thumbnails,
		on_result => sub {
			my $result = shift;
			
			$changes++;
			
			# XXX flag for new/changed/deleted
			new($result);
			
			$abortCheck->();
		},
		on_error => sub {
			my $error = shift;
			
			$log->error(
				'ERROR SCANNING ' . $error->path . ': ' . $error->error_string
				. '(code ' . $error->error_code . ')'
			);
			
			$abortCheck->();
		},
		on_progress => sub {
			if ($progress) {
				my $p = shift;
				
				my $total = $p->total;
			
				if ( $total && (!$progress->total || $progress->total < $total) ) {
					# Initial progress data, report the total number in the log too
					$log->error( "Scanning new media files ($total)" ) unless main::SCANNER && $main::progress;
					
					$progress->total( $total );
				}
			
				if ( $p->cur_item ) {
					$progress->update( $p->cur_item, $p->done );
				}
				
				# Commit for every chunk when using scanner.pl
				main::SCANNER && Slim::Schema->forceCommit;
			}
			
			$abortCheck->();
		},
		on_finish => sub {
			my $stats = {};
			#$changes = $stats->{change_count}; # XXX library should provide this?
			
			$progress && $progress->final;
			
			main::DEBUGLOG && $log->is_debug && $log->debug("Finished scanning");
			
			# plugin hook
			if ( my $handler = $pluginHandlers->{onFinishedHandler} ) {
				$handler->($changes);
			}
			
			# Update the last rescan time if any changes were made
			if ($changes) {
				main::DEBUGLOG && $log->is_debug && $log->debug("Scanner made $changes changes, updating last rescan timestamp");
				Slim::Music::Import->setLastScanTime();
				Slim::Music::Import->setLastScanTimeIsDST();
				Slim::Schema->wipeCaches();
			}
			
			# Persist the count of "changes since last optimization"
			# so for example adding 50 tracks, then 50 more would trigger optimize
			my $totalChanges = $changes + _getChangeCount();
			if ( $totalChanges >= OPTIMIZE_THRESHOLD ) {
				main::DEBUGLOG && $log->is_debug && $log->debug("Scan change count reached $changes, optimizing database");
				Slim::Schema->optimizeDB() if main::SCANNER;		# in the standalone scanner optimize will always be run at the end
				_setChangeCount(0);
			}
			else {
				_setChangeCount($totalChanges);
			}
			
			if ( !main::SCANNER ) {
				Slim::Music::Import->setIsScanning(0);
				Slim::Control::Request::notifyFromArray( undef, [ 'rescan', 'done' ] );
			}
			
			if ( $args->{onFinished}) {
				$args->{onFinished}->();
			}

			# Stop async watcher
			undef $watcher;
			
			# Clean up Media::Scan thread, etc
			undef $s;
		},
	} );
	
	if ( !main::SCANNER && $args->{no_async} ) {
		# All done, send a done event
		Slim::Music::Import->setIsScanning(0);
		Slim::Schema->wipeCaches();
		Slim::Control::Request::notifyFromArray( undef, [ 'rescan', 'done' ] ); # XXX also needs the scan path?
	}
	
	# Setup async scan monitoring
	if ( !$args->{no_async} ) {
		$watcher = AnyEvent->io(
			fh   => $s->async_fd,
			poll => 'r',
			cb   => sub {
				$s->async_process;
				
				if ($aborted) {
					# Stop the IO watcher and destroy the Media::Scan object
					undef $watcher;
					undef $s;
				}
			},
		);
	}
	
	return $changes;
	
}

sub new {
	my $result = shift;
	
	my $work;
	my $coverPrefix = 'music';
	
	if ( $result->type == 1 ) { # Video
		$coverPrefix = 'video';
		$work = sub {
			main::INFOLOG && $log->is_info && !(main::SCANNER && $main::progress) && $log->info("Handling new video " . $result->path);
			
			my $video = Slim::Schema::Video->updateOrCreateFromResult($result);
			
			if ( !defined $video ) {
				$log->error( 'ERROR SCANNING VIDEO ' . $result->path . ': ' . Slim::Schema->lastError );
				return;
			}
			
			# plugin hook
			if ( my $handler = $pluginHandlers->{onNewVideoHandler} ) {
				$handler->( { hashref => $video } );
			}
		};
	}
	elsif ( $result->type == 3 ) { # Image
		$coverPrefix = 'image';
		$work = sub {
			main::INFOLOG && $log->is_info && !(main::SCANNER && $main::progress) && $log->info("Handling new image " . $result->path);
			
			my $image = Slim::Schema::Image->updateOrCreateFromResult($result);
			
			if ( !defined $image ) {
				$log->error( 'ERROR SCANNING IMAGE ' . $result->path . ': ' . Slim::Schema->lastError );
				return;
			}
			
			# plugin hook
			if ( my $handler = $pluginHandlers->{onNewImageHandler} ) {
				$handler->( { hashref => $image } );
			}
		};
	}
	else {
		warn "File not scanned: " . Data::Dump::dump($result->as_hash) . "\n";
	}
	
	# Cache all thumbnails that were generated by Media::Scan
	for my $thumb ( @{ $result->thumbnails } ) {
		my $cached = {
			content_type  => $thumb->{codec} eq 'JPEG' ? 'jpg' : 'png',
			mtime         => $result->mtime,
			original_path => $result->path,
			data_ref      => \$thumb->{data},
		};
		
		my $width = $thumb->{width};
		my $height = $thumb->{height};
		
		my $key = "$coverPrefix/" . $result->hash . "/cover_${width}x${width}_m." . $cached->{content_type};
		Slim::Utils::ArtworkCache->new->set( $key, $cached );
		
		main::INFOLOG && $log->is_info && !(main::SCANNER && $main::progress) 
			&& $log->info("Cached thumbnail for $key ($width x $height)");
	}

	if ( $work ) {
		if ( Slim::Schema->dbh->{AutoCommit} ) {
			Slim::Schema->txn_do($work);
		}
		else {
			$work->();
		}
	}
}

sub _getChangeCount {
	my $sth = Slim::Schema->dbh->prepare_cached("SELECT value FROM metainformation WHERE name = 'scanChangeCount'");
	$sth->execute;
	my ($count) = $sth->fetchrow_array;
	$sth->finish;
	
	return $count || 0;
}

sub _setChangeCount {
	my $changes = shift;
	
	my $dbh = Slim::Schema->dbh;
	
	my $sth = $dbh->prepare_cached("SELECT 1 FROM metainformation WHERE name = 'scanChangeCount'");
	$sth->execute;
	if ( $sth->fetchrow_array ) {
		my $sta = $dbh->prepare_cached( "UPDATE metainformation SET value = ? WHERE name = 'scanChangeCount'" );
		$sta->execute($changes);
	}
	else {
		my $sta = $dbh->prepare_cached( "INSERT INTO metainformation (name, value) VALUES (?, ?)" );
		$sta->execute( 'scanChangeCount', $changes );
	}
	
	$sth->finish;
}

1;
	
