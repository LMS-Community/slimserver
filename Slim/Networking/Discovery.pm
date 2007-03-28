package Slim::Networking::Discovery;

# $Id$

# SlimServer Copyright (c) 2001-2006 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use IO::Socket;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Network;

my $log = logger('network.protocol');

=head1 NAME

Slim::Networking::Discovery

=head1 DESCRIPTION

This module implements a UDP discovery protocol, used by Squeezebox, SLIMP3 and Transporter hardware.

=head1 FUNCTIONS

=head2 serverHostname()

Return a 17 character hostname, suitable for display on a client device.

=cut

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

	$log->info(" calculated $hostname length: " . length($hostname));

	return $hostname;
}

=head2 sayHello( $udpsock, $paddr )

Say hello to a client.

Send the client on the other end of the $udpsock a hello packet.

=cut

sub sayHello {
	my ($udpsock, $paddr) = @_;

	$log->info(" Saying hello!");	

	$udpsock->send( 'h'. pack('C', 0) x 17, 0, $paddr);
}

=head2 gotDiscoveryRequest( $udpsock, $clientpaddr, $deviceid, $revision, $mac )

Respond to a response packet from a client device, sending it the hostname we found.

=cut

sub gotDiscoveryRequest {
	my ($udpsock, $clientpaddr, $deviceid, $revision, $mac) = @_;

	$revision = join('.', int($revision / 16), ($revision % 16));

	$log->info("gotDiscoveryRequest: deviceid = $deviceid, revision = $revision, MAC = $mac");

	my $response = undef;

	if ($deviceid == 1) {

		$log->info("It's a SLIMP3 (note: firmware v2.2 always sends revision of 1.1).");

		$response = 'D'. pack('C', 0) x 17; 

	} elsif ($deviceid >= 2 || $deviceid <= 4) {

		$log->info("It's a Squeezebox");

		$response = 'D'. serverHostname(); 

	} else {

		$log->info("Unknown device.");
	}

	$udpsock->send($response, 0, $clientpaddr);

	$log->info("gotDiscoveryRequest: Sent discovery response.");
}

=head1 SEE ALSO

L<Slim::Networking::UDP>

L<Slim::Networking::SliMP3::Protocol>

=cut

1;
