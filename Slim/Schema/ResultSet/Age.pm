package Slim::Schema::ResultSet::Age;

# $Id$

use strict;
use base qw(Slim::Schema::ResultSet::Album);

use Slim::Utils::Prefs;

sub title {
	my $self = shift;

	return 'BROWSE_NEW_MUSIC';
}

sub allTitle {
	my $self = shift;

	return 'ALL_ALBUMS';
}

sub pageBarResults     { 0 }
sub alphaPageBar       { 0 }
sub ignoreArticles     { 0 }

sub browse {
	my $self = shift;
	my $find = shift;
	my $cond = shift;
	my $sort = shift;

	return $self->search($cond, {
		'order_by' => 'tracks.timestamp desc, tracks.disc, tracks.tracknum, tracks.titlesort',
		'join'     => 'tracks',
		'limit'    => (preferences('server')->get('browseagelimit') - 1),
	});
}

1;
