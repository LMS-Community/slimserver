package Slim::DataStores::DBI::DirlistTrack;

# $Id: DirlistTrack.pm,v 1.1 2004/12/17 20:33:03 dsully Exp $
#
# Directory to track mapping class

use strict;
use base 'Slim::DataStores::DBI::DataModel';

{
	my $class = __PACKAGE__;

	$class->table('dirlist_track');
	$class->columns(Essential => qw/id position dirlist item/);

	$class->has_a(dirlist => 'Slim::DataStores::DBI::Track');

	$class->add_constructor('tracksOf' => 'dirlist = ? ORDER BY position');
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
