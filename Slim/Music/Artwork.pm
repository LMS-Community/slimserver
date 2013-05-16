package Slim::Music::Artwork;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Music::Artwork

=head1 DESCRIPTION

L<Slim::Music::Artwork>

=cut

use strict;

use File::Basename qw(basename dirname);
use File::Slurp;
use File::Path qw(mkpath rmtree);
use File::Spec::Functions qw(catfile catdir);
use Path::Class;
use Scalar::Util qw(blessed);
use Tie::Cache::LRU;

use Slim::Formats;
use Slim::Music::Import;
use Slim::Music::Info;
use Slim::Music::TitleFormatter;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Unicode;
use Slim::Utils::OSDetect;

use constant MAX_RETRIES => 5;

# Global caches:
my $artworkDir = '';
my $log        = logger('artwork');
my $importlog  = logger('scan.import');

my $prefs = preferences('server');

tie my %lastFile, 'Tie::Cache::LRU', 128;

# Small cache of path -> cover.jpg mapping to speed up
# scans of files in the same directory
# Don't use Tie::Cache::LRU as it is a bit too expensive in the scanner
my %findArtCache;

# Public class methods
sub findStandaloneArtwork {
	my ( $class, $trackAttributes, $deferredAttributes, $dirurl ) = @_;
	
	my $isInfo = main::INFOLOG && $log->is_info;
	
	my $art = $findArtCache{$dirurl};
	
	# Files to look for
	my @files = qw(cover folder album thumb);
	
	# User-defined artwork format
	my $coverFormat = $prefs->get('coverArt');

	if ( !defined $art ) {
		my $parentDir = Path::Class::dir( Slim::Utils::Misc::pathFromFileURL($dirurl) );
		
		# coverArt/artfolder pref support
		if ( $coverFormat ) {
			# If the user has specified a pattern to match the artwork on, we need
			# to generate that pattern. This is nasty.
			if ( $coverFormat =~ /^%(.*?)(\..*?){0,1}$/ ) {
				my $suffix = $2 ? $2 : '.jpg';

				# Merge attributes to use with TitleFormatter
				# XXX This may break for some people as it's not using a Track object anymore
				my $meta = { %{$trackAttributes}, %{$deferredAttributes} };
				
				if ( my $prefix = Slim::Music::TitleFormatter::infoFormat( undef, $1, undef, $meta ) ) {
					$coverFormat = $prefix . $suffix;

					if ( main::ISWINDOWS ) {
						# Remove illegal characters from filename.
						$coverFormat =~ s/\\|\/|\:|\*|\?|\"|<|>|\|//g;
					}
					
					# Generating a pathname from tags is dangerous because the filesystem
					# encoding may not match the locale, but that is the best guess that we have.
					$coverFormat = Slim::Utils::Unicode::encode_locale($coverFormat);

					my $artPath = $parentDir->file($coverFormat)->stringify;
					
					if ( my $artDir = $prefs->get('artfolder') ) {
						$artDir  = Path::Class::dir($artDir);
						$artPath = $artDir->file($coverFormat)->stringify;
					}
					
					if ( -e $artPath ) {
						$isInfo && $log->info("Found variable cover $coverFormat from $1");
						$art = $artPath;
					}
					else {
						$isInfo && $log->info("No variable cover $coverFormat found from $1");
					}
				}
				else {
				 	$isInfo && $log->info("No variable cover match for $1");
				}
			}
			elsif ( defined $coverFormat ) {
				if ( main::ISWINDOWS ) {
					# Remove illegal characters from filename.
					$coverFormat =~ s/\\|\/|\:|\*|\?|\"|<|>|\|//g;
				}

				push @files, $coverFormat;
			}
		}
		
		if ( !$art ) {
			# Find all image files in the file directory
			my $types = qr/\.(?:jpe?g|png|gif)$/i;
			
			my $files = File::Next::files( {
				file_filter    => sub { Slim::Utils::Misc::fileFilter($File::Next::dir, $_, $types, undef, 1) },
				descend_filter => sub { 0 },
			}, $parentDir );
	
			my @found;
			while ( my $image = $files->() ) {
				push @found, $image;
			}
			
			# Prefer cover/folder/album/thumb, then just take the first image
			my $filelist = join( '|', @files );
			if ( my @preferred = grep { basename($_) =~ qr/^(?:$filelist)\./i } @found ) {
				$art = $preferred[0];
			}
			else {
				$art = $found[0] || 0;
			}
		}
	
		# Cache found artwork for this directory to speed up later tracks
		# No caching if using a user-defined artwork format, the user may have multiple
		# files in a single directory with different artwork
		if ( !$coverFormat ) {
			%findArtCache = () if scalar keys %findArtCache > 32;
			$findArtCache{$dirurl} = $art;
		}
	}
	
	$isInfo && $log->info("Using $art");
	
	return $art || 0;
}

sub getImageContentAndType {
	my $class = shift;
	my $path  = shift;

	# Bug 3245 - for systems who's locale is not UTF-8 - turn our UTF-8
	# path into the current locale.
	# Bug 16683: this is no longer true - all paths should be native encoding already
	# (locale encoding of $path removed)

	my $content = eval { read_file($path, 'binmode' => ':raw') };

	if (defined($content) && length($content)) {

		return ($content, $class->_imageContentType(\$content));
	}

	main::DEBUGLOG && $log->is_debug && $log->debug("Image File empty or couldn't read: $path : $! [$@]");

	return undef;
}

sub readCoverArt {
	my $class = shift;
	my $track = shift;  

	my $url  = Slim::Utils::Misc::stripAnchorFromURL($track->url);
	my $file = $track->path;

	# Try to read a cover image from the tags first.
	my ($body, $contentType, $path) = $class->_readCoverArtTags($track, $file);

	# Nothing there? Look on the file system.
	if (!defined $body) {
		($body, $contentType, $path) = $class->_readCoverArtFiles($track, $file);
	}

	return ($body, $contentType, $path);
}

# Private class methods
sub _imageContentType {
	my $class = shift;
	my $body  = shift;

	use bytes;

	# iTunes sometimes puts PNG images in and says they are jpeg
	if ($$body =~ /^\x89PNG\x0d\x0a\x1a\x0a/) {

		return 'image/png';

	} elsif ($$body =~ /^GIF(\d\d)([a-z])/) {

		return 'image/gif';

	} elsif ($$body =~ /^.*?(\xff\xd8\xff)/) {

		my $header = $1;

		# See http://www.obrador.com/essentialjpeg/headerinfo.htm for
		# the JPEG header spec.
		#
		# jpeg images must start with ff d8 or they are not jpeg,
		# the next table will always start with ff as well, so look
		# for that. JFIF is an addition to the standard, we've seen
		# baseline images (bug 3850) without a JFIF header.
		# sometimes there is junk before.
		$$body =~ s/^.*?$header/$header/;

		return 'image/jpeg';

	} elsif ($$body =~ /^BM/) {

		return 'image/bmp';
	}

	return 'application/octet-stream';
}

sub _readCoverArtTags {
	my $class = shift;
	my $track = shift;
	my $file  = shift;

	my $isInfo = main::INFOLOG && $log->is_info;

	$isInfo && $log->info("Looking for a cover art image in the tags of: [$file]");

	if (blessed($track) && $track->can('audio') && $track->audio) {

		my $ct          = Slim::Schema->contentType($track);
		my $formatClass = Slim::Formats->classForFormat($ct);
		my $body        = undef;

		if (Slim::Formats->loadTagFormatForType($ct) && $formatClass->can('getCoverArt')) {

			$body = $formatClass->getCoverArt($file);
		}

		if ($body) {

			my $contentType = $class->_imageContentType(\$body);
			
			$isInfo && $log->info(sprintf("Found image of length [%d] bytes with type: [$contentType]", length($body)));

			return ($body, $contentType, length($body));
		}

 	} else {

		$isInfo && $log->info("Not file we can extract artwork from. Skipping.");
	}

	return undef;
}

sub _readCoverArtFiles {
	my $class = shift;
	my $track = shift;
	my $path  = shift;
	
	my $isInfo = main::INFOLOG && $log->is_info;

	my @names      = qw(cover Cover thumb Thumb album Album folder Folder);
	my @ext        = qw(png jpg jpeg gif);

	my $file       = file($path);
	my $parentDir  = $file->dir;
	my $trackId    = $track->id;

	$isInfo && $log->info("Looking for image files in $parentDir");

	my %nameslist  = map { $_ => [do { my $t = $_; map { "$t.$_" } @ext }] } @names;
	
	# these seem to be in a particular order - not sure if that means anything.
	my @filestotry = map { @{$nameslist{$_}} } @names;
	my $artwork    = $prefs->get('coverArt');

	# If the user has specified a pattern to match the artwork on, we need
	# to generate that pattern. This is nasty.
	if (defined($artwork) && $artwork =~ /^%(.*?)(\..*?){0,1}$/) {

		my $suffix = $2 ? $2 : ".jpg";

		if (my $prefix = Slim::Music::TitleFormatter::infoFormat(
				Slim::Utils::Misc::fileURLFromPath($track->url), $1)) {
		
			$artwork = $prefix . $suffix;
	
			$isInfo && $log->info("Variable cover: $artwork from $1");
	
			if (main::ISWINDOWS) {
				# Remove illegal characters from filename.
				$artwork =~ s/\\|\/|\:|\*|\?|\"|<|>|\|//g;
			}		
			
			# Generating a pathname from tags is dangerous because the filesystem
			# encoding may not match the locale, but that is the best guess that we have.
			$artwork = Slim::Utils::Unicode::encode_locale($artwork);
	
			my $artPath = $parentDir->file($artwork)->stringify;
	
			my ($body, $contentType) = $class->getImageContentAndType($artPath);
	
			my $artDir  = dir($prefs->get('artfolder'));
	
			if (!$body && defined $artDir) {
	
				$artPath = $artDir->file($artwork)->stringify;
	
				($body, $contentType) = $class->getImageContentAndType($artPath);
			}
	
			if ($body && $contentType) {
	
				$isInfo && $log->info("Found image file: $artPath");
	
				return ($body, $contentType, $artPath);
			}
		} else {
			
			$isInfo && $log->info("Variable cover: no match from $1");
		}

	} elsif (defined $artwork) {

		unshift @filestotry, $artwork;
	}

	if (defined $artworkDir && $artworkDir eq $parentDir) {

		if (exists $lastFile{$trackId} && $lastFile{$trackId} ne 1) {

			$isInfo && $log->info("Using existing image: $lastFile{$trackId}");

			my ($body, $contentType) = $class->getImageContentAndType($lastFile{$trackId});

			return ($body, $contentType, $lastFile{$trackId});

		} elsif (exists $lastFile{$trackId}) {

			$isInfo && $log->info("No image in $artworkDir");

			return undef;
		}

	} else {

		$artworkDir = $parentDir;
		%lastFile = ();
	}

	for my $file (@filestotry) {

		$file = $parentDir->file($file)->stringify;

		next unless -f $file;

		my ($body, $contentType) = $class->getImageContentAndType($file);

		if ($body && $contentType) {

			$isInfo && $log->info("Found image file: $file");

			$lastFile{$trackId} = $file;

			return ($body, $contentType, $file);

		} else {

			$lastFile{$trackId} = 1;
		}
	}

	return undef;
}

sub precacheAllArtwork {
	my $class = shift;
	my $cb    = shift; # optional callback when done (main process async mode)
	my $force = shift; # sometimes we want all artwork to be re-rendered
	
	my $isDebug = main::DEBUGLOG && $importlog->is_debug;
	
	my $isEnabled = $prefs->get('precacheArtwork');
	
	my $dbh = Slim::Schema->dbh;
		
	# Find all tracks with un-cached artwork:
	# * All distinct cover values where cover isn't 0 and cover_cached is null
	# * Tracks share the same cover art when the cover field is the same
	#   (same path or same embedded art length).
	my $sql = qq{
		SELECT
			tracks.url,
			tracks.cover,
			tracks.coverid,
			albums.id AS albumid,
			albums.title AS album_title,
			albums.artwork AS album_artwork
		FROM   tracks
		JOIN   albums ON (tracks.album = albums.id)
		WHERE  tracks.cover != '0'
		AND    tracks.coverid IS NOT NULL
	}
	. ($force ? '' : ' AND    tracks.cover_cached IS NULL')
	. qq{ 
		GROUP BY tracks.cover
 	};

	my $sth_update_tracks = $dbh->prepare( qq{
	    UPDATE tracks
	    SET    coverid = ?, cover_cached = 1
	    WHERE  album = ?
	    AND    cover = ?
	} );
	
	my $sth_update_albums = $dbh->prepare( qq{
		UPDATE albums
		SET    artwork = ?
		WHERE  id = ?
	} );

	my ($count) = $dbh->selectrow_array( qq{
		SELECT COUNT(*) FROM ( $sql ) AS t1
	} );
	
	$log->error("Starting precacheArtwork for $count albums");
	
	if ( !$count ) {
		$cb && $cb->();
		
		if ( main::SCANNER ) {
			Slim::Music::Import->endImporter('precacheArtwork');
		}
		
		return;
	}

	my $progress = Slim::Utils::Progress->new( { 
		type  => 'importer',
		name  => 'precacheArtwork',
		total => $count, 
		bar   => 1,
	} );
	
	# Pre-cache this artwork resized to our commonly-used sizes/formats
	# 1. user's thumb size or 100x100_o (large web artwork)
	# 2. 50x50_o (small web artwork)
	# 3+ SqueezePlay/Jive size artwork
	my @specs;
	
	if ($isEnabled) {
		@specs = getResizeSpecs();
		
		require Slim::Utils::ImageResizer;
	}
	
	my $sth = $dbh->prepare($sql);
	$sth->execute;
	
	my ($url, $cover, $coverid, $albumid, $album_title, $album_artwork);
	$sth->bind_columns(\$url, \$cover, \$coverid, \$albumid, \$album_title, \$album_artwork);
	
	my $i = 0;
	
	my %artCount;
	
	my $work = sub {
		if ( $sth->fetch ) {
			# Make sure album.artwork points to this track, as it may not
			# be pointing there now because we did not join tracks via the
			# artwork column.
			if ( $album_artwork && $album_artwork ne $coverid ) {
				$sth_update_albums->execute( $coverid, $albumid );
			}
			
			$artCount{$albumid}++;
			
			# Callback after resize is finished, needed for async resizing
			my $finished = sub {			
				if ($isEnabled) {
					# Update the rest of the tracks on this album
					# to use the same coverid and cover_cached status
					$sth_update_tracks->execute( $coverid, $albumid, $cover );
				}
				
				$progress->update( $album_title );

				if ( ++$i % 50 == 0 ) {
					Slim::Schema->forceCommit;
				}
				
				Slim::Utils::Scheduler::unpause() if !main::SCANNER;
			};
			
			# Do the actual pre-caching only if the pref for it is enabled
			if ( $isEnabled ) {
				# Image to resize is either a cover path or the audio file
				my $path = $cover =~ /^\d+$/
					? Slim::Utils::Misc::pathFromFileURL($url)
					: $cover;
			
				$isDebug && $importlog->debug( "Pre-caching artwork for " . $album_title . " from $path" );
				
				# have scheduler wait for the finished callback
				Slim::Utils::Scheduler::pause() if !main::SCANNER;
			
				Slim::Utils::ImageResizer->resize($path, "music/$coverid/cover_", join(',', @specs), $finished);
			}
			else {
				$finished->();
			}
			
			return 1;
		}
		
		# for albums where we have different track artwork, use the first track's cover as the album artwork
		my $sth_get_album_art = $dbh->prepare( qq{
			SELECT tracks.coverid
			FROM   tracks
			WHERE  tracks.album = ?
			AND    tracks.coverid IS NOT NULL
			ORDER BY tracks.disc, tracks.tracknum
			LIMIT 1
	 	});
	 	
	 	$i = 0;

		while ( my ($albumId, $trackCount) = each %artCount ) {
			
			next unless $trackCount > 1;

			$sth_get_album_art->execute($albumId);
			my ($coverId) = $sth_get_album_art->fetchrow_array;
			
			$sth_update_albums->execute( $coverId, $albumId ) if $coverId;
			
		}

		%artCount = ();
		
		$progress->final;
		
		$log->error( "precacheArtwork finished in " . $progress->duration );
		
		$cb && $cb->();
		
		return 0;
	};
	
	if ( main::SCANNER ) {
		# Non-async mode in scanner
		while ( $work->() ) { }
		
		Slim::Music::Import->endImporter('precacheArtwork');
	}
	else {
		# Run async in main process
		Slim::Utils::Scheduler::add_ordered_task($work);
	}	
}

sub getResizeSpecs {
	my @specs = (
		'64x64_m',	# Fab4 10'-UI Album list
		'41x41_m',	# Jive/Baby Album list
		'40x40_m',	# Fab4 Album list
	);

	if (!Slim::Utils::OSDetect::isSqueezeOS()) {
		my $thumbSize = $prefs->get('thumbSize') || 100;
		
		push(@specs, 
			"${thumbSize}x${thumbSize}_o", # Web UI large thumbnails
			'75x75_p',  # iPeng, Controller App (high-res displays) 
			'50x50_o',	# Web UI small thumbnails, Controller App (low-res display)
		);
		
		if ( my $customSpecs = $prefs->get('customArtSpecs') ) {
			main::DEBUGLOG && $log->is_debug && $log->debug("Adding custom artwork resizing specs:\n" . Data::Dump::dump($customSpecs));
			push @specs, keys %$customSpecs;
		} 

		# sort by size, so we can batch convert
		@specs = sort {
			my ($sizeA) = $a =~ /^(\d+)/;
			my ($sizeB) = $b =~ /^(\d+)/;
			$b <=> $a;
		# XXX - this is duplicated from Slim::Web::Graphics->parseSpec, which is not loaded in scanner mode
		} grep {
			/^(?:([0-9X]+)x([0-9X]+))?(?:_(\w))?(?:_([\da-fA-F]+))?(?:\.(\w+))?$/
		# remove duplicates
		} keys %{{
			map {$_ => 1} @specs
		}};

		main::DEBUGLOG && $log->is_debug && $log->debug("Full list of artwork pre-cache specs:\n" . Data::Dump::dump(@specs));
	}
	
	return @specs;
}

=pod We don't have an artwork provider for this feature.

sub downloadArtwork {
	my $class = shift;
	my $cb    = shift; # optional callback when done (main process async mode)
	
	# don't try to run this in embedded mode
	if ( !$prefs->get('downloadArtwork') ) {
		$cb && $cb->();
		return;
	}
	
	# Artwork requires an SN account
	if ( !$prefs->get('sn_email') && !Slim::Utils::OSDetect::isSqueezeOS() ) {
		$importlog->warn( "Automatic artwork download requires a SqueezeNetwork account" );
		Slim::Music::Import->endImporter('downloadArtwork');
		$cb && $cb->();
		return;
	}
	
	# Find distinct albums to check for artwork.
	my $tracks = Slim::Schema->search('Track', {
		'me.audio'   => 1,
		'me.coverid' => { '='  => undef },
	}, {
		'join'     => 'album',
	});

	my $dbh = Slim::Schema->dbh;

	my $sth_update_tracks = $dbh->prepare( qq{
	    UPDATE tracks
	    SET    cover = ?, coverid = ?
	    WHERE  album = ?
	} );
	
	my $sth_update_albums = $dbh->prepare( qq{
		UPDATE albums
		SET    artwork = ?
		WHERE  id = ?
	} );
	
	my $progress = undef;
	my $count    = $tracks->count;

	if ($count) {
		$progress = Slim::Utils::Progress->new({ 
			'type'  => 'importer',
			'name'  => 'downloadArtwork',
			'total' => $count,
			'bar'   => 1
		});
	}

	$importlog->error("Starting downloadArtwork for $count tracks");

	# don't load these modules unless we get here, as they're pulling in a lot of dependencies
	require Slim::Networking::SqueezeNetwork;

	if ( main::SCANNER ) {
		require LWP::UserAgent;
		require HTTP::Headers;
	}
	else {
		require Slim::Networking::SimpleAsyncHTTP;
		require Slim::Utils::Network;
	}

	# Add an auth header
	my $authHeader = Slim::Networking::SqueezeNetwork->getAuthHeaders();

	my $cacheDir = catdir( $prefs->get('librarycachedir'), 'DownloadedArtwork' );
	mkpath $cacheDir if !-d $cacheDir;
	
	my $ua;
	
	if ( main::SCANNER ) {
		$ua = LWP::UserAgent->new(
			agent   => 'Logitech Media Server/' . $::VERSION,
			timeout => 10,
		);
		$ua->default_header($authHeader->[0] => $authHeader->[1]);
	}

	while ( _downloadArtwork({
		headers           => $authHeader,
		snUrl             => Slim::Networking::SqueezeNetwork->url( '/api/artwork/search' ),
		tracks            => $tracks,
		count             => $count,
		progress          => $progress,
		sth_update_tracks => $sth_update_tracks,
		sth_update_albums => $sth_update_albums, 
		cacheDir          => $cacheDir,
		cb                => $cb,
		ua                => $ua,
	}) ) {}
}

my $serverDown = 0;
sub _downloadArtwork {
	my $params = shift;

	if ( $serverDown < MAX_RETRIES ) {

		my $isInfo  = main::INFOLOG && $importlog->is_info;
		my $isDebug = main::DEBUGLOG && $importlog->is_debug;

		my ($artist, $done);
	
		# try other contributors of previous track
		if ( $artist = delete $lastFile{meta}->{contributors} ) {
			$lastFile{meta}->{title} = $lastFile{meta}->{albumname} . '/' . $artist;
		}
		
		# get next track from db
		elsif ( my $track = $params->{tracks}->next ) {
			
			my $albumname = $track->album->name;
			my $albumid   = $track->album->id;
			
			# Skip if we have already looked for this album before with no results
			if ( $lastFile{ "failed_$albumid" } ) {
				$isDebug && $importlog->debug( "Skipping $albumname, previous search failed" );
			} 
			
			# Only lookup albums that have artist names
			elsif ( $track->album->contributor && !$lastFile{ $albumid } ) {

				# let's join all contributors together, in case the album artist doesn't match (eg. compilations)
				my @artists;
				foreach ($track->album->contributors) {
					push @artists, $_->name;
				}
				
				# last.fm stores compilations under the non-localized "Various Artists" artist
				if ($track->album->compilation) {
					push @artists, 'Various Artists';
				}

				my $trackartists = join(',', @artists);
				$artist = $track->album->contributor->name;

				$lastFile{meta} = {
					albumname  => $albumname,
					albumid    => $albumid,
					album_mbid => $track->album->musicbrainz_id,
					title      => "$albumname/$artist",
					track      => $track,
				};
				
				# we'll not only try the album artist, but track artists too
				# iTunes tends to oddly flag albums as compilations when they're not
				# store contributors in params hash for later use
				if ( lc($trackartists) ne lc($artist) ) {
					$lastFile{meta}->{contributors} = $trackartists;
				}
			}

			# update the progress status unless we give this track another try with a different contributor
			if ( $params->{progress} ) {
				$params->{progress}->update( $albumname );
			}
		}
		
		# nothing left to do
		else {
			$done = 1;
		}

		my $args = '?album=' . URI::Escape::uri_escape_utf8( $lastFile{meta}->{albumname} || '' )
			. '&artist=' . URI::Escape::uri_escape_utf8( $artist || '' )
			. '&mbid=' . ( $lastFile{meta}->{album_mbid} || '' );
	
		my $base = catfile( $params->{cacheDir}, Digest::SHA1::sha1_hex($args) );
	
		# if we're done or have failed on that combination before, skip it
		if ( $done || $lastFile{ "failed_" . $lastFile{meta}->{albumid} } || $lastFile{ "failed_$base" } || $lastFile{ $lastFile{meta}->{albumid} } ) {
			# nothing really to do here... 
		}
		
		# check whether we already have cached artwork from earlier lookup
		elsif ( my $file = _getCoverFromFileCache( $base ) ) {
			 if ($isDebug) {
			 	 $importlog->debug( "Artwork for $lastFile{meta}->{title} found in cache:" );
			 	 $importlog->debug( $file );
			 }
			_setCoverArt( $file, $params );
		}
		
		# get artwork from mysb.com
		else {

			$isInfo && $importlog->info("Trying to get artwork for $lastFile{meta}->{title} from mysqueezebox.com");

			my $file = catfile($base) . '.tmp';
			my $url  = $params->{snUrl} . $args;

			# we're going to use sync downloads in the scanner
			if ( main::SCANNER ) {
				my $res = $params->{ua}->get( $url, ':content_file' => $file );
				
				_gotArtwork({
					params => {
						%$params,
						saveAs => $file,
					},
					error  => $res->code != 200 ? $res->code . ' ' . $res->message : undef,
					ct     => $res->content_type,
				})
			}
			
			# use async downloads when running in-process
			else {
				my $http = Slim::Networking::SimpleAsyncHTTP->new(
					\&_gotArtwork,
					\&_gotArtwork,
					{
						%$params,
						saveAs   => $file,
						timeout  => 10,
					}
				);
			
				$http->get( $url, @{ $params->{headers} } );

				return;
			}
		}


		# if we're running in the standalone scanner, return true value
		if ( main::SCANNER && !$done ) {
			return 1;
		}
		# didn't need to download artwork - call ourselves for the next lookup
		elsif (!$done) {
			_downloadArtwork($params);			
			return;
		}
	}

	if ( my $progress = $params->{progress} ) {
		$progress->final($params->{count}) ;
	
		if ($serverDown >= MAX_RETRIES) {
			$importlog->error( "downloadArtwork aborted after repeated failure connecting to mysqueezebox.com " . $progress->duration );
		}
		else {
			$importlog->error( "downloadArtwork finished in " . $progress->duration );
		}
	}

	Slim::Music::Import->endImporter('downloadArtwork');

	$serverDown = 0;
	%lastFile = ();
	if ( my $cb = $params->{cb} ) {
		$cb->();
	}
	
	return 0;
}

sub _gotArtwork {
	my $http = shift;
	
	my ($params, $ct, $error);
	
	# SimpleAsyncHTTP will return an object
	if ( blessed($http) ) {
		$params = $http->params;
		$ct     = $http->headers() && $http->headers()->content_type;
		$error  = $http->error;
	}
	else {
		$params = $http->{params};
		$ct     = $http->{ct};
		$error  = $http->{error};
	}
	
	my $base = $params->{saveAs};
	$base =~ s/\.tmp$//i;

	if ( !$error && $ct =~ m{image/(jpe?g|gif|png)$} && -f $params->{saveAs} ) {
		# move artwork file to sub-folder 
		my $file = catfile( $base, "cover.$1" );
		mkdir $base;
		rename $params->{saveAs}, $file;

		if (main::DEBUGLOG && $importlog->is_debug) {
			$importlog->debug( "Successfully downloaded artwork for $lastFile{meta}->{title}" );
			$importlog->debug( "Cached as $file" );
		} 
		$serverDown = 0;
		delete $lastFile{meta}->{contributor};
		
		_setCoverArt( $file, $params );
	}
	elsif ( !$error ) {
		
		# sometimes the error message is the response's content
		if ( $ct eq 'text/plain' && -f $params->{saveAs} ) {
			$error = eval { read_file($params->{saveAs}) };
		}

		$error ||= "Invalid file type $ct, or file not found: $params->{saveAs}";

	}

	if ( $error ) {
		# 50x - server problem, 403 - authentication required
		if ( $error =~ /^(:5|403|connect timed out)/i ) {
			$serverDown++;
		}
		else {
			$serverDown = 0;
		}

		$importlog->error( "Failed to download artwork for $lastFile{meta}->{title}: " . $error );
		$lastFile{ "failed_$base" } = 1;
	}	
	
	# remove left-overs
	unlink $params->{saveAs};
	delete $params->{saveAs};
	
	# we're in async mode - call ourselves
	if ( !main::SCANNER ) {
		_downloadArtwork($params);
	}
}

sub _setCoverArt {
	my ( $file, $params ) = @_;
	
	my $track     = $lastFile{meta}->{track};
	my $progress  = $params->{progress};
	my $albumid   = $lastFile{meta}->{albumid};
	
	if ( $file && -e $file ) {
		my $coverid = $track->generateCoverId({
			cover => $file,
			url   => $track->url,
			mtime => $track->timestamp,
			size  => $track->filesize,
		});
		
		my $c = $params->{sth_update_tracks}->execute( $file, $coverid, $albumid );
		$params->{sth_update_albums}->execute( $coverid, $albumid );

		# if the track update returned a number, we'll increase progress by this value
		if ( $c && $progress ) {
			$progress->update( $lastFile{meta}->{title}, $progress->done() + $c - 1 );
		}

		$lastFile{ $albumid } = 1;
		
		# don't look up alternative artist for track if one has been found
		delete $lastFile{meta}->{contributors};
	}
	
	else {
		$importlog->warn( "Failed to download artwork for $lastFile{meta}->{title}" );
		
		$lastFile{ "failed_$albumid" } = 1;
	}
}

sub _getCoverFromFileCache {
	my $base = shift;
	
	opendir(DIR, $base) || return;
	
	my @f = grep /cover\.(?:jpe?g|png|gif)$/i, readdir(DIR);

	return catdir($base, $f[0]) if @f;
}
=cut

1;
