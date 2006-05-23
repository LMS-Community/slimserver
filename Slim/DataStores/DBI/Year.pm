package Slim::DataStores::DBI::Year;

# $Id$

use strict;
use base 'Slim::DataStores::DBI::Album';

use Slim::Utils::Misc;

{
	my $class = __PACKAGE__;

	# Magic to create a ResultSource for this inherited class.
	$class->table($class->table);

	$class->resultset_class('Slim::DataStores::DBI::ResultSet::Year');
}

sub displayAsHTML {
	my ($self, $form, $descend, $sort) = @_;

	$form->{'text'} = $self->year;
}

1;

__END__
