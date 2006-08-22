package Slim::Utils::Scanner;

# $Id$
#
# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
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
use base qw(Class::Data::Inheritable);

use Audio::WMA;
use FileHandle;
use File::Basename qw(basename);
use HTTP::Request;
use IO::String;
use Path::Class;
use Scalar::Util qw(blessed);

use Slim::Formats;
use Slim::Formats::Playlists;
use Slim::Music::Info;
use Slim::Player::ProtocolHandlers;
use Slim::Networking::Async::HTTP;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Cache;
use Slim::Utils::FileFindRule;
use Slim::Utils::Misc;
use Slim::Utils::ProgressBar;
use Slim::Utils::Strings;

=head2 scanPathOrURL( { url => $url, callback => $callback, ... } )

Scan any local or remote URL.  When finished, calls back to $callback with
an arrayref of items that were found.

=cut

sub scanPathOrURL {
	my ($class, $args) = @_;

	my $cb = $args->{'callback'} || sub {};

	my $pathOrUrl = $args->{'url'} || do {

		errorMsg("scanPathOrURL: No path or URL was requested!\n");

		return $cb->( [] );
	};

	if (Slim::Music::Info::isRemoteURL($pathOrUrl)) {

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
		my $foundItems = $class->scanDirectory( $args, 'return' );

		# Bug: 3078 - propagate an error message to the caller
		return $cb->( $foundItems || [], scalar @{$foundItems} ? undef : 'PLAYLIST_EMPTY' );
	}
}

=head2 findFilesMatching( $topDir, $args )

Starting at $topDir, uses L<Slim::Utils::FileFindRule> to find any files matching 
our list of supported files.

=cut

sub findFilesMatching {
	my $class  = shift;
	my $topDir = shift;
	my $args   = shift;

	my $os     = Slim::Utils::OSDetect::OS();

	# See perldoc File::Find::Rule for more information.
	my $rule   = Slim::Utils::FileFindRule->new;
	my $extras = { 'no_chdir' => 1 };

	# File::Find doesn't like follow on Windows.
	# Bug: 3767 - Ignore items we've seen more than once, and don't die.
	if ($os ne 'win') {

		$extras->{'follow'}      = 1;
		$extras->{'follow_skip'} = 2;

	} else {

		# skip hidden files on Windows
		$rule->exec(\&_skipWindowsHiddenFiles);
	}

	$rule->extras($extras);

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

	# Make sure we can read the file.
	$rule->readable;

	my $files = $rule->in($topDir);
	my $found = $args->{'foundItems'} || [];

	# File::Find::Rule doesn't keep filenames properly sorted, so we sort them here
	for my $file ( sort @{$files} ) {

		# Only check for Windows Shortcuts on Windows.
		# Are they named anything other than .lnk? I don't think so.
		if ($file =~ /\.lnk$/i) {

			if ($os ne 'win') {
				next;
			}

			my $url = Slim::Utils::Misc::fileURLFromPath($file);

			$url  = Slim::Utils::Misc::fileURLFromWinShortcut($url) || next;
			$file = Slim::Utils::Misc::pathFromFileURL($url);

			# Bug: 2485:
			# Use Path::Class to determine if the file points to a
			# directory above us - if so, that's a loop and we need to break it.
			if (dir($file)->subsumes($topDir)) {

				msg("findFilesMatching: Warning- Found an infinite loop! Breaking out: $file -> $topDir\n");
				next;
			}

			# Recurse into additional shortcuts and directories.
			if ($file =~ /\.lnk$/i || -d $file) {

				$::d_scan && msg("findFilesMatching: Following Windows Shortcut to: $url\n");

				$class->findFilesMatching($file, { 'foundItems' => $found });

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
MusicMagic can reuse the logic.

=cut

sub findFilesForRescan {
	my $class  = shift;
	my $topDir = shift;
	my $args   = shift;

	$::d_scan && msg("findFilesForRescan: Generating file list from disk & database...\n");

	my $onDisk = $class->findFilesMatching($topDir, $args);
	my $inDB   = Slim::Schema->rs('Track')->allTracksAsPaths;

	return $class->findNewAndChangedFiles($onDisk, $inDB);
}

=head2 findNewAndChangedFiles( $onDisk, $inDB )

Compares file list between disk and database to generate rescan list.

=cut

sub findNewAndChangedFiles {
	my $class  = shift;
	my $onDisk = shift;
	my $inDB   = shift;

	$::d_scan && msg("findNewAndChangedFiles: Comparing file list between disk & database to generate rescan list...\n");

	# When rescanning: we need to find files:
	#
	# * That are new - not in the db
	# * That have changed - are in the db, but timestamp or size is different.
	#
	# Generate a list of files that are on disk, but are not in the database.
	my $last  = Slim::Schema->lastRescanTime;
	my $found = Slim::Utils::Misc::arrayDiff($onDisk, $inDB);

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

	if (1 || $::d_scan) {

		msg("About to look for files in $topDir\n");
		msgf("For files with extensions in: [%s]\n", Slim::Music::Info::validTypeExtensions($args->{'types'}) );
	}

	my $files  = [];

	if ($::rescan) {
		$files = $class->findFilesForRescan($topDir->stringify, $args);
	} else {
		$files = $class->findFilesMatching($topDir->stringify, $args);
	}

	if (!scalar @{$files}) {

		$::d_scan && msg("scanDirectory: Didn't find any valid files in: [$topDir]\n");
		return $foundItems;

	} else {

		msgf("Found %d files in %s\n", scalar @{$files}, $topDir);
	}

	# Give the user a progress indicator if available.
	my $progress = Slim::Utils::ProgressBar->new({ 'total' => scalar @{$files} });

	# If we're starting with a clean db - don't bother with searching for a track
	my $method   = $::wipe ? 'newTrack' : 'updateOrCreate';

	for my $file (@{$files}) {

		my $url = Slim::Utils::Misc::fileURLFromPath($file);

		if (Slim::Music::Info::isSong($url)) {

			$::d_scan && msg("ScanDirectory: Adding $url to database.\n");

			my $track = Slim::Schema->$method({
				'url'        => $url,
				'readTags'   => 1,
				'checkMTime' => 1,
			});
			
			if ( defined $track && $return ) {
				push @{$foundItems}, $track;
			}

		} elsif (Slim::Music::Info::isCUE($url) || 
			(Slim::Music::Info::isPlaylist($url) && Slim::Utils::Misc::inPlaylistFolder($url))) {

			# Only read playlist files if we're in the playlist dir. Read cue sheets from anywhere.
			$::d_scan && msg("ScanDirectory: Adding playlist $url to database.\n");

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

		$progress->update if $progress;
	}

	$progress->final if $progress;

	return $foundItems;
}

=head2 scanRemoteURL( $args )

Scan a remote URL, determine its content-type, and handle it as either audio or a playlist.

=cut

sub scanRemoteURL {
	my $class = shift;
	my $args  = shift;
	
	# passthrough is here to support recursive scanRemoteURL calls from scanPlaylistURLs
	my $cb    = $args->{'callback'} || sub {};
	my $pt    = $args->{'passthrough'} || [];
	my $url   = $args->{'url'};
	
	my $foundItems = [];

	if ( !$url ) {
		return $cb->( $foundItems, @{$pt} );
	}

	if ( !Slim::Music::Info::isRemoteURL($url) ) {

		return $cb->( $foundItems, @{$pt} );
	}

	if ( Slim::Music::Info::isAudioURL($url) ) {

		$::d_scan && msg("scanRemoteURL: remote stream $url known to be audio\n");

		my $track = Slim::Schema->rs('Track')->updateOrCreate({
			'url' => $url,
		});

		$track->content_type( Slim::Music::Info::typeFromPath($url) );
		
		push @{$foundItems}, $track;

		return $cb->( $foundItems, @{$pt} );
	}
	
	my $originalURL = $url;
	
	my $request = HTTP::Request->new( GET => $url );
	
	# Use WMP headers for MMS protocol URLs or ASF/ASX/WMA URLs
	if ( $url =~ /(?:^mms|\.asf|\.asx|\.wma)/i ) {
		$url =~ s/^mms/http/;
		
		$request->uri( $url );
		
		my $h = $request->headers;
		$h->header( Accept => '*/*' );
		$h->header( 'User-Agent' => 'NSPlayer/4.1.0.3856' );
		$h->header( Pragma => 'xClientGUID={' . Slim::Player::Protocols::MMS::randomGUID(). '}' );
		$h->header( Pragma => 'no-cache,rate=1.0000000,stream-time=0,stream-offset=0:0,request-context=1,max-duration=0' );
		$h->header( Connection => 'close' );
	}
	elsif ( $url !~ /^http/ ) {
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $url );
		
		# check if protocol is supported on the current player (only for Rhapsody at the moment)
		if ( $args->{'client'} && $handler && $handler->can('isUnsupported') ) {
			if ( my $error = $handler->isUnsupported( $args->{'client'}->model ) ) {
				push @{$pt}, $error;
				return $cb->( $foundItems, @{$pt} );
			}
		}
		
		if ( $handler && $handler->can('getHTTPURL') ) {
			# Use the protocol handler to normalize the URL
			$url = $handler->getHTTPURL( $url );
		}
		else {
			# just change it to HTTP
			$url =~ s/^[a-z0-9]+:/http:/;
		}
		
		$request->uri( $url );
	}

	$::d_scan && msg("scanRemoteURL: opening remote location $url\n");
	
	my $http = Slim::Networking::Async::HTTP->new();
	$http->send_request( {
		'request'     => $request,
		'onHeaders'   => \&readRemoteHeaders,
		'onError'     => sub {
			my ( $http, $error ) = @_;

			errorMsg("scanRemoteURL: Can't connect to remote server to retrieve playlist: $error.\n");

			push @{$pt}, 'PLAYLIST_PROBLEM_CONNECTING';
			return $cb->( $foundItems, @{$pt} );
		},
		'passthrough' => [ $args, $originalURL ],
	} );
}

=head2 readRemoteHeaders( $http, $args, $originalURL )

Async callback from scanRemoteURL.  The remote headers are read to determine the content-type.

=cut

sub readRemoteHeaders {
	my ( $http, $args, $originalURL ) = @_;
	
	my $cb = $args->{'callback'};
	my $pt = $args->{'passthrough'} || [];

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
	if ( !$type && $http->response->header( 'icy-name' ) ) {
		$type = 'mp3';
	}
	
	# mms URLs with application/octet-stream are audio, such as
	# mms://ms2.capitalinteractive.co.uk/xfm_high
	if ( $originalURL =~ /^mms/ && $type eq 'application/octet-stream' ) {
		$type = 'wma';
	}
	
	$::d_scan && msg("scanRemoteURL: Content-Type is $type for $url\n");
	
	$track->content_type( $type );
	$track->update;
	
	Slim::Music::Info::setContentType( $url, $type );

	# Check if it's still a playlist after we open the
	# remote stream. We may have got a different content
	# type while loading.
	if ( Slim::Music::Info::isSong($track) ) {

		$::d_scan && msg("scanRemoteURL: found that $url is audio [$type]\n");
		
		# If we redirected, we need to update the title on the final URL to match
		# the title for the original URL
		if ( $url ne $originalURL ) {
			my $title = Slim::Music::Info::title( $originalURL );
			Slim::Music::Info::setTitle( $url, $title );
			Slim::Music::Info::setCurrentTitle( $url, $title );
		}
		
		# If the audio is mp3, we can read the bitrate from the header or stream
		if ( $type eq 'mp3' ) {
			if ( my $bitrate = ( $http->response->header( 'icy-br' ) || $http->response->header( 'x-audiocast-bitrate' ) ) * 1000 ) {
				$::d_scan && msgf( "scanRemoteURL: Found bitrate in header: %d\n", $bitrate );
				$track->bitrate( $bitrate );
				$track->update;
				Slim::Music::Info::setBitrate( $url, $bitrate );
				
				$http->disconnect;
			}
			else {
				$::d_scan && msg("scanRemoteURL: scanning mp3 stream for bitrate\n");
				
				$http->read_body( {
					'readLimit'   => 16 * 1024,
					'onBody'      => sub {
						my $http = shift;
						
						my $io = IO::String->new( $http->response->content_ref );
						
						my ($bitrate, $vbr) = scanBitrate( $io, 'mp3', $url );

						Slim::Music::Info::setBitrate( $url, $bitrate, $vbr );
					},
				} );
			}
		}
		else {
			# We don't disconnect if reading mp3 frames
			$http->disconnect;
		}
		
		# If the original URL was mms:// fix it so direct streaming works properly
		if ( $originalURL =~ /^mms/ ) {
			my $url = $track->url;
			$url =~ s/^http/mms/;
			$track->url( $url );
			$track->update;
		}
		
		my $foundItems = [ $track ];
		
		# Bug 3980
		# On WMA streams, we need to make an initial request to determine the stream
		# number to use, and we also grab various metadata during this request
		# This prevents the player from needing to make 2 requests for each WMA stream
		
		if ( $type eq 'wma' ) {
			
			scanWMAStream( {
				'url'         => $url,
				'callback'    => $cb,
				'passthrough' => $pt,
				'foundItems'  => $foundItems,
			} );
		}
		else {
			
			return $cb->( $foundItems, @{$pt} );
		}
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

=head2 readPlaylistBody( $http, $args )

Async callback from readRemoteHeaders.  If the URL was determined to be a playlist, this
method hands off the playlist body to scanPlaylistFileHandle().

=cut

sub readPlaylistBody {
	my ( $http, $args ) = @_;
	
	$http->disconnect;
	
	scanPlaylist( $http->response->content_ref, $args );
}

=head2 scanPlaylist( $contentRef, $args )

Scan a scalar ref for playlist items.

=cut
	
sub scanPlaylist {
	my ( $contentRef, $args ) = @_;
	
	my $foundItems = [];
	
	my $playlistFH = IO::String->new( $contentRef );
	
	my @objects = __PACKAGE__->scanPlaylistFileHandle( $args->{'playlist'}, $playlistFH );

	# report an error if the playlist contained no items
	my $cb = $args->{'callback'};
	my $pt = $args->{'passthrough'} || [];
	
	if ( !@objects ) {
		push @{$pt},  'PLAYLIST_NO_ITEMS_FOUND';
		return $cb->( $foundItems, @{$pt} );
	}
	else {
		push @{$foundItems}, @objects;
	}
	
	# Bugs 2589, 2723
	# If a playlist item has no title or is just a URL, give it
	# a friendlier title from the parent item, unless the parent title is
	# also just a URL
	my $title = $args->{'playlist'}->title;
	for my $item ( @objects ) {
		if ( blessed $item ) {
			if ( !$item->title || Slim::Music::Info::isRemoteURL($item->title) ) {
				if ( Slim::Music::Info::isRemoteURL($title) ) {
					$item->title( $item->url );
				}
				else {
					$item->title( $title );
				}
				$item->update;
			}
		}
	}

	# Scan each playlist item until we find the first audio URL
	if ( !$args->{'scanningPlaylist'} ) {
		return scanPlaylistURLs( $foundItems, $args );
	}
	else {
		return $cb->( $foundItems, @{$pt} );
	}
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

		$::d_scan && msg("scanPlaylistFileHandle: will scan $url, base: $parentDir\n");
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

	if ( $::d_scan ) {
		msgf( "scanPlaylistFileHandle: found %d items in playlist:\n", scalar @playlistTracks );
		map { msgf( "  %s\n", $_->url ) } @playlistTracks;
	}

	return wantarray ? @playlistTracks : \@playlistTracks;
}

=head2 scanPlaylistURLs ( $foundItems, $args, $toScan, $error )

Recursively scan nested playlist URLs until we find an audio file or reach our recursion limit.

=cut

sub scanPlaylistURLs {
	my ( $foundItems, $args, $toScan, $error ) = @_;
	
	my $cb = $args->{'callback'};
	my $pt = $args->{'passthrough'} || [];
	
	my $offset = 0;
	for my $item ( @{$foundItems} ) {
		if ( Slim::Music::Info::isAudioURL( $item->url ) || Slim::Music::Info::isSong( $item ) ) {
			# we finally found an audio URL, so we're done
			$::d_scan && msgf( "scanPlaylistURLs: Found an audio URL: %s [%s]\n",
				$item->url,
				$item->content_type,
			);
			
			# return a list with the first found audio URL at the top
			unshift @{$foundItems}, splice @{$foundItems}, $offset, 1;

			if ( $item->content_type eq 'wma' ) {
				
				scanWMAStream( {
					'url'         => $item->url,
					'callback'    => $cb,
					'passthrough' => $pt,
					'foundItems'  => $foundItems,
				} );
				
				return;
			}
			else {
			
				return $cb->( $foundItems, @{$pt} );
			}
		}
		$offset++;
	}
	
	$toScan ||= [];
	
	push @{$toScan}, map { $_->url } @{$foundItems};
	
	# This counter makes sure we don't go into an infinite loop
	$args->{'loopCount'} ||= 0;
	
	if ( $args->{'loopCount'} > 5 ) {
		$::d_parse && msg("scanPlaylistURLs: recursion limit reached, giving up\n");
		push @{$pt}, 'PLAYLIST_NO_ITEMS_FOUND';
		return $cb->( [], @{$pt} );
	}
	
	$args->{'loopCount'}++;
	
	# Select the next URL to scan
	if ( my $scanURL = shift @{$toScan} ) {
		
		__PACKAGE__->scanRemoteURL( {
			'url'              => $scanURL,
			'scanningPlaylist' => 1,
			'callback'         => \&scanPlaylistURLs,
			'passthrough'      => [ $args, $toScan ],
		} );
	}
	else {
		# no more items left to scan and no audio found, return error
		push @{$pt}, 'PLAYLIST_NO_ITEMS_FOUND';
		return $cb->( $foundItems, @{$pt} );
	}
}

=head2 scanBitrate( $fh, $contentType, $url )

Scan a remote stream for bitrate information using a temporary file.

Currently supports MP3, Ogg, and FLAC streams (any format class that implements 'scanBitrate')

=cut

sub scanBitrate {
	my ( $fh, $contentType, $url ) = @_;

	my $formatClass = Slim::Formats->classForFormat($contentType);

	if (Slim::Formats->loadTagFormatForType($contentType) && $formatClass->can('scanBitrate')) {

		return $formatClass->scanBitrate( $fh, $url );
	}

	$::d_scan && msg("scanBitrate: Unable to scan content-type: $contentType\n");

	return (-1, undef);
}

=head2 scanWMAStream( { url => $url, callback => $callback } )

Make the initial WMA stream request to determine stream number and cache
the result for use by the direct streaming code in Protocols::MMS.

=cut

sub scanWMAStream {
	my $args = shift;
	
	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&scanWMAStreamDone,
		\&scanWMAStreamError,
		{
			args => $args,
		},
	);
	
	my %headers = (		
		Accept       => '*/*',
		'User-Agent' => 'NSPlayer/4.1.0.3856',
		Pragma       => 'xClientGUID={' . Slim::Player::Protocols::MMS::randomGUID(). '}',
		Pragma       => 'no-cache,rate=1.0000000,stream-time=0,stream-offset=0:0,request-context=1,max-duration=0',
		Connection   => 'close',
	);
	
	my $url = $args->{'url'};
	$url =~ s/^mms/http/;
	
	$http->get( $url, %headers );
}

=head2 scanWMAStreamDone( $http )

Callback from scanWMAStream that parses the ASF header data.  For reference see
http://avifile.sourceforge.net/asf-1.0.htm

=cut

sub scanWMAStreamDone {
	my $http = shift;
	my $args = $http->params('args');
	
	# Check content-type of stream to make sure it's audio
	my $type = $http->headers->header('Content-Type');
	
	if (   $type ne 'application/octet-stream'
		&& $type ne 'application/x-mms-framed' 
		&& $type ne 'application/vnd.ms.wms-hdr.asfv1'
	) {
		# It's not audio, treat it as ASX redirector
		$::d_scan && msgf("scanWMA: Stream returned non-audio content-type: $type, treating as ASX redirector\n");
		
		# Re-fetch as a playlist.
		$args->{'playlist'} = Slim::Schema->rs('Playlist')->objectForUrl({
			'url'          => $args->{'url'},
			'content_type' => 'asx',
		});
		
		return scanPlaylist( $http->contentRef, $args );
	}
	
	# parse the ASF header data
	my $header = $http->content;
	
	my $chunkType = unpack 'v', substr($header, 0, 2);
	if ( $chunkType != 0x4824 ) {
		return scanWMAStreamError( $http, 'ASF_UNABLE_TO_PARSE' );
	}
	
	my $chunkLength = unpack 'v', substr($header, 2, 2);
	
	# skip to the body data
	my $io = IO::String->new( substr($header, 12, $chunkLength) );
	
	my $wma = Audio::WMA->new($io);
	
	$::d_scan && msg("WMA header data: " . Data::Dump::dump($wma) . "\n");
	
	if ( !$wma ) {
		return scanWMAStreamError( $http, 'ASF_UNABLE_TO_PARSE' );
	}
	
	my $streamNum = 1;
	
	# Some ASF streams appear to have no stream objects (mms://ms1.capitalinteractive.co.uk/fm_high)
	# I think it's safe to just assume stream #1 in this case
	if ( ref $wma->stream ) {
		
		# Look through all available streams and select the one with the highest bitrate still below
		# the user's preferred max bitrate
		# XXX: Playing stream IDs > 1 seems to be broken, firmware bug?
		my $max = Slim::Utils::Prefs::get('maxWMArate') || 9999;
	
		my $bitrate = 0;
		for my $stream ( @{ $wma->stream } ) {
			next unless defined $stream->{'streamNumber'};
		
			my $streamBitrate = int($stream->{'bitrate'} / 1000);
		
			$::d_scan && msgf("scanWMA: Available stream: #%d, %d kbps\n",
				$stream->{'streamNumber'},
				$streamBitrate,
			);

			if ( $stream->{'bitrate'} > $bitrate && $max >= $streamBitrate ) {
				$streamNum = $stream->{'streamNumber'};
				$bitrate   = $stream->{'bitrate'};
			}
		}
	
		if ( !$bitrate ) {
			# maybe we couldn't parse bitrate information, so just use the first stream
			$streamNum = $wma->stream(0)->{'streamNumber'};
		}

		$::d_scan && msgf("scanWMA: Will play stream #%d, bitrate: %s kbps\n",
			$streamNum,
			$bitrate ? int($bitrate / 1000) : 'unknown',
		);
	}
	
	# Always cache with mms URL prefix
	my $mmsURL = $args->{'url'};
	$mmsURL =~ s/^http/mms/;
	
	# Cache this metadata for the MMS protocol handler to use
	my $cache = Slim::Utils::Cache->instance;
	$cache->set( 'wma_streamNum_' . $mmsURL, $streamNum,      '1 day' );	
	$cache->set( 'wma_metadata_'  . $mmsURL, $wma,            '1 day' );
	
	# All done
	my $cb         = $args->{'callback'};
	my $pt         = $args->{'passthrough'} || [];
	my $foundItems = $args->{'foundItems'};
	
	return $cb->( $foundItems, @{$pt} );
}

sub scanWMAStreamError {
	my ( $http, $error ) = @_;
	my $args = $http->params('args');
	
	$::d_scan && msg("scanWMA Error: $error\n");
	
	if ( !Slim::Utils::Strings::stringExists($error) ) {
		$error = 'PROBLEM_CONNECTING';
	}
	
	my $cb         = $args->{'callback'};
	my $pt         = $args->{'passthrough'} || [];
	my $foundItems = $args->{'foundItems'};
	
	# Our error was on the first stream in foundItems, so remove it
	shift @{$foundItems};
	
	# If there are other streams in foundItems, try them
	if ( @{$foundItems} ) {
		$::d_scan && msgf("scanWMA: Trying next stream: %s\n", $foundItems->[0]->url);
		return scanWMAStream( {
			'url'         => $foundItems->[0]->url,
			'callback'    => $cb,
			'passthrough' => $pt,
			'foundItems'  => $foundItems,
		} );
	}
	
	# Callback with no foundItems, as we had an error
	push @{$pt}, $error;
	return $cb->( [], @{$pt} );
}

sub _skipWindowsHiddenFiles {
	my $attribs;

	return Win32::File::GetAttributes($_, $attribs) && !($attribs & Win32::File::HIDDEN());
}

1;

__END__
