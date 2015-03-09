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
use File::Next;
use Path::Class;

use Slim::Music::Info;
use Slim::Player::ProtocolHandlers;
use Slim::Utils::Log;
use Slim::Utils::Misc;

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

	# Volatile local tracks are dealt with like remote files. Use the mediafolder query to resolve a folder into its content.
	# We can't rely on the remote URL scanner, as we would want inject the list of files instead of a folder item.
	if ( $pathOrUrl =~ /^tmp:/ ) {
		my $items;

		my $request = Slim::Control::Request::executeRequest( undef, ['mediafolder', 0, 500, "url:$pathOrUrl", 'tags:u'] );
		my $results = $request->getResults();
			
		if ( $results && $results->{folder_loop} ) {
			$items = [ map { $_->{url} } grep { $_->{type} eq 'track' } @{$results->{folder_loop}} ];
		}

		return $cb->( $items || [ $pathOrUrl ] );
		
	} elsif ( Slim::Music::Info::isRemoteURL($pathOrUrl) ) {

		# Do not scan remote URLs now, they will be scanned right before playback by
		# an onJump handler.
		
		return $cb->( [ $pathOrUrl ] );

	} else {

		if (Slim::Music::Info::isFileURL($pathOrUrl)) {

			$pathOrUrl = Slim::Utils::Misc::pathFromFileURL($pathOrUrl);

		}

		# Bug 9097, don't try to scan non-remote protocol handlers like randomplay://
		if ( my $handler = Slim::Player::ProtocolHandlers->handlerForURL($pathOrUrl) ) {
			if ( $handler && $handler->can('isRemote') && !$handler->isRemote ) {
				return $cb->( [ $pathOrUrl ] );
			}
		}

		# Always let the user know what's going on..
		main::INFOLOG && $log->info("Finding valid files in: $pathOrUrl");

		# XXX - can't replace with mediafolder query, yet, as that wouldn't be recursive

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

	my $types  = Slim::Music::Info::validTypeExtensions();

	my $descend_filter = sub {
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
		if ( main::ISWINDOWS && $file =~ /\.lnk$/i ) {

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

				$class->findFilesMatching($file, {
					'foundItems' => $found,
				});

				next;
			}
		}

		elsif ( main::ISMAC && (my $file = Slim::Utils::Misc::pathFromMacAlias($file)) ) {
			if (dir($file)->subsumes($topDir)) {

				logWarning("Found an infinite loop! Breaking out: $file -> $topDir");
				next;
			}
			
			# Recurse into additional shortcuts and directories.
			if (-d $file) {

				main::INFOLOG && $log->info("Following Mac Alias to: $file");

				$class->findFilesMatching($file, {
					'foundItems' => $found,
				});

				next;
			}
		}

		# Fix slashes
		push @{$found}, File::Spec->canonpath($file);
	}

	return $found;
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
		$log->info("For files with extensions in: ", Slim::Music::Info::validTypeExtensions());
	}

	my $files  = $class->findFilesMatching($topDir->stringify, $args);

	if (!scalar @{$files}) {

		$log->warn("Didn't find any valid files in: [$topDir]");

		return $foundItems;

	} else {
		
		$log->error( sprintf( "Found %d files in %s\n", scalar @{$files}, $topDir ) );
	}

	for my $file (@{$files}) {
		
		# Skip client playlists
		next if $file =~ /clientplaylist.*\.m3u$/;

		Slim::Schema->clearLastError;

		my $url = Slim::Utils::Misc::fileURLFromPath($file);

		if (Slim::Music::Info::isSong($url)) {

			main::DEBUGLOG && $log->debug("Adding $url to database.");

			my $track = Slim::Schema->updateOrCreate({
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
			my $playlist = Slim::Schema->updateOrCreate({
				'url'        => $url,
				'readTags'   => 1,
				'checkMTime' => 1,
				'playlist'   => 1,
				'attributes' => {
					'MUSICMAGIC_MIXABLE' => 1,
				}
			});

			my @tracks = Slim::Utils::Scanner::Local::scanPlaylistFileHandle($playlist, FileHandle->new($file));
			
			if ( scalar @tracks && $return ) {
				push @{$foundItems}, @tracks;
			}
		}

	}

	return $foundItems;
}

sub scanPlaylistFileHandle {
	my $class = shift;
	
	logBacktrace("Slim::Utils::Scanner->scanPlaylistsFileHandle() is deprecated. Please use Slim::Utils::Scanner::Local instead.");
	
	my $playlistTracks = Slim::Utils::Scanner::Local::scanPlaylistFileHandle(@_);

	return wantarray ? @$playlistTracks : $playlistTracks;
}

1;

__END__
