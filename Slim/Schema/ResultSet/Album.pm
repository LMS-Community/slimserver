package Slim::Schema::ResultSet::Album;

# $Id$

use strict;
use base qw(Slim::Schema::ResultSet::Base);

use Slim::Utils::Prefs;

sub title {
	my $self = shift;

	return 'BROWSE_BY_ALBUM';
}

sub allTitle {
	my $self = shift;

	return 'ALL_ALBUMS';
}

sub pageBarResults {
	my $self = shift;
	my $sort = shift;

	my $table = $self->{'attrs'}{'alias'};
	my $name  = "$table.titlesort";

	# pagebar based on contributors if first sort field and results already sorted by this
	if ($sort && $sort =~ /^contributor\.namesort/) {

		if ($self->{'attrs'}{'order_by'} =~ /contributor\.namesort/) {
			$name  = "contributor.namesort";
		}

# bug 4633: sorting album views isn't fully supported yet
#		elsif ($self->{'attrs'}{'order_by'} =~ /me\.namesort/) {
#			$name  = "me.namesort";
#		}
	}

	$self->search(undef, {
		'select'     => [ \"LEFT($name, 1)", { count => \"DISTINCT($table.id)" } ],
		as           => [ 'letter', 'count' ],
		group_by     => \"LEFT($name, 1)",
		result_class => 'Slim::Schema::PageBar',
	});
}

sub alphaPageBar {
	my $self = shift;
	my $sort = shift;
	my $hierarchy = shift;

	# bug 4633: sorting album views isn't fully supported yet
	# use simple numerical pagebar if we used a different hierarchy than album/*
	return 0 unless ($hierarchy =~ /^album/ || !$sort || $sort =~ /^album\.titlesort/);

	return (!$sort || $sort =~ /^(?:contributor\.namesort|album\.titlesort)/) ? 1 : 0;
}

sub ignoreArticles {
	my $self = shift;

	return 1;
}

sub searchColumn {
	my $self  = shift;

	return 'titlesearch';
}

sub searchNames {
	my $self  = shift;
	my $terms = shift;
	my $attrs = shift || {};

	$attrs->{'order_by'} ||= 'me.titlesort, me.disc';
	$attrs->{'distinct'} ||= 'me.id';

	return $self->search({ 'me.titlesearch' => { 'like' => $terms } }, $attrs);
}

sub browse {
	my $self = shift;
	my $find = shift;
	my $cond = shift;
	my $sort = shift;

	my @join = ();

	# This sort/join logic is here to handle the 'Sort Browse Artwork'
	# feature - which applies to albums, as artwork is just a view on the
	# album list.
	#
	# Quick and dirty to get something working again. This code should be
	# expanded to be generic per level. A UI feature would be to have a
	# drop down on certain browse pages of how to order the items being
	# displayed. Album is problably the most flexible of all our browse
	# modes.
	#
	# Writing this code also brought up how we might be able to abstract
	# out some join issues/duplications - if we resolve all potential
	# joins first, like the contributorAlbums issue below.
	if ($sort) {

		if ($sort =~ /contributor/) {

			push @join, 'contributor';
		}

		if ($sort =~ /genre/) {

			push @join, { 'tracks' => { 'genreTracks' => 'genre' } };
		}

		$sort = $self->fixupSortKeys($sort);
	}

	# Bug: 2563 - force a numeric compare on an alphanumeric column.
	return $self->search($cond, {
		'order_by' => $sort || "concat('0', me.titlesort), me.disc",
		'distinct' => 'me.id',
		'join'     => \@join,
	});
}

sub descendTrack {
	my $self = shift;
	my $find = shift;
	my $cond = shift;
	my $sort = shift;

	# Create a "clean" resultset, without any joins on it - since we'll
	# just want information from the album.
	my $rs = $self->result_source->resultset;

	# Force a specified sort order right now, since Track's aren't sortable.
	$sort = "concat('0', me.titlesort), tracks.disc, tracks.tracknum, concat('0', tracks.titlesort)";

	my $attr = {
		'order_by' => $sort,
	};

	# Filter by genre if requested.
	if (!preferences('server')->get('noGenreFilter') && defined $find->{'genre.id'}) {

		push @{$attr->{'join'}}, 'genreTracks';
		$cond->{'genreTracks.genre'} = $find->{'genre.id'};
	}

	# Check if contributor.id exists, so that we can only select tracks
	# for the album for that contributor. See Bug: 3558
	if (my $contributor = $find->{'contributor.id'}) {

		if (Slim::Schema->variousArtistsObject->id != $contributor) {

			push @{$attr->{'join'}}, 'contributorTracks';
			$cond->{'contributorTracks.contributor'} = $contributor;
		}
	}

	# Only select tracks for this album or year
	while (my ($key, $value) = each %{$find}) {

		if ($key =~ /^album\.(\w+)$/) {

			$cond->{"me.$1"} = $value;
		}

		if ($key =~ /^(year)\.\w+$/) {

			# we want to filter on the track level, not album level (bug 5748)
			$cond->{"tracks.$1"} = $value;
		}
	}

	return $rs->search_related('tracks', $rs->fixupFindKeys($cond), $attr);
}

1;
