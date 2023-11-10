package Slim::Plugin::OnlineLibrary::EditGenreMappings;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Digest::MD5 qw(md5_hex);

use Slim::Utils::Prefs;

my $genreMappings = preferences('plugin.onlinelibrary-genres');
my $releaseTypeMappings = preferences('plugin.onlinelibrary-releasetypes');

sub new {
	my $class = shift;
	Slim::Web::Pages->addPageFunction($class->page, $class);
}

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_ONLINE_LIBRARY_MODULE_NAME');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/OnlineLibrary/editMappings.html');
}

sub handler {
	my ($class, $client, $params) = @_;

	if ($params->{saveSettings}) {
		# mapping based on album/artist names
		while (my ($prefName, $prefData) = each %{$params}) {
			if ($prefName =~ /genre_([a-f0-9]+)/) {
				_setMapping($genreMappings, $1, $prefData);
			}
			elsif ($prefName =~ /releasetype_([a-f0-9]+)/) {
				_setMapping($releaseTypeMappings, $1, $prefData);
			}
		}
	}

	$params->{genre_list} = [ sort map { $_->name } Slim::Schema->search('Genre')->all ];

	$class->SUPER::handler($client, $params);
}

sub _setMapping {
	my ($prefs, $key, $prefData) = @_;

	# if there was a duplicate entry, we'd get a list instead of a string - pick the first entry
	($prefData) = grep /\w+/, @$prefData if ref $prefData;
	$prefData =~ s/^\s+|\s+$//g;

	if ($prefData) {
		$prefs->set($key, $prefData);
	}
	else {
		$prefs->remove($key);
	}
}

sub beforeRender {
	my ($class, $params, $client) = @_;
	($params->{mappings}, $params->{sortOrder}) = _getMappings();
}

sub _getMappings {
	my $dbh = Slim::Schema->dbh;

	$dbh->do('DROP TABLE IF EXISTS album_track');
	$dbh->do(q(
		CREATE TEMPORARY TABLE album_track AS
			SELECT DISTINCT(album) AS album, MIN(id) AS track
			FROM tracks
			WHERE extid IS NOT NULL
			GROUP BY album
	));
	$dbh->do('CREATE INDEX IF NOT EXISTS album ON album_track (album)');

	my ($title, $titlesearch, $name, $namesearch, $releasetype, $genre);

	my $sth = $dbh->prepare_cached(q(
		SELECT albums.title, albums.titlesearch, contributors.name, contributors.namesearch, genres.name, albums.release_type
		FROM albums
			JOIN contributors ON contributors.id = albums.contributor
			JOIN album_track ON album_track.album = albums.id
			JOIN genre_track ON genre_track.track = album_track.track
			JOIN genres ON genres.id = genre_track.genre
		WHERE albums.extid IS NOT NULL
		ORDER BY contributors.namesort, albums.titlesort
	));
	$sth->execute();
	$sth->bind_columns(\$title, \$titlesearch, \$name, \$namesearch, \$genre, \$releasetype);

	my $mappings = {};
	my $order = [];
	while ( $sth->fetch ) {
		my $key = md5_hex("$titlesearch||$namesearch");
		utf8::decode($title);
		utf8::decode($name);
		utf8::decode($genre);
		push @$order, $key unless $mappings->{$key};
		$mappings->{$key} ||= [ $title, $name, $genreMappings->get($key), $releaseTypeMappings->get($key), $genre, $releasetype ];
	}

	$dbh->do('DROP TABLE IF EXISTS album_track');

	return ($mappings, $order);
}

1;
