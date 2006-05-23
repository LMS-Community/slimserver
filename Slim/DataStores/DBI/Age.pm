package Slim::DataStores::DBI::Age;

# $Id$

use strict;
use base 'Slim::DataStores::DBI::Album';

use Slim::Utils::Misc;

{
	my $class = __PACKAGE__;

	# Magic to create a ResultSource for this inherited class.
	$class->table($class->table);

	$class->resultset_class('Slim::DataStores::DBI::ResultSet::Age');
}

1;

__END__
