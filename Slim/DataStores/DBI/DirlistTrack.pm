package Slim::DataStores::DBI::DirlistTrack;

# $Id$
#
# Directory to track mapping class

use strict;
use base 'Slim::DataStores::DBI::DataModel';

{
	my $class = __PACKAGE__;

	$class->table('dirlist_track');

	$class->columns(Primary => qw/id/);

	$class->columns(Essential => qw/position dirlist item/);

	$class->has_a(dirlist => 'Slim::DataStores::DBI::Track');
	$class->has_a(item => 'Slim::DataStores::DBI::LightWeightTrack');

	$class->add_constructor('tracksOf' => 'dirlist = ? ORDER BY position');

	$class->set_sql('deleteDirItems' => 'DELETE FROM __TABLE__ WHERE dirlist = ?');
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
