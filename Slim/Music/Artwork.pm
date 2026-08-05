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
use constant MAX_LEVELS_FOR_BOX_ARTWORK => 3;

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
my $artFolderRead;
my $imageTypesRegex;

# Public class methods
sub findStandaloneArtwork {
	my ( $class, $trackAttributes, $deferredAttributes, $dirurl, $args ) = @_;

	return wantarray ? () : 0 if !Slim::Music::Info::isFileURL($dirurl);

	my $isInfo = main::INFOLOG && $log->is_info;

	my $art = $findArtCache{$dirurl};

	# Files to look for
	my @files = @{$args->{coverFiles} || []} || qw(cover album folder thumb);

	# User-defined artwork format
	my $coverFormat = $prefs->get('coverArt');

	my $artDir = $prefs->get('artfolder');
	my $candidateForArtfolder;

	if ( !defined $art ) {
		my $parentDir = Path::Class::dir( Slim::Utils::Misc::pathFromFileURL($dirurl) );

		# coverArt/artfolder pref support
		if ( $coverFormat ) {
			# If the user has specified a pattern to match the artwork on, we need
			# to generate that pattern. This is nasty.
			if ( $coverFormat =~ /^%(.*?)(\..*?){0,1}$/ ) {
				my $formatStr = $1;
				my $suffix = $2;

				my $track = $trackAttributes && delete $trackAttributes->{_track};

				# Merge attributes to use with TitleFormatter
				# XXX This may break for some people as it's not using a Track object anymore
				my $meta = { %{$trackAttributes}, %{$deferredAttributes} } unless $track;

				if ( my $coverName = Slim::Music::TitleFormatter::infoFormat( $track, $formatStr, undef, $meta ) ) {
					$coverName .= $suffix;

					if ( main::ISWINDOWS ) {
						# Remove illegal characters from filename.
						$coverName =~ s/\\|\/|\:|\*|\?|\"|<|>|\|//g;
					}

					# Generating a pathname from tags is dangerous because the filesystem
					# encoding may not match the locale, but that is the best guess that we have.
					$coverName = Slim::Utils::Unicode::encode_locale($coverName);

					unshift @files, $coverName;

					if ( $artDir && -d $artDir ) {
						$candidateForArtfolder = $coverName;

						# add the content of the artwork folder to our scanned picture table
						if (main::SCANNER && !$artFolderRead) {
							Slim::Utils::Scanner::Local::Async->find( $artDir, {
								types => 'image',
								no_async => 1,
							}, sub {} );

							$artFolderRead = 1;
						}
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

				unshift @files, $coverFormat;
			}
		}

		if (wantarray) {
			my @artFiles = _findStandaloneArtwork($parentDir, \@files);
			if ($candidateForArtfolder) {
				push @artFiles, _findStandaloneArtwork($artDir, [$candidateForArtfolder]);
			}
			push @artFiles, _findStandaloneArtwork($parentDir);

			return @artFiles;
		}

		# look up "artist name" (or whatever the template), cover, album, etc. in music folder first
		$art ||= _findStandaloneArtwork($parentDir, \@files);

		# check for "artist name" (or whatever) in the artwork folder (if defined)
		if ( !$art && $candidateForArtfolder && $artFolderRead ) {
			$art = _findStandaloneArtwork($artDir, [$candidateForArtfolder]);
		}

		# pick any picture in music folder
		$art ||= _findStandaloneArtwork($parentDir);

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

sub _findStandaloneArtwork {
	my ($parentDir, $filenameTemplates) = @_;
	my $dbh = Slim::Schema->dbh;

	$imageTypesRegex ||= Slim::Music::Info::validTypeExtensions('image');

	my @candidates = $filenameTemplates ? Slim::Utils::Misc::uniq(map {
		my $name = $_;
		my @variations;

		if ($name =~ $imageTypesRegex) {
			push @variations, catfile($parentDir, $name);
		}
		else {
			@variations = map {(
				catfile($parentDir, "$name.$_"),
				catfile($parentDir, $name . '.' . uc($_)),
			)} ('jpg', 'jpeg', 'png', 'gif');
		}

		@variations;
	} @$filenameTemplates) : ();

	my @images;

	if (main::SCANNER) {
		my $sql = 'SELECT url FROM scanned_pics WHERE url ';
		if (scalar @candidates) {
			$sql .= sprintf('IN (%s)', join(',', map { '?' } @candidates));
		}
		else {
			# doing a range search helps us avoid a LIKE query, which would result in a scan
			$sql .= '>= ? AND url < ?';
			my $pathUrl = Slim::Utils::Misc::fileURLFromPath($parentDir);
			push @candidates, $pathUrl,  $pathUrl . chr(0xff);
		}

		my $sth = Slim::Schema->dbh->prepare_cached($sql);

		@images = Slim::Utils::Misc::uniq(map {
			Slim::Utils::Misc::pathFromFileURL($_->[0]);
		} @{
			$dbh->selectall_arrayref($sth, undef, map { Slim::Utils::Misc::fileURLFromPath($_) } @candidates)
		});
	}
	else {
		@images = Slim::Utils::Misc::uniq(grep { -f $_ } @candidates);

		# read the folder anyway, as we don't have the full list of images in the database table
		if (!scalar @images && !$filenameTemplates) {
			my $files = File::Next::files( {
				file_filter    => sub { Slim::Utils::Misc::fileFilter($File::Next::dir, $_, $imageTypesRegex, undef, 1) },
				descend_filter => sub { 0 },
			}, $parentDir );

			while ( my $image = $files->() ) {
				# just take the first image found...
				push @images, $image;
				last;
			}
		}
	}

	# keep sort order from the templates list
	if (scalar @images > 1) {
		my %rank;
		@rank{ map { $_ } @$filenameTemplates } = (0 .. $#$filenameTemplates);

		@images = sort {
			my $a_rank = $rank{ basename($a) } // 999_999;
			my $b_rank = $rank{ basename($b) } // 999_999;
			$a_rank <=> $b_rank;
		} @images;
	}

	return wantarray ? @images : ($images[0] || 0);
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
		WHERE $where
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

	if ( !$count ) {
		$cb && $cb->();
		main::SCANNER && Slim::Music::Import->endImporter('updateStandaloneArtwork');
		return;
	}

	$log->error("Starting updateStandaloneArtwork for $count albums");

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
			if ( (!$cover || !$newCoverId) && Slim::Music::Info::isFileURL($url) ) {
				# store properties in a hash
				my $track = Slim::Schema->find('Track', $trackid);

				if ($track) {
					my $newCover = Slim::Music::Artwork->findStandaloneArtwork(
						{ _track => $track },	# pass track object to avoid deflation unless necessary
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
			elsif ( $cover =~ /^https?:/ && (!$album_artwork || $album_artwork ne $cover) ) {
				$sth_update_albums->execute( $newCoverId, $albumid );

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

sub updateBoxsetArtwork {
	my $class = shift;
	my $cb    = shift; # optional callback when done (main process async mode)

	my $dbh = Slim::Schema->dbh;

	# get singledir parameter from the scanner if available
	# shortcut for online library scan only - we don't have the necessary information
	my $singledir = main::SCANNER ? $ARGV[-1] : undef;
	my $skipUpdate = $singledir && $singledir eq 'onlinelibrary';

	my $boxsetSql = qq{
		SELECT album
		FROM tracks
		WHERE album IS NOT NULL AND coverid IS NOT NULL AND substr(url, 0, 8) = 'file://'
		GROUP BY album
		HAVING COUNT(DISTINCT coverid) > 1
	};

	my ($count) = $dbh->selectrow_array( qq{
		SELECT COUNT(*) FROM ( $boxsetSql ) AS t1
	} ) unless $skipUpdate;

	if ( !$count ) {
		$cb && $cb->();
		main::SCANNER && Slim::Music::Import->endImporter('updateBoxsetArtwork');
		return;
	}

	my ($isPrecachingEnabled, $specs) = _initPrecacheArtworkIfEnabled();

	$log->error("Starting updateBoxsetArtwork for $count albums");

	my $progress = Slim::Utils::Progress->new( {
		type  => 'importer',
		name  => 'updateBoxsetArtwork',
		total => $count,
		bar   => 1,
	} );

	my $sth_boxset = $dbh->prepare_cached($boxsetSql);
	$sth_boxset->execute;

	my $sth_album_tracks = $dbh->prepare_cached( qq{
		SELECT url FROM tracks WHERE album = ?
	} );

	my $sth_update_albums = $dbh->prepare( qq{
		UPDATE albums
		SET    artwork = ?
		WHERE  id = ?
	} );

	my $albumId;
	$sth_boxset->bind_columns(\$albumId);

	my $t = 0;

	my $work = sub {
		if ( $sth_boxset->fetch ) {
			$sth_album_tracks->execute($albumId);

			# get unique folder names for this album, as we may have multiple folders for a boxset
			my @paths = Slim::Utils::Misc::uniq(
				map {
					dirname(Slim::Utils::Misc::pathFromFileURL($_->[0]))
				} @{$sth_album_tracks->fetchall_arrayref()}
			);

			# put parent folder first in list if we have multiple folders for this album
			unshift @paths, Slim::Utils::Misc::commonParentPath(\@paths, MAX_LEVELS_FOR_BOX_ARTWORK) if scalar @paths > 1;

			# don't look for artwork in the root folder or on a Windows drive letter, as that is likely to be a false positive
			@paths = grep { $_ && $_ ne '/' && !Slim::Utils::Misc::isWinDrive(substr($_, 0, 2)) } @paths;

			$progress->update( $paths[0] || '' );

			if ( $t < time ) {
				Slim::Schema->forceCommit;
				$t = time + 5;
			}

			my ($newCover, $folder);
			foreach (@paths) {
				$newCover = Slim::Music::Artwork->findStandaloneArtwork({}, {}, Slim::Utils::Misc::fileURLFromPath($_), {
					coverFiles => [qw(boxset album cover folder)],
				});

				if ($newCover) {
					$folder = $_;
					last;
				}
			}

			my $newCoverId = $class->generateImageId({
				image => $newCover,
				url   => Slim::Utils::Misc::fileURLFromPath($newCover),
			}) if $newCover;

			if ($newCoverId) {
				my ($coverTrackExists) = $dbh->selectrow_array( qq{
					SELECT 1 FROM tracks WHERE coverid = ?
				}, undef, $newCoverId );

				# In order to avoid the need for another schema change in albums, we create a track object
				# for the album folder and store the coverid there. This is a bit of a hack, but it works.
				my $trackObjForAlbum = Slim::Schema->objectForUrl({
					url => Slim::Utils::Misc::fileURLFromPath($folder),
					create => 1,
					readTags => 0,
					playlist => 0,
					checkMTime => 0,
				});

				$trackObjForAlbum->content_type('dir');   # directories should not show up anywhere (audio, lists, images...)
				$trackObjForAlbum->coverid($newCoverId);
				$trackObjForAlbum->cover($newCover);
				$trackObjForAlbum->update;

				$sth_update_albums->execute( $newCoverId, $albumId );

				Slim::Utils::ImageResizer->resize($newCover, "music/$newCoverId/cover_", $specs) if $isPrecachingEnabled;
			}

			return 1;
		}

		$progress->final;

		$cb && $cb->();

		return 0;
	};

	if ( main::SCANNER ) {
		# Non-async mode in scanner
		while ( $work->() ) { }

		Slim::Music::Import->endImporter('updateBoxsetArtwork');
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

	my $parentDir  = file($path)->dir;

	$isInfo && $log->info("Looking for image files in $parentDir");

	my @candidates = $class->findStandaloneArtwork({ _track => $track }, {}, Slim::Utils::Misc::fileURLFromPath($path));

	foreach my $artPath (@candidates) {
		my ($body, $contentType) = $class->getImageContentAndType($artPath);

		if ($body && $contentType) {
			$isInfo && $log->info("Found image file: $artPath");
			return ($body, $contentType, $artPath);
		}
	}

	return undef;
}

sub precacheAllArtwork {
	my $class = shift;
	my $cb    = shift; # optional callback when done (main process async mode)
	my $force = shift; # sometimes we want all artwork to be re-rendered

	my $isDebug = main::DEBUGLOG && $importlog->is_debug;

	my ($isEnabled, $specs) = _initPrecacheArtworkIfEnabled();

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
		GROUP BY tracks.cover, tracks.album
 	};

	my $sth_update_tracks = $dbh->prepare( qq{
	    UPDATE tracks
	    SET    coverid = ?, cover_cached = 1
	    WHERE  album = ?
	    AND    (cover = ? OR cover LIKE 'http%')
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

				Slim::Utils::ImageResizer->resize($path, "music/$coverid/cover_", $specs, $finished);
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

sub _initPrecacheArtworkIfEnabled {
	return (0, undef) unless $prefs->get('precacheArtwork');

	require Slim::Utils::ImageResizer;
	return (1, join(',', getResizeSpecs()));
}

1;
