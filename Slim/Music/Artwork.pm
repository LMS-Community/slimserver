package Slim::Music::Artwork;


# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024-2026 Lyrion Community.
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
use File::Spec::Functions qw(catdir canonpath splitdir);
use List::Util qw(min);
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

my $imgProxyCache;

tie my %lastFile, 'Tie::Cache::LRU', 128;

# Small cache of path -> cover.jpg mapping to speed up
# scans of files in the same directory
# Don't use Tie::Cache::LRU as it is a bit too expensive in the scanner
my %findArtCache;

# Public class methods
sub findStandaloneArtwork {
	# PR https://github.com/LMS-Community/slimserver/pull/1536
	# new parameter $commonParent flag introduced. If this is passed $dirurl should be the parent directory and we don't need
	# to have received anything in $trackAttributes or $deferredAttributes as track-based variable cover art format is bypassed.

	my ( $class, $trackAttributes, $deferredAttributes, $dirurl, $commonParent, $trackid, $trackDisc ) = @_;

	my $discNumber = $trackAttributes->{disc} || $trackDisc;

	return 0 if !Slim::Music::Info::isFileURL($dirurl);

	my $isInfo = main::INFOLOG && $log->is_info;

	my $discCacheKey = $dirurl;
	$discCacheKey .= "|disc:$discNumber" if $discNumber;
	my $art = $findArtCache{$discCacheKey};

	if ( !defined $art ) {

		my $dbh = Slim::Schema->dbh;
		my $image_sth = $dbh->prepare("SELECT name FROM scanned_pics WHERE directory = ?");
		my $parentDir = Path::Class::dir( Slim::Utils::Misc::pathFromFileURL($dirurl) );

		# Files to look for
		my @files = ( _discSpecificArtworkNames($discNumber||0), qw(cover folder album thumb) );

		# User-defined artwork format
		my $coverFormat = $prefs->get('coverArt');

		# coverArt/artfolder pref support

		# if called with the commonParent parameter we only accept a hardcoded user pref.
		if ($commonParent && $coverFormat && $coverFormat !~ /^%/) {
			push @files, $coverFormat;
		}
		elsif ( !$commonParent && $coverFormat ) {
			# If the user has specified a pattern to match the artwork on, we need
			# to generate that pattern. This is nasty.
			if ( $coverFormat =~ /^%(.*?)(\..*?){0,1}$/ ) {
				my $suffix = $2 ? $2 : '.jpg';

				# Merge attributes to use with TitleFormatter
				# XXX This may break for some people as it's not using a Track object anymore
				my $meta = { %{$trackAttributes}, %{$deferredAttributes} };

				if ( keys %$meta == 0 && $trackid ) {

					my @cols = map { "tracks.$_" } keys %{Slim::Schema::Track->attributes};
					push @cols, ( "albums.title", "albums.titlesort", "albums.discc", "works.title");
					my $cols = join(', ', @cols);

					my $meta_sth = $dbh->prepare( qq{
						SELECT $cols
						FROM tracks
						JOIN albums ON albums.id = tracks.album
						LEFT JOIN works ON tracks.work = works.id
						WHERE tracks.id = ?
						} );
					$meta_sth->execute($trackid);
					my @data = $meta_sth->fetchrow_array;

					@$meta{@cols} = @data;
					$meta->{"albumid"} = delete $meta->{"tracks.album"};
					$meta->{"workid"} = delete $meta->{"tracks.work"};

					if ( $1 =~ /ARTIST|COMPOSER|CONDUCTOR|BAND/ ) {
						$meta_sth = $dbh->prepare( qq{
						SELECT name, namesort, role
						FROM contributor_track
						JOIN contributors ON contributors.id = contributor_track.contributor
						WHERE contributor_track.track = ?
						} );
						$meta_sth->execute($trackid);
						my ($name, $namesort, $role);
						$meta_sth->bind_columns(\$name, \$namesort, \$role);
						while ( $meta_sth->fetch ) {
							my $rolename = Slim::Schema::Contributor->roleToType($role);
							push @{$meta->{$rolename}}, $name;
							push @{$meta->{${rolename}. "SORT"}}, $namesort;
						}
					}

					if ( $1 =~ /GENRE/ ) {
						$meta_sth = $dbh->prepare( qq{
						SELECT name
						FROM genre_track
						JOIN genres ON genres.id = genre_track.genre
						WHERE genre_track.track = ? LIMIT 1
						} );
						$meta_sth->execute($trackid);
						my ($name);
						$meta_sth->bind_columns(\$name);
						$meta_sth->fetch;
						$meta->{'genre'} = $name;
					}
				}

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

			my @found = map { $_->[0] } @{ $dbh->selectall_arrayref($image_sth, undef, $parentDir) };

			# Prefer cover/folder/album/thumb, then just take the first image
			my $filelist = join( '|', @files );
			if ( my @preferred = grep { basename($_) =~ qr/^(?:$filelist)\./i } @found ) {
				$art = $preferred[0];
			}
			else {
				# exclude disc-specific artwork (if we had wanted them, they'd have been picked up already, above)
				my @discSpecificNames = _discSpecificArtworkNames();
				my $excludedList = join( '|', @discSpecificNames );
				if ( my @preferred = grep { basename($_) !~ qr/^(?:$excludedList)\w+\./i } @found ) {
					$art = $preferred[0];
				}
				else {
					$art = $found[0] || 0;
				}
			}
		}

		# Cache found artwork for this directory to speed up later tracks
		# No caching if using a user-defined artwork format, the user may have multiple
		# files in a single directory with different artwork
		if ( !$coverFormat ) {
			%findArtCache = () if scalar keys %findArtCache > 32;
			$findArtCache{$discCacheKey} = $art;
		}
	}

	$isInfo && $log->info("Using $art");

	return $art || 0;
}

sub updateStandaloneArtwork {
	my $class = shift;
	my $cb    = shift; # optional callback when done (main process async mode)

	my $dbh = Slim::Schema->dbh;

	my $where = qq{
		tracks.cover LIKE '%jpg'
		OR tracks.cover LIKE '%jpeg'
		OR tracks.cover LIKE '%png'
		OR tracks.cover LIKE '%gif'
		OR tracks.cover LIKE 'http%'
		OR tracks.coverid IS NULL
	};

	# get singledir parameter from the scanner if available
	my $singledir = main::SCANNER ? $ARGV[-1] : undef;
	if ($singledir && $singledir eq 'onlinelibrary') {
		# shortcut for online library scan only - ignore local files
		$where = qq{
			tracks.url NOT LIKE 'file://%'
			AND tracks.cover LIKE 'http%'
			AND tracks.coverid IS NULL
		};
	}
	elsif ($singledir) {
		$singledir = Slim::Utils::Misc::fileURLFromPath(Slim::Utils::Unicode::encode_locale($singledir));
		$where = qq{
			tracks.url LIKE '$singledir%'
			AND ($where)
		};
	}

	# Find all tracks with un-cached internal artwork or external artwork:
	# * All distinct cover values where cover is an external image, or isn't 0 and cover_cached is null
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
			albums.discc AS disc_count,
			albums.artwork AS album_artwork,
			-- This is the Sqlite equivalent of dirname()
			RTRIM(tracks.url, REPLACE(tracks.url, '/', '')) AS dirname,
			tracks.disc
		FROM  tracks
		JOIN  albums ON (tracks.album = albums.id)
		WHERE $where
		GROUP BY tracks.cover, tracks.album, dirname, tracks.disc
		ORDER BY tracks.album, tracks.disc, dirname
	};

	my $sth_update_tracks = $dbh->prepare( qq{
	    UPDATE tracks
	    SET    cover = ?, coverid = ?, cover_cached = NULL
	    WHERE  album = ? AND url LIKE ? AND disc = ?
	} );

	my $sth_update_track_cover_cached_null = $dbh->prepare( qq{
	    UPDATE tracks
	    SET    cover_cached = NULL
	    WHERE  album = ?
	} );

	my ($count) = $dbh->selectrow_array( qq{
		SELECT COUNT(DISTINCT albumid) FROM ( $sql ) AS t1
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

	my ($trackid, $url, $cover, $coverid, $albumid, $album_title, $disc_count, $album_artwork, $dirname, $disc_number);
	$sth->bind_columns(\$trackid, \$url, \$cover, \$coverid, \$albumid, \$album_title, \$disc_count, \$album_artwork, \$dirname, \$disc_number);

	my $i = 0;
	my $t = 0;
	my $previousAlbum;
	my $prevAlbumArtwork;
	my @albumDirs;

	my $processAlbum = sub {
		if ( scalar @albumDirs ) {
			my $newAlbumCover = $prevAlbumArtwork; # assume it hasn't changed
			@albumDirs = Slim::Utils::Misc::uniq(@albumDirs);
			my $commonParent = _findCommonParent(\@albumDirs);

			if ( my $parentArtwork = Slim::Music::Artwork->findStandaloneArtwork({}, {}, Slim::Utils::Misc::fileURLFromPath($commonParent), 1) ) {
				my $parentUrl = Slim::Utils::Misc::fileURLFromPath($parentArtwork);
				$newAlbumCover = Slim::Music::Artwork->generateImageId({
					image => $parentArtwork,
					url   => $parentUrl,
				});
			}
			# parent artwork changed so make sure cache update is triggered
			if ( $newAlbumCover ne $prevAlbumArtwork )  {
				$sth_update_track_cover_cached_null->execute($previousAlbum);
			}
		}
	};

	my $work = sub {
		if ( $sth->fetch ) {

			my $newCoverId = undef;
			my $newCover = undef;
			my $urlDir  = dirname(Slim::Utils::Misc::pathFromFileURL($url)) if Slim::Music::Info::isFileURL($url);

			$progress->update( $album_title );

			if ( $t < time ) {
				Slim::Schema->forceCommit;
				$t = time + 5;
			}

			if ( $previousAlbum != $albumid ) {
				if ( $previousAlbum ) {
					$processAlbum->();
				}
				$prevAlbumArtwork = $album_artwork;
				$previousAlbum = $albumid;
				@albumDirs = ();
			}
			push @albumDirs, $urlDir;

			# check for updated artwork
			if ( $cover ) {
				$newCoverId = Slim::Music::Artwork->generateImageId({
					image => $cover,
					url   => Slim::Utils::Misc::fileURLFromPath($cover),
				});
				$newCover = $cover if $newCoverId;
			}

			# check for new artwork to unchanged file
			# - !$cover: there wasn't any previously
			# - !$newCoverId: existing file has disappeared

			if ( Slim::Music::Info::isFileURL($url) && (!$cover || !$newCoverId || $urlDir ne dirname($cover) || $disc_count > 1) ) {
				$newCover = Slim::Music::Artwork->findStandaloneArtwork(
					{},
					{},
					Slim::Utils::Misc::fileURLFromPath($urlDir),
					undef,
					$trackid,
					$disc_number,
				);

				if ($newCover && $newCover ne $cover) {
					$newCoverId = Slim::Music::Artwork->generateImageId({
						image => $newCover,
						url   => Slim::Utils::Misc::fileURLFromPath($newCover),
					});
				}
			}

			if ( $newCoverId && ($coverid || '') ne $newCoverId ) {
				# Make sure album.artwork points to this track, as it may not
				# be pointing there now because we did not join tracks via the
				# artwork column.
				$sth_update_tracks->execute( $newCover, $newCoverId, $albumid, $dirname . "%", $disc_number );

				if ( ++$i % 50 == 0 ) {
					Slim::Schema->forceCommit;
					$t = time + 5;
				}

				Slim::Utils::Scheduler::unpause() if !main::SCANNER;
			}
			elsif ( $cover =~ /^https?:/ && (!$album_artwork || $album_artwork ne $cover) ) {
				$sth_update_track_cover_cached_null->execute($albumid);

				if ( ++$i % 50 == 0 ) {
					Slim::Schema->forceCommit;
					$t = time + 5;
				}

				Slim::Utils::Scheduler::unpause() if !main::SCANNER;
			}
			# cover art has disappeared
			elsif ( $coverid && !$newCoverId ) {
				$sth_update_tracks->execute( 0, undef, $albumid, $dirname . "%", $disc_number );

				$log->warn('Artwork has been removed for ' . $album_title);
			}

			return 1;
		}

		$processAlbum->();

		$progress->final;

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


sub generateImageId {
	my ( $class, $args ) = @_;

	my $image = $args->{image} || '';
	my $imageId;
	my $mtime;
	my $size;

	if ( $image =~ /^https?/ ) {
		$mtime = $size = 1;
	}
	elsif ( $image =~ /^\d+$/ ) {
		# Cache is based on mtime/size of the file containing embedded art
		$mtime = $args->{mtime};
		$size  = $args->{size};
	}
	elsif ( -e $image ) {
		# Cache is based on mtime/size of artwork file
		($size, $mtime) = (stat _)[7, 9];
	}

	if ( $mtime && $size ) {
		$imageId = substr( safe_md5_hex( $args->{url} . $mtime . $size ), 0, 8 );
	}

	return $imageId;
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
	}
	. ($force ? '' : ' WHERE tracks.cover_cached IS NULL')
	. qq{
		GROUP BY tracks.cover, tracks.album
		ORDER BY tracks.album
 	};

	my $sth_update_tracks = $dbh->prepare( qq{
	    UPDATE tracks
	    SET    coverid = ?, cover_cached = 1
	    WHERE  album = ?
	    AND    (cover = ? OR cover LIKE 'http%')
	} );

	my $sth_update_tracks_with_parent = $dbh->prepare( qq{
	    UPDATE tracks
	    SET    cover = ?, coverid = ?, cover_cached = 1
	    WHERE  album = ?
	    AND    (cover = ? OR cover LIKE 'http%')
	} );

	my $sth_update_albums = $dbh->prepare( qq{
		UPDATE albums
		SET    artwork = ?
		WHERE  id = ?
	} );

	my ($count) = $dbh->selectrow_array( qq{
		SELECT COUNT(DISTINCT albumid) FROM ( $sql ) AS t1
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
	my $parentArtwork;
	my $parentArtworkId;
	my $previousAlbum;
	my $sth_album_urls = $dbh->prepare_cached("SELECT url FROM tracks WHERE tracks.album = ? AND tracks.url LIKE 'file://%'");

	my $work = sub {
		if ( $sth->fetch ) {

			# Callback after resize is finished, needed for async resizing
			my $finished = sub {
				if ($isEnabled) {
					# Update the rest of the tracks on this album
					# to use the same coverid and cover_cached status
					if ( $parentArtwork && $parentArtworkId && !$coverid ) {
						$sth_update_tracks_with_parent->execute( $parentArtwork, $parentArtworkId, $albumid, $cover );
					}
					else {
						$sth_update_tracks->execute( $coverid, $albumid, $cover );
					}
				}

				$progress->update( $album_title );

				if ( ++$i % 50 == 0 ) {
					Slim::Schema->forceCommit;
				}

				Slim::Utils::Scheduler::unpause() if !main::SCANNER;
			};

			if ( $previousAlbum != $albumid ) {
				$previousAlbum = $albumid;
				if ( Slim::Music::Info::isFileURL($url) ) {
					my @currentAlbumUrls = @{$dbh->selectall_arrayref($sth_album_urls, {}, $albumid)};
					my @paths = Slim::Utils::Misc::uniq(map( dirname(Slim::Utils::Misc::pathFromFileURL($_->[0])), @currentAlbumUrls ));

					my $commonParent;
					if (@paths == 1) {
						$commonParent = $paths[0];
					}
					elsif (scalar @paths) {
						$commonParent = _findCommonParent(\@paths);
					}
					my $urlDir = dirname(Slim::Utils::Misc::pathFromFileURL($url));
					if ( $parentArtwork = Slim::Music::Artwork->findStandaloneArtwork({}, {}, Slim::Utils::Misc::fileURLFromPath($commonParent), 1) ) {
						$parentArtworkId = Slim::Music::Artwork->generateImageId({
							image => $parentArtwork,
							url   => Slim::Utils::Misc::fileURLFromPath($parentArtwork),
						}) || '';
						$sth_update_albums->execute( $parentArtworkId, $albumid );
						Slim::Utils::ImageResizer->resize($parentArtwork, "music/$parentArtworkId/cover_", join(',', @specs), undef);
					}
					else {
						$parentArtwork = undef;
						$parentArtworkId = undef;
					}
				}
			}


			$artCount{$albumid}++ unless $parentArtwork;

			# Do the actual pre-caching only if the pref for it is enabled
			if ( $isEnabled ) {
				# let's grab external images when run in the scanner
				if (main::SCANNER && $cover =~ /^https?:/) {
					require Slim::Web::ImageProxy;
					$imgProxyCache ||= Slim::Web::ImageProxy::Cache->new();

					if (my $cached = $imgProxyCache->get($cover)) {
						$cover = $cached->{data_ref};
					}
					else {
						require Slim::Networking::SimpleSyncHTTP;
						my $result = Slim::Networking::SimpleSyncHTTP->new({
							cache => 1
						})->get($cover);

						if ($result->is_success) {
							my ($ct) = $result->headers->content_type =~ /image\/(png|jpe?g)/;
							$ct =~ s/jpeg/jpg/;

							my $fetched = $result->contentRef;

							$imgProxyCache->set($cover, {
								content_type  => $ct,
								mtime         => 0,
								original_path => undef,
								data_ref      => $fetched,
							});

							$cover = $fetched;
						}
					}
				}

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
			ORDER BY CASE WHEN CAST(CAST(tracks.cover AS INTEGER) AS TEXT) = tracks.cover THEN '1' ELSE '0' END, tracks.disc, tracks.tracknum
			LIMIT 1
	 	});

	 	$i = 0;

		while ( my ($albumId, $trackCount) = each %artCount ) {

			$sth_get_album_art->execute($albumId);
			my ($coverId) = $sth_get_album_art->fetchrow_array;

			$sth_update_albums->execute( $coverId, $albumId );

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

	my $thumbSize = $prefs->get('thumbSize') || 100;

	push(@specs,
		"${thumbSize}x${thumbSize}_o", # Web UI large thumbnails
		'50x50_o',	# Web UI small thumbnails, Controller App (low-res display)
	);

	# HiDPI versions of web UI artwork
	if ($prefs->get('precacheHiDPIArtwork')) {
		$thumbSize *= 2;
		push @specs, "${thumbSize}x${thumbSize}_o", '100x100_o';
	}

	if ( my $customSpecs = $prefs->get('customArtSpecs') ) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Adding custom artwork resizing specs:\n" . Data::Dump::dump($customSpecs));
		push @specs, keys %$customSpecs;
	}

	# sort by size, so we can batch convert
	@specs = sort {
		my ($sizeA) = $a =~ /^(\d+)/;
		my ($sizeB) = $b =~ /^(\d+)/;
		$sizeB <=> $sizeA;
	# XXX - this is duplicated from Slim::Web::Graphics->parseSpec, which is not loaded in scanner mode
	} grep {
		/^(?:([0-9X]+)x([0-9X]+))?(?:_(\w))?(?:_([\da-fA-F]+))?(?:\.(\w+))?$/
	# remove duplicates
	} keys %{{
		map {$_ => 1} @specs
	}};

	main::DEBUGLOG && $log->is_debug && $log->debug("Full list of artwork pre-cache specs:\n" . Data::Dump::dump(@specs));

	return @specs;
}

sub _findCommonParent {
	my $paths = shift;
	return undef if ref $paths ne 'ARRAY';
	return $paths->[0] if scalar @$paths == 1;

	my @split_paths = map {
		my $normalized = canonpath($_);
		[splitdir($normalized)];
	} @$paths;

	my @common;
	my $min_len = min(map { scalar @$_ } @split_paths);

	for my $i (0 .. $min_len - 1) {
		my $component = $split_paths[0][$i];
		my $all_same = 1;

		for my $path (@split_paths) {
			if ($path->[$i] ne $component) {
				$all_same = 0;
				last;
			}
		}

		last unless $all_same;
		push @common, $component;
	}

	return @common ? catdir(@common) : undef;
}

sub _discSpecificArtworkNames {
	my $discId = shift;

	return () if defined($discId) && !$discId;

	my @discSpecificNames = (
		'cover-disc%s', 'cover_disc%s', 'coverdisc%s',
		'folder-disc%s', 'folder_disc%s', 'folderdisc%s',
		'disc%s', 'cd%s'
	);
	return ( map {sprintf($_, $discId)} @discSpecificNames );
}

1;
