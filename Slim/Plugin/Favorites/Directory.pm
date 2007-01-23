package Slim::Plugin::Favorites::Directory;

# $Id$

# Class to implement directory menus for slim picks and others

use strict;

use Slim::Utils::Log;
use XML::Simple;

my $cache_time = 30 * 60; # time to cache directory opml files for

my $log = logger('favorites');


sub new {
	my $class = shift;
	my $url   = shift;

	my $ref = bless {}, $class;

	$ref->load($url) if $url;

	return $ref;
}

sub load {
	my $class = shift;
	my $url   = shift;

	my $cache = Slim::Utils::Cache->new();

	# FIXME - this is sync http for the moment
	unless ( $class->{'opml'} = $cache->get( 'opml_dir:' . $url ) ) {

		$log->info("Fetching $url directory");

		my $http = Slim::Player::Protocols::HTTP->new( { 'url' => $url, 'create' => 0, 'timeout' => 10 } );

		if ( defined $http ) {

			my $content = $http->content;
			$http->close;

			if ( defined $content ) {

				$class->{'opml'} = eval { XMLin( \$content, forcearray => [ 'outline', 'body' ], SuppressEmpty => undef ) };

				if ($@) {

					$log->warn("Failed to parse directory OPML <$url> because: $@");

				} else {

					$cache->set( 'opml_dir:' . $url, $class->{'opml'}, $cache_time );

				}
			}
		}
	}
}

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

sub title {
	my $class = shift;

	return unless $class->{'opml'};

	return $class->{'opml'}->{'head'}->{'title'};
}

1;
