package Slim::Networking::Discovery::Server;

# $Id: Server.pm 15258 2007-12-13 15:29:14Z mherger $

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use IO::Socket;

use Slim::Networking::UDP;
use Slim::Utils::Log;
use Slim::Utils::Network;
use Slim::Utils::Timers;

my $log = logger('network.protocol');

my $discovery_packet = pack 'a5xa4xa4', 'eIPAD', 'NAME', 'JSON';

# List of server we see
my $server_list = {};

# Default polling time
use constant POLL_INTERVAL => 15;

=head1 NAME

Slim::Networking::Discovery::Server

=head1 DESCRIPTION

This module implements a UDP discovery protocol, used by SqueezeCenter to discover other servers in the network.


=head1 FUNCTIONS

=head2 init()

initialise the server discovery polling

=cut

sub init {
	my $udpsock = Slim::Networking::UDP::socket();

	fetch_servers($udpsock);
}


=head2 fetch_servers()

Poll the SqueezeCenter/SlimServers in our network

=cut

sub fetch_servers {
	my $udpsock = Slim::Networking::UDP::socket();

	Slim::Utils::Timers::killTimers($udpsock, \&fetch_servers);

	# broadcast command to discover SlimServers
	my $opt = $udpsock->sockopt(SO_BROADCAST);
	$udpsock->sockopt(SO_BROADCAST, 1);

	my $ipaddr = sockaddr_in(3483, inet_aton('255.255.255.255'));
	$udpsock->send($discovery_packet, 0, $ipaddr);
	
	$udpsock->sockopt(SO_BROADCAST, $opt);

	Slim::Utils::Timers::setTimer(
		undef,
		time() + POLL_INTERVAL,
		\&fetch_servers,
	);
}

=head2 getServerList()

Return the full list of servers available in our network

=cut

sub getServerList {
	return $server_list;
}

=head2 getServerAddress()

Return a server's IP address if available

=cut

sub getServerAddress {
	my $server = shift;
	return $server_list->{$server}->{IP} || $server;
}


=head2 gotTLVResponse( $udpsock, $clientpaddr, $msg )

Process TLV based discovery response.

=cut
sub gotTLVResponse {
	my ($udpsock, $clientpaddr, $msg) = @_;

	use bytes;

	unless ($msg =~ /^E/) {
		$log->warn("bad discovery packet - ignoring");
		return;
	}

	$log->info("discovery response packet:");

	# chop of leading character
	$msg = substr($msg, 1);
	
	my $len = length($msg);
	my ($tag, $len2, $val);

	my $server = {};

	while ($len > 0) {

		$tag  = substr($msg, 0, 4);
		$len2 = unpack("xxxxC", $msg);
		$val  = $len2 ? substr($msg, 5, $len2) : undef;

		$log->debug(" TLV: $tag len: $len2, $val");

		$server->{$tag} = $val;

		$msg = substr($msg, $len2 + 5);
		$len = $len - $len2 - 5;
	}

	# get server's IP address
	if ($clientpaddr) {
		
		my ($portno, $ipaddr) = sockaddr_in($clientpaddr);
		$server->{IP} = inet_ntoa($ipaddr);
	}

	if ($log->is_debug) {	
		$log->debug(" Discovered server $server->{NAME} ($server->{IP}), using port $server->{JSON}");
	}

	if ($server->{NAME}) {
		
		$server_list->{$server->{NAME}}              = $server;
		$server_list->{$server->{NAME}}->{timestamp} = time();
	}
}


=head1 SEE ALSO

L<Slim::Networking::Discovery>

L<Slim::Networking::UDP>

L<Slim::Networking::SliMP3::Protocol>

=cut

1;
