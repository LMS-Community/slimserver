package Slim::DataStores::DBI::ResultSet::Age;

# $Id$

use strict;
use base qw(Slim::DataStores::DBI::ResultSet::Base);

use Slim::Utils::Prefs;

sub title {
	my $self = shift;

	return 'BROWSE_NEW_MUSIC';
}

sub allTitle {
	my $self = shift;

	return 'ALL_ALBUMS';
}

sub browse {
	my $self = shift;
	my $find = shift;
	my $sort = shift;

	return $self->search($find, {
		'order_by' => 'tracks.timestamp desc, tracks.disc, tracks.tracknum, tracks.titlesort',
		'join'     => 'tracks',
		'limit'    => Slim::Utils::Prefs::get('browseagelimit'),
	});
}

sub descendTrack {
        my $self = shift;

        return $self->search_related('tracks', @_);
}

1;
