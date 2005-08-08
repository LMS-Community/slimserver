package Slim::DataStores::DBI::Comment;

# $Id$

use strict;
use base 'Slim::DataStores::DBI::DataModel';

{
	my $class = __PACKAGE__;

	$class->table('comments');

	$class->columns(Primary => qw/id/);

	$class->columns(Essential => qw/track value/);

	$class->has_a(track => 'Slim::DataStores::DBI::Track');

	$class->add_constructor('commentsOf' => 'track = ?');
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
