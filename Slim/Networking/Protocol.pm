# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
package Slim::Networking::Protocol;

use strict;

use IO::Socket;
use IO::Select;

use Slim::Utils::Misc;
use Slim::Player::SLIMP3;
# The following settings are for testing the new streaming protocol.
# They allow easy simulation of latency and packet loss in the receive direction.
# This is just to for *very* basic testing - for real network simulation, use Dummynet.
my $SIMULATE_RX_LOSS  = 0.00;  # packet loss, 0..1
my $SIMULATE_RX_DELAY = 000;  # delay, milliseconds

#-------- You probably don't want to change this -----------------#
my $SERVERPORT = 3483;		# IANA-assigned port for the Slim protocol, used in firmware 1.3+
#-----------------------------------------------------------------#

# Select objects and select array ref returns
use vars qw(
	    $selUDPRead
	    $udpsock);

sub processMessage {
	my ($client,$msg) = @_;

	my $type   = unpack('a',$msg);

	#  Packet format for IR code. Numbers are unsigned, network order.
	#
	#  [0]       'i'
	#  [1]       0x00
	#  [2..5]    player's time since startup in 'ticks' @ 625 KHz
	#  [6]       0xFF  (will eventually be an identifier for different IR code sets)
	#  [7]       number of bits ( always 16 for JVC )
	#  [8..11]   the IR code, up to 32 bits
	#  [12..17]  reserved/ignored

	if ($type eq 'i') {
		# extract the IR code and the timestamp for the IR message
		my ($irTime, $irCodeBytes) = unpack 'xxNxxH8', $msg;	
		
		Slim::Hardware::IR::enqueue($client, $irCodeBytes, $irTime);

	} elsif ($type eq 'h') {

	} elsif ($type eq '2') {

		# ignore SLIMP3's i2c acks

	} elsif ($type eq 'a') {

		my ($wptr, $rptr, $seq) = unpack 'xxxxxxnnn', $msg;

		Slim::Networking::Stream::gotAck($client, $wptr, $rptr, $seq);

		Slim::Player::Playlist::checkSync($client);

	} else {
		$::d_protocol && msg("debug: unknown type: [$type]\n");
	}

	return 1;
}

sub init {
	$selUDPRead = IO::Select->new();

# FIXME: Add a setup option to bind the server to a particular IP:PORT
#
	$udpsock = IO::Socket::INET->new(
		Proto     => 'udp',
		LocalPort => $SERVERPORT,
		LocalAddr => $main::localClientNetAddr
	);
	
	if (!$udpsock) {
		msg("Problem: There is already another copy of the Slim Server running on this machine.\n");
		exit 1;
	}

	$selUDPRead->add($udpsock); #to allow full processing of all pending UDP requests
	$::selRead->add($udpsock);
	
# say hello to the old clients that we might remember...
	my $clients = Slim::Utils::Prefs::get("clients");

	$::d_protocol && msg("Going to say hello to everybody we remember: $clients\n");
	
	if (defined($clients)) {
		foreach my $addr (split( /,/, $clients)) {
			#make sure any new preferences get set to default values
			assert($addr);
			next unless ($addr=~/\d+\.\d+\.\d+\.\d+:\d+/); # skip client addrs that aren't dotted-4 with a port
			### FIXME don't say hello to http clients!!!
			Slim::Network::Discovery::sayHello($udpsock, ipaddress2paddr($addr));
			
			#throttle the broadcasts
			select(undef,undef,undef,0.05);
		}
	}
}

sub idle {

	my $clientpaddr;
	my $msg = '';
	my $sock;
	
	my $start = Time::HiRes::time();
	# handle UDP activity...
	while ($sock=pending()) { 			#process all pending UDP messages
		my $now = Time::HiRes::time();
		if (($now - $start) > 0.5) {
			$::d_perf && msg("stayed in idle too long...\n");
			last;
		}
		$clientpaddr = recv($sock,$msg,1500,0);

		# simulate random packet loss
#		next if ($SIMULATE_RX_LOSS && (rand() < $SIMULATE_RX_LOSS));

		if ($clientpaddr) {
			# check that it's a message type we know: starts with i r 2 d a or h (but not h followed by 0x00 0x00)
			if ($msg =~ /^(?:[ir2a]|h(?!\x00\x00))/) {
				my $client = getUdpClient($clientpaddr, $sock, $msg);

				if (!defined($client)) {
					next;
				}
				if ($::d_protocol_verbose) {
					my ($clientport, $clientip) = sockaddr_in($clientpaddr);
					msg("Client: ".inet_ntoa($clientip).":$clientport\n");
				}

				if ($SIMULATE_RX_DELAY) {
					# simulate rx delay
					Slim::Utils::Timers::setTimer($client, $now + $SIMULATE_RX_DELAY/1000,
								\&Slim::Networking::Protocols::processMessage, $msg);
				} else {
					processMessage($client, $msg);
				}

			} elsif ($msg =~/^d/) {
				# Discovery request: note that slimp3 sends deviceid and revision in the discovery
				# request, but the revision is wrong (v 2.2 sends revision 1.1). Oops. 
				# also, it does not send the MAC address until the [h]ello packet.
				# Squeezebox sends all fields correctly.

				my ($msgtype, $deviceid, $revision, @mac) = unpack 'axCCxxxxxxxxH2H2H2H2H2H2', $msg;
				my $mac = join(':', @mac);
				Slim::Network::Discovery::gotDiscoveryRequest($sock, $clientpaddr, $deviceid, $revision, $mac);

			# Playlist::executecommand can be accessed over the UDP port
			} elsif ($msg=~/^executecommand\((.*)\)$/) {
				my $ecArgs=$1;
				my @ecArgs=split(/, ?/, $ecArgs);
				$::d_protocol && msg("UDP: executecommand($ecArgs)\n");
				my $clientipport = shift(@ecArgs);
				my $client = Slim::Player::Client::getClient($clientipport);
				Slim::Control::Command::execute($client, \@ecArgs);
			} else {
				if ($::d_protocol) {
					my ($clientport, $clientip) = sockaddr_in($clientpaddr);
					msg("ignoring Client: ".inet_ntoa($clientip).":$clientport that sent bogus message $msg\n");
				}
			}
		} else {
			last;
		}
	}
}

sub paddr2ipaddress {
	my ($port, $ip) = sockaddr_in(shift);
	$ip = inet_ntoa($ip);
	return $ip.":".$port;
}

sub ipaddress2paddr {
	my ($ip, $port) = split( /:/, shift);
	$ip = inet_aton($ip);
	my $paddr = sockaddr_in($port, $ip);
	return $paddr;
}


###################
# return the client based on IP address and socket.  will create a new one if
# necessary 
sub getUdpClient {
	my ($clientpaddr,$udpsock, $msg) = @_;

	my ($msgtype, $deviceid, $revision, @mac) = unpack 'aCCxxxxxxxxxH2H2H2H2H2H2', $msg;
	
	my $newplayeraddr;

	my $mac = join(':', @mac);
	my $id = $mac;

	my $client = Slim::Player::Client::getClient($id);

# DISABLING FIRMWARE 2.0 SUPPORT
#	# alas, pre 2.2 clients don't always include the MAC address, so we use the IP address as the ID.
#	if (!defined($client)) {
#		$id = paddr2ipaddress($clientpaddr);
#		$client = Slim::Player::Client::getClient($id);
#	}

	if (!defined($client)) {
		if ($msgtype eq 'h') {

			$revision = int($revision / 16) + ($revision % 16)/10.0;
			
			if ($revision >= 2.2) { $id = $mac; }
			
			$newplayeraddr = paddr2ipaddress($clientpaddr);

			if ($deviceid != 0x01) { return undef;}

			$::d_protocol && msg("$id ($msgtype) deviceid: $deviceid revision: $revision address: $newplayeraddr\n");
			$client = Slim::Player::SLIMP3->new(
					$id, 
					$clientpaddr,
					$newplayeraddr,
					$deviceid,
					$revision,
					$udpsock,
					undef
				);			
			
			$client->init();

		} else {
			Slim::Network::Discovery::sayHello($udpsock, $clientpaddr);
			return undef;
		} 
	}

	$client->paddr($clientpaddr);
	
	$revision = $client->revision;
		
	return $client
}

sub pending {
	my @readablesocks = ($selUDPRead->can_read(0));
	return(shift(@readablesocks));
}
