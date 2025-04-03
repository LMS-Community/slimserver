package Slim::Music::ContributorPictureScan;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2025 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Music::ContributorPictureScan

=head1 DESCRIPTION

L<Slim::Music::ContributorPictureScan>

=cut

use strict;

use File::Basename qw(dirname basename);
use File::Spec::Functions qw(catdir catfile);
use Path::Class;

use Slim::Music::Import;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Scanner::Local;

my $log = logger('scan.import');
my $prefs = preferences('server');

my ($dbh, $sth_album_folders, $sth_contributor_picture, $sth_update_contributor_picture, @artworkFolders, $specs, $i);

# when walking up the folder hierarchy, don't go above these folders
my $audioDirs = { map { $_ => 1 } @{Slim::Utils::Misc::getAudioDirs()} };

sub init {
	my $class = shift;

	Slim::Music::Import->addImporter( $class, {
		type   => 'artwork',
		weight => 5,
	} );

	Slim::Music::Import->useImporter($class, !$prefs->get('noContributorPictures'));
}

sub startArtworkScan {
	my $class = shift;

	if ($prefs->get('precacheArtwork')) {
		require Slim::Utils::ImageResizer;
		$specs = join(',', Slim::Music::Artwork::getResizeSpecs());
	}

	$dbh = Slim::Schema->dbh;

	main::INFOLOG && $log->info("Starting contributor portrait scan");

	my $imageFolder = $prefs->get('artfolder');
	if ( $imageFolder && -d $imageFolder ) {
		$class->addArtworkFolder($imageFolder);
	}

	$sth_album_folders = $dbh->prepare_cached(qq{
		SELECT url
		FROM tracks
		JOIN contributor_track ON contributor_track.track = tracks.id
		WHERE contributor_track.contributor = ? AND tracks.url LIKE 'file://%'
		GROUP BY album
	});

	$sth_contributor_picture = $dbh->prepare_cached(qq{
		SELECT portrait, portraitid
		FROM contributors
		WHERE id = ?
	});

	$sth_update_contributor_picture = $dbh->prepare_cached(qq{
		UPDATE contributors
		SET portrait = ?, portraitid = ?
		WHERE id = ?
	});

	my $roles = join( ',', map { Slim::Schema::Contributor->typeToRole($_) } Slim::Schema::Contributor->activeContributorRoles() );

	my $sql = qq{
		SELECT id, name, portrait, portraitid
		FROM contributors
			LEFT JOIN contributor_album ON contributor_album.contributor = contributors.id
		WHERE contributor_album.role IS NULL OR contributor_album.role IN ($roles)
		GROUP BY contributors.id
	};

	my ($count) = $dbh->selectrow_array( qq{ SELECT COUNT(*) FROM ($sql) } ) || (0);

	$sql =~ s/, portrait, portraitid// if $main::wipe;

	my $sth = $dbh->prepare($sql);
	$sth->execute();

	my $progress = undef;

	if ($count) {
		$progress = Slim::Utils::Progress->new({
			'type'  => 'importer',
			'name'  => 'contributor_picture',
			'total' => $count,
			'bar'   => 1
		});
	}

	while ( _getArtistPhotoURL({
		sth      => $sth,
		count    => $count,
		progress => $progress,
	}) ) {}

	main::INFOLOG && $log->info("Finished scan for contributor pictures.");

	Slim::Music::Import->endImporter($class);
}

sub _getArtistPhotoURL {
	my $params = shift;

	my $progress = $params->{progress};

	# get next artist from db
	if ( my $artist = ($params->{sth}->fetchrow_hashref) ) {
		my ($img, $candidates);

		$artist->{name} = Slim::Utils::Unicode::utf8decode($artist->{name});
		$progress->update( $artist->{name} ) if $progress;
		time() > $i && ($i = time + 5) && Slim::Schema->forceCommit;

		# don't re-evaluate if we already have a portrait
		if (main::SCANNER && !$main::wipe && $artist->{portrait} && $artist->{portraitid}) {
			my $pictureId = Slim::Music::Artwork->generateImageId({
				image => Slim::Utils::Misc::pathFromFileURL($artist->{portrait}),
				url   => $artist->{portrait},
			}) || '';

			# return early if existing image hasn't changed
			if ($pictureId eq $artist->{portraitid}) {
				return 1;
			}
			elsif ($pictureId) {
				$img = Slim::Utils::Misc::pathFromFileURL($artist->{portrait});
			}
		}

		# check if we have a portrait in the artwork folder(s)
		if (!$img) {
			$candidates = sanitizedNameVariants($artist->{name});

			main::INFOLOG && $log->is_info && $log->info("Looking for pictures of  " . $artist->{name});

			foreach my $folder (@artworkFolders) {
				$img = imageInFolder($folder, @$candidates);
				last if $img;
			}
		}

		# check if we have a portrait in the album folders (and up)
		if (!$img) {
			$sth_album_folders->execute($artist->{id});

			my %seen;
			ALBUMFOLDER: while (my $track = $sth_album_folders->fetchrow_hashref) {
				my $path = Slim::Utils::Misc::pathFromFileURL($track->{url});
				$path = dirname($path) if !-d $path;

				if (-d $path) {
					my $dir = Path::Class::dir($path);

					# check parent/grandparent folder, assuming many have a music/artist/album/(CDx) hierarchy
					my $parent = $dir->parent->stringify if !$audioDirs->{$path};
					my $grandparent = $dir->parent->parent->stringify if $parent && !$audioDirs->{$parent};

					foreach ($parent, $path, $grandparent) {
						next if !$_ || $seen{$_}++ || $audioDirs->{$_};
						$img = imageInFolder($_, @$candidates, 'artist', 'contributor');
						last ALBUMFOLDER if $img;
					}
				}
			}

			$sth_album_folders->finish;
		}

		if ($img) {
			$img = Slim::Utils::Unicode::utf8encode($img);
			my $url = Slim::Utils::Misc::fileURLFromPath($img);
			my $imgId = Slim::Music::Artwork->generateImageId({
				image => $img,
				url   => $url,
			});

			my $contributorPicture = $dbh->selectrow_arrayref($sth_contributor_picture, undef, $artist->{id});

			if ( $imgId && !($contributorPicture && $contributorPicture->[1] eq $imgId) ) {
				# updated or new portrait
				$sth_update_contributor_picture->execute($url, $imgId, $artist->{id});

				Slim::Utils::ImageResizer->resize($img, "contributor/$imgId/image_", $specs) if $specs;
			}
		}
		else {
			$log->warn("No portrait found for " . $artist->{name});
		}

		return 1;
	}

	if ( $progress ) {
		$progress->final($params->{count});
	}

	return 0;
}

sub addArtworkFolder {
	my ($class, $folder) = @_;

	if (!($folder && -d $folder)) {
		$log->warn("Invalid folder: $folder");
		return;
	}

	@artworkFolders = Slim::Utils::Misc::uniq(@artworkFolders, $folder);
}

sub sanitizedNameVariants {
	my ($name) = @_;

	# Remove wildcards and other stuff potentially conflicting with file system limitations
	# For whatever reason those aren't removed by S::U::Misc::cleanupFilename()
	$name =~ s/[:?*]//g;

	my @candidates = map {
		(
			$_,
			Slim::Utils::Unicode::utf8encode($_),
			Slim::Utils::Text::ignorePunct($_)
		);
	} (Slim::Utils::Misc::cleanupFilename($name), $name);

	push @candidates, Slim::Utils::Unicode::utf8toLatin1Transliterate($candidates[-1]);

	return [ Slim::Utils::Misc::uniq(@candidates) ];
}

sub imageInFolder {
	my ($folder, @names) = @_;

	return unless $folder && @names;

	main::INFOLOG && $log->info("Trying to find artwork in $folder for pictures called " . join(', ', map { "'$_'" } @names));

	my $file;

	LOOKUP: foreach my $name (@names) {
		foreach my $ext ('jpg', 'png', 'jpeg', 'JPG', 'PNG', 'JPEG') {
			my $candidate = catdir($folder, $name . ".$ext");

			if (-f $candidate) {
				$file = $candidate;
				last LOOKUP;
			}
		}
	}

	return $file;
}



=head1 SEE ALSO

L<Slim::Music::Import>

=cut

1;

__END__
