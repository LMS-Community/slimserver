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

sub descendAlbum {
	my $self = shift;
	my $find = shift;
	my $cond = shift;
	my $sort = shift;

	# Create a clean resultset
	my $rs = $self->result_source->resultset;

	# Handle sorts from the web UI.
	$sort ||= "concat('0', album.titlesort), album.disc";

	my @join;

	if ($sort =~ /contributor/) {

		push @join, 'contributor';
	}

	if ($sort =~ /genre/) {

		push @join, { 'tracks' => { 'genreTracks' => 'genre' } };
	}

	$sort = $self->fixupSortKeys($sort);

	return $self->search_related('album', $cond, { 'join' => \@join, 'order_by' => $sort });
}

1;
