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

# The following settings are for testing the new streaming protocol.
# They allow easy simulation of latency and packet loss in the receive direction.
# This is just to for *very* basic testing - for real network simulation, use Dummynet.
my $SIMULATE_RX_LOSS  = 0.00;  # packet loss, 0..1
my $SIMULATE_RX_DELAY = 000;  # delay, milliseconds

#-------- You probably don't want to change this -----------------#
my $OLDSERVERPORT = 1069;   # Port that 1.2 and earlier clients use
my $SERVERPORT = 3483;		# IANA-assigned port for the Slim protocol, used in firmware 1.3+
#-----------------------------------------------------------------#

# Select objects and select array ref returns
use vars qw(
	    $selUDPRead
	    $oldudpsock
	    $udpsock);

# This is all there is to it - it's like tftp, except that the client requests each
# chunk, as opposed to acknowlegding the data as we send it. Client handles timeouts.
sub gotAudioRequest {

# FIXME - it would be nice to have per-client and server-wide statistics on bytes sent,
# packets dropped, average data rate, etc.

	my ($client, $msg) = @_;
	
	my ($wptr) = unpack 'xxn', $msg;

	$::d_protocol_verbose && msgf("Request wptr = $wptr - %04x\n", $wptr);

	if  ($client->waitforstart()) {	# if we're waiting for the client to request the first chunk
					# of a new stream:

		if ($wptr != 0 ) {
			# if $wptr!=0 then this is probably a stray packet from the last stream we were playing
			# just log it and do nothing (it's normal).

			$::d_protocol && msg("Ignoring request from previous stream\n");
			return;

		} else {
			$client->waitforstart(0);
		}
	}

	# if we're not currently playing anything, just ignore the client.
	# FIXME - shouldn't we send the stop command?
	if (Slim::Player::Playlist::playmode($client) ne "play") {
		$::d_protocol && msg("got a request, but we're not playing anything.\n");
	}

	my $chunkRef = undef;
	
	# packet was dropped, and the client requested a resend.
	if ($client->prevwptr() == $wptr) {
		$::d_protocol && msg("Duplicate request: wptr = $wptr\n");
		$chunkRef = Slim::Player::Playlist::lastChunk($client);
	} else {
		$chunkRef = Slim::Player::Playlist::nextChunk($client, Slim::Utils::Prefs::get('udpChunkSize'));
	}

	if (!defined($chunkRef)) {
		return;
	};
	# pad to a len of 18: 0123456789012345678
	my $header = pack    'axn xxxxxxxxxxxxxxx', ('m', $wptr);

	my $append = '';
	
	# We must send an even number of bytes.
	if ((length($$chunkRef) % 2) != 0) {
		$append = '.';
	}

	sendClient($client, $header . $$chunkRef . $append);

	$::d_protocol_verbose && msg(Slim::Player::Client::id($client) . " " . Time::HiRes::time() . " Sending ".length($$chunkRef . $append)." bytes. wptr = $wptr\n");

	$client->prevwptr($wptr);
}

sub sendClient {
	my $client = shift;
	my $sock = $client->udpsock();
	if (defined $sock) {		
		return send( $sock, shift, 0, $client->paddr()); 
	} else {
		if ($::d_protocol && $client->type eq 'player') {
			bt();
			die Slim::Player::Client::id($client) . " no udpsock ready for client";
		}
	}	
}

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

	} elsif ($type eq 'r') {

		gotAudioRequest($client, $msg);

		Slim::Player::Playlist::checkSync($client);

	} elsif ($type eq 'h') {

	} elsif ($type eq '2') {

		Slim::Hardware::i2c::gotAck($client, unpack('xC',$msg));

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

	$oldudpsock = IO::Socket::INET->new(
		Proto     => 'udp',
		LocalPort => $OLDSERVERPORT,
		LocalAddr => $main::localClientNetAddr
	);

	if (!$oldudpsock) {
		warn "Unable to open UDP socket on port $OLDSERVERPORT.  Make sure all clients are upgraded to version 1.3 or above.";
	} else {
		$selUDPRead->add($oldudpsock); #to allow full processing of all pending UDP requests
		$::selRead->add($oldudpsock);
	}
	
# say hello to the old clients that we might remember...
	my $clients = Slim::Utils::Prefs::get("clients");
	if (defined($clients)) {
		foreach my $addr (split( /,/, $clients)) {
			#make sure any new preferences get set to default values

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
	while ($sock=pending()) { #process all pending UDP messages on both old and new UDP ports
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
				my $client = getClient($clientpaddr, $sock, $msg);

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
				Slim::Network::Discovery::gotDiscoveryRequest($sock, $clientpaddr);
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
sub getClient {
	my ($clientpaddr,$udpsock, $msg) = @_;

	my ($msgtype, $deviceid, $revision, @mac) = unpack 'aCCxxxxxxxxxH2H2H2H2H2H2', $msg;
	
	my $newplayeraddr;

	my $mac = join(':', @mac);
	my $id = $mac;
							
	my $client = Slim::Player::Client::getClient($id);
	
	# alas, pre 2.2 clients don't always include the MAC address, so we use the IP address as the ID.
	if (!defined($client)) {
		$id = paddr2ipaddress($clientpaddr);
		$client = Slim::Player::Client::getClient($id);
	}

	if (!defined($client)) {
		if ($msgtype eq 'h') {

			$revision = int($revision / 16) + ($revision % 16)/10.0;
			
			if ($revision >= 2.2) { $id = $mac; }
			
			$newplayeraddr = paddr2ipaddress($clientpaddr);

			if ($deviceid > 0x02 || $deviceid < 0x01) { return undef;}

			$client = Slim::Player::Client::newClient($id, $newplayeraddr);

			$::d_protocol && msg("$id ($msgtype) deviceid: $deviceid revision: $revision address: $newplayeraddr\n");

			$client->revision($revision);
			$client->deviceid($deviceid);
			$client->udpsock($udpsock);

			if ($revision >= 2.2) {
				$client->macaddress($mac);
				if ($mac eq '00:04:20:03:04:e0') {
					$client->vfdmodel('futaba-latin1');
				} elsif ($mac eq '00:04:20:02:07:6e' ||
						 $mac =~ /^00:04:20:04:1/ ||
						 $mac =~ /^00:04:20:00:/	) {
					$client->vfdmodel('noritake-european');
				} else {
					$client->vfdmodel('noritake-katakana');
				}			
			} else {
				$client->vfdmodel('noritake-katakana');
			}
			
			if ($deviceid == 0x01) {
				$client->decoder('mas3507d');
				$client->ticspersec(625000);
				$client->type('player');
				$client->model('slimp3');
			} elsif ($deviceid == 0x02) {
				$client->decoder('mas35x9');
				$client->ticspersec(1000);
				$client->type('player');
				$client->model('squeezebox');
			} else {
				$::d_protocol && msg("bogus client: $id, fugettaboutit\n");
				return undef;
			}
		} else {
			Slim::Network::Discovery::sayHello($udpsock, $clientpaddr);
			return undef;
		} 
	}

	$client->paddr($clientpaddr);
	
	$revision = $client->revision;
		
	# alas, the mac address isn't included with the 2.0 hello packet, 
	# so we need to check subsequently in order to get the MAC and therefor the VFD model...
	if ($revision < 2.2 && $revision >= 2.0) {
		if (!defined($client->macaddress)) {
			$::d_protocol && msg("MAC: $mac from message type: $msgtype\n");
			if ($mac ne '00:00:00:00:00:00') {
				$client->macaddress($mac);
			}
		}
	}
		
	if ($newplayeraddr) {
		# add the new client all the currently known clients so we can say hello to them later
		my $clientlist = Slim::Utils::Prefs::get("clients");
	
		if (defined($clientlist)) {
			$clientlist .= ",$newplayeraddr";
		} else {
			$clientlist = $newplayeraddr;
		}
	
		my %seen = ();
		my @uniq = ();
		foreach my $item (split( /,/, $clientlist)) {
			push(@uniq, $item) unless $seen{$item}++ || $item eq '';
		}
		Slim::Utils::Prefs::set("clients", join(',', @uniq));
		
		# fire it up!
		Slim::Player::Client::power($client,Slim::Utils::Prefs::clientGet($client, 'power'));
		
		Slim::Player::Client::startup($client);

		# start the screen saver
		Slim::Buttons::ScreenSaver::screenSaver($client);
	}

	return $client
}

sub pending {
	my @readablesocks = ($selUDPRead->can_read(0));
	return(shift(@readablesocks));
}
