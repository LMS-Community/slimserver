package Slim::Networking::Async::Socket::HTTPS;


# Logitech Media Server Copyright 2003-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

BEGIN {
	# Force Net::HTTPS to use IO::Socket::SSL
	use IO::Socket::SSL;
}

use base qw(Net::HTTPS::NB Slim::Networking::Async::Socket);

sub new {
	my ($class, %args) = @_;
	# unfortunately Windows crashes when using non-blocking handshaking, but a timeout occurs
	# let's disable this until somebody has figured out what's wrong with it on Windows - mh
	$args{'Blocking'} = main::ISWINDOWS || 0;
	return $class->SUPER::new(%args);
}

sub close {
	my $self = shift;

	# remove self from select loop
	Slim::Networking::Select::removeError($self);
	Slim::Networking::Select::removeRead($self);
	Slim::Networking::Select::removeWrite($self);
	Slim::Networking::Select::removeWriteNoBlockQ($self);

	$self->SUPER::close();
}

1;
