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
	my $class = shift;
	my $client = Slim::Player::Player->new( @_ );
	bless $client, $class;
	
	return $client;
}

sub model {
	return 'squeezebox';
}

sub type {
	return 'player';
}

sub deviceid {
	return 0x02;
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