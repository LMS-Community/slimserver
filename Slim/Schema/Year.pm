package Slim::Schema::Year;

# $Id$

use strict;
use base 'Slim::Schema::Album';

use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

{
	my $class = __PACKAGE__;

	# Magic to create a ResultSource for this inherited class.
	$class->table($class->table);

	$class->resultset_class('Slim::Schema::ResultSet::Year');
}

sub displayAsHTML {
	my ($self, $form, $descend, $sort) = @_;

	$form->{'text'} = $self->year || string('UNK');
}

1;

__END__
