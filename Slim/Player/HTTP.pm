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
package Slim::Player::HTTP;

@ISA = ("Slim::Player::Client");

sub new {
	my (
		$class,
		$id,
		$paddr,			# sockaddr_in
		$newplayeraddr,		# ASCII ip:port  TODO don't pass both of these in
		$tcpsock
	) = @_;
	
	my $client = Slim::Player::Client->new( $id, $paddr, $newplayeraddr, 0,0,0);
	$client->streamingsocket($tcpsock);
	bless $client, $class;

	return $client;
}

sub init {
	my $client = shift;
	Slim::Player::Client::startup($client);
}

sub type {
	return 'http';
}

sub update {
}

1;