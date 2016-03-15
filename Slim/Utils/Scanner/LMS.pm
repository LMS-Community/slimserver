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
				Slim::Schema->optimizeDB();
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
	
=pod
	# Get list of files within this path
	Slim::Utils::Scanner::Local->find( $next, $args, sub {
		my $count  = shift;
		my $others = shift || []; # other dirs we need to scan (shortcuts/aliases)
		
		my $basedir = Slim::Utils::Misc::fileURLFromPath($next);
		
		my $dbh = Slim::Schema->dbh;
		
		# Generate 3 lists of files:
		
		# 1. Files that no longer exist on disk
		#    and are not virtual (from a cue sheet)
		my $inDBOnlySQL = qq{
			SELECT DISTINCT url
			FROM            tracks
			WHERE           url NOT IN (
				SELECT url FROM scanned_files
				WHERE filesize != 0
			)
			AND             url LIKE '$basedir%'
			AND             virtual IS NULL
			AND             content_type != 'dir'
		};
		
		# 2. Files that are new and not in the database.
		my $onDiskOnlySQL = qq{
			SELECT DISTINCT url
			FROM            scanned_files
			WHERE           url NOT IN (
				SELECT url FROM tracks
			)
			AND             url LIKE '$basedir%'
			AND             filesize != 0
		};
		
		# 3. Files that have changed mtime or size.
		# XXX can this query be optimized more?
		my $changedOnlySQL = qq{
			SELECT scanned_files.url
			FROM scanned_files
			JOIN tracks ON (
				scanned_files.url = tracks.url
				AND (
					scanned_files.timestamp != tracks.timestamp
					OR
					scanned_files.filesize != tracks.filesize
				)
				AND tracks.content_type != 'dir'
			)
			WHERE scanned_files.url LIKE '$basedir%'
		};
		
		my ($inDBOnlyCount) = $dbh->selectrow_array( qq{
			SELECT COUNT(*) FROM ( $inDBOnlySQL ) AS t1
		} );
    	
		my ($onDiskOnlyCount) = $dbh->selectrow_array( qq{
			SELECT COUNT(*) FROM ( $onDiskOnlySQL ) AS t1
		} );
		
		my ($changedOnlyCount) = $dbh->selectrow_array( qq{
			SELECT COUNT(*) FROM ( $changedOnlySQL ) AS t1
		} );
		
		$log->error( "Removing deleted files ($inDBOnlyCount)" ) unless main::SCANNER && $main::progress;
		
		if ( $inDBOnlyCount ) {
			my $inDBOnly = $dbh->prepare_cached($inDBOnlySQL);
			$inDBOnly->execute;
			
			my $deleted;
			$inDBOnly->bind_col(1, \$deleted);

			$pending{$next} |= PENDING_DELETE;
			
			my $progress;
			if ( $args->{progress} ) {
				$progress = Slim::Utils::Progress->new( {
					type  => 'importer',
					name  => $args->{scanName} . '_deleted',
					bar	  => 1,
					every => ($args->{scanName} && $args->{scanName} eq 'playlist'), # record all playists in the db
					total => $inDBOnlyCount,
				} );
			}
			
			my $handle_deleted = sub {
				if ( $inDBOnly->fetch ) {
					$progress && $progress->update($deleted);
					$changes++;
					
					deleted($deleted);
					
					return 1;
				}
				else {
					markDone( $next => PENDING_DELETE, $changes ) unless $args->{no_async};
				
					$progress && $progress->final;
					
					return 0;
				}
			};
			
			if ( $args->{no_async} ) {
				my $i = 0;
				while ( $handle_deleted->() ) {
					if (++$i % 200 == 0) {
						Slim::Schema->forceCommit;
					}
				}
			}
			else {
				Slim::Utils::Scheduler::add_ordered_task( $handle_deleted );
			}
		}
		
		$log->error( "Scanning new files ($onDiskOnlyCount)" ) unless main::SCANNER && $main::progress;
		
		if ( $onDiskOnlyCount ) {
			my $onDiskOnly = $dbh->prepare_cached($onDiskOnlySQL);
			$onDiskOnly->execute;
			
			my $new;
			$onDiskOnly->bind_col(1, \$new);
			
			$pending{$next} |= PENDING_NEW;
			
			my $progress;
			if ( $args->{progress} ) {
				$progress = Slim::Utils::Progress->new( {
					type  => 'importer',
					name  => $args->{scanName} . '_new',
					bar   => 1,
					every => ($args->{scanName} && $args->{scanName} eq 'playlist'), # record all playists in the db
					total => $onDiskOnlyCount,
				} );
			}
			
			my $handle_new = sub {
				if ( $onDiskOnly->fetch ) {
					$progress && $progress->update($new);
					$changes++;
				
					new($new);
					
					return 1;
				}
				else {
					markDone( $next => PENDING_NEW, $changes ) unless $args->{no_async};
				
					$progress && $progress->final;
					
					return 0;
				}
			};
			
			if ( $args->{no_async} ) {
				my $i = 0;
				while ( $handle_new->() ) {
					if (++$i % 200 == 0) {
						Slim::Schema->forceCommit;
					}
				}
			}
			else {
				Slim::Utils::Scheduler::add_ordered_task( $handle_new );
			}
		}
		
		$log->error( "Rescanning changed files ($changedOnlyCount)" ) unless main::SCANNER && $main::progress;
		
		if ( $changedOnlyCount ) {
			my $changedOnly = $dbh->prepare_cached($changedOnlySQL);
			$changedOnly->execute;
			
			my $changed;
			$changedOnly->bind_col(1, \$changed);
						
			$pending{$next} |= PENDING_CHANGED;
			
			my $progress;
			if ( $args->{progress} ) {
				$progress = Slim::Utils::Progress->new( {
					type  => 'importer',
					name  => $args->{scanName} . '_changed',
					bar   => 1,
					every => ($args->{scanName} && $args->{scanName} eq 'playlist'), # record all playists in the db
					total => $changedOnlyCount,
				} );
			}
			
			my $handle_changed = sub {
				if ( $changedOnly->fetch ) {
					$progress && $progress->update($changed);
					$changes++;
					
					changed($changed);
					
					return 1;
				}
				else {
					markDone( $next => PENDING_CHANGED, $changes ) unless $args->{no_async};
				
					$progress && $progress->final;
					
					return 0;
				}	
			};
			
			if ( $args->{no_async} ) {
				my $i = 0;
				while ( $handle_changed->() ) {
					if (++$i % 200 == 0) {
						Slim::Schema->forceCommit;
					}
				}
			}
			else {
				Slim::Utils::Scheduler::add_ordered_task( $handle_changed );
			}
		}
		
		# Scan other directories found via shortcuts or aliases
		if ( scalar @{$others} ) {
			if ( $args->{no_async} ) {
				$class->rescan( $others, $args );
			}
			else {
				Slim::Utils::Timers::setTimer( $class, AnyEvent->now, \&rescan, $others, $args );
			}
		}
		
		# If nothing changed, send a rescan done event
		elsif ( !$inDBOnlyCount && !$onDiskOnlyCount && !$changedOnlyCount ) {
			if ( !main::SCANNER && !$args->{no_async} ) {
				Slim::Music::Import->setIsScanning(0);
				Slim::Control::Request::notifyFromArray( undef, [ 'rescan', 'done' ] );
			}
		}
	} );
=cut

}

=pod
sub deleted {
	my $url = shift;
	
	my $dbh = Slim::Schema->dbh;
	
	my $work;
	
	my $content_type = _content_type($url);
	
	if ( Slim::Music::Info::isSong($url, $content_type) ) {
		$log->error("Handling deleted track $url") unless main::SCANNER && $main::progress;

		# XXX no DBIC objects
		my $track = Slim::Schema->rs('Track')->search( url => $url )->single;
		
		if ( $track ) {
			$work = sub {
				my $album    = $track->album;
				my @contribs = $track->contributors->all;
				my $year     = $track->year;
				my @genres   = map { $_->id } $track->genres;
				
				# plugin hook
				if ( my $handler = $pluginHandlers->{onDeletedTrackHandler} ) {
					$handler->( { id => $track->id, obj => $track, url => $url } );
				}
		
				# delete() will cascade to:
				#   contributor_track
				#   genre_track
				#   comments
				$track->delete;
			
				# Tell Contributors to rescan, if no other tracks left, remove contributor.
				# This will also remove entries from contributor_track and contributor_album
				for my $contrib ( @contribs ) {
					Slim::Schema::Contributor->rescan( $contrib->id );
				}

				
				if ( $album ) {
					# Reset compilation status as it may have changed from VA -> non-VA
					# due to this track being deleted.  Also checks in_storage in case
					# the album was deleted by the $album->rescan.
					if ( $album->in_storage && $album->compilation ) {
						$album->compilation(undef);
						$album->update;
						
						# Re-check VA status for the album,
						# this will also save the album
						Slim::Schema->mergeSingleVAAlbum( $album->id );
					}
					
					# Tell Album to rescan, by looking for remaining tracks in album.  If none, remove album.
					Slim::Schema::Album->rescan( $album->id );
				}
			
				# Tell Year to rescan
				if ( $year ) {
					Slim::Schema::Year->rescan($year);
				}
			
				# Tell Genre to rescan
				Slim::Schema::Genre->rescan( @genres );				
			};
		}
	}
	elsif ( Slim::Music::Info::isCUE($url, $content_type) ) {
		$log->error("Handling deleted cue sheet $url") unless main::SCANNER && $main::progress;
		
		$work = sub {
			my $sth = $dbh->prepare_cached( qq{
				SELECT * FROM tracks WHERE url = ?
			} );
			$sth->execute($url);
			my ($playlist) = $sth->fetchrow_hashref;
			$sth->finish;
		
			# Get the list of all virtual tracks from the cue sheet
			# This has to be done before deleting the playlist because
			# it cascades to deleting the playlist_track entries
			$sth = $dbh->prepare_cached( qq{
				SELECT id, album, year FROM tracks
				WHERE url IN (
					SELECT track
					FROM playlist_track
					WHERE playlist = ?
				)
			} );
			$sth->execute( $playlist->{id} );
			my $ptracks = $sth->fetchall_arrayref( {} );
			$sth->finish;
			
			# Bug 10636, FLAC+CUE doesn't use playlist_track entries for some reason
			# so we need to find the virtual tracks by looking at the URL
			if ( !scalar @{$ptracks} ) {
				$sth = $dbh->prepare( qq{
					SELECT id, album, year
					FROM   tracks
					WHERE  url LIKE '$url#%'
					AND    virtual = 1
				} );
				$sth->execute;
				$ptracks = $sth->fetchall_arrayref( {} );
				$sth->finish;
			}
			
			# plugin hook
			if ( my $handler = $pluginHandlers->{onDeletedPlaylistHandler} ) {
				$handler->( { id => $playlist->{id}, url => $url } );
			}
		
			# Delete the playlist
			# This will cascade to remove the playlist_track entries
			$sth = $dbh->prepare_cached( qq{
				DELETE FROM tracks WHERE id = ?
			} );
			$sth->execute( $playlist->{id} );
		
			# Continue cue handling after playlist/playlist_tracks have been deleted

			# Get contributors for tracks before we delete them
			my $ids = join( ',', map { $_->{id} } @{$ptracks} );
			my $contribs = $dbh->selectall_arrayref( qq{
				SELECT DISTINCT(contributor)
				FROM contributor_track
				WHERE track IN ($ids)
			}, { Slice => {} } );
		
			# Get genres for tracks before we delete them
			my $genres = $dbh->selectall_arrayref( qq{
				SELECT DISTINCT(genre)
				FROM genre_track
				WHERE track IN ($ids)
			}, { Slice => {} } );
		
			# 1. Delete the virtual tracks from this cue sheet
			# This will cascade to:
			#   contributor_track
			#   genre_track
			#   comments
			$sth = $dbh->prepare_cached( qq{
				DELETE FROM tracks WHERE id = ?
			} );
			for my $ptrack ( @{$ptracks} ) {
				$sth->execute( $ptrack->{id} );
			}
			$sth->finish;
		
			# 2. Rescan the album(s) created from the cue sheet
			my %seen;
			my @albums = grep { defined $_ && !$seen{$_}++ } map { $_->{album} } @{$ptracks};
			Slim::Schema::Album->rescan( @albums );
		
			# 3. Rescan contributors created from the cue sheet
			Slim::Schema::Contributor->rescan( map { $_->{contributor} } @{$contribs} );
		
			# 4. Rescan genres created from the cue sheet
			Slim::Schema::Genre->rescan( map { $_->{genre} } @{$genres} );
					
			# 5. Rescan years created from the cue sheet
			%seen = ();
			my @years = grep { defined $_ && !$seen{$_}++ } map { $_->{year} } @{$ptracks};
			Slim::Schema::Year->rescan( @years );
		};
	}
	elsif ( Slim::Music::Info::isList($url, $content_type) ) {
		$log->error("Handling deleted playlist $url") unless main::SCANNER && $main::progress;

		$work = sub {
			# Get the playlist details
			my $sth = $dbh->prepare_cached( qq{
				SELECT * FROM tracks WHERE url = ?
			} );
			$sth->execute($url);
			my ($playlist) = $sth->fetchrow_hashref;
			$sth->finish;
			
			# plugin hook
			if ( my $handler = $pluginHandlers->{onDeletedPlaylistHandler} ) {
				$handler->( { id => $playlist->{id}, url => $url } );
			}
			
			# Delete the playlist
			# This will cascade to remove the playlist_track entries
			$sth = $dbh->prepare_cached( qq{
				DELETE FROM tracks WHERE id = ?
			} );
			$sth->execute( $playlist->{id} );
		};
	}
	
	if ( $work ) {
		if ( $dbh->{AutoCommit} ) {
			Slim::Schema->txn_do($work);
		}
		else {
			$work->();
		}
	}
}
=cut

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

=pod	
	if ( Slim::Music::Info::isSong($url) ) {
		
		# This costs too much to do all the time, and it fills the log
		main::INFOLOG && $log->is_info && !(main::SCANNER && $main::progress) && $log->info("Handling new track $url");
		
		$work = sub {
			# We need to make a quick check to make sure this track has not already
			# been entered due to being referenced in a cue sheet.
			if ( _content_type($url) eq 'cur' ) { # cur = cue referenced
				main::INFOLOG && $log->is_info && $log->info("Skipping track because it's referenced by a cue sheet");
				return;
			}
			
			# Scan tags & create track row and other related rows.
			my $trackid = Slim::Schema->updateOrCreateBase( {
				url        => $url,
				readTags   => 1,
				new        => 1,
				checkMTime => 0,
				commit     => 0,
			} );
			
			if ( !defined $trackid ) {
				$log->error( "ERROR SCANNING $url: " . Slim::Schema->lastError );
				return;
			}
			
			# plugin hook
			if ( my $handler = $pluginHandlers->{onNewTrackHandler} ) {
				$handler->( { id => $trackid, url => $url } );
			}
			
			# XXX iTunes, use onNewTrack
		};
	}
	elsif ( 
		Slim::Music::Info::isCUE($url)
		|| 
		( Slim::Music::Info::isPlaylist($url) && Slim::Utils::Misc::inPlaylistFolder($url) )
	) {
		# Only read playlist files if we're in the playlist dir. Read cue sheets from anywhere.
		$log->error("Handling new playlist $url") unless main::SCANNER && $main::progress;
		
		$work = sub {
			# XXX no DBIC objects
			my $playlist = Slim::Schema->updateOrCreate( {
				url        => $url,
				readTags   => 1,
				new        => 1,
				playlist   => 1,
				checkMTime => 0,
				commit     => 0,
				attributes => {
					MUSICMAGIC_MIXABLE => 1,
				},
			} );
		
			if ( !defined $playlist ) {
				$log->error( "ERROR SCANNING $url: " . Slim::Schema->lastError );
				return;
			}

			scanPlaylistFileHandle(
				$playlist,
				FileHandle->new( Slim::Utils::Misc::pathFromFileURL($url) ),
			);
			
			# plugin hook
			if ( my $handler = $pluginHandlers->{onNewPlaylistHandler} ) {
				$handler->( { id => $playlist->id, obj => $playlist, url => $url } );
			}
		};
	}
=cut

	if ( $work ) {
		if ( Slim::Schema->dbh->{AutoCommit} ) {
			Slim::Schema->txn_do($work);
		}
		else {
			$work->();
		}
	}
}

=pod XXX
sub changed {
	my $url = shift;
	
	my $dbh = Slim::Schema->dbh;
	
	my $isDebug = main::DEBUGLOG && $log->is_debug;
	
	my $content_type = _content_type($url);
	
	if ( Slim::Music::Info::isSong($url, $content_type) ) {
		$log->error("Handling changed track $url") unless main::SCANNER && $main::progress;
		
		my $work = sub {
			# Fetch some original track, album, contributors, and genre information
			# so we can compare with the new data and decide what other data needs to be refreshed
			my $sth = $dbh->prepare_cached( qq{
				SELECT tracks.id, tracks.year, albums.id AS album_id, albums.artwork
				FROM   tracks
				JOIN   albums ON (tracks.album = albums.id)
				WHERE  tracks.url = ?
			} );
			$sth->execute($url);
			my $origTrack = $sth->fetchrow_hashref;
			$sth->finish;
			
			my $orig = {
				year => $origTrack->{year},
			};
			
			# Fetch all contributor IDs used on the original track
			$sth = $dbh->prepare_cached( qq{
				SELECT DISTINCT(contributor) FROM contributor_track WHERE track = ?
			} );
			$sth->execute( $origTrack->{id} );
			$orig->{contribs} = $sth->fetchall_arrayref;
			$sth->finish;
			
			# Fetch all genres used on the original track
			$sth = $dbh->prepare_cached( qq{
				SELECT genre FROM genre_track WHERE track = ?
			} );
			$sth->execute( $origTrack->{id} );
			$orig->{genres} = $sth->fetchall_arrayref;
			$sth->finish;
			
			# Scan tags & update track row
			# XXX no DBIC objects
			my $track = Slim::Schema->updateOrCreate( {
				url        => $url,
				readTags   => 1,
				checkMTime => 0, # not needed as we already know it's changed
				commit     => 0,
			} );
			
			if ( !defined $track ) {
				$log->error( "ERROR SCANNING $url: " . Slim::Schema->lastError );
				return;
			}
			
			# Tell Contributors to rescan, if no other tracks left, remove contributor.
			# This will also remove entries from contributor_track and contributor_album
			for my $contrib ( @{ $orig->{contribs} } ) {
				Slim::Schema::Contributor->rescan( $contrib->[0] );
			}
			
			my $album = $track->album;
			
			# XXX Check for newer cover.jpg here?
					
			# Add/replace coverid
			$track->coverid(undef);
			$track->cover_cached(undef);
			$track->update;
				
			# Make sure album.artwork points to this track, so the album
			# uses the newest available artwork
			if ( my $coverid = $track->coverid ) {
				if ( $album->artwork ne $coverid ) {
					$album->artwork($coverid);
				}
			}
			
			# Reset compilation status as it may have changed
			if ( $album ) {
				# XXX no longer works after album code ported to native DBI
				$album->compilation(undef);
				$album->update;
				
				# Auto-rescan mode, immediately merge VA
				Slim::Schema->mergeSingleVAAlbum( $album->id );
			}
			
			# XXX
			# Rescan comments
			
			# Rescan genre, to check for no longer used genres
			my $origGenres = join( ',', sort map { $_->[0] } @{ $orig->{genres} } );
			my $newGenres  = join( ',', sort map { $_->id } $track->genres );
			
			if ( $origGenres ne $newGenres ) {
				main::DEBUGLOG && $isDebug && $log->debug( "Rescanning changed genre(s) $origGenres -> $newGenres" );
				
				Slim::Schema::Genre->rescan( @{ $orig->{genres} } );
			}
			
			# Bug 8034, Rescan years if year value changed, to remove the old year
			if ( $orig->{year} != $track->year ) {
				main::DEBUGLOG && $isDebug && $log->debug( "Rescanning changed year " . $orig->{year} . " -> " . $track->year );
				
				Slim::Schema::Year->rescan( $orig->{year} );
			}
			
			# plugin hook
			if ( my $handler = $pluginHandlers->{onChangedTrackHandler} ) {
				$handler->( { id => $track->id, obj => $track, url => $url } );
			}
		};
		
		if ( Slim::Schema->dbh->{AutoCommit} ) {
			Slim::Schema->txn_do($work);
		}
		else {
			$work->();
		}
	}
	elsif ( Slim::Music::Info::isCUE($url, $content_type) ) {
		$log->error("Handling changed cue sheet $url") unless main::SCANNER && $main::progress;
		
		# XXX could probably be more intelligent but this works for now
		deleted($url);
		new($url);
	}
	elsif ( Slim::Music::Info::isList($url, $content_type) ) {
		$log->error("Handling changed playlist $url") unless main::SCANNER && $main::progress;
		
		# For a changed playlist, just delete it and then re-scan it
		deleted($url);
		new($url);
	}
}
=cut

=pod
# Check if we're done with all our rescan tasks
sub markDone {
	my ( $path, $type, $changes ) = @_;
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Finished scan type $type for $path");
	
	$pending{$path} &= ~$type;
	
	# Check all pending tasks, make sure all are done before notifying
	for my $task ( keys %pending ) {
		if ( $pending{$task} > 0 ) {
			return;
		}
	}
	
	main::DEBUGLOG && $log->is_debug && $log->debug("All rescan tasks finished (total changes: $changes)");
	
	# plugin hook
	if ( my $handler = $pluginHandlers->{onFinishedHandler} ) {
		$handler->($changes);
	}
	
	# Done with all tasks
	if ( !main::SCANNER ) {

//=pod
		# try to autocomplete artwork from mysqueezebox.com		
		Slim::Music::Artwork->downloadArtwork( sub {
//=cut
			
			# Precache artwork, when done send rescan done event
			Slim::Music::Artwork->precacheAllArtwork( sub {
				# Update the last rescan time if any changes were made
				if ($changes) {
					main::DEBUGLOG && $log->is_debug && $log->debug("Scanner made $changes changes, updating last rescan timestamp");
					Slim::Music::Import->setLastScanTime();
					Slim::Schema->wipeCaches();
				}
				
				# Persist the count of "changes since last optimization"
				# so for example adding 50 tracks, then 50 more would trigger optimize
				$changes += _getChangeCount();
				if ( $changes >= OPTIMIZE_THRESHOLD ) {
					main::DEBUGLOG && $log->is_debug && $log->debug("Scan change count reached $changes, optimizing database");
					Slim::Schema->optimizeDB();
					_setChangeCount(0);
				}
				else {
					_setChangeCount($changes);
				}
				
				Slim::Music::Import->setIsScanning(0);
				Slim::Control::Request::notifyFromArray( undef, [ 'rescan', 'done' ] );
			} );
	}
	
	%pending = ();
}
=cut

=head2 scanPlaylistFileHandle( $playlist, $playlistFH )

Scan a playlist filehandle using L<Slim::Formats::Playlists>.

=cut

=pod
sub scanPlaylistFileHandle {
	my $playlist   = shift;
	my $playlistFH = shift || return;
	
	my $url        = $playlist->url;
	my $parentDir  = undef;

	if (Slim::Music::Info::isFileURL($url)) {

		#XXX This was removed before in 3427, but it really works best this way
		#XXX There is another method that comes close if this shouldn't be used.
		$parentDir = Slim::Utils::Misc::fileURLFromPath( Path::Class::file($playlist->path)->parent );

		main::DEBUGLOG && $log->is_debug && $log->debug("Will scan $url, base: $parentDir");
	}

	my @playlistTracks = Slim::Formats::Playlists->parseList(
		$url,
		$playlistFH, 
		$parentDir, 
		$playlist->content_type,
	);

	# Be sure to remove the reference to this handle.
	if (ref($playlistFH) eq 'IO::String') {
		untie $playlistFH;
	}

	undef $playlistFH;

	if (scalar @playlistTracks) {
		$playlist->setTracks(\@playlistTracks);
		
		# plugin hook
		if ( my $handler = $pluginHandlers->{onNewTrackHandler} ) {
			for my $track ( @playlistTracks ) {
				$handler->( { id => $track->id, obj => $track, url => $track->url } );
				main::idleStreams();
			}
		}
	}

	# Create a playlist container
	if (!$playlist->title) {

		my $title = Slim::Utils::Misc::unescape(basename($url));
		   $title =~ s/\.\w{3}$//;

		$playlist->title($title);
		$playlist->titlesort( Slim::Utils::Text::ignoreCaseArticles( $title ) );
	}

	# With the special url if the playlist is in the
	# designated playlist folder. Otherwise, Dean wants
	# people to still be able to browse into playlists
	# from the Music Folder, but for those items not to
	# show up under Browse Playlists.
	#
	# Don't include the Shoutcast playlists or cuesheets
	# in our Browse Playlist view either.
	my $ct = Slim::Schema->contentType($playlist);

	if (Slim::Music::Info::isFileURL($url) && Slim::Utils::Misc::inPlaylistFolder($url)) {
		main::DEBUGLOG && $log->is_debug && $log->debug( "Playlist item $url changed from $ct to ssp content-type" );
		$ct = 'ssp';
	}

	$playlist->content_type($ct);
	$playlist->update;
	
	# Copy playlist title to all items if they are remote URLs and do not already have a title
	# XXX: still needed?
	for my $track ( @playlistTracks ) {
		if ( blessed($track) && $track->remote ) {
			my $curTitle = $track->title;
			if ( !$curTitle || Slim::Music::Info::isURL($curTitle) ) {
				$track->title( $playlist->title );
				$track->update;
				
				if ( main::DEBUGLOG && $log->is_debug ) {
					$log->debug( 'Playlist item ' . $track->url . ' given title ' . $track->title );
				}
			}
		}
	}
	
	if ( main::DEBUGLOG && $log->is_debug ) {

		$log->debug(sprintf("Found %d items in playlist: ", scalar @playlistTracks));

		for my $track (@playlistTracks) {

			$log->debug(sprintf("  %s", blessed($track) ? $track->url : ''));
		}
	}

	return wantarray ? @playlistTracks : \@playlistTracks;
}
=cut

=pod
sub _content_type {
	my $url = shift;
	
	my $sth = Slim::Schema->dbh->prepare_cached( qq{
		SELECT content_type FROM tracks WHERE url = ?
	} );
	$sth->execute($url);
	my ($content_type) = $sth->fetchrow_array;
	$sth->finish;
	
	return $content_type || '';
}
=cut

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
	
