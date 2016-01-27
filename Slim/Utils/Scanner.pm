package Slim::Utils::Scanner;

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

	# use the same code for volatile tracks as for regular tracks, but replace the URLs
	# and create track objects for those temporary items
	if ( Slim::Music::Info::isRemoteURL($pathOrUrl) && !Slim::Music::Info::isVolatileURL($pathOrUrl) ) {

		# Do not scan remote URLs now, they will be scanned right before playback by
		# an onJump handler.
		
		return $cb->( [ $pathOrUrl ] );

	} else {
		
		if ( Slim::Music::Info::isVolatileURL($pathOrUrl) ) {
			require Slim::Player::Protocols::Volatile;
	
			$args->{'volatile'} = $pathOrUrl;

			$args->{'url'} =~ s/^tmp/file/;
			$args->{'url'} = $pathOrUrl = Slim::Utils::Misc::pathFromFileURL($args->{'url'});
		}
		

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
	my $args   = shift || {};

	my $types  = $args->{types} || Slim::Music::Info::validTypeExtensions();

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
		# call idle streams to service timers - used for blocking animation.
		if (!scalar @$found % 3) {
			main::idleStreams();
		}

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
					'types'      => $types,
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
					'types'      => $types,
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

	my $foundItems = $return && ($args->{foundItems} || []);
	
	my $url = $args->{volatile} || $args->{url};

	# Can't do much without a starting point.
	if (!$url) {
		return $foundItems;
	}
	
	my @items;
	
	if ( Slim::Music::Info::isSong($url) ) {
		push @items, {
			url => Slim::Utils::Misc::fileURLFromPath($url),
			type => 'audio'
		};
	}
	elsif ( Slim::Music::Info::isPlaylist($url) ) {
		push @items, {
			url => Slim::Utils::Misc::fileURLFromPath($url),
			type => 'playlist'
		};
	}
	else {
		my $request = Slim::Control::Request->new( undef, [ 'musicfolder', 0, 999_999, 'url:' . $url, 'tags:u', 'type:list|audio', 'recursive:1' ] );
		$request->execute();
	
		if ( $request->isStatusError() ) {
			$log->error($request->getStatusText());
		}
		elsif ($return) {
			@items = @{ $request->getResult('folder_loop') || [] };
		}
	}

	foreach ( @items ) {
		if ($_->{type} =~ /track|audio/) {
			push @{$foundItems}, $_->{url};
		}
		elsif ($_->{type} =~ /playlist/) {
			my $playlist = Slim::Schema->updateOrCreate({
				'url'        => Slim::Utils::Misc::fileURLFromPath($url),
				'readTags'   => 1,
				'checkMTime' => 1,
				'playlist'   => 1,
			});
			
			my $url = $_->{url};
			if ($args->{volatile}) {
				$url = Slim::Utils::Misc::fileURLFromPath($args->{url});
			};

			my @tracks = Slim::Utils::Scanner::Local::scanPlaylistFileHandle($playlist, FileHandle->new(Slim::Utils::Misc::pathFromFileURL( $url )));
			
			if ( scalar @tracks ) {
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
