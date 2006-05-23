package Slim::Schema::ResultSet::Genre;

# $Id$

use strict;
use base qw(Slim::Schema::ResultSet::Base);

use Slim::Utils::Prefs;

sub pageBarResults {
	my $self = shift;

	my $table = $self->{'attrs'}{'alias'};
	my $name  = "$table.namesort";

	$self->search(undef, {
		'select'     => [ \"LEFT($name, 1)", { count => \"DISTINCT($table.id)" } ],
		as           => [ 'letter', 'count' ],
		group_by     => \"LEFT($name, 1)",
		result_class => 'Slim::Schema::PageBar',
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

	return $self->search_like(
		{ 'me.namesearch' => $terms },
		{ 'order_by' => 'me.namesort', 'distinct' => 'me.id' }
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

	my $roles  = Slim::Schema->artistOnlyRoles;
	my $ctFind = {};

	# The user may not want to include all the composers / conductors
	if ($roles) {

		$ctFind->{'contributorTracks.role'} = { 'in' => $roles };
	}

	# Get our own RS first - then search for related, which builds up a LEFT JOIN query.
	return $self->search($find)
		->search_related('genreTracks')
		->search_related('track')
		->search_related('contributorTracks', $ctFind)
		->search_related('contributor');
}

1;
