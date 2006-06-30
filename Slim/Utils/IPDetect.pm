package Slim::Utils::IPDetect;

# $Id:$

# SlimServer Copyright (c) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# this package determines the IP address of the machine running the
# server.

use strict;
use IO::Socket;
use Slim::Utils::Misc;

my $detectedIP = undef;

# returns ip address of the machine we are running on.
sub IP {

	if (!$detectedIP) { 
		init(); 
	}

	return $detectedIP;
}

sub init {

	my $server = 'www.google.com:80';

	if (!$detectedIP) {

		my $socket = IO::Socket::INET->new(
			'PeerAddr'  => $server,
			'LocalAddr' => $main::localClientNetAddr,
		) or do {

			msg("Failed to detect server IP address. $!\n");
		};

		# Find my half of the connection
		my ($port, $address) = sockaddr_in( (getsockname($socket))[0] );

		$detectedIP = inet_ntoa($address);
	}
}

1;

__END__
