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

sub updateStandaloneArtwork {
	my $class = shift;
	my $cb    = shift; # optional callback when done (main process async mode)
	
	my $dbh = Slim::Schema->dbh;
		
	# Find all tracks with un-cached artwork:
	# * All distinct cover values where cover isn't 0 and cover_cached is null
	# * Tracks share the same cover art when the cover field is the same
	#   (same path or same embedded art length).
	my $sql = qq{
		SELECT
			tracks.id,
			tracks.url,
			tracks.cover,
			tracks.coverid,
			albums.id AS albumid,
			albums.title AS album_title,
			albums.artwork AS album_artwork
		FROM  tracks
		JOIN  albums ON (tracks.album = albums.id)
		WHERE tracks.cover LIKE '%jpg' OR tracks.cover LIKE '%jpeg' OR tracks.cover LIKE '%png' OR tracks.cover LIKE '%gif' OR tracks.coverid IS NULL
		GROUP BY tracks.cover, tracks.album
 	};

	my $sth_update_tracks = $dbh->prepare( qq{
	    UPDATE tracks
	    SET    cover = ?, coverid = ?, cover_cached = NULL
	    WHERE  album = ?
	} );
	
	my $sth_update_albums = $dbh->prepare( qq{
		UPDATE albums
		SET    artwork = ?
		WHERE  id = ?
	} );

	my ($count) = $dbh->selectrow_array( qq{
		SELECT COUNT(*) FROM ( $sql ) AS t1
	} );
	
	$log->error("Starting updateStandaloneArtwork for $count albums");
	
	if ( !$count ) {
		$cb && $cb->();
		main::SCANNER && Slim::Music::Import->endImporter('updateStandaloneArtwork');
		return;
	}

	my $progress = Slim::Utils::Progress->new( { 
		type  => 'importer',
		name  => 'updateStandaloneArtwork',
		total => $count, 
		bar   => 1,
	} );
	
	my $sth = $dbh->prepare($sql);
	$sth->execute;
	
	my ($trackid, $url, $cover, $coverid, $albumid, $album_title, $album_artwork);
	$sth->bind_columns(\$trackid, \$url, \$cover, \$coverid, \$albumid, \$album_title, \$album_artwork);
	
	my $i = 0;
	my $t = 0;
	
	my $work = sub {
		if ( $sth->fetch ) {
			my $newCoverId;
			
			$progress->update( $album_title );
			
			if ( $t < time ) {
				Slim::Schema->forceCommit;
				$t = time + 5;
			}

			# check for updated artwork
			if ( $cover ) {
				$newCoverId = Slim::Schema::Track->generateCoverId({
					cover => $cover,
					url   => $url,
				});
			}
			
			# check for new artwork to unchanged file
			# - !$cover: there wasn't any previously
			# - !$newCoverId: existing file has disappeared
			if ( !$cover || !$newCoverId ) {
				# store properties in a hash
				my $track = Slim::Schema->find('Track', $trackid);
				
				if ($track) {
					my %columnValueHash = map { $_ => $track->$_() } keys %{$track->attributes};
					$columnValueHash{primary_artist} = $columnValueHash{primary_artist}->id if $columnValueHash{primary_artist};

					my $newCover = Slim::Music::Artwork->findStandaloneArtwork(
						\%columnValueHash,
						{}, 
						Slim::Utils::Misc::fileURLFromPath(
							dirname(Slim::Utils::Misc::pathFromFileURL($url))
						),
					);
					
					if ($newCover) {
						$cover = $newCover;

						$newCoverId = Slim::Schema::Track->generateCoverId({
							cover => $newCover,
							url   => $url,
						});
					}
				}
			}
			
			if ( $newCoverId && ($coverid || '') ne $newCoverId ) {
				# Make sure album.artwork points to this track, as it may not
				# be pointing there now because we did not join tracks via the
				# artwork column.
				if ( ($album_artwork || '') ne $newCoverId ) {
					$sth_update_albums->execute( $newCoverId, $albumid );
				}
	
				# Update the rest of the tracks on this album
				# to use the same coverid and cover_cached status
				$sth_update_tracks->execute( $cover, $newCoverId, $albumid );

				if ( ++$i % 50 == 0 ) {
					Slim::Schema->forceCommit;
					$t = time + 5;
				}
				
				Slim::Utils::Scheduler::unpause() if !main::SCANNER;
			}
			# cover art has disappeared
			elsif ( !$newCoverId ) {
				$sth_update_albums->execute( undef, $albumid );
				$sth_update_tracks->execute( 0, undef, $albumid );

				$log->warn('Artwork has been removed for ' . $album_title);
			}
			
			return 1;
		}
		
		$progress->final;
		
		$log->error( "updateStandaloneArtwork finished in " . $progress->duration );
		
		$cb && $cb->();
		
		return 0;
	};
	
	if ( main::SCANNER ) {
		# Non-async mode in scanner
		while ( $work->() ) { }
		
		Slim::Music::Import->endImporter('updateStandaloneArtwork');
	}
	else {
		# Run async in main process
		Slim::Utils::Scheduler::add_ordered_task($work);
	}	
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

	if ( !defined $body ) {
		logBacktrace("Can't discover content type for undefined data.") if main::DEBUGLOG && $log->is_debug;
	}

	# iTunes sometimes puts PNG images in and says they are jpeg
	elsif ($$body =~ /^\x89PNG\x0d\x0a\x1a\x0a/) {

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

		# wipe internal cache
		%findArtCache = ();		
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
		my $sth_get_album_art = $dbh->prepare_cached( qq{
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

		$sth_get_album_art->finish;

		# wipe internal cache
		%findArtCache = ();		
		
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

1;
