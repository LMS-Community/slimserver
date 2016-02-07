package Slim::Networking::Async::Socket::UDP;

# Logitech Media Server Copyright 2003-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This class contains the socket we use for async multicast UDP communication

use strict;

use base qw(IO::Socket::INET Slim::Networking::Async::Socket);

# Avoid IO::Socket's import method
sub import {}

use Socket;
use Slim::Utils::Log;

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
	
	my $dest_addr = sockaddr_in( $port, inet_aton( $addr ) );
	send( $self, $msg, 0, $dest_addr );
}

# configure a socket for multicast
sub mcast_add {
	my ( $self, $mcast_host, $if_addr ) = @_;
	
	$if_addr ||= '0.0.0.0';
	
	my ($mcast_addr) = split /:/, $mcast_host;
	
	# Tell the kernel that we want multicast messages on this interface
	setsockopt(
		$self,
		getprotobyname('ip') || 0,
		_constant('IP_ADD_MEMBERSHIP'),
		inet_aton($mcast_addr) . inet_aton($if_addr)
	) || logError("While adding multicast membership, UPnP may not work properly: $!");
	
	# Configure outgoing multicast messages to use the desired interface
	setsockopt(
		$self,
		getprotobyname('ip') || 0,
		_constant('IP_MULTICAST_IF'),
		inet_aton($if_addr)
	) || logError("While setting IP_MULTICAST_IF, UPnP may not work properly: $!");
	
	# Allow our multicast packets to be routed with TTL 4
	setsockopt(
		$self,
		getprotobyname('ip') || 0,
		_constant('IP_MULTICAST_TTL'),
		pack _constant('PACK_TEMPLATE'), 4,
	) || logError("While setting multicast TTL, UPnP may not work properly: $!");
}

sub _constant {
	my $name = shift;
	
	my %names = (
		'IP_MULTICAST_TTL'  => 0,
		'IP_ADD_MEMBERSHIP' => 1,
		'IP_MULTICAST_IF'   => 2,
		'PACK_TEMPLATE'     => 3,
	);
	
	my %constants = (
		'MSWin32' => [10,12,9,'I'],
		'cygwin'  => [3,5,2,'I'],
		'darwin'  => [10,12,9,'I'],
		'freebsd' => [10,12,9,'I'],
		'solaris' => [17,19,16,'C'],
		'default' => [33,35,32,'I'],
	);
	
	my $index = $names{$name};
	
	my $ref = $constants{ $^O } || $constants{default};
	
	return $ref->[ $index ];
}

1;
