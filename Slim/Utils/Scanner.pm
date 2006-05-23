package Slim::Utils::Scanner;

# $Id$
#
# SlimServer Copyright (c) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, version 2.

# This file implements a number of class methods to scan directories,
# playlists & remote "files" and add them to our data store.
#
# It is meant to be simple and straightforward. Short methods that do what
# they say and no more.

use strict;
use base qw(Class::Data::Inheritable);

use FileHandle;
use File::Basename qw(basename);
use File::Find::Rule;
use IO::String;
use Path::Class;
use Scalar::Util qw(blessed);

use Slim::Formats::Parse;
use Slim::Music::Info;
use Slim::Utils::Misc;

sub init {
	my $class = shift;

        $class->mk_classdata('useProgressBar');

	$class->useProgressBar(0);

	# Term::ProgressBar requires Class::MethodMaker, which is rather large and is
	# compiled. Many platforms have it already though..
	if ($::d_scan) {

		eval "use Term::ProgressBar";

		if (!$@ && -t STDOUT) {

			$class->useProgressBar(1);
		}
	}
}

sub scanProgressBar {
	my $class = shift;
	my $count = shift;

	if ($class->useProgressBar) {

		my $progress = Term::ProgressBar->new({
			'count' => $count,
			'ETA'   => 'linear',
		});

		$progress->minor(0);

		return $progress;
	}

	return undef;
}

# Handle any type of URI thrown at us.
sub scanPathOrURL {
	my ($class, $args) = @_;

	my $pathOrUrl = $args->{'url'} || do {

		errorMsg("scanPathOrURL: No path or URL was requested!\n");
		return;
	};

	if (Slim::Music::Info::isRemoteURL($pathOrUrl)) {

		msg("scanPathOrURL: Reading metdata from remote URL: $pathOrUrl\n");

		$class->scanRemoteURL($args);

	} else {

		if (Slim::Music::Info::isFileURL($pathOrUrl)) {

			$pathOrUrl = Slim::Utils::Misc::pathFromFileURL($pathOrUrl);
		}

		# Always let the user know what's going on..
		msg("scanPathOrURL: Finding valid files in: $pathOrUrl\n");

		$class->scanDirectory($args);
	}
}

# Scan a directory on disk, and depending on the type of file, add it to the database.
sub scanDirectory {
	my $class = shift;
	my $args  = shift;

	# Can't do much without a starting point.
	if (!$args->{'url'}) {
		return;
	}

	my $ds     = Slim::Music::Info::getCurrentDataStore();
	my $os     = Slim::Utils::OSDetect::OS();
	my $last   = 0; # $ds->lastRescanTime;

	# Create a Path::Class::Dir object for later use.
	my $topDir = dir($args->{'url'});

	# See perldoc File::Find::Rule for more information.
	# follow symlinks.
	my $rule   = File::Find::Rule->new;
	my $extras = { 'no_chdir' => 1 };

	# File::Find doesn't like follow on Windows.
	if ($os ne 'win') {
		$extras->{'follow'} = 1;
	}

	$rule->extras($extras);

	# Only rescan the file if it's changed since our last scan time.
	if ($::rescan && $last) {
		$rule->mtime( sprintf('>%d', $last) );
	}

	# Honor recursion
	if (defined $args->{'recursive'} && $args->{'recursive'} == 0) {
		$rule->maxdepth(0);
	}

	# validTypeExtensions returns a qr// regex.
	$rule->name( Slim::Music::Info::validTypeExtensions() );

	my @files   = $rule->in($topDir);
	my @objects = ();

	if (!scalar @files) {

		$::d_scan && msg("scanDirectory: Didn't find any valid files in: [$topDir]\n");
		return;
	}

	# Give the user a progress indicator if available.
	my $progress = $class->scanProgressBar(scalar @files);

        for my $file (@files) {

		my $url = Slim::Utils::Misc::fileURLFromPath($file);

		# Only check for Windows Shortcuts on Windows.
		# Are they named anything other than .lnk? I don't think so.
		if ($file =~ /\.lnk$/) {

			if ($os ne 'win') {
				next;
			}

			$url  = Slim::Utils::Misc::fileURLFromWinShortcut($url) || next;
			$file = Slim::Utils::Misc::pathFromFileURL($url);

			# Bug: 2485:
			# Use Path::Class to determine if the file points to a
			# directory above us - if so, that's a loop and we need to break it.
			if (dir($file)->subsumes($topDir)) {

				errorMsg("Found an infinite loop! Breaking out: $file -> $topDir\n");
				next;
			}

			# Recurse
			if (Slim::Music::Info::isDir($url) || Slim::Music::Info::isWinShortcut($url)) {

				$::d_scan && msg("scanDirectory: Following Windows Shortcut to: $url\n");

				$class->scanDirectory({
					'url'     => $file,
					'listRef' => $args->{'listRef'},
				});

				next;
			}
		}

		# If we have an audio file or a CUE sheet (in the music dir), scan it.
		if (Slim::Music::Info::isSong($url) || Slim::Music::Info::isCUE($url)) {

			# $::d_scan && msg("ScanDirectory: Adding $url to database.\n");

			push @objects, $ds->updateOrCreate({
				'url'        => $url,
				'readTags'   => 1,
				'checkMTime' => 1,
			});

		} elsif (Slim::Music::Info::isPlaylist($url) && 
			 Slim::Utils::Misc::inPlaylistFolder($url) && $url !~ /ShoutcastBrowser_Recently_Played/) {

			# Only read playlist files if we're in the playlist dir
			# $::d_scan && msg("ScanDirectory: Adding playlist $url to database.\n");

			my $track = $ds->updateOrCreate({
				'url'        => $url,
				'readTags'   => 0,
				'checkMTime' => 1,
			});

			push @objects, $class->scanPlaylistFileHandle($track, FileHandle->new($file));
		}

		if ($class->useProgressBar) {

			$progress->update;
		}
	}

	# If the caller wants the list of objects we found.
	if (scalar @objects && ref($args->{'listRef'}) eq 'ARRAY') {

		push @{$args->{'listRef'}}, @objects;
	}
}

sub scanRemoteURL {
	my $class = shift;
	my $args  = shift;

	my $url   = $args->{'url'} || return;
	my $ds    = Slim::Music::Info::getCurrentDataStore();

	if (!Slim::Music::Info::isRemoteURL($url)) {

		return 0;
	}

	$::d_scan && msg("scanRemoteURL: opening remote stream $url\n");

	my $remoteFH = Slim::Player::ProtocolHandlers->openRemoteStream($url);
	my @objects  = ();

	if (!$remoteFH) {
		errorMsg("scanRemoteURL: Can't connect to remote server to retrieve playlist.\n");
		return 0;
	}

	#
	my $track = $ds->updateOrCreate({
		'url'      => $url,
		'readTags' => 0,
	});

	# Check if it's still a playlist after we open the
	# remote stream. We may have got a different content
	# type while loading.
	if (Slim::Music::Info::isSong($track)) {

		$::d_scan && msg("scanRemoteURL: found that $url is audio!\n");

		if (defined $remoteFH) {

			$remoteFH->close;
			$remoteFH = undef;

			push @objects, $track;
		}

	} else {

		@objects = $class->scanPlaylistFileHandle($track, $remoteFH);
	}

	# If the caller wants the list of objects we found.
	if (scalar @objects && ref($args->{'listRef'}) eq 'ARRAY') {

		push @{$args->{'listRef'}}, @objects;
	}

	return @objects;
}

sub scanPlaylistFileHandle {
	my $class      = shift;
	my $track      = shift;
	my $playlistFH = shift || return;

	my $url        = $track->url;
	my $parentDir  = undef;
	my $ds         = Slim::Music::Info::getCurrentDataStore();

	if (Slim::Music::Info::isFileURL($url)) {

		#XXX This was removed before in 3427, but it really works best this way
		#XXX There is another method that comes close if this shouldn't be used.
		$parentDir = Slim::Utils::Misc::fileURLFromPath( file($track->path)->parent );

		$::d_scan && msgf("scanPlaylistFileHandle: will scan $url, base: $parentDir\n");
	}

	if (ref($playlistFH) eq 'Slim::Formats::HTTP' || ref($playlistFH) eq 'Slim::Player::Protocols::HTTP') {

		# we've just opened a remote playlist.  Due to the synchronous
		# nature of our parsing code and our http socket code, we have
		# to make sure we download the entire file right now, before
		# parsing.  To do that, we use the content() method.  Then we
		# convert the resulting string into the stream expected by the parsers.
		my $playlistString = $playlistFH->content;

		# Be sure to close the socket before reusing the
		# scalar - otherwise we'll leave the socket in a CLOSE_WAIT state.
		$playlistFH->close;
		$playlistFH = undef;

		$playlistFH = IO::String->new($playlistString);
	}

	my @playlistTracks = Slim::Formats::Parse::parseList($url, $playlistFH, $parentDir);

	# Be sure to remove the reference to this handle.
	if (ref($playlistFH) eq 'IO::String') {
		untie $playlistFH;
	}

	undef $playlistFH;

	if (scalar @playlistTracks) {

		# Create a playlist container
		if (!$track->title) {

			my $title = Slim::Utils::Misc::unescape(basename($url));
			   $title =~ s/\.\w{3}$//;

			$track->title($title);
		}

		# With the special url if the playlist is in the
		# designated playlist folder. Otherwise, Dean wants
		# people to still be able to browse into playlists
		# from the Music Folder, but for those items not to
		# show up under Browse Playlists.
		#
		# Don't include the Shoutcast playlists or cuesheets
		# in our Browse Playlist view either.
		my $ct = $ds->contentType($track);

		if (Slim::Music::Info::isFileURL($url) && 
		    Slim::Utils::Misc::inPlaylistFolder($url) &&
			$url !~ /ShoutcastBrowser_Recently_Played/) {

			$ct = 'ssp';
		}

		$track->content_type($ct);
		$track->setTracks(\@playlistTracks);
		$track->update;
	}

	$::d_scan && msgf("scanPlaylistFileHandle: found %d items in playlist.\n", scalar @playlistTracks);

	return wantarray ? @playlistTracks : \@playlistTracks;
}

1;

__END__
