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
use Slim::Utils::Misc;
package Slim::Player::SLIMP3;

@ISA = ("Slim::Player::Player");

sub new {
	my $class = shift;
	my $client = Slim::Player::Player->new( @_ );
	print "creating a new $class\n";
	bless $client, $class;
	
	return $client;
}

sub model {
	return 'slimp3';
}

sub type {
	return 'player';
}

sub deviceid {
	return 0x01;
}

sub ticspersec {
	return 625000;
}

sub decoder {
	return 'mas3507d';
}

sub vfdmodel {
	my $client = shift;
	if ($client->revision >= 2.2) {
		my $mac = $client->macaddress();
		if ($mac eq '00:04:20:03:04:e0') {
			return 'futaba-latin1';
		} elsif ($mac eq '00:04:20:02:07:6e' ||
				$mac =~ /^00:04:20:04:1/ ||
				$mac =~ /^00:04:20:00:/	) {
			return 'noritake-european';
		} else {
			return 'noritake-katakana';
		}
	} else {
		return 'noritake-katakana';
	}		
}


1;

