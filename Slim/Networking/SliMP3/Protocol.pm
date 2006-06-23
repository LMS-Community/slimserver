package Slim::Networking::SliMP3::Protocol;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;

use Slim::Player::SLIMP3;
use Slim::Networking::Discovery;
use Slim::Networking::Select;
use Slim::Utils::Misc;
use Slim::Utils::Network;

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

		Slim::Networking::SliMP3::Stream::gotAck($client, $wptr, $rptr, $seq);

		Slim::Player::Sync::checkSync($client);

	} else {
		$::d_protocol && msg("debug: unknown type: [$type]\n");
	}

	return 1;
}

###################
# return the client based on IP address and socket.  will create a new one if
# necessary 
sub getUdpClient {
	my ($clientpaddr, $sock, $msg) = @_;

	my ($msgtype, $deviceid, $revision, @mac) = unpack 'aCCxxxxxxxxxH2H2H2H2H2H2', $msg;

	my $mac = join(':', @mac);
	my $id  = $mac;

	my $client = Slim::Player::Client::getClient($id);

	if (!defined($client)) {

		if ($msgtype eq 'h') {

			$revision = int($revision / 16) + ($revision % 16)/10.0;

			if ($revision >= 2.2)  { $id = $mac }
			if ($deviceid != 0x01) { return undef }

			$::d_protocol && msg("$id ($msgtype) deviceid: $deviceid revision: $revision address: " .
				Slim::Utils::Network::paddr2ipaddress($clientpaddr) . "\n");

			$client = Slim::Player::SLIMP3->new($id, $clientpaddr, $revision, $sock);			

			$client->macaddress($mac);
			$client->init;

		} else {

			Slim::Networking::Discovery::sayHello($sock, $clientpaddr);

			return undef;
		} 
	}

	$client->paddr($clientpaddr);
	
	return $client
}

1;
