package Slim::Networking::Discovery;

# $Id$

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This module implements a UDP discovery protocol, used by all Slim Devices hardware.

use strict;
use IO::Socket;

use Slim::Utils::Misc;
use Slim::Utils::Network;

sub serverHostname {
	my $hostname = Slim::Utils::Network::hostName();

	# may return several lines of hostnames, just take the first.	
	$hostname =~ s/\n.*//;

	# may return a dotted name, just take the first part
	$hostname =~ s/\..*//;

	# just take the first 16 characters, since that's all the space we have 
	$hostname = substr $hostname, 0, 16;

	# pad it out to 17 characters total
	$hostname .= pack('C', 0) x (17 - (length $hostname));

	$::d_protocol && msg(" calculated $hostname length: " . length($hostname) . "\n");	

	return $hostname;
}

# Say hello to a client
sub sayHello {
	my ($udpsock, $paddr) = @_;

	$::d_protocol && msg(" Saying hello!\n");	

	$udpsock->send( 'h'. pack('C', 0) x 17, 0, $paddr);
}

# We received a discovery request
sub gotDiscoveryRequest {
	my ($udpsock, $clientpaddr, $deviceid, $revision, $mac) = @_;

	$revision = join('.', int($revision / 16), ($revision % 16));

	$::d_protocol && msg("gotDiscoveryRequest: deviceid = $deviceid, revision = $revision, MAC = $mac\n");

	my $response = undef;

	if ($deviceid == 1) {

		$::d_protocol && msg("It's a SLIMP3 (note: firmware v2.2 always sends revision of 1.1).\n");

		$response = 'D'. pack('C', 0) x 17; 

	} elsif ($deviceid >= 2 || $deviceid <= 4) {

		$::d_protocol && msg("It's a Squeezebox\n");

		$response = 'D'. serverHostname(); 

	} else {

		$::d_protocol && msg("Unknown device.\n");
	}

	$udpsock->send($response, 0, $clientpaddr);

	$::d_protocol && msg("gotDiscoveryRequest: Sent discovery response.\n");
}

1;
