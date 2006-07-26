package Slim::Schema::ResultSet::Year;

# $Id$

use strict;
use base qw(Slim::Schema::ResultSet::Base);

use Slim::Utils::Prefs;

sub title {
	my $self = shift;

	return 'BROWSE_BY_YEAR';
}

sub allTitle {
	my $self = shift;

	return '';
}

sub browse {
	my $self = shift;
	my $find = shift;
	my $cond = shift;
	my $sort = shift || 'me.id';

	return $self->search($cond, {
		'order_by' => $sort,
	});
}

sub distinct {
	my $self = shift;

	return $self;
}

sub descendAlbum {
	my $self = shift;
	my $find = shift;
	my $cond = shift;
	my $sort = shift;

	# Force result_class to be of the Album type. Because Year ISA Album,
	# things are a little whack.
	return $self->search_related('albums', $cond, { 'order_by' => "concat('0', albums.titlesort), albums.disc" });
}

1;
