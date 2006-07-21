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

	# pagebar based on contibutors if first sort field and results already sorted by this
	if ($sort && $sort =~ /^contributor\.namesort/ && $self->{'attrs'}{'order_by'}[0] =~ /contributor\.namesort/) {
		$name  = "contributor.namesort";
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

	return (!defined($sort) || $sort =~ /^(?:contributor\.namesort|album\.titlesort)/ ) ? 1 : 0;
}

sub ignoreArticles {
	my $self = shift;

	return 1;
}

sub searchNames {
	my ($self, $terms) = @_;

	return $self->search(
		{ 'me.titlesearch' => { 'like' => $terms } },
		{ 'order_by' => 'me.titlesort, me.disc', 'distinct' => 'me.id' }
	);
}

sub browse {
	my $self = shift;
	my $find = shift;
	my $cond = shift;
	my $sort = shift;

	my @join = ();
	my $roles = Slim::Schema->artistOnlyRoles;

	# The user may not want to include all the composers / conductors
	if ($roles) {

		$cond->{'contributorAlbums.role'} = { 'in' => $roles };

		push @join, 'contributorAlbums';
	}

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

			# Only join contributorAlbums once.
			if (!$roles) {
				push @join, { 'contributorAlbums' => 'contributor' };
			} else {
				push @join, 'contributor';
			}
		}

		if ($sort =~ /genre/) {

			push @join, { 'tracks' => { 'genreTracks' => 'genre' } };
		}

		# Turn all occurences of album into me, since this is an Album RS
		$sort =~ s/(album)\./me./g;
		$sort =~ s/(\w+?.\w+?sort)/concat('0', $1)/g;

		# Always append disc
		if ($sort !~ /me\.disc/) {
			$sort .= ', me.disc';
		}
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

	if (!$sort) {
		$sort = "concat('0', me.titlesort), tracks.disc, tracks.tracknum, concat('0', tracks.titlesort)";
	}

	my $attr = {
		'order_by' => $sort,
	};

	# Filter by genre if requested.
	if (!Slim::Utils::Prefs::get('noGenreFilter') && defined $find->{'genre.id'}) {

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
	}

	# Create a "clean" resultset, without any joins on it - since we'll
	# just want information from the album.
	my $rs = $self->result_source->resultset;

	return $rs->search_related('tracks', $rs->fixupFindKeys($cond), $attr);
}

1;
