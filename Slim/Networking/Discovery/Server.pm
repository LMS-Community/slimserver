package Slim::Networking::Discovery::Server;

# $Id: Server.pm 15258 2007-12-13 15:29:14Z mherger $

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use IO::Socket qw(SO_BROADCAST sockaddr_in inet_aton inet_ntoa);

use Slim::Networking::UDP;
use Slim::Networking::Discovery::Players;
use Slim::Utils::Log;
use Slim::Utils::Network;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;
use Slim::Utils::Unicode;

my $log = logger('network.protocol');
my $prefs = preferences('server');

my $discovery_packet = pack 'a5xa4xa4xa4xa4x', 'eIPAD', 'NAME', 'JSON', 'UUID', 'VERS';

# List of server we see
my $server_list = {};

# Default polling time
use constant POLL_INTERVAL => 60;

=head1 NAME

Slim::Networking::Discovery::Server

=head1 DESCRIPTION

This module implements a UDP discovery protocol, used by Logitech Media Server to discover other servers in the network.


=head1 FUNCTIONS

=head2 init()

initialise the server discovery polling

=cut

sub init {
	fetch_servers();
}


=head2 fetch_servers()

Poll the servers in our network

=cut

sub fetch_servers {
    # bug 9227 - disable server detection on Windows 2000
    return if Slim::Utils::OSDetect::details->{osName} =~ /Windows 2000/i;

	my $udpsock = Slim::Networking::UDP::socket();

	Slim::Utils::Timers::killTimers(undef, \&fetch_servers);

	_purge_server_list();

	# broadcast command to discover servers
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

=head2 _purge_server_list()

purge servers from the list when they haven't been discovered in two poll cycles

=cut

sub _purge_server_list {
	foreach my $server (keys %{$server_list}) {
		
		if (!$server_list->{$server}->{ttl} || $server_list->{$server}->{ttl} < time()) {

			delete $server_list->{$server};
		}
	}
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
	my $id = shift;
	my $server = _getServerConfig($id) || {};	
	return $server->{IP} || $id;
}

=head2 getServerPort()

Return a server's port if available

=cut

sub getServerPort {
	my $server = _getServerConfig(shift) || {};
	return $server->{JSON} || 9000;
}

=head2 getServerUUID()

Return a server's UUID if available

=cut

sub getServerUUID {
	my $server = _getServerConfig(shift) || {};
	return $server->{UUID} || '';
}

=head2 getServerVersion()

Return a server's Version if available

=cut

sub getServerVersion {
	my $server = _getServerConfig(shift) || {};
	return $server->{VERS} || '';
}

=head2 getWebHostAddress()

Return a server's full address to access its web page

=cut

sub getWebHostAddress {
	my $id = shift;
	return 'http://' . getServerAddress($id) . ':' . getServerPort($id) . '/';
}

sub _getServerConfig {
	my ($id) = @_;
	
	my $server = $server_list->{$id};
	
	# if we were not given the server's key, try to find it by UUID, Name or IP address
	if (!$server || !ref $server) {
		my $lcId = lc($id);
		($server) = grep {
			lc($_->{UUID}) eq $lcId || lc($_->{NAME}) eq $lcId || $_->{IP} eq $id
		} values %$server_list;
	}
	
	return $server || {};
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

	main::INFOLOG && $log->info("discovery response packet:");

	# chop of leading character
	$msg = substr($msg, 1);
	
	my $len = length($msg);
	my ($tag, $len2, $val);

	my $server = {};

	while ($len > 0) {

		$tag  = substr($msg, 0, 4);
		$len2 = unpack("xxxxC", $msg);
		$val  = $len2 ? substr($msg, 5, $len2) : undef;

		main::DEBUGLOG && $log->debug(" TLV: $tag len: $len2, $val");

		$server->{$tag} = $val;

		$msg = substr($msg, $len2 + 5);
		$len = $len - $len2 - 5;
	}

	# get server's IP address
	if ($clientpaddr) {
		
		my ($portno, $ipaddr) = sockaddr_in($clientpaddr);
		$server->{IP} = inet_ntoa($ipaddr);

		# should we remove ourselves from the list?
#		if (is_self($server->{IP})) {
#			$server = undef;
#		}
	}

	if (main::DEBUGLOG && $log->is_debug) {	
		$log->debug(" Discovered server $server->{NAME} ($server->{IP}), using port $server->{JSON}, UUID $server->{UUID}, version $server->{VERS}");
	}

	if ($server->{NAME}) {
		
		$server->{NAME} = Slim::Utils::Unicode::utf8decode($server->{NAME});
		
		$server_list->{$server->{NAME}}        = $server;
		$server_list->{$server->{NAME}}->{ttl} = time() + 2 * POLL_INTERVAL;

		unless (is_self($server->{IP})) {

			Slim::Utils::Timers::killTimers($server->{NAME}, \&fetch_servers);

			Slim::Utils::Timers::setTimer(
				$server->{NAME},
				time() + 2,
				\&Slim::Networking::Discovery::Players::fetch_players,
			);
		}
	}
}

sub is_self {
	my $id = shift;
	
	# compare IP addresses - backwards compatible
	return 1 if $id eq Slim::Utils::Network::serverAddr();
	
	# check based on UUID - better
	return 1 if lc(getServerUUID($id)) eq lc($prefs->get('server_uuid'));
}

=head1 SEE ALSO

L<Slim::Networking::Discovery>

L<Slim::Networking::UDP>

L<Slim::Networking::SliMP3::Protocol>

=cut

1;
