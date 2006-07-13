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

	my $table = $self->{'attrs'}{'alias'};
	my $name  = "$table.titlesort";

	$self->search(undef, {
		'select'     => [ \"LEFT($name, 1)", { count => \"DISTINCT($table.id)" } ],
		as           => [ 'letter', 'count' ],
		group_by     => \"LEFT($name, 1)",
		result_class => 'Slim::Schema::PageBar',
	});
}

sub alphaPageBar {
	my $self = shift;
	my $cond = shift;
	my $sort = shift;

	return (!defined($sort) || $sort =~ /^contributor|^album/ ) ? 1 : 0;
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

	# The user may not want to include all the composers / conductors
	if (my $roles  = Slim::Schema->artistOnlyRoles) {

		$cond->{'contributorAlbums.role'} = { 'in' => $roles };

		push @join, 'contributorAlbums';
	}

	# if sort includes contributor ensure album contributor is used so all VA albums appear in one place
	if ($sort && $sort =~ /contributor/) {

		# This allows SQL::Abstract to see a scalar
		# reference passed and treat it as literal.
		$cond->{'contributorAlbums.contributor'} = \'= me.contributor';

		push @join, 'contributorAlbums';
	}

	# Bug: 2563 - force a numeric compare on an alphanumeric column.
	return $self->search($cond, {
		'order_by' => $sort || "concat(me.titlesort, '0'), me.disc",
		'distinct' => 'me.id',
		'join'     => \@join,
	});
}

sub descendTrack {
	my $self = shift;
	my $find = shift;
	my $cond = shift;
	my $attr = shift;

	if (!$attr->{'order_by'}) {
		$attr->{'order_by'} = "concat(me.titlesort, '0'), tracks.disc, tracks.tracknum, concat(tracks.titlesort, '0')";
	}

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

	# Only select tracks for this album.
	if (my $album = $find->{'album.id'}) {

		$cond->{'me.id'} = $album;
	}

	# Create a "clean" resultset, without any joins on it - since we'll
	# just want information from the album.
	my $rs = $self->result_source->resultset;

	return $rs->search_related('tracks', $rs->fixupFindKeys($cond), $attr);
}

1;
