package Slim::DataStores::DBI::GenreTrack;

# $Id$
#
# Genre to track mapping class

use strict;
use base 'Slim::DataStores::DBI::DataModel';

INIT: {
	my $class = __PACKAGE__;

	$class->table('genre_track');

	$class->add_columns(qw/genre track/);

	$class->set_primary_key(qw/genre track/);

	$class->belongs_to('genre' => 'Slim::DataStores::DBI::Genre');
	$class->belongs_to('track' => 'Slim::DataStores::DBI::Track');
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
