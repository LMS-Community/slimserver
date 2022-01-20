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
			if ($prefName =~ /mapping_([a-f0-9]+)/) {
				# if there was a duplicate entry, we'd get a list instead of a string - pick the first entry
				($prefData) = grep /\w+/, @$prefData if ref $prefData;
				$prefData =~ s/^\s+|\s+$//g;

				if ($prefData) {
					$genreMappings->set($1, $prefData);
				}
				else {
					$genreMappings->remove($1);
				}
			}
		}
	}

	$params->{genre_list} = [ sort map { $_->name } Slim::Schema->search('Genre')->all ];

	$class->SUPER::handler($client, $params);
}

sub beforeRender {
	my ($class, $params, $client) = @_;
	($params->{genreMappings}, $params->{sortOrder}) = _getGenreMappings();
}

sub _getGenreMappings {
	my $sql = q(SELECT albums.title, albums.titlesearch, contributors.name, contributors.namesearch
						FROM albums JOIN contributors ON contributors.id = albums.contributor
						WHERE albums.extid IS NOT NULL
						ORDER BY contributors.namesort, albums.titlesort;);

	my ($title, $titlesearch, $name, $namesearch);

	my $sth = Slim::Schema->dbh->prepare_cached($sql);
	$sth->execute();
	$sth->bind_columns(\$title, \$titlesearch, \$name, \$namesearch);

	my $mappings = {};
	my $order = [];
	while ( $sth->fetch ) {
		my $key = md5_hex("$titlesearch||$namesearch");
		utf8::decode($title);
		utf8::decode($name);
		$mappings->{$key} = [ $title, $name, $genreMappings->get($key) ];
		push @$order, $key;
	}

	return ($mappings, $order);
}

1;
