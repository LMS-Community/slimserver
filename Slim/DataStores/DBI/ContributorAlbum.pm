package Slim::DataStores::DBI::ContributorAlbum;

# $Id$
#
# Contributor to album mapping class

use strict;
use base 'Slim::DataStores::DBI::DataModel';

{
	my $class = __PACKAGE__;

	$class->table('contributor_album');

	$class->columns(Primary => qw/role contributor album/);

	$class->has_a(contributor => 'Slim::DataStores::DBI::Contributor');
	$class->has_a(album       => 'Slim::DataStores::DBI::Album');

	$class->add_constructor('contributorsForAlbumAndRole' => 'album = ? AND role = ?');
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
