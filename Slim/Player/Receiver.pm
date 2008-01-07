package Slim::Player::Receiver;

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use base qw(Slim::Player::Squeezebox2);

use Slim::Player::ProtocolHandlers;
use Slim::Player::Transporter;
use Slim::Utils::Prefs;
use Slim::Hardware::TriLED;

my $WHITE_COLOR =      0x00f0f0f0;
my $DARK_WHITE_COLOR = 0x00101010;

sub new {
	my $class = shift;

	my $client = $class->SUPER::new(@_);

	return $client;
}

sub canPowerOff { return 0; }

sub model {
	return 'receiver';
}

sub stop {
	my $client = shift;

	Slim::Hardware::TriLED::setTriLED( $client, $DARK_WHITE_COLOR, 1);
	return $client->SUPER::stop(@_);
}

sub pause {
	my $client = shift;

	Slim::Hardware::TriLED::setTriLED( $client, $DARK_WHITE_COLOR, 1);
	return $client->SUPER::pause(@_);
}

sub resume {
	my $client = shift;

	Slim::Hardware::TriLED::setTriLED( $client, $WHITE_COLOR, 1);
	return $client->SUPER::resume(@_);
}

sub play {
	my $client = shift;

	Slim::Hardware::TriLED::setTriLED( $client, $WHITE_COLOR, 1);
	return $client->SUPER::play(@_);
}

1;

__END__
