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
	my $find = shift;
	my $sort = shift;

	return (!defined($sort) || $sort =~ /^artist|^album/ ) ? 1 : 0;
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
	my $sort = shift;

	my @join = ();

	# The user may not want to include all the composers / conductors
	if ($find->{'roles'}) {

		$find->{'contributorAlbums.role'} = delete $find->{'roles'};

		push @join, 'contributorAlbums';
	}


	if (defined $find->{'genre.id'}) {
		
		# We want to filter albums by genre
		
		if (Slim::Utils::Prefs::get('noGenreFilter') && defined $find->{'contributor.id'}) {

			# Don't filter by genre - it's unneccesary and
			# creates a intensive query. We're already at
			# the album level for an artist
			delete $find->{'genre.id'};
		}
		else {
			# join genres
			push @join, {'tracks' => {'genreTracks' => 'genre'}};
		}
	}

	# Bug: 2192 - Don't filter out compilation
	# albums at the artist level - we want to see all of them for an artist.
	if ($find->{'contributor.id'} && $find->{'album.compilation'} != 1) {

		delete $find->{'album.compilation'};
	}

	# if sort includes artist ensure album contributor is used so all VA albums appear in one place
	if ($sort && $sort =~ /artist/) {

		# This allows SQL::Abstract to see a scalar
		# reference passed and treat it as literal.
		$find->{'contributors.id'} = \'= albums.contributor';

		push @join, 'contributors';
	}

	if ($sort && $sort =~ /^(\w+)\./) {
		push @join, $1;
	}

	# Bug: 2563 - force a numeric compare on an alphanumeric column.
	# Not sure if we need this logic anywhere else..
	return $self->search($find, {
		'order_by' => $sort || 'concat(me.titlesort, \'0\'), me.disc',
		'distinct' => 'me.id',
		'join'     => \@join,
	});
}

sub descendTrack {
	my $self = shift;
	my $find = shift;
	my $attr = shift;

	if (!$attr->{'order_by'}) {
		$attr->{'order_by'} = 'tracks.disc, tracks.tracknum, tracks.titlesort';
	}

	# XXXX - Go through some contortions to get the previous level's id -
	# the contributor.id if it exists, so that we can only select tracks
	# for the album for that contributor. See Bug: 3558
	if (ref($self->{'attrs'}{'where'}) eq 'HASH' && exists $self->{'attrs'}{'where'}->{'-and'}) {

		my $and = $self->{'attrs'}{'where'}->{'-and'};

		if (ref($and) eq 'ARRAY' && ref($and->[1]) eq 'HASH' && exists $and->[1]->{'me.id'}) {

			$attr->{'join'} = 'contributorTracks';
			$find->{'contributorTracks.contributor'} = $and->[1]->{'me.id'};
		}
	}

	# Create a "clean" resultset, without any joins on it - since we'll
	# just want information from the album.
	my $rs   = $self->result_source->resultset;

	return $rs->search_related('tracks', $rs->fixupFindKeys($find), $attr);

	# return $self->search_related('tracks', @_);
}

1;
