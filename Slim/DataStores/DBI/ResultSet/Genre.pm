package Slim::DataStores::DBI::ResultSet::Genre;

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

        return 'BROWSE_BY_GENRE';
}

sub allTitle {
        my $self = shift;

        return 'ALL_GENRES';
}

sub alphaPageBar { 1 }

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

	return $self->search($find, {
		'order_by' => 'me.namesort',
	});
}

sub descendContributor {
	my $self = shift;
	my $find = shift;
	my $role = shift;

	my $roles = {};

	if ($role) {
		$roles->{'contributorTracks.role'} = $role;
	}

	# Get our own RS first - then search for related, which builds up a LEFT JOIN query.
	my $rs = $self->search($find);
	#my $rs = $self->search({ 'me.id' => $id });

	return $rs
		->search_related('genreTracks')
		->search_related('track')
		->search_related('contributorTracks', $roles)
		->search_related('contributor');
}

1;
