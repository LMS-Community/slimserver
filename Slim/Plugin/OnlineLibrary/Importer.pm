package Slim::Plugin::OnlineLibrary::Importer;

# Logitech Media Server Copyright 2001-2023 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Digest::MD5 qw(md5_hex);

use Slim::Utils::Prefs;
use Slim::Utils::Progress;

use Slim::Plugin::OnlineLibrary::Libraries;

my $prefs = preferences('plugin.onlinelibrary');
my $genreMappings = preferences('plugin.onlinelibrary-genres');
my $releaseTypeMappings = preferences('plugin.onlinelibrary-releasetypes');

sub initPlugin {
	my $class = shift;

	# don't run importer if we're doing a singledir scan
	return if main::SCANNER && $ARGV[-1] && 'onlinelibrary' ne $ARGV[-1];

	Slim::Plugin::OnlineLibrary::Libraries->initLibraries() || [];

	Slim::Music::Import->addImporter( 'Slim::Plugin::OnlineLibrary::Importer::VirtualLibrariesCleanup', {
		type   => 'post',
		weight => 110,       # this importer needs to be run after the VirtualLibraries (weight: 100)
		onlineLibraryOnly => 1,
		'use'  => $prefs->get('enablePreferLocalLibraryOnly'),
	} );

	my $mappings = $prefs->get('genreMappings');

	return unless scalar @$mappings || keys %{$genreMappings->all || {}} || keys %{$releaseTypeMappings->all || {}};

	Slim::Music::Import->addImporter( $class, {
		type   => 'post',
		weight => 100,
		onlineLibraryOnly => 1,
		'use'  => 1,
	} );
}

sub startScan {
	my ($class) = @_;
	my $mappings = $prefs->get('genreMappings') || [];

	my $dbh = Slim::Schema->dbh or return;
	my $sth = $dbh->prepare_cached("SELECT COUNT(1) FROM albums WHERE albums.extid IS NOT NULL;");
	$sth->execute();
	my ($count) = $sth->fetchrow_array;
	$sth->finish;

	my $progress = Slim::Utils::Progress->new({
		'type'  => 'importer',
		'name'  => 'plugin_online_library_genre_replacement',
		'total' => $count + scalar @$mappings,
		'bar'   => 1,
		'every' => 1,
	});

	my %SQL = (
		title => q(
			SELECT DISTINCT tracks.id
			FROM tracks
			WHERE tracks.extid IS NOT NULL AND title LIKE ?
		),
		album => q(
			SELECT DISTINCT tracks.id
			FROM tracks
			LEFT JOIN albums ON albums.id = tracks.album
			WHERE tracks.extid IS NOT NULL AND albums.title LIKE ?
		),
		contributor => q(
			SELECT DISTINCT tracks.id
			FROM tracks
			LEFT JOIN contributor_track ON contributor_track.track = tracks.id
			LEFT JOIN contributors ON contributors.id = contributor_track.contributor
			WHERE tracks.extid IS NOT NULL AND contributors.name LIKE ?
		)
	);

	foreach my $mapping (@$mappings) {
		$progress->update();
		Slim::Schema->forceCommit;

		if (my $selectSQL = $SQL{$mapping->{field}}) {
			next unless $mapping->{text} && $mapping->{genre};

			my $condition = sprintf('%%%s%%', $mapping->{text});
			my $genreName = $mapping->{genre};

			my $sth = $dbh->prepare_cached($selectSQL);
			$sth->execute($condition);

			my $trackId;
			$sth->bind_columns(\$trackId);

			while ($sth->fetch) {
				Slim::Schema::Genre->add($genreName, $trackId + 0);
			}
		}
	}

	Slim::Schema->forceCommit;

	my $sql = q(SELECT albums.id, albums.title, albums.titlesearch, contributors.name, contributors.namesearch
					FROM albums JOIN contributors ON contributors.id = albums.contributor
					WHERE albums.extid IS NOT NULL;);

	my ($albumId, $title, $titlesearch, $name, $namesearch);

	$sth = $dbh->prepare_cached($sql);
	$sth->execute();
	$sth->bind_columns(\$albumId, \$title, \$titlesearch, \$name, \$namesearch);

	my $trackId;
	my $tracks_sth = $dbh->prepare_cached( q(
		SELECT tracks.id
		FROM tracks
		WHERE tracks.album = ? AND tracks.extid IS NOT NULL
	) );
	$tracks_sth->bind_columns(\$trackId);

	my $update_release_type_sth = $dbh->prepare_cached( q(
		UPDATE albums
		SET release_type = ?
		WHERE id = ?
	) );

	while ( $sth->fetch ) {
		$progress->update(sprintf('%s - %s', $title, $name));
		Slim::Schema->forceCommit;

		my $key = md5_hex("$titlesearch||$namesearch");
		if (my $genreName = $genreMappings->get($key)) {
			$tracks_sth->execute($albumId);

			while ($tracks_sth->fetch) {
				Slim::Schema::Genre->add($genreName, $trackId + 0);
			}
		}

		if (my $releaseType = $releaseTypeMappings->get($key)) {
			my $ucReleaseType = Slim::Utils::Text::ignoreCase($releaseType);
			$update_release_type_sth->execute($ucReleaseType, $albumId);
			Slim::Schema::Album->addReleaseTypeMap($releaseType, $ucReleaseType);
		}
	}

	$progress->final();
	Slim::Schema->forceCommit;

	Slim::Music::Import->endImporter($class);
}

1;


package Slim::Plugin::OnlineLibrary::Importer::VirtualLibrariesCleanup;

sub startScan {
	my ($class) = @_;

	if (!$prefs->get('enablePreferLocalLibraryOnly')) {
		Slim::Music::Import->endImporter($class);
		return;
	}

	my $dbh = Slim::Schema->dbh or return;

	$dbh->do('DROP TABLE IF EXISTS duplicate_albums');
	$dbh->do(q(
		CREATE TEMPORARY TABLE duplicate_albums AS
			SELECT albums.id AS online, otheralbums.id AS local
			FROM albums
			JOIN albums otheralbums ON otheralbums.extid IS NULL AND
				LOWER(otheralbums.title) = LOWER(albums.title) AND
				otheralbums.contributor = albums.contributor
			WHERE albums.extid IS NOT NULL AND
				(
					SELECT otheralbums.id
						FROM albums otheralbums
						WHERE otheralbums.extid IS NULL AND
								LOWER(otheralbums.title) = LOWER(albums.title) AND
								otheralbums.contributor = albums.contributor
				) IS NOT NULL
	) );

	$dbh->do('CREATE INDEX IF NOT EXISTS online ON duplicate_albums (online)');
	$dbh->do('CREATE INDEX IF NOT EXISTS local ON duplicate_albums (local)');

	my $delAlbumSth = $dbh->prepare_cached(q(
		DELETE FROM library_album
		WHERE library_album.album = ? AND library = ? AND (
			SELECT online FROM duplicate_albums WHERE online = ?
		) IS NOT NULL
	));

	my $onlineAlbumsSth = $dbh->prepare_cached(q(
		SELECT album FROM library_album WHERE library = ? AND album IN (SELECT online FROM duplicate_albums)
	));

	my $localAlbumsSth = $dbh->prepare_cached(q(
		SELECT album FROM library_album WHERE library = ? AND album IN (SELECT local FROM duplicate_albums WHERE online = ?)
	));

	my $libraryAlbumDelSth = $dbh->prepare_cached(q(
		DELETE FROM library_album WHERE library = ? AND album = ?
	));

	my $libraryTrackDelSth = $dbh->prepare_cached(q(
		DELETE FROM library_track WHERE library = ? AND track IN (SELECT id FROM tracks WHERE album = ?)
	));

	foreach my $library (keys %{ Slim::Music::VirtualLibraries->getLibraries() } ) {
		$onlineAlbumsSth->execute($library);
		while ( my ($onlineId) = $onlineAlbumsSth->fetchrow_array ) {
			$localAlbumsSth->execute($library, $onlineId);
			my $localAlbumIds = $localAlbumsSth->fetchall_arrayref;
			foreach my $albumId (@{ $localAlbumIds || [] }) {
				$libraryAlbumDelSth->execute($library, $albumId->[0]);
				$libraryTrackDelSth->execute($library, $albumId->[0]);
			}
		}
	}

	$dbh->do('DROP TABLE IF EXISTS duplicate_albums');

	Slim::Music::Import->endImporter($class);
}

1;