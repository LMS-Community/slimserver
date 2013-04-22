package Slim::Utils::IPDetect;

# $Id:$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use Socket qw(inet_aton inet_ntoa sockaddr_in pack_sockaddr_in PF_INET SOCK_DGRAM INADDR_ANY);
use Symbol;
use Slim::Utils::Log;

my $detectedIP = undef;
my $localhost  = '127.0.0.1';

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

sub IP_port {
	return IP() . ':' . $main::SLIMPROTO_PORT;
}

sub _init {

	if ($detectedIP) {
		return;
	}

	# This code used to try and connect to www.google.com:80 in order to
	# find the local IP address.
	# 
	# Thanks to trick from Bill Fenner, trying to use a UDP socket won't
	# send any packets out over the network, but will cause the routing
	# table to do a lookup, so we can find our address. Don't use a high
	# level abstraction like IO::Socket, as it dies when connect() fails.
	#
	# time.nist.gov - though it doesn't really matter.
	my $raddr = '192.43.244.18';
	my $rport = 123;

	my $proto = (getprotobyname('udp'))[2];
	my $pname = (getprotobynumber($proto))[0];
	my $sock  = Symbol::gensym();

	my $iaddr = inet_aton($raddr) || do {

		logWarning("Couldn't call inet_aton($raddr) - falling back to $localhost");

		$detectedIP = $localhost;

		return;
	};

	my $paddr = sockaddr_in($rport, $iaddr);

	socket($sock, PF_INET, SOCK_DGRAM, $proto) || do {

		logWarning("Couldn't call socket(PF_INET, SOCK_DGRAM, \$proto) - falling back to $localhost");

		$detectedIP = $localhost;

		return;
	};

	if ($main::localClientNetAddr && $main::localClientNetAddr =~ /^[\d\.]+$/) {

		my $laddr = inet_aton($main::localClientNetAddr) || INADDR_ANY;

		bind($sock, pack_sockaddr_in(0, $laddr)) or do {

			logWarning("Couldn't call bind(pack_sockaddr_in(0, \$laddr) - falling back to $localhost");

			$detectedIP = $localhost;

			return;
		};
	}

	connect($sock, $paddr) || do {

		logWarning("Couldn't call connect() - falling back to $localhost");

		$detectedIP = $localhost;

		return;
	};

	# Find my half of the connection
	my ($port, $address) = sockaddr_in( (getsockname($sock))[0] );

	$detectedIP = inet_ntoa($address);
}

1;

__END__
