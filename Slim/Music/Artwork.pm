package Slim::Music::Artwork;

# $Id$

# Squeezebox Server Copyright 2001-2009 Logitech.
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

# Global caches:
my $artworkDir = '';
my $log        = logger('artwork');
my $importlog  = logger('scan.import');

my $prefs = preferences('server');

tie my %lastFile, 'Tie::Cache::LRU', 32;

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

	if ( !defined $art ) {
		my $parentDir = Path::Class::dir( Slim::Utils::Misc::pathFromFileURL($dirurl) );
		
		# coverArt/artfolder pref support
		if ( my $coverFormat = $prefs->get('coverArt') ) {
			# If the user has specified a pattern to match the artwork on, we need
			# to generate that pattern. This is nasty.
			if ( $coverFormat && $coverFormat =~ /^%(.*?)(\..*?){0,1}$/ ) {
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

					my $artPath = $parentDir->file($coverFormat)->stringify;
					
					if ( my $artDir = $prefs->get('artfolder') ) {
						$artDir  = Path::Class::dir($artDir);
						$artPath = $artDir->file($coverFormat)->stringify;
					}
					
					if ( -e $artPath ) {
						main::INFOLOG && $isInfo && $log->info("Found variable cover $coverFormat from $1");
						$art = $artPath;
					}
					else {
						main::INFOLOG && $isInfo && $log->info("No variable cover $coverFormat found from $1");
					}
				}
				else {
				 	main::INFOLOG && $isInfo && $log->info("No variable cover match for $1");
				}
			}
			elsif ( defined $coverFormat ) {
				push @files, $coverFormat;
			}
		}
		
		if ( !$art ) {
			# Find all image files in the file directory
			my $types = qr/\.(?:jpe?g|png|gif)$/i;
			
			my $files = File::Next::files( {
				file_filter    => sub { Slim::Utils::Misc::fileFilter($File::Next::dir, $_, $types) },
				descend_filter => sub { 0 },
			}, $parentDir );
	
			my @found;
			while ( my $image = $files->() ) {
				push @found, $image;
			}
			
			# Prefer cover/folder/album/thumb, then just take the first image
			my $filelist = join( '|', @files );
			if ( my @preferred = grep { basename($_) =~ qr/^(?:$filelist)/i } @found ) {
				$art = $preferred[0];
			}
			else {
				$art = $found[0] || 0;
			}
		}
	
		# Cache found artwork for this directory to speed up later tracks
		%findArtCache = () if scalar keys %findArtCache > 32;
		$findArtCache{$dirurl} = $art;
	}
	
	main::INFOLOG && $isInfo && $log->info("Using $art");
	
	return $art || 0;
}

sub getImageContentAndType {
	my $class = shift;
	my $path  = shift;

	# Bug 3245 - for systems who's locale is not UTF-8 - turn our UTF-8
	# path into the current locale.
	my $locale = Slim::Utils::Unicode::currentLocale();

	if ($locale ne 'utf8' && !-e $path) {
		$path = Slim::Utils::Unicode::encode($locale, $path);
	}

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

	my $isInfo = $log->is_info;

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
	
	my $isInfo = $log->is_info;

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
	
	my $isDebug = $importlog->is_debug;
	
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
		AND    tracks.cover_cached IS NULL
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
		if (Slim::Utils::OSDetect::isSqueezeOS()) {
			@specs = (
				'75x75_p',  # iPeng
				'64x64_m',	# Fab4 10'-UI Album list
				'41x41_m',	# Jive/Baby Album list
				'40x40_m',	# Fab4 Album list
			);
		} else {
			my $thumbSize = $prefs->get('thumbSize') || 100;
			@specs = (
				"${thumbSize}x${thumbSize}_o", # Web UI large thumbnails
				'75x75_p',	# iPeng
				'64x64_m',	# Fab4 10'-UI Album list
				'50x50_o',	# Web UI small thumbnails
				'41x41_m',	# Jive/Baby Album list
				'40x40_m',	# Fab4 Album list
			);
		}
		
		require Slim::Utils::ImageResizer;
	}
	
	my $sth = $dbh->prepare($sql);
	$sth->execute;
	
	my ($url, $cover, $coverid, $albumid, $album_title, $album_artwork);
	$sth->bind_columns(\$url, \$cover, \$coverid, \$albumid, \$album_title, \$album_artwork);
	
	my $i = 0;
	
	my $work = sub {
		if ( $sth->fetch ) {
			# Make sure album.artwork points to this track, as it may not
			# be pointing there now because we did not join tracks via the
			# artwork column.
			if ( $album_artwork && $album_artwork ne $coverid ) {
				$sth_update_albums->execute( $coverid, $albumid );
			}
			
			# Do the actual pre-caching only if the pref for it is enabled
			if ( $isEnabled ) {
					
				# Image to resize is either a cover path or the audio file
				my $path = $cover =~ /^\d+$/
					? Slim::Utils::Misc::pathFromFileURL($url)
					: $cover;
			
				main::DEBUGLOG && $isDebug && $importlog->debug( "Pre-caching artwork for " . $album_title . " from $path" );
			
				if ( Slim::Utils::ImageResizer->resize($path, "music/$coverid/cover_", join(',', @specs), undef) ) {				
					# Update the rest of the tracks on this album
					# to use the same coverid and cover_cached status
					$sth_update_tracks->execute( $coverid, $albumid, $cover );
				}
			}
		
			$progress->update( $album_title );
		
			if ( ++$i % 50 == 0 ) {
				Slim::Schema->forceCommit;
			}
			
			return 1;
		}
		
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

sub downloadArtwork {
	my $class = shift;
	
	# don't try to run this in embedded mode
	return unless $prefs->get('downloadArtwork');

	# Artwork requires an SN account
	if ( !$prefs->get('sn_email') ) {
		$importlog->warn( "Automatic artwork download requires a SqueezeNetwork account" );
		Slim::Music::Import->endImporter('downloadArtwork');
		return;
	}

	# don't load these modules unless we get here, as they're pulling in a lot of dependencies
	require Slim::Networking::SqueezeNetwork;
	require Digest::SHA1;
	require LWP::UserAgent;
	
	# Find distinct albums to check for artwork.
	my $tracks = Slim::Schema->search('Track', {
		'me.audio'   => 1,
		'me.coverid' => { '='  => undef },
	}, {
		'join'     => 'album',
	});
	
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
	
	# Agent for talking to SN
	my $ua = LWP::UserAgent->new(
		agent   => 'Squeezebox Server/' . $::VERSION,
		timeout => 30,
	);
	
	# Add an auth header
	my $email = $prefs->get('sn_email');
	my $pass  = $prefs->get('sn_password_sha');
	$ua->default_header( sn_auth => $email . ':' . Digest::SHA1::sha1_base64( $email . $pass ) );
	
	my $snURL = Slim::Networking::SqueezeNetwork->url( '/api/artwork/search' );
	
	my $cacheDir = catdir( $prefs->get('cachedir'), 'DownloadedArtwork' );
	mkpath $cacheDir if !-d $cacheDir;
	
	tie my %cache, 'Tie::Cache::LRU', 128;
	
	while ( my $track = $tracks->next ) {

		my $albumname = $track->album->name;
		$progress->update( $albumname );
		
		# Only lookup albums that have artist names
		if ( $track->album->contributor ) {

			my $file;
			my $albumid   = $track->album->id;
			my $album_mbid= $track->album->musicbrainz_id;
			
			# Skip if we have already looked for this album before with no results
			if ( $cache{ "artwork_download_failed_$albumid" } ) {
				main::DEBUGLOG && $importlog->is_debug &&	$importlog->debug( "Skipping $albumname, previous search failed" );
				next;
			} 

			# let's join all contributors together, in case the album artist doesn't match (eg. compilations)
			my @artists;
			foreach ($track->album->contributors) {
				push @artists, $_->name;
			}
			
			# last.fm stores compilations under the non-localized "Various Artists" artist
			if ($track->album->compilation) {
				push @artists, 'Various Artists';
			}

			# we'll not only try the album artist, but track artists too
			# iTunes tends to oddly flag albums as compilations when they're not
			foreach my $contributor ( $track->album->contributor->name, join(',', @artists) ) {
				
				my $url = $snURL
					. '?album=' . URI::Escape::uri_escape_utf8( $albumname )
					. '&artist=' . URI::Escape::uri_escape_utf8( $contributor )
					. '&mbid=' . $album_mbid;

				$file = $cache{$url};
				my $res;
					
				if ( $file && -e $file ) {
					main::DEBUGLOG && $importlog->is_debug && $importlog->debug( "Artwork for $albumname/$contributor already downloaded: $file" );
					last;
				}
				else {
		
					main::DEBUGLOG && $importlog->is_debug && $importlog->debug("Trying to get artwork for $albumname/$contributor from mysqueezebox.com");
					
					$res = $ua->get($url);
	
					if ( $res->is_success ) {
						# Save the artwork to a cache file
						my ($ext) = $res->content_type =~ m{image/(jpe?g|gif|png)$};
						$file = catfile( $cacheDir, $albumid ) . ".$ext";
		
						if ( $ext && write_file( $file, { binmode => ':raw' }, $res->content ) ) {
							$cache{$url} = $file;
							main::DEBUGLOG && $importlog->is_debug && $importlog->debug( "Downloaded artwork for $albumname" );
							last;
						}
					}
				}
			
			}
			
			if ( -e $file ) {
				$track->cover( $file );
				$track->update;

				$track->coverid( $track->generateCoverId({
					cover => $file,
					url   => $track->url,
					mtime => $track->timestamp,
					size  => $track->filesize,
				}) );
				$track->update;

				if (!$track->album->artwork) {
					$track->album->artwork( $track->coverid );
					$track->album->update;
				}
			}
			
			else {
				main::DEBUGLOG && $importlog->is_debug && $importlog->debug( "Failed to download artwork for $albumname" );
				
				$cache{"artwork_download_failed_$albumid"} = 1;
			}
			
			# Don't hammer the artwork server
#			sleep 1;
		}
	}

	$progress->final($count) if $count;

	Slim::Music::Import->endImporter('downloadArtwork');
}

sub wipeDownloadedArtwork {
	my $class = shift;
	
	main::DEBUGLOG && $importlog->is_debug && $importlog->debug('Wiping artwork download folder');
	
	my $cacheDir = catdir( $prefs->get('cachedir'), 'DownloadedArtwork' );
	rmtree $cacheDir if -d $cacheDir;
}

1;
