package Slim::DataStores::DBI::Album;

# $Id$

use strict;
use base 'Slim::DataStores::DBI::DataModel';

{
	my $class = __PACKAGE__;

	$class->table('albums');

	$class->columns(Essential => qw/id title titlesort contributors artwork_path disc discc musicmagic_mixable/);

	$class->columns(Stringify => qw/title/);

	$class->add_constructor('hasArtwork' => 'artwork_path IS NOT NULL');

	$class->has_many(tracks => 'Slim::DataStores::DBI::Track', { order_by => 'tracknum'});
}

tie my %_cache, 'Tie::Cache::LRU', 5000;

sub searchTitle {
	my $class   = shift;
	my $pattern = shift;

	s/\*/%/g for @$pattern;

	my %where   = ( titlesort => $pattern, );
	my $findKey = join(':', @$pattern);

	$_cache{$findKey} ||= [ $class->searchPattern('albums', \%where, ['titlesort']) ];

	return wantarray ? @{$_cache{$findKey}} : $_cache{$findKey}->[0];
}

sub contributors {
	my $self = shift;
	my @contributors = @_;

	# Setter case
	if (scalar @contributors > 0) {

		# Take the contributors that were passed in directly.
		my %contributorMap = map { $_->id, 1 } @contributors;

		# Merge in any previous contributors
		for my $id (split /:/, $self->get('contributors')) {

			$contributorMap{$id} = 1;
		}

		# Set them all back.
		$self->set('contributors', join(':', sort { $a <=> $b } keys %contributorMap));

	} else {

		# and getters
		for my $id (split /:/, $self->get('contributors')) {

			push @contributors, Slim::DataStores::DBI::Contributor->retrieve($id);
		}
	}

	return @contributors;
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
