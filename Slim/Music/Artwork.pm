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
use Path::Class;
use Scalar::Util qw(blessed);
use Tie::Cache::LRU;

use Slim::Formats;
use Slim::Music::Import;
use Slim::Music::Info;
use Slim::Music::TitleFormatter;
use Slim::Utils::Cache;
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
			my $files = File::Next::files( {
				file_filter    => sub { $_ =~ /\.(?:jpe?g|png|gif)$/i },
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

# XXX remove after BMF is moved to use Scanner::Local
sub findArtwork {
	my $class = shift;
	my $track = shift;
	
	my $isDebug = $importlog->is_debug;

	# Only look for track/album combos that don't already have artwork.
	my $cond = {
		'me.audio'      => 1,
		'me.timestamp'  => { '>=' => Slim::Music::Import->lastScanTime },
		'album.artwork' => { '='  => undef },
	};

	my $attr = {
		'join'     => 'album',
		'group_by' => 'album',
		'prefetch' => 'album',
	};

	# If the user passed in a track (dir) object, match on that base directory.
	if (blessed($track) && $track->content_type eq 'dir') {

		$cond->{'me.url'} = { 'like' => sprintf('%s%%', $track->url) };

	} elsif (blessed($track) && $track->audio) {

		$cond->{'me.url'} = { 'like' => sprintf('%s%%', dirname($track->url)) };
	}

	# Find distinct albums to check for artwork.
	my $tracks = Slim::Schema->search('Track', $cond, $attr);

	my $progress = undef;
	my $count    = $tracks->count;

	if ($count) {
		$progress = Slim::Utils::Progress->new({ 
			'type' => 'importer', 'name' => 'artwork', 'total' => $count, 'bar' => 1
		});
	}

	while (my $track = $tracks->next) {
		my $album = $track->album;
		
		main::DEBUGLOG && !$main::progress && $isDebug && $importlog->debug( "Looking for cover file for " . $album->title );

		if ($track->coverArtExists) {
			$album->artwork($track->coverid);
			$album->update;
			
			main::DEBUGLOG && !$main::progress && $isDebug && $importlog->debug( "Using cover from " . $track->cover );
		}

		$progress->update( $album->title );
	}

	$progress->final($count) if $count;

	Slim::Music::Import->endImporter('findArtwork');
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
	
	my $isDebug = $importlog->is_debug;
	
	my $cache = Slim::Utils::Cache->new('Artwork', 1, 1);
	
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

	if ( $count ) {
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
		
		my $isEnabled = $prefs->get('precacheArtwork');
		my $thumbSize = $prefs->get('thumbSize') || 100;

		my @specs = (
			"${thumbSize}x${thumbSize}_o",
			'64x64_m',
			'50x50_o',
			'41x41_m',
			'40x40_m',
		);
		
		if ($isEnabled) {
			require Slim::Utils::ImageResizer;
		}
		
		my $sth = $dbh->prepare($sql);
		$sth->execute;
		
		my $i = 0;
		while ( my $track = $sth->fetchrow_hashref ) {
			# Make sure album.artwork points to this track, as it may not
			# be pointing there now because we did not join tracks via the
			# artwork column.
			if ( $track->{album_artwork} && $track->{album_artwork} ne $track->{coverid} ) {
				$sth_update_albums->execute( $track->{coverid}, $track->{albumid} );
			}
				
			# Do the actual pre-caching only if the pref for it is enabled
			if ( $isEnabled ) {
						
				# Image to resize is either a cover path or the audio file
				my $path = $track->{cover} =~ /^\d+$/
					? Slim::Utils::Misc::pathFromFileURL( $track->{url} )
					: $track->{cover};
				
				main::DEBUGLOG && $isDebug && $importlog->debug( "Pre-caching artwork for " . $track->{album_title} . " from $path" );
				
				if ( Slim::Utils::ImageResizer->resize($path, 'music/' . $track->{coverid} . '/cover_', join(',', @specs), undef) ) {				
					# Update the rest of the tracks on this album
					# to use the same coverid and cover_cached status
					$sth_update_tracks->execute( $track->{coverid}, $track->{albumid}, $track->{cover} );
				}
			}
			
			$progress->update( $track->{album_title} );
			
			if (++$i % 50 == 0) {
				Slim::Schema->forceCommit;
			}
		}
		
		$sth->finish;

		$progress->final($count);
	}

	Slim::Music::Import->endImporter('precacheArtwork');
}

1;
