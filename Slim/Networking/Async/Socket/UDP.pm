package Slim::Networking::Async::Socket::UDP;

# $Id$

# SlimServer Copyright (c) 2003-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This class contains the socket we use for async multicast UDP communication

use strict;
use warnings;

use base qw(IO::Socket::INET Slim::Networking::Async::Socket);

use Socket;

sub new {
	my $class = shift;
	
	return $class->SUPER::new(
		Proto => 'udp',
		@_,
	);
}

# send a multicast UDP packet
sub mcast_send {
	my ( $self, $msg, $host ) = @_;
	
	my ( $addr, $port ) = split /:/, $host;
	
	setsockopt(
		$self,
		getprotobyname('ip') || 0,
		_constant('IP_MULTICAST_TTL'),
		pack 'I', 4,
	) || msg("UPnP: Error setting multicast TTL: $!\n");
	
	my $dest_addr = sockaddr_in( $port, inet_aton( $addr ) );
	send( $self, $msg, 0, $dest_addr );
}

# listen for multicast responses
sub mcast_add {
	my ( $self, $host ) = @_;
	
	my ( $addr, $port ) = split /:/, $host;
	
	my $ip_mreq = inet_aton( $addr ) . INADDR_ANY;
	
	setsockopt(
		$self,
		getprotobyname('ip') || 0,
		_constant('IP_ADD_MEMBERSHIP'),
		$ip_mreq
	) || msg("UPnP: Error adding multicast membership, UPnP may not work properly: $!\n");
}

sub _constant {
	my $name = shift;
	
	my %names = (
		'IP_MULTICAST_TTL'  => 0,
		'IP_ADD_MEMBERSHIP' => 1,
	);
	
	my %constants = (
		'MSWin32' => [10,12],
		'cygwin'  => [3,5],
		'darwin'  => [10,12],
		'default' => [33,35],
	);
	
	my $index = $names{$name};
	
	my $ref = $constants{ $^O } || $constants{default};
	
	return $ref->[ $index ];
}

1;