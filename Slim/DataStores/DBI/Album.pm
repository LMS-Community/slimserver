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

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
