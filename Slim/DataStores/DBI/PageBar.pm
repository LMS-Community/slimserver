package Slim::DataStores::DBI::PageBar;

use strict;
use base qw(DBIx::Class::Core);

{
	my $class = __PACKAGE__;

	$class->register_column($_) for qw(letter count);
}

1;
