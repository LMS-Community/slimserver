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
use IO::String;
use Path::Class;
use Scalar::Util qw(blessed);

use Slim::Formats::Playlists;
use Slim::Music::Info;
use Slim::Networking::Async::HTTP;
use Slim::Utils::FileFindRule;
use Slim::Utils::Misc;
use Slim::Utils::ProgressBar;

# CBR bitrates
our %cbr = map { $_ => 1 } qw(32 40 48 56 64 80 96 112 128 160 192 224 256 320);

# Handle any type of URI thrown at us.
sub scanPathOrURL {
	my ($class, $args) = @_;
	
	my $cb = $args->{'callback'};

	my $pathOrUrl = $args->{'url'} || do {

		errorMsg("scanPathOrURL: No path or URL was requested!\n");

		return ref($cb) eq 'CODE' ? $cb->() : undef;
	};

	if (Slim::Music::Info::isRemoteURL($pathOrUrl)) {

		$::d_scan && msg("scanPathOrURL: Reading metdata from remote URL: $pathOrUrl\n");

		# Async scan of remote URL, it will call the callback when done
		$class->scanRemoteURL($args);

	} else {

		if (Slim::Music::Info::isFileURL($pathOrUrl)) {

			$pathOrUrl = Slim::Utils::Misc::pathFromFileURL($pathOrUrl);

		} else {

			$pathOrUrl = Slim::Utils::Misc::fixPathCase($pathOrUrl);
		}

		# Always let the user know what's going on..
		msg("scanPathOrURL: Finding valid files in: $pathOrUrl\n");

		# Non-async directory scan
		$class->scanDirectory($args);

		return ref($cb) eq 'CODE' ? $cb->() : undef;
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

	my $os     = Slim::Utils::OSDetect::OS();
	my $last   = Slim::Schema->lastRescanTime;

	# If the caller wants the list of objects we found.
	my $append = ref($args->{'listRef'}) eq 'ARRAY' ? 1 : 0;

	# Create a Path::Class::Dir object for later use.
	my $topDir = dir($args->{'url'});

	# See perldoc File::Find::Rule for more information.
	# follow symlinks.
	my $rule   = Slim::Utils::FileFindRule->new;
	my $extras = { 'no_chdir' => 1 };

	# File::Find doesn't like follow on Windows.
	if ($os ne 'win') {

		$extras->{'follow'} = 1;

	} else {                                                                                                                                            

		# skip hidden files on Windows
		$rule->exec(\&_skipWindowsHiddenFiles);
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
	$rule->name( Slim::Music::Info::validTypeExtensions($args->{'types'}) );

	# Don't include old style internal playlists.
	$rule->not_name(qr/\W__\S+\.m3u$/);

	# Don't include old Shoutcast recently played items.
	$rule->not_name(qr/ShoutcastBrowser_Recently_Played/);

	# iTunes 4.x makes binary metadata files with the format of: ._filename.ext
	# In the same directory as the real audio files. Ignore those, so we
	# don't create bogus tracks and try to guess names based off the file,
	# thus duplicating tracks & albums, etc.
	$rule->not_name(qr/\/\._/);

	msg("About to look for files in $topDir\n");
	msgf("For files with extensions in: [%s]\n", Slim::Music::Info::validTypeExtensions($args->{'types'}) );

	my $files = $rule->in($topDir);

	if (!scalar @{$files}) {

		$::d_scan && msg("scanDirectory: Didn't find any valid files in: [$topDir]\n");
		return;

	} else {

		msgf("Found %d files in %s\n", scalar @{$files}, $topDir);
	}

	# Give the user a progress indicator if available.
	my $progress = Slim::Utils::ProgressBar->new({ 'total' => scalar @{$files} });

	for my $file (@{$files}) {

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

				msg("scanDirectory: Warning- Found an infinite loop! Breaking out: $file -> $topDir\n");
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

		# If we're starting with a clean db - don't bother with searching for a track
		my $method = $::wipe ? 'newTrack' : 'updateOrCreate';
		my $track  = undef;

		if (Slim::Music::Info::isSong($url)) {

			$::d_scan && msg("ScanDirectory: Adding $url to database.\n");

			$track = Slim::Schema->$method({
				'url'        => $url,
				'readTags'   => 1,
				'checkMTime' => 1,
			});

		} elsif (Slim::Music::Info::isCUE($url) || 
			(Slim::Music::Info::isPlaylist($url) && Slim::Utils::Misc::inPlaylistFolder($url))) {

			# Only read playlist files if we're in the playlist dir. Read cue sheets from anywhere.
			$::d_scan && msg("ScanDirectory: Adding playlist $url to database.\n");

			my $playlist = Slim::Schema->$method({
				'url'        => $url,
				'readTags'   => 0,
				'checkMTime' => 1,
				'playlist'   => 1,
				'attributes' => {
					'MUSICMAGIC_MIXABLE'    => 1,
				}
			});

			$track = $class->scanPlaylistFileHandle($playlist, FileHandle->new($file));
		}

		# Bug: 3606 - only append to the listRef if a listRef exists.
		if (defined $track && $append) {

			push @{$args->{'listRef'}}, $track;
		}

		$track = undef;

		$progress->update if $progress;
	}

	$progress->final if $progress;
}

sub scanRemoteURL {
	my $class = shift;
	my $args  = shift;
	
	my $cb    = $args->{'callback'};
	my $url   = $args->{'url'};

	if (!$url) {
		return ref($cb) eq 'CODE' ? $cb->() : undef;
	}

	if (!Slim::Music::Info::isRemoteURL($url)) {

		return ref($cb) eq 'CODE' ? $cb->() : undef;
	}

	if (Slim::Music::Info::isAudioURL($url)) {

		$::d_scan && msg("scanRemoteURL: remote stream $url known to be audio\n");

		my $track = Slim::Schema->rs('Track')->updateOrCreate({
			'url'      => $url,
		});

		$track->content_type( Slim::Music::Info::typeFromPath($url) );
		
		push @{$args->{'listRef'}}, $track if (ref($args->{'listRef'}) eq 'ARRAY');

		return ref($cb) eq 'CODE' ? $cb->() : undef;
	}
	
	# Fix URL for Rhapsody playlists
	$url =~ s/^rhap/http/;

	$::d_scan && msg("scanRemoteURL: opening remote stream $url\n");
	
	my $http = Slim::Networking::Async::HTTP->new();
	$http->send_request( {
		'method'      => 'GET',
		'url'         => $url,
		'onHeaders'   => \&readRemoteHeaders,
		'onError'     => sub {
			my ( $http, $error ) = @_;

			errorMsg("scanRemoteURL: Can't connect to remote server to retrieve playlist: $error.\n");

			return ref($cb) eq 'CODE' ? $cb->() : undef;
		},
		'passthrough' => [ $args, $url ],
	} );
}

sub readRemoteHeaders {
	my ( $http, $args, $originalURL ) = @_;

	my $url = $http->request->uri->as_string;

	my $track = Slim::Schema->rs('Track')->updateOrCreate({
		'url'      => $url,
		'readTags' => 1,
	});
	
	# Make sure the content type of the track is correct
	my $type 
		= Slim::Music::Info::mimeToType( $http->response->content_type ) 
		|| $http->response->content_type;
	
	# Bug 3396, some m4a audio is incorrectly served as audio/mpeg.
	# In this case, prefer the file extension to the content-type
	if ( $url =~ /(m4a|aac)$/i && $type eq 'mp3' ) {
		$type = 'mov';
	}
	
	# Content-Type may have multiple elements, i.e. audio/x-mpegurl; charset=ISO-8859-1
	if ( ref $type eq 'ARRAY' ) {
		$type = $type->[0];
	}
	
	# Some Shoutcast/Icecast servers don't send content-type
	if ( $http->response->header( 'icy-name' ) ) {
		$type = 'mp3';
	}
	
	$track->content_type( $type );
	$track->update;
	
	Slim::Music::Info::setContentType( $url, $type );
	
	my @objects  = ();

	# Check if it's still a playlist after we open the
	# remote stream. We may have got a different content
	# type while loading.
	if (Slim::Music::Info::isSong($track)) {

		$::d_scan && msg("scanRemoteURL: found that $url is audio\n");
		
		# If we redirected, we need to update the title on the final URL to match
		# the title for the original URL
		if ( $url ne $originalURL ) {
			my $title = Slim::Music::Info::title( $originalURL );
			Slim::Music::Info::setTitle( $url, $title );
		}
		
		# If the audio is mp3, we can read the bitrate from the header or stream
		if ( $type eq 'mp3' ) {
			if ( my $bitrate = $http->response->header( 'icy-br' ) * 1000 ) {
				$::d_scan && msgf( "scanRemoteURL: Found bitrate in header: %d\n", $bitrate );
				$track->bitrate( $bitrate );
				$track->update;
				Slim::Music::Info::setBitrate( $url, $bitrate );
				
				$http->disconnect;
			}
			else {
				$::d_scan && msg("scanRemoteURL: scanning mp3 stream for bitrate\n");
				
				my @bitrates;
				my ($avg, $sum) = (0, 0);
				
				$http->read_mpeg_frames( {
					'onFrame'    => sub {
						my $frame = shift;
						if ( $frame->bitrate ) {
							push @bitrates, $frame->bitrate;
							$sum += $frame->bitrate;
							$avg = int( $sum / @bitrates );
						}
						
						if ( $avg && scalar @bitrates ) {		
							my $vbr = undef;
							if ( !$cbr{$avg} ) {
								$vbr = 1;
							}

							$::d_scan && msg("scanRemoteURL: Read bitrate from stream: $avg " . ( $vbr ? 'VBR' : 'CBR' ) . "\n");

							Slim::Music::Info::setBitrate( $url, $avg * 1000, $vbr );
						}
					},
					'maxFrames'  => 20,
					'disconnect' => 1,   # disconnect after done reading frames
				} );
			}
		}
		else {
			# We don't disconnect if reading mp3 frames
			$http->disconnect;
		}
		
		push @objects, $track;
		
		# If the caller wants the list of objects we found.
		if (scalar @objects && ref($args->{'listRef'}) eq 'ARRAY') {

			push @{$args->{'listRef'}}, @objects;
		}

		return ref($args->{'callback'}) eq 'CODE' ? $args->{'callback'}->() : undef;
	} 
	else {
		
		$::d_scan && msg("scanRemoteURL: found that $url is a playlist\n");

		# Re-fetch as a playlist.
		$args->{'playlist'} = Slim::Schema->rs('Playlist')->objectForUrl({
			'url' => $url,
		});
		
		# read the remote playlist body
		$http->read_body( {
			'onBody'      => \&readPlaylistBody,
			'passthrough' => [ $args ],
		} );
	}
}

sub readPlaylistBody {
	my ( $http, $args ) = @_;
	
	$http->disconnect;
	
	my $playlistFH = IO::String->new( $http->response->content_ref );
	
	my @objects = __PACKAGE__->scanPlaylistFileHandle( $args->{'playlist'}, $playlistFH );
	
	# If the caller wants the list of objects we found.
	if (scalar @objects && ref($args->{'listRef'}) eq 'ARRAY') {

		push @{$args->{'listRef'}}, @objects;
	}
	
	# Bugs 2589, 2723
	# If a playlist item has no title or is just a URL, give it
	# a friendlier title from the parent item, unless the parent title is
	# also just a URL
	my $title = $args->{'playlist'}->title;
	for my $item ( @{ $args->{'listRef'} } ) {
		if ( blessed $item ) {
			if ( !$item->title || $item->title =~ /^(?:http|mms)/i ) {
				if ( $title =~ /^(?:http|mms)/ ) {
					$item->title( $item->url );
				}
				else {
					$item->title( $title );
				}
				$item->update;
			}
		}
	}

	return ref($args->{'callback'}) eq 'CODE' ? $args->{'callback'}->() : undef;
}

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

		$::d_scan && msgf("scanPlaylistFileHandle: will scan $url, base: $parentDir\n");
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

	if (Slim::Music::Info::isFileURL($url) && 
	    Slim::Utils::Misc::inPlaylistFolder($url) &&
		$url !~ /ShoutcastBrowser_Recently_Played/) {

		$ct = 'ssp';
	}

	$playlist->content_type($ct);
	$playlist->update;

	$::d_scan && msgf("scanPlaylistFileHandle: found %d items in playlist.\n", scalar @playlistTracks);

	return wantarray ? @playlistTracks : \@playlistTracks;
}

sub _skipWindowsHiddenFiles {
	my $attribs;

	return Win32::File::GetAttributes($_, $attribs) && !($attribs & Win32::File::HIDDEN());
}

1;

__END__
