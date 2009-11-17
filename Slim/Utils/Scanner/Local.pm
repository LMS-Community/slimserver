package Slim::Utils::Scanner::Local;

# $Id$
#
# Squeezebox Server Copyright 2001-2009 Logitech.
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

sub find {
	my ( $class, $path, $args, $cb ) = @_;
	
	# Return early if we were passed a file
	lstat $path;
	if ( -f _ ) {
		my $types = Slim::Music::Info::validTypeExtensions( $args->{types} || 'audio' );
		
		if ( Slim::Utils::Misc::fileFilter( dirname($path), basename($path), $types, 1 ) ) {
			$cb->( [ [ $path, (stat _)[9], (stat _)[7] ] ] ); # file / mtime / size
		}
		else {
			$cb->( [] );
		}
		
		return;
	}
	
	$findclass->find( $path, $args, $cb );
}

sub rescan {
	my ( $class, $paths, $args ) = @_;
	
	if ( ref $paths ne 'ARRAY' ) {
		$paths = [ $paths ];
	}
	
	my $next = shift @{$paths};
	
	# Strip trailing slashes
	$next =~ s{/$}{};
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Rescanning $next");
	
	$pending{$next} = 0;
	
	if ( !main::SCANNER ) {
		Slim::Music::Import->setIsScanning(1);
	}
	
	$log->error("Discovering files in $next");
	
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
			)
			AND             url LIKE '$basedir%'
			AND             virtual IS NULL
		};
		
		# 2. Files that are new and not in the database.
		my $onDiskOnlySQL = qq{
			SELECT DISTINCT url
			FROM            scanned_files
			WHERE           url NOT IN (
				SELECT url FROM tracks
			)
			AND             url LIKE '$basedir%'
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
					
					deleted($deleted);
					
					return 1;
				}
				else {
					markDone( $next => PENDING_DELETE ) unless $args->{no_async};
				
					$progress && $progress->final;
					
					return 0;
				}
			};
			
			if ( $args->{no_async} ) {
				while ( $handle_deleted->() ) {}
			}
			else {
				Slim::Utils::Scheduler::add_task( $handle_deleted );
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
				
					new($new);
					
					return 1;
				}
				else {
					markDone( $next => PENDING_NEW ) unless $args->{no_async};
				
					$progress && $progress->final;
					
					return 0;
				}
			};
			
			if ( $args->{no_async} ) {
				while ( $handle_new->() ) {}
			}
			else {
				Slim::Utils::Scheduler::add_task( $handle_new );
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
					
					changed($changed);
					
					return 1;
				}
				else {
					markDone( $next => PENDING_CHANGED ) unless $args->{no_async};
				
					$progress && $progress->final;
					
					return 0;
				}	
			};
			
			if ( $args->{no_async} ) {
				while ( $handle_changed->() ) {}
			}
			else {
				Slim::Utils::Scheduler::add_task( $handle_changed );
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
			if ( !main::SCANNER ) {
				Slim::Music::Import->setIsScanning(0);
				Slim::Control::Request::notifyFromArray( undef, [ 'rescan', 'done' ] );
			}
		}
	} );
	
	# Continue scanning if we had more paths
	if ( @{$paths} ) {
		if ( $args->{no_async} ) {
			$class->rescan( $paths, $args );
		}
		else {
			Slim::Utils::Timers::setTimer( $class, AnyEvent->now, \&rescan, $paths, $args );
		}
	}
}

sub deleted {
	my $url = shift;
	
	my $dbh = Slim::Schema->dbh;
	
	my $work;
	
	if ( Slim::Music::Info::isSong($url) ) {
		$log->error("Handling deleted track $url") unless main::SCANNER && $main::progress;

		# XXX no DBIC objects
		my $track = Slim::Schema->rs('Track')->search( url => $url )->single;
		
		if ( $track ) {
			$work = sub {
				my $album    = $track->album;
				my @contribs = $track->contributors->all;
				my $year     = $track->year;
				my @genres   = map { $_->id } $track->genres;
		
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

				# Tell Album to rescan, by looking for remaining tracks in album.  If none, remove album.
				if ( $album ) {
					Slim::Schema::Album->rescan( $album->id );
				
					# Reset compilation status as it may have changed from VA -> non-VA
					# due to this track being deleted.  Also checks in_storage in case
					# the album was deleted by the $album->rescan.
					if ( $album->in_storage && $album->compilation ) {
						$album->compilation(undef);
						$album->update;
					
						if ( !main::SCANNER ) {
							# Re-check VA status for the album,
							# this will also save the album
							Slim::Schema->mergeSingleVAAlbum( $album->id );
						}
						else {
							# Album will be checked for VA status in mergeVA phase
						}
					}
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
	else {
		$log->error("Handling deleted playlist $url") unless main::SCANNER && $main::progress;

		$work = sub {
			# Get the playlist details
			my $ptracks;
			
			my $sth = $dbh->prepare_cached( qq{
				SELECT * FROM tracks WHERE url = ?
			} );
			$sth->execute($url);
			my ($playlist) = $sth->fetchrow_hashref;
			$sth->finish;
			
			# If this was a cue sheet, we need to do some extra work
			if ( $playlist->{content_type} eq 'cue' ) {
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
				$ptracks = $sth->fetchall_arrayref( {} );
				$sth->finish;
			}
			
			# Delete the playlist
			# This will cascade to remove the playlist_track entries
			$sth = $dbh->prepare_cached( qq{
				DELETE FROM tracks WHERE id = ?
			} );
			$sth->execute( $playlist->{id} );
			
			# Continue cue handling after playlist/playlist_tracks have been deleted
			if ( $ptracks ) {
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
				
				# 3. Rescan genres created from the cue sheet
				Slim::Schema::Genre->rescan( map { $_->{genre} } @{$genres} );
							
				# 5. Rescan years created from the cue sheet
				%seen = ();
				my @years = grep { defined $_ && !$seen{$_}++ } map { $_->{year} } @{$ptracks};
				Slim::Schema::Year->rescan( @years );
			}
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

sub new {
	my $url = shift;
	
	my $work;
	
	if ( Slim::Music::Info::isSong($url) ) {
		$log->error("Handling new track $url") unless main::SCANNER && $main::progress;
		
		$work = sub {
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
			
=pod
			# XXX
			# Reset negative compilation status on this album so mergeVA will re-check it
			# as it may have just become a VA album from this new track.  When run in
			# the scanner, mergeVA will handle this later.
			if ( !main::SCANNER && $album && !$album->compilation ) {				
				# Auto-rescan mode, immediately merge VA
				Slim::Schema->mergeSingleVAAlbum( $album->id );
			}
=cut
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

			scanPlaylistFileHandle( $playlist, FileHandle->new(Slim::Utils::Misc::pathFromFileURL($url)) );
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
	
	my $isDebug = $log->is_debug;
	
	$log->error("Handling changed track $url") unless main::SCANNER && $main::progress;
	
	if ( Slim::Music::Info::isSong($url) ) {
		my $work = sub {
			my $dbh = Slim::Schema->dbh;
			
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
				
				if ( !main::SCANNER ) {
					# Auto-rescan mode, immediately merge VA
					Slim::Schema->mergeSingleVAAlbum( $album->id );
				}
				else {
					# Will be checked later during mergeVA phase
				}
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
		};
		
		if ( Slim::Schema->dbh->{AutoCommit} ) {
			Slim::Schema->txn_do($work);
		}
		else {
			$work->();
		}
	}
	
	# XXX changed playlist
}

# Check if we're done with all our rescan tasks
sub markDone {
	my ( $path, $type ) = @_;
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Finished scan type $type for $path");
	
	$pending{$path} &= ~$type;
	
	# Check all pending tasks, make sure all are done before notifying
	for my $task ( keys %pending ) {
		if ( $pending{$task} > 0 ) {
			return;
		}
	}
	
	main::DEBUGLOG && $log->is_debug && $log->debug('All rescan tasks finished');
	
	# Done with all tasks
	if ( !main::SCANNER ) {
		Slim::Music::Import->setIsScanning(0);		
		Slim::Control::Request::notifyFromArray( undef, [ 'rescan', 'done' ] );
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

1;
	
