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
use HTTP::Request;
use IO::String;
use MPEG::Audio::Frame;
use Path::Class;
use Scalar::Util qw(blessed);

use Slim::Formats::Playlists;
use Slim::Music::Info;
use Slim::Player::ProtocolHandlers;
use Slim::Networking::Async::HTTP;
use Slim::Utils::FileFindRule;
use Slim::Utils::Misc;
use Slim::Utils::ProgressBar;

# Constant Bitrates
our %cbr = map { $_ => 1 } qw(32 40 48 56 64 80 96 112 128 160 192 224 256 320);

# Handle any type of URI thrown at us.
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

		return $cb->( $foundItems || [] );
	}
}

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

	my $files = $rule->in($topDir);
	my $found = $args->{'foundItems'} || [];

	for my $file (@{$files}) {

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

# Wrapper around findNewAndChangedFiles(), so that other callers (iTunes,
# MusicMagic can reuse the logic.
sub findFilesForRescan {
	my $class  = shift;
	my $topDir = shift;
	my $args   = shift;

	$::d_scan && msg("findFilesForRescan: Generating file list from disk & database...\n");

	my $onDisk = $class->findFilesMatching($topDir, $args);
	my $inDB   = Slim::Schema->rs('Track')->allTracksAsPaths;

	return $class->findNewAndChangedFiles($onDisk, $inDB);
}

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

# Scan a directory on disk, and depending on the type of file, add it to the database.
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

	if ($::d_scan) {

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

	for my $file (@{$files}) {

		my $url = Slim::Utils::Misc::fileURLFromPath($file);

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
					'MUSICMAGIC_MIXABLE' => 1,
				}
			});

			$track = $class->scanPlaylistFileHandle($playlist, FileHandle->new($file));
		}

		# Bug: 3606 - only append to the listRef if a listRef exists.
		if (defined $track && $return) {

			push @{$foundItems}, $track;
		}

		$track = undef;

		$progress->update if $progress;
	}

	$progress->final if $progress;

	return $foundItems;
}

sub scanRemoteURL {
	my $class = shift;
	my $args  = shift;
	
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

		$::d_scan && msg("scanRemoteURL: found that $url is audio\n");
		
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
					'readLimit'   => 8 * 1024,
					'onBody'      => sub {
						my $http = shift;
						
						my $io = IO::String->new( $http->response->content_ref );
						
						my ($bitrate, $vbr) = scanBitrate($io);
						
						if ( $bitrate ) {
							Slim::Music::Info::setBitrate( $url, $bitrate, $vbr );
						}
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
		return $cb->( $foundItems, @{$pt} );
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
	
	my $cb = $args->{'callback'};
	my $pt = $args->{'passthrough'} || [];
	
	my $foundItems = [];
	
	$http->disconnect;
	
	my $playlistFH = IO::String->new( $http->response->content_ref );
	
	my @objects = __PACKAGE__->scanPlaylistFileHandle( $args->{'playlist'}, $playlistFH );
	
	# report an error if the playlist contained no items
	if ( !@objects ) {
		push @{$pt}, 'PLAYLIST_NO_ITEMS_FOUND';
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

	# Scan each playlist item until we find the first audio URL
	if ( !$args->{'scanningPlaylist'} ) {
		return scanPlaylistURLs( $foundItems, $args );
	}
	else {
		my $cb = $args->{'callback'};
		my $pt = $args->{'passthrough'} || [];
		return $cb->( $foundItems, @{$pt} );
	}
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

	if ( $::d_scan ) {
		msgf( "scanPlaylistFileHandle: found %d items in playlist:\n", scalar @playlistTracks );
		map { msgf( "  %s\n", $_->url ) } @playlistTracks;
	}

	return wantarray ? @playlistTracks : \@playlistTracks;
}

sub scanPlaylistURLs {
	my ( $foundItems, $args, $toScan, $error ) = @_;
	
	my $cb = $args->{'callback'};
	my $pt = $args->{'passthrough'} || [];
	
	my $offset = 0;
	for my $item ( @{$foundItems} ) {
		if ( Slim::Music::Info::isAudioURL( $item->url ) || Slim::Music::Info::isSong( $item ) ) {
			# we finally found an audio URL, so we're done
			$::d_scan && msgf( "scanPlaylistURLs: Found an audio URL: %s\n", $item->url );
			
			# return a list with the first found audio URL at the top
			unshift @{$foundItems}, splice @{$foundItems}, $offset, 1;
			
			return $cb->( $foundItems, @{$pt} );
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

sub scanBitrate {
	my $io = shift;
	
	# Check if first frame has a Xing VBR header
	# This will allow full files streamed from places like LMA or UPnP servers
	# to have accurate bitrate/length information
	my $frame = MPEG::Audio::Frame->read( $io );
	if ( $frame && $frame->content =~ /(Xing.*)/ ) {
		my $xing = IO::String->new( $1 );
		my $vbr  = {};
		my $off  = 4;
		
		# Xing parsing code from MP3::Info
		my $unpack_head = sub { unpack('l', pack('L', unpack('N', $_[0]))) };

		seek $xing, $off, 0;
		read $xing, my $flags, 4;
		$off += 4;
		$vbr->{flags} = $unpack_head->($flags);
		
		if ( $vbr->{flags} & 1 ) {
			seek $xing, $off, 0;
			read $xing, my $bytes, 4;
			$off += 4;
			$vbr->{frames} = $unpack_head->($bytes);
		}

		if ( $vbr->{flags} & 2 ) {
			seek $xing, $off, 0;
			read $xing, my $bytes, 4;
			$off += 4;
			$vbr->{bytes} = $unpack_head->($bytes);
		}
		
		my $mfs = $frame->sample / ( $frame->version ? 144000 : 72000 );
		my $bitrate = sprintf "%.0f", $vbr->{bytes} / $vbr->{frames} * $mfs;
		
		$::d_scan && msg("scanBitrate: Found Xing VBR header in stream, bitrate: $bitrate kbps VBR\n");
		
		return ($bitrate * 1000, 1);
	}
	
	# No Xing header, take an average of frame bitrates

	my @bitrates;
	my ($avg, $sum) = (0, 0);
	
	seek $io, 0, 0;
	while ( my $frame = MPEG::Audio::Frame->read( $io ) ) {
		
		# Sample all frames to try to see if we're VBR or not
		if ( $frame->bitrate ) {
			push @bitrates, $frame->bitrate;
			$sum += $frame->bitrate;
			$avg = int( $sum / @bitrates );
		}
	}

	if ( $avg ) {			
		my $vbr = undef;
		if ( !$cbr{$avg} ) {
			$vbr = 1;
		}
		
		$::d_scan && msg("scanBitrate: Read average bitrate from stream: $avg " . ( $vbr ? 'VBR' : 'CBR' ) . "\n");
		
		return ($avg * 1000, $vbr);
	}
	
	$::d_scan && msg("scanBitrate: Unable to find any MP3 frames in stream\n");
	
	return (undef, undef);
}

sub _skipWindowsHiddenFiles {
	my $attribs;

	return Win32::File::GetAttributes($_, $attribs) && !($attribs & Win32::File::HIDDEN());
}

1;

__END__
