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

sub searchColumn {
	my $self  = shift;

	return 'namesearch';
}

sub searchNames {
	my $self  = shift;
	my $terms = shift;
	my $attrs = shift || {};

	$attrs->{'order_by'} ||= 'me.namesort';
	$attrs->{'distinct'} ||= 'me.id';

	return $self->search({ 'me.namesearch' => { 'like' => $terms } }, $attrs);
}

sub browse {
	my $self = shift;
	my $find = shift;
	my $cond = shift;
	my $sort = shift;

	return $self->search($cond, { 'order_by' => 'me.namesort' });
}

sub descendContributor {
	my $self = shift;
	my $find = shift;
	my $cond = shift;
	my $sort = shift;

	# Get our own RS first - then search for related, which builds up a LEFT JOIN query.
	my $rs   = $self->search($cond)->search_related('genreTracks');

	# If we are automatically identifiying VA albums, constrain the query.
	if (preferences('server')->get('variousArtistAutoIdentification')) {

		$rs = $rs->search_related('track', {
			'album.compilation' => [ { 'is' => undef }, { '=' => 0 } ]
		}, { 'join' => 'album' });

	} else {

		$rs = $rs->search_related('track');
	}

	# The user may not want to include all the composers / conductors
	if (my $roles = Slim::Schema->artistOnlyRoles) {

		$rs = $rs->search_related('contributorTracks', { 'contributorTracks.role' => { 'in' => $roles } });

	} else {

		$rs = $rs->search_related('contributorTracks');
	}

	return $rs->search_related('contributor', {}, { 'order_by' => $sort || 'contributor.namesort' });
}

1;
