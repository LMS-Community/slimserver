package Slim::Network::Discovery;

# $Id: Discovery.pm,v 1.8 2003/08/09 19:57:53 kdf Exp $

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use IO::Socket;
use Slim::Utils::Misc;
use Sys::Hostname;

sub serverHostname {
	my $hostname = hostname();
	$hostname = substr $hostname, 0, 16;
	$hostname .= pack('C', 0) x (17 - (length $hostname));
	$::d_protocol && msg(" calculated $hostname\n");	
	return $hostname;
}

# Say hello to a client
#
sub sayHello {
	my $udpsock = shift;
	my $paddr = shift;
	$::d_protocol && msg(" Saying hello!\n");	
	$udpsock->send( 'h'. pack('C', 0) x 17, 0, $paddr);
}


#
# We received a discovery request
#
sub gotDiscoveryRequest {
	my ($udpsock, $clientpaddr, $deviceid, $revision, $mac) = @_;

	$revision=int($revision/16).'.'.($revision%16);

	$::d_protocol && msg(" Got discovery request, deviceid = $deviceid, revision = $revision, MAC = $mac\n");

	my $response;

	if ($deviceid == 1) {
		$::d_protocol && msg("It's a SLIMP3 (note: firmware v2.2 always sends revision of 1.1).\n");
		$response = 'D'. pack('C', 0) x 17; 
	} elsif ($deviceid == 2) {
		$::d_protocol && msg("It's a squeezebox\n");
		$response = 'D'. serverHostname(); 
	} else {
		$::d_protocol && msg("Unknown device.\n");
	}


	$udpsock->send( $response, 0, $clientpaddr);

	$::d_protocol && msg("sent discovery response\n");
}

1;
