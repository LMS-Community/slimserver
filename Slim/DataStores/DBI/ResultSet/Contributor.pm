package Slim::DataStores::DBI::ResultSet::Contributor;

# $Id$

use strict;
use base qw(Slim::DataStores::DBI::ResultSet::Base);

use Slim::Utils::Prefs;

sub pageBarResults {
	my $self = shift;

	my $name = sprintf('%s.namesort', $self->{'attrs'}{'alias'});

	$self->search(undef, {
		'select'     => [ \"LEFT($name, 1)", { count => \'*' } ],
		as           => [ 'letter', 'count' ],
		group_by     => \"LEFT($name, 1)",
		result_class => 'Slim::DataStores::DBI::PageBar',
	});
}

sub title {
        my $self = shift;

        return 'BROWSE_BY_ARTIST';
}

sub allTitle {
        my $self = shift;

        return 'ALL_ARTISTS';
}

sub alphaPageBar { 1 }
sub ignoreArticles { 1 }

sub searchNames {
	my ($self, $terms) = @_;

	return $self->search(
		{
			'me.namesearch' => { 'like' => $terms },
		},
		{
			'order_by' => 'me.namesort',
			'distinct' => 'me.id',
		}
	);
}

sub browse {
	my $self = shift;
	my $find = shift;
	my $sort = shift;

	my @join = ();

	# The user may not want to include all the composers / conductors
	if ($find->{'roles'}) {

		$find->{'contributorTracks.role'} = delete $find->{'roles'};
	}

	if (Slim::Utils::Prefs::get('variousArtistAutoIdentification') && !$find->{'genre'}) {

		$find->{'albums.compilation'} = 0;

		push @join, 'albums',
	}

	return $self->search($find, {
		'order_by' => 'me.namesort',
		'distinct' => 'me.id',
		'join'     => \@join,
	});
}

sub descendAlbum {
	my $self = shift;
	my $find = shift || {};
	my $sort = shift;

	my @join = ();

	# The user may not want to include all the composers / conductors
	if ($find->{'roles'}) {

		$find->{'contributorAlbums.role'} = delete $find->{'roles'};
	}

	if (Slim::Utils::Prefs::get('variousArtistAutoIdentification') && !$find->{'genre'}) {

		#$find->{'albums.compilation'} = 0;

		push @join, 'albums',
	}

	return $self->search_related('contributorAlbums', $find)->search_related('album');
	#{
		#'order_by' => 'me.namesort',
		#'distinct' => 'me.id',
		#'join'     => \@join,
	#});
}

1;
