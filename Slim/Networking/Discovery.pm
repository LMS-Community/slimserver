package Slim::Network::Discovery;

# $Id: Discovery.pm,v 1.2 2003/07/24 23:14:04 dean Exp $

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
	$udpsock->send( 'h'. serverHostname(), 0, $paddr);
}

#
# send the discovery response
#
sub sendDiscoveryResponse {
	my $udpsock = shift;
	my $clientpaddr = shift;

	my $response = 'D'. serverHostname();
	
	$::d_protocol && msg(" send discovery response\n");

	$udpsock->send( $response, 0, $clientpaddr);
}

#
# We received a discovery request
#
sub gotDiscoveryRequest {
	my $udpsock = shift;
	my $clientpaddr = shift;

	$::d_protocol && msg(" Got discovery request\n");
	&sendDiscoveryResponse($udpsock, $clientpaddr);
}

1;
