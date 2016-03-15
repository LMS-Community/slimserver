package Slim::Utils::Scanner::Local;

# $Id$
#
# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, version 2.

use strict;

use File::Basename qw(basename dirname);
use File::Next;
use FileHandle;
use Path::Class ();
use Scalar::Util qw(blessed);

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

# Number of items to process at once, this value will affect the max size of the WAL file
use constant CHUNK_SIZE => 50;

my $log   = logger('scan.scanner');
my $prefs = preferences('server');

my $findclass;
if ( main::HAS_AIO ) {
	$findclass = 'Slim::Utils::Scanner::Local::AIO';
}
else {
	$findclass = 'Slim::Utils::Scanner::Local::Async';
}
eval "use $findclass";
die $@ if $@;

my %pending = ();

# Coderefs to plugin handler functions
my $pluginHandlers = {};

sub find {
	my ( $class, $path, $args, $cb ) = @_;
	
	# Before looking for files, ensure the path and all children are deleted
	# from the list of scanned files
	my $dbh = Slim::Schema->dbh;
	
	my $file = Slim::Utils::Misc::fileURLFromPath($path);
	
	if ( $args->{recursive} && !$args->{dirs} ) {
		# XXX how best to delete files in non-recursive mode?
		# Delete the directory itself and all children
		$dbh->do("DELETE FROM scanned_files WHERE url = '${file}' OR url LIKE '${file}/%'");
	}
	
	stat $path;
	
	if ( -f _ ) {
		# A single file was passed in, handle it directly here
		my $types = Slim::Music::Info::validTypeExtensions( $args->{types} || 'audio' );
		
		if ( Slim::Utils::Misc::fileFilter( dirname($path), basename($path), $types, 0 ) ) {
			# Add single file to scanned_files
			my $sth = $dbh->prepare_cached( qq{
				INSERT INTO scanned_files
				(url, timestamp, filesize)
				VALUES
				(?, ?, ?)
			} );
			
			$sth->execute(
				$file,
				(stat _)[9], # mtime
				(stat _)[7], # size
			);
			
			# Callback that we found 1 file
			$cb->(1);
		}
		else {
			$cb->(0);
		}
		
		return;
	}
	elsif ( -d _ ) {
		# Scan the directory for files		
		if ( $args->{no_async} ) {
			# Force the use of the async find class if not in async mode
			# (it can run it a tight loop, AIO can't)
			require Slim::Utils::Scanner::Local::Async;
			Slim::Utils::Scanner::Local::Async->find( $path, $args, $cb );
		}
		else {
			$findclass->find( $path, $args, $cb );
		}
	}
	else {
		# Item does not exist
		$cb->(0);
	}
}

sub rescan {
	my ( $class, $paths, $args ) = @_;
	
	# Wipe if requested
	if ( $args->{wipe} ) {
		Slim::Schema->wipeAllData;

		# Wipe cached data used for Jive, i.e. albums query data
		if (!main::SCANNER) {	
			Slim::Control::Queries::wipeCaches();
		}
	}
	
	# Default to a recursive scan
	if ( !exists $args->{recursive} ) {
		$args->{recursive} = 1;
	}
	
	if ( ref $paths ne 'ARRAY' ) {
		$paths = [ $paths ];
	}
	
	# get rid of empty entries in our $paths list
	$paths = [ grep { $_ } @$paths ];
	
	my $next = shift @{$paths};
	
	# Must make sure all scanned paths are raw bytes, since the UTF-8
	# flag may be enabled for the paths from odd sources (no longer for the audiodir),
	# this could cause the join() in catdir in File::Next
	# to upgrade the path to UTF-8 which caused -d tests to fail in some cases
	$next = Slim::Utils::Unicode::encode_locale($next);
	
	# Strip trailing slashes
	$next =~ s{/$}{};
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Rescanning $next");
	
	$pending{$next} = 0;
	
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
	
	# Initialize plugin hooks if any plugins want scan events.
	# The API module is only loaded if a plugin uses it.
	$pluginHandlers = {};
	
	if ( Slim::Utils::Scanner::API->can('getHandlers') ) {
		$pluginHandlers = Slim::Utils::Scanner::API->getHandlers();
	}
	
	$log->error("Discovering audio files in $next");
	
	# Keep track of the number of changes we've made so we can decide
	# if we should optimize the database or not, and also so we know if
	# we need to udpate lastRescanTime
	my $changes = 0;
	
	# Get list of files within this path
	Slim::Utils::Scanner::Local->find( $next, $args, sub {
		my $count  = shift;
		
		# Save any other dirs we need to scan (shortcuts/aliases)
		my $others = shift || [];
		push @{$paths}, @{$others};
		
		my $basedir = Slim::Utils::Misc::fileURLFromPath($next);
		
		my $dbh = Slim::Schema->dbh;
		
		# Use the most recent existing track ID to prevent paged onDiskOnly query
		# from missing any files. This will be 0 during a wipe
		my ($maxTrackId) = $dbh->selectrow_array('SELECT MAX(id) FROM tracks');
		$maxTrackId ||= 0;
		
		# Generate 3 lists of files:
		
		# 1. Files that no longer exist on disk
		#    and are not virtual (from a cue sheet)
		my $inDBOnlySQL = qq{
			SELECT DISTINCT(url)
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
			SELECT DISTINCT(url)
			FROM            scanned_files
			WHERE           url NOT IN (
				SELECT url FROM tracks
				WHERE id <= $maxTrackId
			)
			AND             url LIKE '$basedir%'
			AND             filesize != 0
		};
		
		# 3. Files that have changed mtime or size.
		# XXX can this query be optimized more?
		my $changedOnlySQL = qq{
			SELECT DISTINCT(scanned_files.url)
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

		# bug 18078 - Windows doesn't handle DST changes in a file's timestamp correctly. We need to do this on our end.
		if ( main::ISWINDOWS && !(main::SCANNER && $main::wipe) ) {
			my $isDST = (localtime(time()))[8] ? 1 : 0;
	
			if ( $isDST != Slim::Music::Import->getLastScanTimeIsDST() ) {
				my $offset = $isDST ? 3600 : -3600;
				
				$log->error("DST has changed since last scan - fix timestamps in tracks table");
				
				$dbh->do("UPDATE tracks SET timestamp = (timestamp + $offset)");
				Slim::Music::Import->setLastScanTimeIsDST();
			}
		}
		
		# only remove missing tracks when looking for audio tracks
		my $inDBOnlyCount = 0;
		($inDBOnlyCount) = $dbh->selectrow_array( qq{
			SELECT COUNT(*) FROM ( $inDBOnlySQL ) AS t1
		} ) if $args->{types} =~ /audio/;
    	
		my ($onDiskOnlyCount) = $dbh->selectrow_array( qq{
			SELECT COUNT(*) FROM ( $onDiskOnlySQL ) AS t1
		} );
		
		my ($changedOnlyCount) = $dbh->selectrow_array( qq{
			SELECT COUNT(*) FROM ( $changedOnlySQL ) AS t1
		} );
		
		$log->error( "Removing deleted audio files ($inDBOnlyCount)" ) unless main::SCANNER && $main::progress;
		
		if ( $inDBOnlyCount && !Slim::Music::Import->hasAborted() ) {
			my $inDBOnlySth;

			$pending{$next} |= PENDING_DELETE;
			
			my $progress;
			if ( $args->{progress} ) {
				$progress = Slim::Utils::Progress->new( {
					type  => 'importer',
					name  => $next . '|' . ($args->{scanName} . '_deleted'),
					bar	  => 1,
					every => ($args->{scanName} && $args->{scanName} eq 'playlist'), # record all playists in the db
					total => $inDBOnlyCount,
				} );
			}
			
			my $deleted;
			my $handle_deleted = sub {
				if ( hasAborted($progress, $args->{no_async}) ) {
					$inDBOnlySth && $inDBOnlySth->finish;
					return 0;
				}
				
				# Page through the files, this is to avoid a long-running read query which 
				# would prevent WAL checkpoints from occurring.
				# Note: Bug 17438, this limit query always uses the first items, because it
				# will be removing those tracks before the next query is run.
				if ( !$inDBOnlySth ) {
					my $sql = $inDBOnlySQL . " LIMIT 0, " . CHUNK_SIZE;
					$inDBOnlySth = $dbh->prepare($sql);
					$inDBOnlySth->execute;
					$inDBOnlySth->bind_col(1, \$deleted);
				}
				
				if ( $inDBOnlySth->fetch ) {
					$progress && $progress->update( Slim::Utils::Misc::pathFromFileURL($deleted) );
					$changes++;
					
					deleted($deleted);
					
					return 1;
				}
				else {
					my $more = 1;
					
					if ( !$inDBOnlySth->rows ) {
						if ( !$args->{no_async} ) {
							$args->{paths} = $paths;
							markDone( $next => PENDING_DELETE, $changes, $args );
						}
						
						$progress && $progress->final;
						$inDBOnlySth->finish;
						$more = 0;
					}
					else {
						# Continue paging with the next chunk
						$inDBOnlySth->finish;
						undef $inDBOnlySth;
					}
					
					# Commit for every chunk when using scanner.pl
					main::SCANNER && Slim::Schema->forceCommit;
					
					return $more;
				}
			};
			
			if ( $args->{no_async} ) {
				while ( $handle_deleted->() ) { }
			}
			else {
				Slim::Utils::Scheduler::add_ordered_task( $handle_deleted );
			}
		}
		
		$log->error( "Scanning new audio files ($onDiskOnlyCount)" ) unless main::SCANNER && $main::progress;
		
		if ( $onDiskOnlyCount && !Slim::Music::Import->hasAborted() ) {
			my $onDiskOnlySth;
			my $onDiskOnlyDone = 0;			
			
			$pending{$next} |= PENDING_NEW;
			
			my $progress;
			if ( $args->{progress} ) {
				$progress = Slim::Utils::Progress->new( {
					type  => 'importer',
					name  => $next . '|' . ($args->{scanName} . '_new'),
					bar   => 1,
					every => ($args->{scanName} && $args->{scanName} eq 'playlist'), # record all playists in the db
					total => $onDiskOnlyCount,
				} );
			}
			
			my $new;
			my $handle_new = sub {
				if ( hasAborted($progress, $args->{no_async}) ) {
					$onDiskOnlySth && $onDiskOnlySth->finish;
					return 0;
				}
				
				# Page through the files, this is to avoid a long-running read query which 
				# would prevent WAL checkpoints from occurring.
				if ( !$onDiskOnlySth ) {
					my $sql = $onDiskOnlySQL . " LIMIT $onDiskOnlyDone, " . CHUNK_SIZE;
					$onDiskOnlySth = $dbh->prepare($sql);
					$onDiskOnlySth->execute;
					$onDiskOnlySth->bind_col(1, \$new);
				}
				
				if ( $onDiskOnlySth->fetch ) {
					$progress && $progress->update( Slim::Utils::Misc::pathFromFileURL($new) );
					$changes++;
					$onDiskOnlyDone++;
				
					new($new);
					
					return 1;
				}
				else {
					my $more = 1;
					
					if ( !$onDiskOnlySth->rows ) {
						if ( !$args->{no_async} ) {
							$args->{paths} = $paths;
							markDone( $next => PENDING_NEW, $changes, $args );
						}
						
						$progress && $progress->final;
						$onDiskOnlySth->finish;
						$more = 0;
					}
					else {
						# Continue paging with the next chunk
						$onDiskOnlySth->finish;
						undef $onDiskOnlySth;
					}
					
					# Commit for every chunk when using scanner.pl
					main::SCANNER && Slim::Schema->forceCommit;
					
					return $more;
				}
			};
			
			if ( $args->{no_async} ) {
				while ( $handle_new->() ) { }
			}
			else {
				Slim::Utils::Scheduler::add_ordered_task( $handle_new );
			}
		}
		
		$log->error( "Rescanning changed audio files ($changedOnlyCount)" ) unless main::SCANNER && $main::progress;
		
		if ( $changedOnlyCount && !Slim::Music::Import->hasAborted() ) {
			my $changedOnlySth;
			my $changedOnlyDone = 0;
						
			$pending{$next} |= PENDING_CHANGED;
			
			my $progress;
			if ( $args->{progress} ) {
				$progress = Slim::Utils::Progress->new( {
					type  => 'importer',
					name  => $next . '|' . ($args->{scanName} . '_changed'),
					bar   => 1,
					every => ($args->{scanName} && $args->{scanName} eq 'playlist'), # record all playists in the db
					total => $changedOnlyCount,
				} );
			}
			
			my $changed;
			my $handle_changed = sub {
				if ( hasAborted($progress, $args->{no_async}) ) {
					$changedOnlySth && $changedOnlySth->finish;
					return 0;
				}
				
				# Page through the files, this is to avoid a long-running read query which 
				# would prevent WAL checkpoints from occurring.
				if ( !$changedOnlySth ) {
					my $sql = $changedOnlySQL . " LIMIT $changedOnlyDone, " . CHUNK_SIZE;
					$changedOnlySth = $dbh->prepare($sql);
					$changedOnlySth->execute;
					$changedOnlySth->bind_col(1, \$changed);
				}
				
				if ( $changedOnlySth->fetch ) {
					$progress && $progress->update( Slim::Utils::Misc::pathFromFileURL($changed) );
					$changes++;
					$changedOnlyDone++;
				
					changed($changed);
					
					return 1;
				}
				else {
					my $more = 1;
					
					if ( !$changedOnlySth->rows ) {
						if ( !$args->{no_async} ) {
							$args->{paths} = $paths;
							markDone( $next => PENDING_CHANGED, $changes, $args );
						}
						
						$progress && $progress->final;
						$changedOnlySth->finish;
						$more = 0;
					}
					else {
						# Continue paging with the next chunk
						$changedOnlySth->finish;
						undef $changedOnlySth;
					}
					
					# Commit for every chunk when using scanner.pl
					main::SCANNER && Slim::Schema->forceCommit;
					
					return $more;
				}	
			};
			
			if ( $args->{no_async} ) {
				while ( $handle_changed->() ) { }
			}
			else {
				Slim::Utils::Scheduler::add_ordered_task( $handle_changed );
			}
		}
		
		
		if ( hasAborted() ) {
			# nothing to do here - should be handled in hasAborted()
		}		
		elsif ( !$inDBOnlyCount && !$onDiskOnlyCount && !$changedOnlyCount ) {
			if ( !main::SCANNER && !$args->{no_async} ) {
				# Nothing changed, but we may have more paths to scan
				if ( scalar @{$paths} ) {
					Slim::Utils::Timers::setTimer( $class, AnyEvent->now, \&rescan, $paths, $args );
				}
				
				# No more paths to scan, notify API handlers and send a rescan done event
				else {
					markDone( undef, undef, $changes, $args );

					Slim::Music::Import->setIsScanning(0);
			
					if ( my $handler = $pluginHandlers->{onFinishedHandler} ) {
						$handler->(0);
					}
			
					Slim::Control::Request::notifyFromArray( undef, [ 'rescan', 'done' ] );
			
					if ( $args->{onFinished} ) {
						$args->{onFinished}->();
					}
				}
			}
		}
	} );
	
	# Continue scanning if we had more paths
	if ( $args->{no_async} ) {	
		if ( @{$paths} && !Slim::Music::Import->hasAborted() ) {
			$class->rescan( $paths, $args );
		}
			
		if ( !main::SCANNER ) {
			hasAborted();

			# All done, send a done event
			Slim::Music::Import->setIsScanning(0);
			Slim::Control::Request::notifyFromArray( undef, [ 'rescan', 'done' ] );
		}
		
		return $changes;
	}
	
	return;
}

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

sub deleted {
	my $url = shift;
	
	my $dbh = Slim::Schema->dbh;
	
	my $work;
	
	my $content_type = _content_type($url);
	
	if ( Slim::Music::Info::isSong($url, $content_type) ) {
		$log->error("Handling deleted audio file $url") unless main::SCANNER && $main::progress;

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
	else {
		# Bug 17452, handle everything else by just deleting the record. This will be used for 'fec' and 'cur' types
		$log->error("Handling deleted file $url") unless main::SCANNER && $main::progress;
		
		$dbh->do( qq{
			DELETE FROM tracks WHERE url = ?
		}, {}, $url );
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

sub new {
	my $url = shift;
	
	my $work;
	
	if ( Slim::Music::Info::isSong($url) ) {
		
		# This costs too much to do all the time, and it fills the log
		main::INFOLOG && $log->is_info && !(main::SCANNER && $main::progress) && $log->info("Handling new audio track $url");
		
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
				$log->error( "ERROR SCANNING audio file $url: " . Slim::Schema->lastError );
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
				$log->error( "ERROR SCANNING playlist $url: " . Slim::Schema->lastError );
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
	
	if ( $work ) {
		if ( Slim::Schema->dbh->{AutoCommit} ) {
			Slim::Schema->txn_do($work);
		}
		else {
			$work->();
		}
	}
}

sub changed {
	my $url = shift;
	
	my $dbh = Slim::Schema->dbh;
	
	my $isDebug = main::DEBUGLOG && $log->is_debug;
	
	my $content_type = _content_type($url);
	
	if ( Slim::Music::Info::isSong($url, $content_type) ) {
		main::INFOLOG && $log->is_info && !(main::SCANNER && $main::progress) && $log->info("Handling changed audio track $url");
		
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
			$orig->{contribs} = $sth->fetchall_arrayref( {} );
			$sth->finish;
			
			# Fetch all genres used on the original track
			$sth = $dbh->prepare_cached( qq{
				SELECT genre FROM genre_track WHERE track = ?
			} );
			$sth->execute( $origTrack->{id} );
			$orig->{genres} = $sth->fetchall_arrayref( {} );
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
				$log->error( "ERROR SCANNING audio file $url: " . Slim::Schema->lastError );
				return;
			}
			
			# Tell Contributors to rescan, if no other tracks left, remove contributor.
			# This will also remove entries from contributor_track and contributor_album
			for my $contrib ( @{ $orig->{contribs} } ) {
				Slim::Schema::Contributor->rescan( $contrib->{contributor} );
			}
			
			my $album = $track->album;
					
			# Add/replace coverid
			$track->coverid(undef);
			$track->cover_cached(undef);
			
			# Check for cover.jpg here
			if ( !$track->cover ) {
				# store track properties in a hash
				my %columnValueHash = map { $_ => $track->$_() } keys %{$track->attributes};
				$columnValueHash{primary_artist} = $columnValueHash{primary_artist}->id if $columnValueHash{primary_artist};

				# Track does not have embedded artwork, look for standalone cover
				# findStandaloneArtwork returns either a full path to cover art or 0
				# to indicate no artwork was found.
				my $cover = Slim::Music::Artwork->findStandaloneArtwork(
					\%columnValueHash, 
					{}, 
					Slim::Utils::Misc::fileURLFromPath(
						dirname(Slim::Utils::Misc::pathFromFileURL($url))
					),
				);
				
				$track->cover($cover) if $cover;
			}
			
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
			my $origGenres = join( ',', sort map { $_->{genre} } @{ $orig->{genres} } );
			my $newGenres  = join( ',', sort map { $_->id } $track->genres );
			
			if ( $origGenres ne $newGenres ) {
				main::DEBUGLOG && $isDebug && $log->debug( "Rescanning changed genre(s) $origGenres -> $newGenres" );
				
				Slim::Schema::Genre->rescan( map { $_->{genre} } @{ $orig->{genres} } );
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

# Check if we're done with all our rescan tasks
sub markDone {
	my ( $path, $type, $changes, $args ) = @_;
	
	$type && $path && main::DEBUGLOG && $log->is_debug && $log->debug("Finished scan type $type for $path");

	# Update the last rescan time if any changes were made
	if (!main::SCANNER && $changes) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Scanner made $changes changes, updating last rescan timestamp");
		Slim::Music::Import->setLastScanTime();
		Slim::Music::Import->setLastScanTimeIsDST();
	}
	
	$pending{$path} &= ~$type if $type;
	
	# Check all pending tasks, make sure all are done before notifying
	for my $task ( keys %pending ) {
		if ( $pending{$task} > 0 ) {
			return;
		}
	}
	
	# If more paths need to be scanned, we aren't done, schedule the next path scan
	my $paths = delete $args->{paths} || [];
	if ( scalar @{$paths} ) {
		Slim::Utils::Timers::setTimer( __PACKAGE__, AnyEvent->now, \&rescan, $paths, $args );
		return;
	}
	
	main::DEBUGLOG && $log->is_debug && $log->debug("All rescan tasks finished (total changes: $changes)");
	
	# plugin hook
	if ( my $handler = $pluginHandlers->{onFinishedHandler} ) {
		$handler->($changes);
	}
	
	# Done with all tasks
	if ( !main::SCANNER ) {

=pod
		# try to autocomplete artwork from mysqueezebox.com		
		Slim::Music::Artwork->downloadArtwork( sub {
=cut
		Slim::Music::Artwork->updateStandaloneArtwork( sub {

			# Precache artwork, when done send rescan done event
			Slim::Music::Artwork->precacheAllArtwork( sub {
				# Update the last rescan time if any changes were made
				if ($changes) {
					main::DEBUGLOG && $log->is_debug && $log->debug("Scanner made $changes changes, updating last rescan timestamp");
					Slim::Music::Import->setLastScanTime();
					Slim::Music::Import->setLastScanTimeIsDST();
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
				
				if ( $args->{onFinished} ) {
					$args->{onFinished}->();
				}
			} );

		} );
	}
	
	%pending = ();
}

=head2 scanPlaylistFileHandle( $playlist, $playlistFH )

Scan a playlist filehandle using L<Slim::Formats::Playlists>.

=cut

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
		$playlist->titlesearch( Slim::Utils::Text::ignoreCaseArticles( $title, 1 ) );
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
	
