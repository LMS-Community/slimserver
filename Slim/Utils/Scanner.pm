package Slim::Utils::Scanner;

# $Id$
#
# SqueezeCenter Copyright 2001-2007 Logitech.
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
use File::Next;
use HTTP::Request;
use IO::String;
use Path::Class;
use Scalar::Util qw(blessed);

use Slim::Formats;
use Slim::Formats::Playlists;
use Slim::Music::Info;
use Slim::Player::ProtocolHandlers;
use Slim::Networking::Async::HTTP;
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
		$log->info("Finding valid files in: $pathOrUrl");

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

	my $os     = Slim::Utils::OSDetect::OS();
	my $types  = Slim::Music::Info::validTypeExtensions($args->{'types'});

	my $descend_filter = sub {
		
		return 0 if defined $args->{'recursive'} && !$args->{'recursive'};

		return Slim::Utils::Misc::folderFilter($File::Next::dir);
	};

	my $file_filter = sub {
		return Slim::Utils::Misc::fileFilter($File::Next::dir, $_, $types);
	};

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

				logWarning("Found an infinite loop! Breaking out: $file -> $topDir");
				next;
			}

			# Recurse into additional shortcuts and directories.
			if ($file =~ /\.lnk$/i || -d $file) {

				$log->info("Following Windows Shortcut to: $url");

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

	$log->info("Generating file list from disk & database...");

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

	$log->info("Comparing file list between disk & database to generate rescan list...");

	# When rescanning: we need to find files:
	#
	# * That are new - not in the db
	# * That have changed - are in the db, but timestamp or size is different.
	#
	# Generate a list of files that are on disk, but are not in the database.
	my $last  = Slim::Music::Import->lastScanTime;
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

	if ( $log->is_info ) {
		$log->info("About to look for files in $topDir");
		$log->info("For files with extensions in: ", Slim::Music::Info::validTypeExtensions($args->{'types'}));
	}

	my $files  = [];

	# Send progress info to the db and progress bar
	my $progress = Slim::Utils::Progress->new({
		'type' => 'importer',
		'name' => $args->{'scanName'} || 'directory',
		'bar' => 1,
		'every'=> ($args->{'scanName'} && $args->{'scanName'} eq 'playlist'), # record all playists in the db
	});

	if ($::rescan) {
		$files = $class->findFilesForRescan($topDir->stringify, $args);
	} else {
		$files = $class->findFilesMatching($topDir->stringify, $args);
	}

	if (!scalar @{$files}) {

		$log->warn("Didn't find any valid files in: [$topDir]");

		$progress->final;

		return $foundItems;

	} else {

		if ( $log->is_info ) {
			$log->info(sprintf("Found %d files in %s\n", scalar @{$files}, $topDir));
		}
	}

	$progress->total( scalar @{$files} );

	# If we're starting with a clean db - don't bother with searching for a track
	my $method   = $::wipe ? 'newTrack' : 'updateOrCreate';

	for my $file (@{$files}) {

		$progress->update($file);

		my $url = Slim::Utils::Misc::fileURLFromPath($file);

		if (Slim::Music::Info::isSong($url)) {

			$log->debug("Adding $url to database.");

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
			$log->debug("Adding playlist $url to database.");

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

	$progress->final;

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
	
	# Let protocol handlers adjust the URL before scanning
	# This is currently used by Live365 to dynamically add the correct
	# session ID to the URL before scanning.
	my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $url );
	if ( $handler && $handler->can('onScan') && !$args->{'onScanDone'} ) {
		$log->debug("scanRemoteURL: Letting $handler handle onScan");
		$handler->onScan(
			$args->{'client'},
			$url,
			sub {
				my $newURL = shift;
				
				# rescan with new URL
				$args->{'url'}        = $newURL;
				$args->{'onScanDone'} = 1;
				
				return $class->scanRemoteURL( $args );
			},
		);
		return;
	}

	if ( Slim::Music::Info::isAudioURL($url) ) {

		$log->debug("Remote stream $url known to be audio");

		my $track = Slim::Schema->rs('Track')->updateOrCreate({
			'url' => $url,
		});

		$track->content_type( Slim::Music::Info::typeFromPath($url) );
		
		push @{$foundItems}, $track;
		
		# Protocol Handlers may want to perform additional actions in an async manner
		# such as Rhapsody Direct.  If so, we assume it's an audio URL, and let the
		# handler call us back when done 
		if ( $handler && $handler->can('onCommand') ) { # this needs a better name
			$log->debug("scanRemoteURL: Letting $handler handle onCommand operations");
			$handler->onCommand(
				$args->{'client'}, 
				$args->{'cmd'}, 
				$url, 
				sub {
					$cb->( $foundItems, @{$pt} );
				}
			);
			return;
		}

		return $cb->( $foundItems, @{$pt} );
	}
	
	# Bug 4522, if user has disabled native WMA decoding to get MMS support, don't scan MMS URLs
	if ( $url =~ /^mms/i ) {
		
		my ($command, $type, $format) = Slim::Player::TranscodingHelper::getConvertCommand(
			$args->{'client'},
			$url,
			'wma',
		);
		
		if ( defined $command && $command ne '-' ) {
			
			$log->debug('Not scanning MMS URL because transcoding is enabled.');

			my $track = Slim::Schema->rs('Track')->updateOrCreate({
				'url' => $url,
			});

			$track->content_type( 'wma' );

			push @{$foundItems}, $track;

			return $cb->( $foundItems, @{$pt} );
		}
	}			
	
	my $originalURL = $url;
	
	my $request = HTTP::Request->new( GET => $url );
	
	# Use WMP headers for MMS protocol URLs or ASF/ASX/WMA URLs
	if ( $url =~ /(?:^mms|\.asf|\.asx|\.wma)/i ) {
		
		addWMAHeaders( $request );
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

	$log->debug("Opening remote location $url");
	
	my $http = Slim::Networking::Async::HTTP->new();
	$http->send_request( {
		'request'     => $request,
		'onRedirect'  => \&handleRedirect,
		'onHeaders'   => \&readRemoteHeaders,
		'onError'     => sub {
			my ( $http, $error ) = @_;

			logError("Can't connect to remote server to retrieve playlist: $error.");

			push @{$pt}, $error;
			return $cb->( $foundItems, @{$pt} );
		},
		'passthrough' => [ $args, $originalURL ],
	} );
}

=head2 addWMAHeaders( $request )

Adds Windows Media Player headers to the HTTP request.

=cut

sub addWMAHeaders {
	my $request = shift;
	
	my $url = $request->uri->as_string;
	$url =~ s/^mms/http/;
	
	$request->uri( $url );
	
	my $h = $request->headers;
	$h->header( Accept => '*/*' );
	$h->header( 'User-Agent' => 'NSPlayer/4.1.0.3856' );
	$h->header( Pragma => [
		'xClientGUID={' . Slim::Player::Protocols::MMS::randomGUID(). '}',
		'no-cache,rate=1.0000000,stream-time=0,stream-offset=0:0,request-context=1,max-duration=0',
	] );
	$h->header( Connection => 'close' );
}

=head2 handleRedirect( $http, $url )

Callback when Async::HTTP encounters a redirect.  If a server (RadioTime) 
redirects to an mms:// protocol URL we need to rewrite the link and set proper headers.

=cut

sub handleRedirect {
	my ( $request, $args, $originalURL ) = @_;
	
	if ( $request->uri =~ /^mms/ ) {

		if ( $log->is_debug ) {
			$log->debug("Server redirected to MMS URL: " . $request->uri . ", adding WMA headers");
		}
		
		addWMAHeaders( $request );
	}
	
	# Maintain title across redirects
	my $title = Slim::Music::Info::title($originalURL);
	Slim::Music::Info::setTitle( $request->uri->as_string, $title );

	if ( $log->is_debug ) {
		$log->debug( "Server redirected, copying title $title from $originalURL to " . $request->uri );
	}
	
	return $request;
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
	
	$log->debug("Content-Type is $type for $url");
	
	$track->content_type( $type );
	$track->update;
	
	Slim::Music::Info::setContentType( $url, $type );

	# Check if it's still a playlist after we open the
	# remote stream. We may have got a different content
	# type while loading.
	if ( Slim::Music::Info::isSong($track) ) {

		$log->debug("Found that $url is audio [$type]");
		
		# If we redirected, we need to update the title on the final URL to match
		# the title for the original URL
		if ( $url ne $originalURL ) {
			
			# On a redirect, the protocol handler may want to know about the new URL
			# This is used by Live365 to get the correct stream URL
			if ( $originalURL !~ /^(?:http|mms)/ ) {
				my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $originalURL );
				if ( $handler && $handler->can('notifyOnRedirect') ) {
					$handler->notifyOnRedirect( $args->{'client'}, $originalURL, $url );
					
					# reset the URL back to the original URL
					$url = $originalURL;
					$track->url($url);
					$track->update;
				}
			}
			
			my $title = Slim::Music::Info::title( $originalURL );
			Slim::Music::Info::setTitle( $url, $title );
			Slim::Music::Info::setCurrentTitle( $url, $title );
		}
		
		# If the URL doesn't have a title, set the title to URL
		if ( !Slim::Music::Info::title( $url ) ) {
			$log->debug( "No title available for $url, displaying URL" );
			Slim::Music::Info::setTitle( $url, $url );
			Slim::Music::Info::setCurrentTitle( $url, $url );
		}
		
		# If the audio is mp3, we can read the bitrate from the header or stream
		if ( $type eq 'mp3' ) {

			if ( my $bitrate = ( $http->response->header( 'icy-br' ) || $http->response->header( 'x-audiocast-bitrate' ) ) * 1000 ) {

				$log->debug("Found bitrate in header: $bitrate");

				$track->bitrate( $bitrate );
				$track->update;

				Slim::Music::Info::setBitrate( $url, $bitrate );
				
				$http->disconnect;
			}
			else {

				$log->debug("Scanning mp3 stream for bitrate");
				
				$http->read_body( {
					'readLimit'   => 128 * 1024,
					'onBody'      => sub {
						my $http = shift;
						
						my $io = IO::String->new( $http->response->content_ref );
						
						my ($bitrate, $vbr) = scanBitrate( $io, 'mp3', $url );
						
						if ( $bitrate > 0 ) {
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
		
		# Bug 3980
		# On WMA streams, we need to make an initial request to determine the stream
		# number to use, and we also grab various metadata during this request
		# This prevents the player from needing to make 2 requests for each WMA stream
		
		if ( $type eq 'wma' && $url =~ /^(?:http|mms)/ ) {
			
			scanWMAStream( {
				'client'      => $args->{'client'},
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
		
		$log->debug("Found that $url is a playlist");

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

		$log->debug("Will scan $url, base: $parentDir");
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

		$ct = 'ssp';
	}

	$playlist->content_type($ct);
	$playlist->update;
	
	# Copy playlist title to all items if they are remote URLs
	for my $track ( @playlistTracks ) {
		if ( $track->remote ) {
			$track->title( $playlist->title );
			$track->update;
		}
	}
	
	if ($log->is_debug) {

		$log->debug(sprintf("Found %d items in playlist: ", scalar @playlistTracks));

		for my $track (@playlistTracks) {

			$log->debug(sprintf("  %s", blessed($track) ? $track->url : ''));
		}
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
		
		next if !blessed $item;
		
		# Ignore Windows Media .nsc files, these are definition files for multicast streams
		# http://en.wikipedia.org/wiki/Windows_Media_Station
		next if $item->content_type eq 'wma' && $item->url =~ /\.nsc$/i;
		
		if ( Slim::Music::Info::isAudioURL( $item->url ) || Slim::Music::Info::isSong( $item ) ) {

			# we finally found an audio URL, so we're done

			if ( $log->is_debug ) {
				$log->debug( sprintf( "Found an audio URL: %s [%s]", $item->url, $item->content_type ) );
			}
			
			# return a list with the first found audio URL at the top
			unshift @{$foundItems}, splice @{$foundItems}, $offset, 1;

			if ( $item->content_type eq 'wma' && $item->url =~ /^(?:http|mms)/ ) {
				
				scanWMAStream( {
					'client'      => $args->{'client'},
					'url'         => $item->url,
					'callback'    => $cb,
					'passthrough' => $pt,
					'foundItems'  => $foundItems,
				} );
				
				return;
			}
			
			return $cb->( $foundItems, @{$pt} );
		}
		$offset++;
	}
	
	$toScan ||= [];
	
	push @{$toScan}, map { $_->url } grep { blessed($_) } @{$foundItems};
	
	# This counter makes sure we don't go into an infinite loop
	$args->{'loopCount'} ||= 0;
	
	if ( $args->{'loopCount'} > 5 ) {

		logger('formats.playlists')->warn("Warning: recursion limit reached, giving up");

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
		push @{$pt}, $error || 'PLAYLIST_NO_ITEMS_FOUND';
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

	if ($formatClass && Slim::Formats->loadTagFormatForType($contentType) && $formatClass->can('scanBitrate')) {

		return $formatClass->scanBitrate( $fh, $url );
	}

	$log->warn("Unable to scan content-type: $contentType");

	return (-1, undef);
}

=head2 scanWMAStream( { url => $url, callback => $callback } )

Make the initial WMA stream request to determine stream number and cache
the result for use by the direct streaming code in Protocols::MMS.

=cut

sub scanWMAStream {
	my $args = shift;
	
	my $request = HTTP::Request->new( GET => $args->{'url'} );
	
	addWMAHeaders( $request );
	
	# Make sure we don't send any bad URLs through
	if ( $request->uri->as_string !~ /^http:/ ) {
		my $error = 'Invalid URL: ' . $args->{'url'};
		scanWMAStreamError( undef, $error, $args );
		return;
	}
	
	if ( $log->is_debug ) {
		$log->debug("Checking stream at " . $request->uri);
	}
	
	my $http = Slim::Networking::Async::HTTP->new();

	$http->send_request( {
		'request'     => $request,
		'readLimit'   => 64 * 1024,
		'onBody'      => \&scanWMAStreamDone,
		'onError'     => \&scanWMAStreamError,
		'passthrough' => [ $args ],
	} );
}

=head2 scanWMAStreamDone( $http )

Callback from scanWMAStream that parses the ASF header data.  For reference see
http://avifile.sourceforge.net/asf-1.0.htm

=cut

sub scanWMAStreamDone {
	my ( $http, $args ) = @_;
	
	# Check content-type of stream to make sure it's audio
	my $type = $http->response->headers->header('Content-Type');
	
	if (   $type ne 'application/octet-stream'
		&& $type ne 'application/x-mms-framed' 
		&& $type ne 'application/vnd.ms.wms-hdr.asfv1'
		&& $type ne 'audio/x-ms-wma'
		&& $type ne 'audio/asf'
	) {

		if ( scalar @{ $args->{'foundItems'} } == 1 ) {

			# if $type is another audio type such as MP3, try to play it using playlist play
			my $filetype = Slim::Music::Info::mimeToType($type);
			if ( Slim::Music::Info::isSong( undef, $filetype ) ) {
				$log->debug( "Stream returned non-WMA audio content-type: $type ($filetype), trying to play" );
				$args->{'url'} =~ s/^mms/http/;
				$args->{'client'}->execute( [ 'playlist', 'play', $args->{'url'} ] );
				return;
			}
			
			$log->debug("Stream returned non-audio content-type: $type, treating as ASX redirector");
		
			# Re-fetch as a playlist.
			$args->{'playlist'} = Slim::Schema->rs('Playlist')->objectForUrl({
				'url' => $args->{'url'},
			});
			$args->{'playlist'}->content_type('asx');
			$args->{'playlist'}->update;
		
			scanPlaylist( $http->response->content_ref, $args );
			
			return;
		}
		else {
			
			# if $type is another audio type such as MP3, try to play it using playlist play
			my $filetype = Slim::Music::Info::mimeToType($type);
			if ( Slim::Music::Info::isSong( undef, $filetype ) ) {
				$log->debug( "Stream returned non-WMA audio content-type: $type ($filetype), trying to play" );
				$args->{'url'} =~ s/^mms/http/;
				$args->{'client'}->execute( [ 'playlist', 'play', $args->{'url'} ] );
				return;
			}
			
			# Skip the stream with the bad content-type, and try the next stream
			$log->debug("Stream returned non-audio content-type: $type, skipping to the next stream.");
			
			shift @{ $args->{'foundItems'} };
			my $next = $args->{'foundItems'}->[0];
			
			scanWMAStream( {
				'client'      => $args->{'client'},
				'url'         => $next->url,
				'callback'    => $args->{'callback'},
				'passthrough' => $args->{'pt'},
				'foundItems'  => $args->{'foundItems'},
			} );
			
			return;
		}
	}
	
	# parse the ASF header data
	
	# The header may be at the front of the file, if the remote
	# WMA file is not a live stream
	my $io  = IO::String->new( $http->response->content_ref );
	my $wma = Audio::WMA->new( $io, length( $http->response->content ) );
	
	if ( !$wma || !ref $wma->stream ) {
		
		# it's probably a live stream, the WMA header is offset
		my $header = $http->response->content;
		my $chunkType = unpack 'v', substr($header, 0, 2);
		if ( $chunkType != 0x4824 ) {
			$log->debug("WMA header does not start with 0x4824");
			return scanWMAStreamError( $http, 'ASF_UNABLE_TO_PARSE', $args );
		}
	
		my $chunkLength = unpack 'v', substr($header, 2, 2);
	
		# skip to the body data
		my $body = substr($header, 12, $chunkLength);
		$io->open(\$body);
		$wma = Audio::WMA->new( $io, length($body) );
	
		if ( !$wma ) {
			return scanWMAStreamError( $http, 'ASF_UNABLE_TO_PARSE', $args );
		}
	}
	
	if ( $log->is_debug ) {
		$log->debug("WMA header data: " . Data::Dump::dump($wma));
	}
	
	my $streamNum = 1;
	
	# Some ASF streams appear to have no stream objects (mms://ms1.capitalinteractive.co.uk/fm_high)
	# I think it's safe to just assume stream #1 in this case
	if ( ref $wma->stream ) {
		
		# Look through all available streams and select the one with the highest bitrate still below
		# the user's preferred max bitrate
		my $max = preferences('server')->get('maxWMArate') || 9999;
	
		my $bitrate = 0;
		for my $stream ( @{ $wma->stream } ) {
			next unless defined $stream->{'streamNumber'};
		
			my $streamBitrate = int($stream->{'bitrate'} / 1000);
		
			$log->debug("Available stream: \#$stream->{'streamNumber'}, $streamBitrate kbps");

			if ( $stream->{'bitrate'} > $bitrate && $max >= $streamBitrate ) {
				$streamNum = $stream->{'streamNumber'};
				$bitrate   = $stream->{'bitrate'};
			}
		}
	
		if ( !$bitrate && ref $wma->stream(0) ) {
			# maybe we couldn't parse bitrate information, so just use the first stream
			$streamNum = $wma->stream(0)->{'streamNumber'};
		}

		if ( $log->is_debug ) {
			$log->debug(sprintf("Will play stream #%d, bitrate: %s kbps",
				$streamNum,
				$bitrate ? int($bitrate / 1000) : 'unknown',
			));
		}
	}
	
	# Always cache with mms URL prefix
	my $mmsURL = $args->{'url'};
	$mmsURL =~ s/^http/mms/;
	
	# Cache this metadata for the MMS protocol handler to use
	my $cache = Slim::Utils::Cache->new;
	$cache->set( 'wma_streamNum_' . $mmsURL, $streamNum,      '1 day' );	
	$cache->set( 'wma_metadata_'  . $mmsURL, $wma,            '1 day' );
	
	# Always return WMA URLs using MMS prefix so correct direct stream headers are used
	$args->{'foundItems'}->[0]->url( $mmsURL );
	$args->{'foundItems'}->[0]->update;
	
	# All done
	my $cb         = $args->{'callback'};
	my $pt         = $args->{'passthrough'} || [];
	my $foundItems = $args->{'foundItems'};
	
	return $cb->( $foundItems, @{$pt} );
}

sub scanWMAStreamError {
	my ( $http, $error, $args ) = @_;
	
	$log->error("Error: $error");
	
	my $cb         = $args->{'callback'};
	my $pt         = $args->{'passthrough'} || [];
	my $foundItems = $args->{'foundItems'};
	
	# Our error was on the first stream in foundItems, so remove it
	shift @{$foundItems};
	
	# If there are other streams in foundItems, try them
	if ( @{$foundItems} ) {

		if ( $log->is_debug ) {
			$log->debug("Trying next stream: %s", $foundItems->[0]->url);
		}

		return scanWMAStream( {
			'client'      => $args->{'client'},
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

1;

__END__
