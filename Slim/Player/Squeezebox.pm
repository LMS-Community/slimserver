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
use Slim::Player::Player;

package Slim::Player::Squeezebox;

@ISA = ("Slim::Player::Player");

sub new {
	my (
		$class,
		$id,
		$paddr,			# sockaddr_in
		$revision,
		$tcpsock,		# defined only for squeezebox
	) = @_;
	
	my $client = Slim::Player::Player->new($id, $paddr, $revision);

	bless $client, $class;

	$client->reconnect($paddr, $revision, $tcpsock);
		
	return $client;
}

sub reconnect {
	my $client = shift;
	my $paddr = shift;
	my $revision = shift;
	my $tcpsock = shift;

	$client->tcpsock($tcpsock);
	$client->paddr($paddr);
	$client->revision($revision);	
	
	$client->update();	
}

sub model {
	return 'squeezebox';
}

sub ticspersec {
	return 1000;
}

sub vfdmodel {
	return 'noritake-european';
}

sub decoder {
	return 'mas35x9';
}

1;