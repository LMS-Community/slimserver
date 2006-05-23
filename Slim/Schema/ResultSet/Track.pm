package Slim::Schema::ResultSet::Track;

# $Id$

use strict;
use base qw(Slim::Schema::ResultSet::Base);

use Slim::Utils::Prefs;

sub title {
	my $self = shift;

	return 'BROWSE_BY_SONG';
}

sub allTitle {
	my $self = shift;

	return 'ALL_SONGS';
}

sub pageBarResults {
	my $self = shift;

	my $table = $self->{'attrs'}{'alias'};
	my $name  = "$table.titlesort";

	$self->search(undef, {
		'select'     => [ \"LEFT($name, 1)", { count => \"DISTINCT($table.id)" } ],
		as           => [ 'letter', 'count' ],
		group_by     => \"LEFT($name, 1)",
		result_class => 'Slim::Schema::PageBar',
	});
}

sub alphaPageBar {
	my $self = shift;
	my $find = shift;
	my $sort = shift;

	return !exists $find->{'album'};
}

sub ignoreArticles { 1 }

sub searchNames {
	my ($self, $terms) = @_;

	return $self->search({
		'me.titlesearch' => { 'like' => $terms },
		'me.audio'       => 1,
	}, { 'order_by' => 'me.titlesort', 'distinct' => 'me.id' });
}

sub browse {
	my $self = shift;
	my $find = shift;
	my $sort = shift;

	my @join = ();

	if (defined $find->{'playlist'}) {

		my $obj = $self->find($find->{'playlist'}) || return [];

		return [ $obj->tracks ];
	}

	if (Slim::Utils::Prefs::get('noGenreFilter') && defined $find->{'genre'}) {

		if (defined $find->{'album'}) {

			# Don't filter by genre - it's unneccesary and
			# creates a intensive query. We're already at
			# the track level for an album. Same goes for artist.
			delete $find->{'genre'};
			delete $find->{'artist'};
			delete $find->{'contributor_track.role'};

		} elsif (defined($find->{'artist'})) {

			# Don't filter by genre - it's unneccesary and
			# creates a intensive query. We're already at
			# the track level for an artist.
			delete $find->{'genre'};
		}
	}

	# Check to see if our only criteria is an
	# Album. If so, we can simply get the album's tracks.
	if (scalar keys %$find == 1 && defined $find->{'album'}) {

		my $albumObj = Slim::Schema->find('Album', $find->{'album'});

		if ($albumObj && $albumObj->can('tracks')) {

			return [ $albumObj->tracks ];
		}
	}

	# Because we store directories, etc in the tracks table - only pull
	# out items that are 'audio' this is needed because we're using idOnly
	# - so ->find doesn't call ->_includeInTrackCount. That should be able
	# to go away shortly as well.
	$find->{'audio'} = 1;

	return $self->search($find, {
		'order_by' => exists $find->{'album'} ? 'me.disc, me.tracknum, me.titlesort' : 'me.titlesort',
		'distinct' => 'me.id',
		# 'join'     => \@join,
	});

}

1;
