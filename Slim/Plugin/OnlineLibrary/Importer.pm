package Slim::Plugin::OnlineLibrary::Importer;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Digest::MD5 qw(md5_hex);

use Slim::Utils::Prefs;
use Slim::Utils::Progress;

use Slim::Plugin::OnlineLibrary::Libraries;

my $prefs = preferences('plugin.onlinelibrary');

sub initPlugin {
	my $class = shift;

	# don't run importer if we're doing a singledir scan
	return if main::SCANNER && $ARGV[-1] && 'onlinelibrary' ne $ARGV[-1];

	Slim::Plugin::OnlineLibrary::Libraries->initLibraries() || [];

	Slim::Music::Import->addImporter( 'Slim::Plugin::OnlineLibrary::Importer::VirtualLibrariesCleanup', {
		type   => 'post',
		weight => 110,       # this importer needs to be run after the VirtualLibraries (weight: 100)
		onlineLibraryOnly => 1,
		'use'  => 1,
	} );

	my $mappings = $prefs->get('genreMappings');

	return unless scalar @$mappings;

	Slim::Music::Import->addImporter( $class, {
		type   => 'post',
		weight => 10,
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

	my $genreMappings = preferences('plugin.onlinelibrary-genres');
	my $sql = q(SELECT albums.id, albums.title, albums.titlesearch, contributors.name, contributors.namesearch
					FROM albums JOIN contributors ON contributors.id = albums.contributor
					WHERE albums.extid IS NOT NULL;);

	my ($albumId, $title, $titlesearch, $name, $namesearch);

	$sth = $dbh->prepare_cached($sql);
	$sth->execute();
	$sth->bind_columns(\$albumId, \$title, \$titlesearch, \$name, \$namesearch);

	my $mappings = {};
	my $selectSQL = q(SELECT tracks.id
							FROM tracks
							WHERE tracks.album = ? AND tracks.extid IS NOT NULL;);

	my $trackId;
	my $tracks_sth = $dbh->prepare_cached($selectSQL);
	$tracks_sth->bind_columns(\$trackId);

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
	}

	$progress->final();
	Slim::Schema->forceCommit;

	Slim::Music::Import->endImporter($class);
}

1;


package Slim::Plugin::OnlineLibrary::Importer::VirtualLibrariesCleanup;

sub startScan {
	my ($class) = @_;

	my $dbh = Slim::Schema->dbh or return;

	$dbh->do('DROP TABLE IF EXISTS duplicate_albums');
	$dbh->do(q(
		CREATE TEMPORARY TABLE duplicate_albums AS
			SELECT albums.id
			FROM albums
			WHERE albums.extid IS NOT NULL
				AND 1 IN (
					SELECT 1
					FROM albums otheralbums
					WHERE otheralbums.extid IS NULL
						AND LOWER(otheralbums.title) = LOWER(albums.title)
						AND otheralbums.contributor = albums.contributor
				)
	));

	$dbh->do(q(DELETE FROM library_album WHERE library_album.album IN (SELECT id FROM duplicate_albums)));
	$dbh->do(q(DELETE FROM library_track WHERE library_track.track in (
		SELECT id FROM tracks WHERE tracks.album IN (SELECT id FROM duplicate_albums)
	)));

	$dbh->do('DROP TABLE IF EXISTS duplicate_albums');

	Slim::Music::Import->endImporter($class);
}

1;