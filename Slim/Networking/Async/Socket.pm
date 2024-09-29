package Slim::Networking::Async::Socket;


# Logitech Media Server Copyright 2003-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# A base class for all sockets

use strict;

# store data within the socket
sub set {
	my ( $self, $key, $val ) = @_;

	${*$self}{$key} = $val;
}

# pull data out of the socket
sub get {
	my ( $self, $key ) = @_;

	return ${*$self}{$key};
}

1;
