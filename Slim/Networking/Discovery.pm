package Slim::Networking::Discovery;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use IO::Socket;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Network;

my $log = logger('network.protocol');

my $prefs = preferences('server');

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

	if ( $log->is_info ) {
		$log->info(" calculated $hostname length: " . length($hostname));
	}

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

Respond to a discovery request from a client device, sending it the hostname we found.

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

my %TLVhandlers = (
	# Requests
	'NAME' => \&Slim::Utils::Network::hostName,        # send full host name - no truncation
	'IPAD' => sub { $::httpaddr },                     # send ipaddress as a string only if it is set
	'JSON' => sub { $prefs->get('httpport') },         # send port as a string
	# Info only
	'JVID' => sub { $log->is_info && $log->info("Jive: " . join(':', unpack( 'H2H2H2H2H2H2', shift))); return undef; },
);

=head2 gotTLVRequest( $udpsock, $clientpaddr, $msg )

Process TLV based discovery request and send appropriate response.

=cut

sub gotTLVRequest {
	my ($udpsock, $clientpaddr, $msg) = @_;

	use bytes;

	# Discovery request and responses contain TLVs of the format:
	# T (4 bytes), L (1 byte unsigned), V (0-255 bytes)
	# To escape from previous discovery format, request are prepended by 'e', responses by 'E'

	unless ($msg =~ /^e/) {
		$log->warn("bad discovery packet - ignoring");
		return;
	}

	$log->info("discovery packet:");

	# chop of leading character
	$msg = substr($msg, 1);
	
	my $len = length($msg);
	my ($t, $l, $v);
	my $response = 'E';

	# parse TLVs
	while ($len > 0) {
		$t = substr($msg, 0, 4);
		$l = unpack("xxxxC", $msg);
		$v = $l ? substr($msg, 5, $l) : undef;

		$log->debug(" TLV: $t len: $l");

		if ($TLVhandlers{$t}) {
			if (my $r = $TLVhandlers{$t}->($v)) {
				if (length $r > 255) {
					$log->warn("Response: $t too long truncating!");
					$r = substr($r, 0, 255);
				}
				$response .= $t . pack("C", length $r) . $r;
			}
		}

		$msg = substr($msg, $l + 5);
		$len = $len - $l - 5;
	}

	if (length $response > 1450) {
		$log->warn("Response packet too long not sending!");
		return;
	}

	$log->info("sending response");

	$udpsock->send($response, 0, $clientpaddr);
}


=head1 SEE ALSO

L<Slim::Networking::UDP>

L<Slim::Networking::SliMP3::Protocol>

=cut

1;
