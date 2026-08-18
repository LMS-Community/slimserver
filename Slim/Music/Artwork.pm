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
use constant IS_SQLITE => (Slim::Utils::OSDetect->getOS()->sqlHelperClass() =~ /SQLite/ ? 1 : 0);

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
	my ( $class, $trackAttributes, $deferredAttributes, $dirurl ) = @_;

	return wantarray ? () : 0 if !Slim::Music::Info::isFileURL($dirurl);

	my $isInfo = main::INFOLOG && $log->is_info;

	my $art = $findArtCache{$dirurl};

	# Files to look for
	my @files = qw(cover album folder thumb);

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

				# Maybe a track instance was passed in, but no longer from updateStandaloneArtwork() which gives us
				# the trackid instead, as we only need to instantiate a track if 'titleformatter' artwork naming is in use.
				my $track = $trackAttributes && delete $trackAttributes->{_track};
				$track ||= Slim::Schema->find('Track', $trackAttributes->{_trackid}) if $trackAttributes->{_trackid};

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

		$isInfo && $log->info("Looking for artwork in $parentDir: " . join(', ', @files));

		if (wantarray) {
			my @artFiles = _findStandaloneArtwork($parentDir, \@files);
			if ($candidateForArtfolder) {
				push @artFiles, _findStandaloneArtwork($artDir, [$candidateForArtfolder]);
			}
			push @artFiles, _findStandaloneArtwork($parentDir);

			$isInfo && $log->info("Found artwork files: " . join(', ', @artFiles));

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

	my @candidates = $filenameTemplates ? map {
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
	} @$filenameTemplates : ();

	my @images;

	if (main::SCANNER) {
		my $sql = "SELECT full_path FROM scanned_pics WHERE (status IS NULL OR status <> 'D') AND ";
		if (scalar @candidates) {
			$sql .= sprintf('full_path IN (%s)', join(',', map { '?' } @candidates));
		}
		else {
			$sql .= 'folder = ?';
			push @candidates, $parentDir;
		}

		my $sth = Slim::Schema->dbh->prepare_cached($sql);

		@images = Slim::Utils::Misc::uniq(map {
			$_->[0]
		} @{
			$dbh->selectall_arrayref($sth, undef, @candidates)
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

### I might have missed it, but I can't see where this might be called in main process async mode.
### If it is, we'll need more work to populate scanned_pics in the main process or just keep a version of the old subroutine for that use.

	my $dbh = Slim::Schema->dbh;

	# unflag existing unchanged artwork
	$dbh->do( qq{
		UPDATE scanned_pics SET status = NULL
		WHERE status = 'E'
		AND EXISTS (SELECT * FROM tracks WHERE tracks.coverid = scanned_pics.coverid)
	} );

	# for online artwork, update album artwork to first track coverid
	### I considered adding rows to scanned_pics for remote images so that they'd be processed in the loop below, but I think this is more efficient.
	#there's a different syntax for MySql.
	my $sql = IS_SQLITE
		? qq{
			UPDATE albums
			SET artwork = tracks.coverid
			FROM tracks
			WHERE tracks.album = albums.id
			AND tracks.cover LIKE 'https%'
			AND (tracks.coverid <> albums.artwork OR albums.artwork IS NULL)
		}
		: qq{
			UPDATE albums JOIN tracks ON albums.id = tracks.album
			SET albums.artwork = tracks.coverid
			WHERE tracks.cover LIKE 'https%'
			AND (albums.artwork IS NULL OR tracks.coverid <> albums.artwork);
		};
	$dbh->do( $sql );

	Slim::Schema->forceCommit;

	my $sql_scanned_pics = qq{
		SELECT full_path, coverid, GROUP_CONCAT(status)
		FROM scanned_pics
		WHERE status IS NOT NULL
		GROUP BY full_path, coverid
	};

	my ($count) = $dbh->selectrow_array( qq{
		SELECT COUNT(*) FROM ( $sql_scanned_pics ) AS t1
	} );

	$log->error("Starting updateStandaloneArtwork for $count images");

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

	my $pic_sth = $dbh->prepare($sql_scanned_pics);
	my ($picPath, $picCoverid, $status);
	$pic_sth->bind_columns(\$picPath, \$picCoverid, \$status);

	my $sql_tracks = qq{
		SELECT 	tracks.id, tracks.url,
			tracks.cover,
			albums.id AS albumid,
			albums.title AS album_title,
			albums.artwork AS album_artwork
		FROM	tracks JOIN albums ON albums.id = tracks.album
		WHERE	url BETWEEN ? AND ?
		AND	instr(substr(url, length(?)+2), "/") < 1
		ORDER BY albums.id
	};
	my $tracks_sth = $dbh->prepare($sql_tracks);

	my $sth_scanned_pics = $dbh->prepare( qq{
		SELECT coverid FROM scanned_pics WHERE full_path = ?
	} );

	my $sth_update_tracks = $dbh->prepare( qq{
	    UPDATE tracks
	    SET    cover = ?, coverid = ?, cover_cached = NULL
	    WHERE  id = ?
	} );

	my $sth_update_albums = $dbh->prepare( qq{
		UPDATE albums
		SET    artwork = ?
		WHERE  id = ?
	} );

	my $previousAlbum = undef;

	my $i = 0;
	my $t = 0;

	$pic_sth->execute;

	my $work = sub {
		if ( $pic_sth->fetch ) {

			if ( $t < time ) {
				Slim::Schema->forceCommit;
				$t = time + 5;
			}

			my $imageDirUrl = Slim::Utils::Misc::fileURLFromPath(dirname($picPath));
			my @params = ($imageDirUrl, $imageDirUrl . chr(0xff), $imageDirUrl);

			my @tracks =  @{
				$dbh->selectall_arrayref($tracks_sth, { Slice => {} }, @params)
			};

			foreach my $track (@tracks) {

				my $newCover = Slim::Music::Artwork->findStandaloneArtwork(
					{ _trackid => $track->{id} },
					{},
					$imageDirUrl
				);

				if ( $track->{cover} ne $newCover ) {
					my ($newCoverid) = $dbh->selectrow_array($sth_scanned_pics, undef, $newCover);
					$sth_update_tracks->execute( $newCover, $newCoverid, $track->{id} );

					if ( $previousAlbum ne $track->{albumid} && $newCoverid ne $track->{album_artwork} ) {
						$progress->update( $track->{album_title} );
						$sth_update_albums->execute( $newCoverid, $track->{albumid} );
						$log->warn('Artwork has been removed for ' . $track->{album_title}) if !$newCoverid;
					}
				}

				if ( ++$i % 50 == 0 ) {
					Slim::Schema->forceCommit;
					$t = time + 5;
				}

				Slim::Utils::Scheduler::unpause() if !main::SCANNER;

				$previousAlbum = $track->{albumid};
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
		$args->{url} = $image; # use the image url, not the music file url 
	}
	elsif ( $image =~ /^\d+$/ ) {
		# Cache is based on mtime/size of the file containing embedded art
		$mtime = $args->{mtime};
		$size  = $args->{size};
	}
	elsif ( -e $image ) {
		# We will no longer get here from the scanner process, as we already got the coverid from the scanned_pics table.
		# Cache is based on mtime/size of artwork file
		($size, $mtime) = (stat _)[7, 9];
		$args->{url} = $image; # use the image path, not the music file url
	}

	if ( $mtime && $size ) {
		$imageId = $class->calculateCoverId($args->{url}, $mtime, $size);
	}

	return $imageId;
}

sub calculateCoverId {
	my ( $class, $file, $mtime, $size ) = @_;

	return substr( safe_md5_hex( $file . $mtime . $size ), 0, 8 );
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

1;
