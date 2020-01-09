package Slim::Schema::GenreTrack;

#
# Genre to track mapping class

use strict;
use base 'Slim::Schema::DBI';

{
	my $class = __PACKAGE__;

	$class->table('genre_track');

	$class->add_columns(qw/genre track/);

	$class->set_primary_key(qw/genre track/);
	$class->add_unique_constraint('genre_track' => [qw/genre track/]);

	$class->belongs_to('genre' => 'Slim::Schema::Genre');
	$class->belongs_to('track' => 'Slim::Schema::Track');
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
