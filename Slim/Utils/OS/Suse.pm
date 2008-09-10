package Slim::Utils::OS::Suse;

use strict;
use base qw(Slim::Utils::OS::RedHat);

sub initDetails {
	my $class = shift;

	$class->{osDetails} = $class->SUPER::initDetails();

	$class->{osDetails}->{isSuse} = 1;
	
	delete $class->{osDetails}->{isRedHat} if defined $class->{osDetails}->{isRedHat};

	return $class->{osDetails};
}

1;