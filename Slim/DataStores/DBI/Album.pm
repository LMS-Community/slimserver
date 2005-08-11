package Slim::DataStores::DBI::Album;

# $Id$

use strict;
use base 'Slim::DataStores::DBI::DataModel';

{
	my $class = __PACKAGE__;

	$class->table('albums');

	$class->columns(Primary => qw/id/);

	$class->columns(Essential => qw/title titlesort contributor compilation year artwork_path disc discc musicmagic_mixable/);

	$class->columns(Others    => qw/titlesearch/);

	$class->columns(Stringify => qw/title/);

	$class->has_a(contributor => 'Slim::DataStores::DBI::Contributor');

	# This has the same sort order as %DataModel::sortFieldMap{'album'}
	$class->add_constructor('hasArtwork' => 'artwork_path IS NOT NULL ORDER BY titlesort, disc');

	$class->has_many(tracks => 'Slim::DataStores::DBI::Track', { order_by => 'tracknum'});
}

# Update the title dynamically if we're part of a set.
sub title {
	my $self = shift;

	if (Slim::Utils::Prefs::get('groupdiscs')) {

		return $self->get('title');
	}

	return Slim::Music::Info::addDiscNumberToAlbumTitle( $self->get(qw(title disc discc)) );
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
