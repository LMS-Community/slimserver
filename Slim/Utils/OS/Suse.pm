package Slim::Utils::OS::Suse;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

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
