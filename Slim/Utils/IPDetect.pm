package Slim::Utils::IPDetect;

# $Id:$

# SlimServer Copyright (c) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use IO::Socket;
use Slim::Utils::Misc;

my $detectedIP = undef;

=head1 NAME

Slim::Utils::IPDetect

=head1 SYNOPSIS

my $detectedIP = IP()

=head1 DESCRIPTION

Determines the IP address of the machine running the server.

=head1 METHODS

=head2 IP()

Returns IP address of the machine we are running on.

=head1 SEE ALSO

L<IO::Socket>

=cut

sub IP {

	if (!$detectedIP) { 
		_init(); 
	}

	return $detectedIP;
}

sub _init {

	my $server = 'www.google.com:80';

	if (!$detectedIP) {

		my $socket = IO::Socket::INET->new(
			'PeerAddr'  => $server,
			'LocalAddr' => $main::localClientNetAddr,
		) or do {

			errorMsg("Failed to detect server IP address. $!\n");
			return;
		};

		# Find my half of the connection
		my ($port, $address) = sockaddr_in( (getsockname($socket))[0] );

		$detectedIP = inet_ntoa($address);
	}
}

1;

__END__
