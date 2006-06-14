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
	my $sort = shift;

	return $self->search($find, {
		'group_by' => 'me.year',
		'order_by' => 'me.year',
	});
}

sub distinct {
	my $self = shift;

	return $self;
}

sub descendAlbum {
        my $self = shift;
	my $find = shift;

	# Force result_class to be of the Album type. Because Year ISA Album,
	# things are a little whack.
	#return $self->search($find, {
	return Slim::Schema->search('Album', $find, {
		'group_by'     => 'me.id',
		'order_by'     => 'me.titlesort + 0, me.disc',
	});
}

1;
