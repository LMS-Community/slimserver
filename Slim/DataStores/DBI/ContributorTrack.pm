package Slim::DataStores::DBI::ContributorTrack;

# $Id$
#
# Contributor to track mapping class

use strict;
use base 'Slim::DataStores::DBI::DataModel';

{
	my $class = __PACKAGE__;

	$class->table('contributor_track');

	$class->columns(Primary => qw/role contributor track/);

	$class->has_a(contributor => 'Slim::DataStores::DBI::Contributor');
	$class->has_a(track => 'Slim::DataStores::DBI::Track');

	$class->add_constructor('contributorsForTrackAndRole' => 'track = ? AND role = ?');
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
