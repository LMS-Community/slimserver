package Slim::Schema::ResultSet::Contributor;

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

	my @joins = ();
	my $find  = {
		'me.namesearch' => { 'like' => $terms },
	};

	# Bug: 2479 - Don't include roles if the user has them unchecked.
	if (my $roles = Slim::Schema->artistOnlyRoles) {

		$find->{'contributorAlbums.role'} = { 'in' => $roles };
		push @joins, 'contributorAlbums';
	}

	return $self->search($find, {
		'order_by' => 'me.namesort',
		'distinct' => 'me.id',
		'join'     => \@joins,
	});
}

sub browse {
	my $self = shift;
	my $find = shift;
	my $sort = shift;

	my @joins = ();
	my $roles = Slim::Schema->artistOnlyRoles;

	# The user may not want to include all the composers / conductors
	if ($roles) {

		$find->{'contributorAlbums.role'} = { 'in' => $roles };
	}

	if (Slim::Utils::Prefs::get('variousArtistAutoIdentification')) {

		$find->{'album.compilation'} = [ { 'is' => undef }, { '=' => 0 } ];

		push @joins, { 'contributorAlbums' => 'album' };

	} elsif ($roles) {

		push @joins, 'contributorAlbums';
	}

	return $self->search($find, {
		'order_by' => 'me.namesort',
		'group_by' => 'me.id',
		'join'     => \@joins,
	});
}

sub descendAlbum {
	my ($self, $find) = @_;

	return $self
		->search_related('contributorAlbums', $find)
		->search_related('album', {}, { 'order_by' => 'album.titlesort, album.disc' });
}

1;
