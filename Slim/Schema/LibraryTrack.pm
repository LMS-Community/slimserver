package Slim::Schema::LibraryTrack;

# Library to track mapping class

use strict;
use base 'Slim::Schema::DBI';

{
	my $class = __PACKAGE__;

	$class->table('library_track');

	$class->add_columns(qw/library track/);

	$class->set_primary_key(qw/track library/);

#	$class->belongs_to('library' => 'Slim::Schema::Library');
	$class->belongs_to('track'   => 'Slim::Schema::Track');
}

1;

__END__
