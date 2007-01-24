package Slim::Plugin::Favorites::Directory;

# $Id$

# Class to implement directory menus for slim picks and others

use base qw(Slim::Plugin::Favorites::Opml);

use strict;

use Slim::Utils::Log;

my $cache_time = 3600; # cache for 60 mins

my $log = logger('favorites');

sub load {
	my $class = shift;
	my $url   = shift;

	my $cache = Slim::Utils::Cache->new();

	$class->{'opml'} = $cache->get( 'opml_dir:' . $url );

	return if $class->{'opml'};

	$class->SUPER::load($url);

	$cache->set( 'opml_dir:' . $url, $class->{'opml'}, $cache_time );

	return $class->{'opml'};
}

sub save {}

sub categories {
	my $class = shift;

	return unless $class->{'opml'};

	my @categories;

	for my $cat (@{$class->{'opml'}->{'body'}[0]->{'outline'}}) {
		push @categories, $cat->{'text'};
	}

	return \@categories;
}

sub itemNames {
	my $class = shift;
	my $cat   = shift;

	return unless $class->{'opml'};

	my @items = ( undef );

	for my $category (@{$class->{'opml'}->{'body'}[0]->{'outline'}}) {

		if ($category->{'text'} eq $cat) {

			for my $entry (@{$category->{'outline'}}) {
				push @items, $entry->{'text'};
			}
		}
	}

	return \@items;
}

sub item {
	my $class = shift;
	my $catind= shift;
	my $name  = shift;

	return unless $class->{'opml'};

	my $category = $class->{'opml'}->{'body'}[0]->{'outline'}->[ $catind ];

	for my $entry (@{$category->{'outline'}}) {

		if ($entry->{'text'} eq $name) {
			return $entry;
		}
	}

	return undef;
}

1;
