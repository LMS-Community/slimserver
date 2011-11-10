package Slim::Utils::Scanner;

# $Id$
#
# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, version 2.

=head1 NAME

Slim::Utils::Scanner

=head1 SYNOPSIS

Slim::Utils::Scanner->scanPathOrURL({ 'url' => $url });

=head1 DESCRIPTION

This class implements a number of class methods to scan directories,
playlists & remote "files" and add them to our data store.

It is meant to be simple and straightforward. Short methods that do what
they say and no more.

=head1 METHODS

=cut

use strict;

use FileHandle ();
use File::Basename qw(basename);
use File::Next;
use IO::String;
use Path::Class;
use Scalar::Util qw(blessed);

use Slim::Formats;
use Slim::Formats::Playlists;
use Slim::Music::Info;
use Slim::Player::ProtocolHandlers;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Progress;
use Slim::Utils::Strings;
use Slim::Utils::Prefs;

my $log = logger('scan.scanner');

=head2 scanPathOrURL( { url => $url, callback => $callback, ... } )

Scan any local or remote URL.  When finished, calls back to $callback with
an arrayref of items that were found.

=cut

sub scanPathOrURL {
	my ($class, $args) = @_;

	my $cb = $args->{'callback'} || sub {};

	my $pathOrUrl = $args->{'url'} || do {

		logError("No path or URL was requested!");

		return $cb->( [] );
	};

	if ( Slim::Music::Info::isRemoteURL($pathOrUrl) ) {

		# Do not scan remote URLs now, they will be scanned right before playback by
		# an onJump handler.
		
		return $cb->( [ $pathOrUrl ] );

	} else {

		if (Slim::Music::Info::isFileURL($pathOrUrl)) {

			$pathOrUrl = Slim::Utils::Misc::pathFromFileURL($pathOrUrl);

		} else {

			$pathOrUrl = Slim::Utils::Misc::fixPathCase($pathOrUrl);
		}

		# Bug 9097, don't try to scan non-remote protocol handlers like randomplay://
		if ( my $handler = Slim::Player::ProtocolHandlers->handlerForURL($pathOrUrl) ) {
			if ( $handler && $handler->can('isRemote') && !$handler->isRemote ) {
				return $cb->( [ $pathOrUrl ] );
			}
		}

		# Always let the user know what's going on..
		main::INFOLOG && $log->info("Finding valid files in: $pathOrUrl");

		# Non-async directory scan
		my $foundItems = $class->scanDirectory( $args, 'return' );

		# Bug: 3078 - propagate an error message to the caller
		return $cb->( $foundItems || [], scalar @{$foundItems} ? undef : 'PLAYLIST_EMPTY' );
	}
}

=head2 findFilesMatching( $topDir, $args )

Starting at $topDir, uses L<File::Next> to find any files matching our list of supported files.

=cut

sub findFilesMatching {
	my $class  = shift;
	my $topDir = shift;
	my $args   = shift;

	my $types  = Slim::Music::Info::validTypeExtensions($args->{'types'});

	my $descend_filter = sub {
		return 0 if defined $args->{'recursive'} && !$args->{'recursive'};
		
		return Slim::Utils::Misc::folderFilter($File::Next::dir, 0, $types);
	};

	my $file_filter = sub {
		return Slim::Utils::Misc::fileFilter($File::Next::dir, $_, $types);
	};


	$topDir = Slim::Utils::Unicode::encode_locale($topDir);

	my $iter  = File::Next::files({
		'file_filter'     => $file_filter,
		'descend_filter'  => $descend_filter,
		'sort_files'      => 1,
		'error_handler'   => sub { errorMsg("$_\n") },
	}, $topDir);

	my $found = $args->{'foundItems'} || [];

	while (my $file = $iter->()) {
		# Only check for Windows Shortcuts on Windows.
		# Are they named anything other than .lnk? I don't think so.
		if (main::ISWINDOWS && $file =~ /\.lnk$/i) {

			my $url = Slim::Utils::Misc::fileURLFromPath($file);

			$url  = Slim::Utils::OS::Win32->fileURLFromShortcut($url) || next;
			$file = Slim::Utils::Misc::pathFromFileURL($url);

			my $mediadirs = Slim::Utils::Misc::getMediaDirs();

			# Bug: 2485:
			# Use Path::Class to determine if the file points to a
			# directory above us - if so, that's a loop and we need to break it.
			if ( dir($file)->subsumes($topDir) || ($mediadirs && grep { dir($file)->subsumes($_) } @$mediadirs) ) {

				logWarning("Found an infinite loop! Breaking out.");
				next;
			}

			# Recurse into additional shortcuts and directories.
			if ($file =~ /\.lnk$/i || -d $file) {

				main::INFOLOG && $log->info("Following Windows Shortcut to: $url");

				# Bug 4027 - pass along the types & recursion
				# flags. The perils of recursive methods.
				$class->findFilesMatching($file, {
					'foundItems' => $found,
					'recursive'  => $args->{'recursive'},
					'types'      => $args->{'types'},
				});

				next;
			}
		}

		elsif (my $file = Slim::Utils::Misc::pathFromMacAlias($file)) {
			if (dir($file)->subsumes($topDir)) {

				logWarning("Found an infinite loop! Breaking out: $file -> $topDir");
				next;
			}
			
			# Recurse into additional shortcuts and directories.
			if (-d $file) {

				main::INFOLOG && $log->info("Following Mac Alias to: $file");

				$class->findFilesMatching($file, {
					'foundItems' => $found,
					'recursive'  => $args->{'recursive'},
					'types'      => $args->{'types'},
				});

				next;
			}
		}

		# Fix slashes
		push @{$found}, File::Spec->canonpath($file);
	}

	return $found;
}

=head2 findFilesForRescan( $topDir, $args )

Wrapper around L<findNewAndChangedFiles>(), so that other callers (iTunes,
MusicIP can reuse the logic.

=cut

sub findFilesForRescan {
	my $class  = shift;
	my $topDir = shift;
	my $args   = shift;
	
	my $path = Slim::Utils::Misc::fileURLFromPath($topDir);

	main::INFOLOG && $log->info("Generating file list from disk & database for $path...");

	my $onDisk = $class->findFilesMatching($topDir, $args);
	my $inDB   = Slim::Schema->rs('Track')->allTracksAsPaths($path);
	
	return $class->findNewAndChangedFiles($onDisk, $inDB);
}

=head2 findNewAndChangedFiles( $onDisk, $inDB )

Compares file list between disk and database to generate rescan list.

=cut

sub findNewAndChangedFiles {
	my $class  = shift;
	my $onDisk = shift;
	my $inDB   = shift;

	main::INFOLOG && $log->info("Comparing file list between disk & database to generate rescan list...");

	# When rescanning: we need to find files:
	#
	# * That are new - not in the db
	# * That have changed - are in the db, but timestamp or size is different.
	#
	# Generate a list of files that are on disk, but are not in the database.
	my $last  = Slim::Music::Import->lastScanTime;
	my $found = Slim::Utils::Misc::arrayDiff($onDisk, $inDB);
	
	# XXX: report progress for this?

	# Check the file list against the last rescan time to determine changed files.
	for my $file (@{$onDisk}) {
		# Only rescan the file if it's changed since our last scan time.
		if ($last && -r $file && (stat(_))[9] > $last) {
			$found->{$file} = 1;
		}
	}

	return [ keys %{$found} ];
}

=head2 scanDirectory( $args, $return )

Scan a directory on disk, and depending on the type of file, add it to the database.

=cut

sub scanDirectory {
	my $class  = shift;
	my $args   = shift;
	my $return = shift;	# if caller wants a list of items we found

	my $foundItems = $args->{'foundItems'} || [];

	# Can't do much without a starting point.
	if (!$args->{'url'}) {
		return $foundItems;
	}

	# Create a Path::Class::Dir object for later use.
	my $topDir = dir($args->{'url'});

	if ( main::INFOLOG && $log->is_info ) {
		$log->info("About to look for files in $topDir");
		$log->info("For files with extensions in: ", Slim::Music::Info::validTypeExtensions($args->{'types'}));
	}

	my $files  = [];

	# Send progress info to the db and progress bar
	my $progress;
	$progress = Slim::Utils::Progress->new({
		'type' => 'importer',
		'name' => $args->{'scanName'} || 'directory',
		'bar' => 1,
		'every'=> ($args->{'scanName'} && $args->{'scanName'} eq 'playlist'), # record all playists in the db
	}) if $args->{progress};

	if ($::rescan) {
		$files = $class->findFilesForRescan($topDir->stringify, $args);
	} else {
		$files = $class->findFilesMatching($topDir->stringify, $args);
	}

	if (!scalar @{$files}) {

		$log->warn("Didn't find any valid files in: [$topDir]");

		$progress->final if $progress;

		return $foundItems;

	} else {
		
		$log->error( sprintf( "Found %d files in %s\n", scalar @{$files}, $topDir ) );
	}

	$progress->total( scalar @{$files} ) if $progress;

	# If we're starting with a clean db - don't bother with searching for a track
	my $method   = $::wipe ? '_newTrack' : 'updateOrCreate';

	for my $file (@{$files}) {
		
		# Skip client playlists
		next if $args->{types} && $args->{types} eq 'list' && $file =~ /clientplaylist.*\.m3u$/;
		
		if ( main::SCANNER && !$main::progress ) {
			$log->error("Scanning: $file");
		}

		$progress->update($file) if $progress;
		
		Slim::Schema->clearLastError;

		my $url = Slim::Utils::Misc::fileURLFromPath($file);

		if (Slim::Music::Info::isSong($url)) {

			main::DEBUGLOG && $log->debug("Adding $url to database.");

			my $track = Slim::Schema->$method({
				'url'        => $url,
				'readTags'   => 1,
				'checkMTime' => 1,
			});
			
			if ( defined $track && $return ) {
				push @{$foundItems}, $track;
			}
			
			if ( !defined $track ) {
				$log->error( "ERROR SCANNING $file: " . Slim::Schema->lastError );
			}

		} elsif (Slim::Music::Info::isCUE($url) || 
			(Slim::Music::Info::isPlaylist($url) && Slim::Utils::Misc::inPlaylistFolder($url))) {

			# Only read playlist files if we're in the playlist dir. Read cue sheets from anywhere.
			main::DEBUGLOG && $log->debug("Adding playlist $url to database.");

			# Bug: 3761 - readTags, so the title is properly decoded with the locale.
			my $playlist = Slim::Schema->$method({
				'url'        => $url,
				'readTags'   => 1,
				'checkMTime' => 1,
				'playlist'   => 1,
				'attributes' => {
					'MUSICMAGIC_MIXABLE' => 1,
				}
			});

			my @tracks = $class->scanPlaylistFileHandle($playlist, FileHandle->new($file));
			
			if ( scalar @tracks && $return ) {
				push @{$foundItems}, @tracks;
			}
		}

	}

	$progress->final if $progress;

	return $foundItems;
}

=head2 scanPlaylistFileHandle( $playlist, $playlistFH )

Scan a playlist filehandle using L<Slim::Formats::Playlists>.

=cut

sub scanPlaylistFileHandle {
	my $class      = shift;
	my $playlist   = shift;
	my $playlistFH = shift || return;
	
	my $url        = $playlist->url;
	my $parentDir  = undef;

	if (Slim::Music::Info::isFileURL($url)) {

		#XXX This was removed before in 3427, but it really works best this way
		#XXX There is another method that comes close if this shouldn't be used.
		$parentDir = Slim::Utils::Misc::fileURLFromPath( file($playlist->path)->parent );

		main::DEBUGLOG && $log->debug("Will scan $url, base: $parentDir");
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
		main::DEBUGLOG && $log->debug( "Playlist item $url changed from $ct to ssp content-type" );
		$ct = 'ssp';
	}

	$playlist->content_type($ct);
	$playlist->update;
	
	# Copy playlist title to all items if they are remote URLs and do not already have a title
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
	
	if (main::DEBUGLOG && $log->is_debug) {

		$log->debug(sprintf("Found %d items in playlist: ", scalar @playlistTracks));

		for my $track (@playlistTracks) {

			$log->debug(sprintf("  %s", blessed($track) ? $track->url : ''));
		}
	}

	return wantarray ? @playlistTracks : \@playlistTracks;
}

1;

__END__
