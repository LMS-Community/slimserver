package Slim::Player::Controller;

# SqueezeCenter Copyright (c) 2001-2008 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use vars qw(@ISA);

BEGIN {
	if ( main::SLIM_SERVICE ) {
		require SDI::Service::Player::SqueezeNetworkClient;
		push @ISA, qw(SDI::Service::Player::SqueezeNetworkClient);
	}
	else {
		require Slim::Player::Squeezebox2;
		push @ISA, qw(Slim::Player::SqueezePlay);
	}
}

sub model     { 'controller' }
sub modelName { 'Controller' }

1;

__END__
