package Slim::DataStores::DBI::Comment;

# $Id$

use strict;
use base 'Slim::DataStores::DBI::DataModel';

{
	my $class = __PACKAGE__;

	$class->table('comments');

	$class->columns(Primary => qw/id/);

	$class->columns(Essential => qw/track value/);

	$class->columns(UTF8 => qw/value/);

	$class->has_a(track => 'Slim::DataStores::DBI::Track');
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
