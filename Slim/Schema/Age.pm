package Slim::Schema::Age;

# $Id$

use strict;
use base 'Slim::Schema::Album';

use Slim::Utils::Misc;

{
	my $class = __PACKAGE__;

	# Magic to create a ResultSource for this inherited class.
	$class->table($class->table);

	$class->resultset_class('Slim::Schema::ResultSet::Age');
}

1;

__END__
