package Slim::Networking::UDP;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This module implements a UDP discovery protocol, used by Squeezebox, Transporter and SLIMP3 hardware.

use strict;
use IO::Socket;

use Slim::Networking::Discovery;
use Slim::Networking::Discovery::Server;
use Slim::Networking::Discovery::Players;
use Slim::Networking::Select;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::Prefs;

# IANA-assigned port for the Slim protocol, used by all Slim Devices hardware.
use constant SERVERPORT => 3483;

my $udpsock = undef;

my $log = logger('network.protocol');

sub init {

	#my $udpsock = IO::Socket::INET->new(
	$udpsock = IO::Socket::INET->new(
		Proto     => 'udp',
		LocalPort => SERVERPORT,
		LocalAddr => $main::localClientNetAddr,
		Broadcast => 1,
		ReuseAddr => 1

	) or do {

		# XXX - exiting in a deep sub is kinda bad. should propagate up.
		logger('')->logdie("FATAL: There is already another copy of the Logitech Media Server running on this machine. ($!)");
	};

	defined(Slim::Utils::Network::blocking($udpsock, 0)) || do { 

		logger('')->logdie("FATAL: Discovery init: Cannot set port nonblocking");
	};

	Slim::Networking::Select::addRead($udpsock, \&readUDP);

	Slim::Networking::Discovery::Server::init() if Slim::Utils::OSDetect::details->{osName} !~ /Windows 2000/i;
	Slim::Networking::Discovery::Players::init();

	# say hello to the old slimp3 clients that we might remember...
	for my $clientID (@{ preferences('server')->get('slimp3clients') || [] }) {

		# make sure any new preferences get set to default values
		assert($clientID);

		# skip client addrs that aren't dotted-4 with a port
		next if $clientID !~ /\d+\.\d+\.\d+\.\d+:\d+/;

		main::INFOLOG && $log->info("Discovery init: Saying hello to $clientID");

		Slim::Networking::Discovery::sayHello($udpsock, Slim::Utils::Network::ipaddress2paddr($clientID));
		
		# throttle the broadcasts
		select(undef, undef, undef, 0.05);
	}
}

my $warnNoSlimp3Support = 0;

sub readUDP {
	my $sock = shift || $udpsock;
	my $clientpaddr;
	my $msg = '';

	do {
		my $ts = Time::HiRes::time();
		
		$clientpaddr = recv($sock, $msg, 1500, 0);
		
		if ($clientpaddr) {

			# check that it's a message type we know: starts with i r 2 d a or h (but not h followed by 0x00 0x00)
			# These are SliMP3 packets.
			if ($msg =~ /^(?:[ir2a]|h(?!\x00\x00))/) {

				if (main::SB1SLIMP3SYNC) {
					if (!$Slim::Player::SLIMP3::SLIMP3Connected) {
	
						Slim::bootstrap::tryModuleLoad('Slim::Networking::SliMP3::Protocol');
					}
	
					my $client = Slim::Networking::SliMP3::Protocol::getUdpClient($clientpaddr, $sock, $msg) || return;
					
					Slim::Networking::SliMP3::Protocol::processMessage($client, $msg, $ts);
				} else {
					if (!$warnNoSlimp3Support) {
						my ($clientport, $clientip) = sockaddr_in($clientpaddr);
						logWarning("Ignoring client: " . inet_ntoa($clientip) . ": no SliMP3 support");
						$warnNoSlimp3Support = 1;
					}
				}
	
			} elsif ($msg =~/^d/) {

				# Discovery request: note that SliMP3 sends deviceid and revision in the discovery
				# request, but the revision is wrong (v 2.2 sends revision 1.1). Oops. 
				# also, it does not send the MAC address until the [h]ello packet.
				# Squeezebox sends all fields correctly.
				#
				# All players send discovery packets
	
				my ($msgtype, $deviceid, $revision, @mac) = unpack 'axCCxxxxxxxxH2H2H2H2H2H2', $msg;

				Slim::Networking::Discovery::gotDiscoveryRequest($sock, $clientpaddr, $deviceid, $revision, join(':', @mac));

			} elsif ($msg =~ /^E(.*)/) {

				Slim::Networking::Discovery::Server::gotTLVResponse($sock, $clientpaddr, $msg);

			} elsif ($msg =~/^e/) {

				# New extensible discovery format - pass to handler for processing

				Slim::Networking::Discovery::gotTLVRequest($sock, $clientpaddr, $msg);
	
			} else {

				my ($clientport, $clientip) = sockaddr_in($clientpaddr);

				if ( $log->is_warn ) {
					$log->warn("Ignoring client: " . inet_ntoa($clientip) . ":$clientport that sent bogus message $msg");
				}
			}
		}

	} while $clientpaddr;
}

sub socket {
	return $udpsock;
}

1;
