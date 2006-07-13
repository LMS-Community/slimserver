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
	my $cond = shift;
	my $sort = shift;

	# Only search for audio
	$cond->{'me.audio'} = 1;

	return $self->search($self->fixupFindKeys($cond), {
		'order_by' => 'me.disc, me.tracknum, me.titlesort',
		'distinct' => 'me.id',
	});
}

# XXX  - These are wrappers around the methods in Slim::Schema, which need to
# be moved here. This is the proper API, and we want to have people using this
# now, and we can migrate the code underneath later.

sub objectForUrl {
	my $self = shift;

	return Slim::Schema->objectForUrl(@_);
}

sub updateOrCreate {
	my $self = shift;

	return Slim::Schema->updateOrCreate(@_);
}

1;
