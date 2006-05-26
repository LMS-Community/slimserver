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

	return $self->search_like(
		{ 'me.titlesearch' => $terms },
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

	if (Slim::Utils::Prefs::get('noGenreFilter') && defined $find->{'genre'} && defined $find->{'artist'}) {

		# Don't filter by genre - it's unneccesary and
		# creates a intensive query. We're already at
		# the album level for an artist
		delete $find->{'genre'};
	}

	# Bug: 2192 - Don't filter out compilation
	# albums at the artist level - we want to see all of them for an artist.
	if ($find->{'artist'} && !$find->{'album.compilation'}) {

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

	#print "XXXX - in Album sort: [$sort]\n";
	#print Data::Dumper::Dumper($find);

	return $self->search($find, {
		'order_by' => $sort || 'me.titlesort, me.disc',
		'distinct' => 'me.id',
		'join'     => \@join,
	});
}

sub descendTrack {
	my $self = shift;
	my $find = shift;
	my $attr = shift;

	# Create a "clean" resultset, without any joins on it - since we'll
	# just want information from the album.
	my $rs   = $self->result_source->resultset;

	return $rs->search_related('tracks', $rs->fixupFindKeys($find), $attr);

	# return $self->search_related('tracks', @_);
}

1;
