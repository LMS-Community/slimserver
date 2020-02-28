package Slim::Plugin::OnlineLibrary::Importer;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Utils::Prefs;
use Slim::Utils::Progress;

use Slim::Plugin::OnlineLibrary::Libraries;

my $prefs = preferences('plugin.onlinelibrary');

sub initPlugin {
	my $class = shift;

	Slim::Plugin::OnlineLibrary::Libraries->initLibraries() || [];

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

	return unless scalar @$mappings;

	my $progress = Slim::Utils::Progress->new({
		'type'  => 'importer',
		'name'  => 'plugin_online_library_genre_replacement',
		'total' => scalar @$mappings,
		'every' => 1,
	});

	my $dbh = Slim::Schema->dbh;
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
			my $condition = sprintf('%%%s%%', $mapping->{text});

			# check whether we have any matching items
			my $count = $dbh->selectall_arrayref(qq(
				SELECT 1
				FROM ($selectSQL)
				LIMIT 1
			), undef, $condition);

			next unless $count && $count->[0] && $count->[0]->[0];

			my $genreName = $mapping->{genre};
			my $genre = Slim::Schema->rs('Genre')->update_or_create({
				name       => $genreName,
				namesort   => Slim::Utils::Text::ignoreCaseArticles($genreName),
				namesearch => Slim::Utils::Text::ignoreCase($genreName, 1),
			}, { key => 'namesearch' });

			my $sth = $dbh->prepare_cached(qq(
				UPDATE genre_track
				SET genre = ?
				WHERE track IN ($selectSQL)
			));

			$sth->execute($genre->id, $condition);
		}
	}

	$progress->final();
	Slim::Schema->forceCommit;

	Slim::Music::Import->endImporter($class);
}

1;