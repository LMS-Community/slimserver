package Slim::Networking::UDP;

# $Id$

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This module implements a UDP discovery protocol, used by all Slim Devices hardware.

use strict;
use IO::Socket;

use Slim::Networking::Discovery;
use Slim::Networking::Select;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::Prefs;

# IANA-assigned port for the Slim protocol, used by all Slim Devices hardware.
use constant SERVERPORT => 3483;

my $udpsock = undef;

sub init {

	#my $udpsock = IO::Socket::INET->new(
	$udpsock = IO::Socket::INET->new(
		Proto     => 'udp',
		LocalPort => SERVERPORT,
		LocalAddr => $main::localClientNetAddr

	) or do {

		errorMsg("There is already another copy of the SlimServer running on this machine. ($!)\n");
		# XXX - exiting in a deep sub is kinda bad. should propagate
		# up. Too bad perl doesn't have real exceptions.
		exit 1;
	};
	
	defined(Slim::Utils::Network::blocking($udpsock, 0)) || do { 

		errorMsg("Discovery init: Cannot set port nonblocking\n");
		die;
	};

	Slim::Networking::Select::addRead($udpsock, \&readUDP);
	
	# say hello to the old slimp3 clients that we might remember...
	for my $clientID (Slim::Utils::Prefs::getKeys('clients')) {

		# make sure any new preferences get set to default values
		assert($clientID);

		# skip client addrs that aren't dotted-4 with a port
		next if $clientID !~ /\d+\.\d+\.\d+\.\d+:\d+/;

		$::d_protocol && msg("Discovery init: Saying hello to $clientID\n");

		Slim::Networking::Discovery::sayHello($udpsock, Slim::Utils::Network::ipaddress2paddr($clientID));
		
		# throttle the broadcasts
		select(undef, undef, undef, 0.05);
	}
}

sub readUDP {
	my $sock = shift || $udpsock;
	my $clientpaddr;
	my $msg = '';

	do {
		$clientpaddr = recv($sock, $msg, 1500, 0);
		
		if ($clientpaddr) {

			# check that it's a message type we know: starts with i r 2 d a or h (but not h followed by 0x00 0x00)
			# These are SliMP3 packets.
			if ($msg =~ /^(?:[ir2a]|h(?!\x00\x00))/) {

				if (!$Slim::Player::SLIMP3::SLIMP3Connected) {

					Slim::bootstrap::tryModuleLoad('Slim::Networking::SliMP3::Protocol');
				}

				my $client = Slim::Networking::SliMP3::Protocol::getUdpClient($clientpaddr, $sock, $msg) || return;
	
				Slim::Networking::SliMP3::Protocol::processMessage($client, $msg);
	
			} elsif ($msg =~/^d/) {

				# Discovery request: note that SliMP3 sends deviceid and revision in the discovery
				# request, but the revision is wrong (v 2.2 sends revision 1.1). Oops. 
				# also, it does not send the MAC address until the [h]ello packet.
				# Squeezebox sends all fields correctly.
				#
				# All Slim Devices hardware sends discovery packets
	
				my ($msgtype, $deviceid, $revision, @mac) = unpack 'axCCxxxxxxxxH2H2H2H2H2H2', $msg;

				Slim::Networking::Discovery::gotDiscoveryRequest($sock, $clientpaddr, $deviceid, $revision, join(':', @mac));
	
			} else {

				if ($::d_protocol) {
					my ($clientport, $clientip) = sockaddr_in($clientpaddr);
					msg("ignoring Client: ".inet_ntoa($clientip).":$clientport that sent bogus message $msg\n");
				}
			}
		}

	} while $clientpaddr;
}

1;
