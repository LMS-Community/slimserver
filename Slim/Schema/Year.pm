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

# For saving favorites
sub url {
	my $self = shift;

	return sprintf('album.year://%s', $self->year);
}

sub displayAsHTML {
	my ($self, $form, $descend, $sort) = @_;

	$form->{'text'} = $self->year || string('UNK');

	my $Imports = Slim::Music::Import->importers;

	for my $mixer (keys %{$Imports}) {
	
		if (defined $Imports->{$mixer}->{'mixerlink'}) {
			&{$Imports->{$mixer}->{'mixerlink'}}($self, $form, $descend);
		}
	}
}

1;

__END__
