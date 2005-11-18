package Slim::DataStores::DBI::GenreTrack;

# $Id$
#
# Genre to track mapping class

use strict;
use base 'Slim::DataStores::DBI::DataModel';

{
	my $class = __PACKAGE__;

	$class->table('genre_track');

	$class->columns(Primary => qw/id/);

	$class->columns(Essential => qw/genre track/);

	$class->has_a(genre => 'Slim::DataStores::DBI::Genre');
	$class->has_a(track => 'Slim::DataStores::DBI::Track');
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
