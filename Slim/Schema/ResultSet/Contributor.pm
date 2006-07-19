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
	my $cond  = {
		'me.namesearch' => { 'like' => $terms },
	};

	# Bug: 2479 - Don't include roles if the user has them unchecked.
	if (my $roles = Slim::Schema->artistOnlyRoles) {

		$cond->{'contributorAlbums.role'} = { 'in' => $roles };
		push @joins, 'contributorAlbums';
	}

	return $self->search($cond, {
		'order_by' => 'me.namesort',
		'distinct' => 'me.id',
		'join'     => \@joins,
	});
}

sub browse {
	my $self = shift;
	my $find = shift;
	my $cond = shift;
	my $sort = shift;

	my @joins = ();
	my $roles = Slim::Schema->artistOnlyRoles;

	# The user may not want to include all the composers / conductors
	if ($roles) {

		$cond->{'contributorAlbums.role'} = { 'in' => $roles };
	}

	if (Slim::Utils::Prefs::get('variousArtistAutoIdentification')) {

		$cond->{'album.compilation'} = [ { 'is' => undef }, { '=' => 0 } ];

		push @joins, { 'contributorAlbums' => 'album' };

	} elsif ($roles) {

		push @joins, 'contributorAlbums';
	}

	return $self->search($cond, {
		'order_by' => 'me.namesort',
		'group_by' => 'me.id',
		'join'     => \@joins,
	});
}

sub descendAlbum {
	my ($self, $find, $cond, $sort) = @_;

	# Create a clean resultset
	my $rs     = $self->result_source->resultset;
	my $attr   = {
		'order_by' => "concat('0', album.titlesort), album.disc",
	};

	if (my $roles = Slim::Schema->artistOnlyRoles) {

		$cond->{'contributorAlbums.role'} = { 'in' => $roles };
	}

	# Bug: 2192 - Don't filter out compilation
	# albums at the artist level - we want to see all of them for an artist.
	if ($cond->{'me.id'} && $find->{'album.compilation'} && $find->{'album.compilation'} != 1) {

		# $cond->{'album.compilation'} = $find->{'album.compilation'};
	}

	$rs = $rs->search_related('contributorAlbums', $rs->fixupFindKeys($cond));

	# Constrain on the genre if it exists.
	if (my $genre = $find->{'genre.id'}) {

		$attr->{'join'} = { 'tracks' => 'genreTracks' };

		$rs = $rs->search_related('album', { 'genreTracks.genre' => $genre }, $attr);

	} else {

		$rs = $rs->search_related('album', {}, $attr);
	}

	return $rs
}

1;
