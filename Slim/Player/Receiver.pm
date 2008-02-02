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
my $OFF_COLOR = 0x00000000;

sub new {
	my $class = shift;

	my $client = $class->SUPER::new(@_);

	return $client;
}

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

sub power {
	my $client = shift;
	my $on = $_[0];
	my $prefs = preferences( 'server');
	my $currOn = $prefs->client( $client)->get( 'power') || 0;

	if( defined( $on) && (!defined(Slim::Buttons::Common::mode($client)) || ($currOn != $on))) {
		if( $on == 1) {
			Slim::Hardware::TriLED::setTriLED( $client, $DARK_WHITE_COLOR, 1);
		} else {
			# Needed because sub stop or sub pause is called _after_ sub power
			Slim::Utils::Timers::setTimer( $client,	Time::HiRes::time() + 0.75, \&powerTurnOffLED);
		}
	}
	return $client->SUPER::power(@_);
}

sub powerTurnOffLED {
	my $client = shift;

	Slim::Utils::Timers::killTimers( $client, \&powerTurnOffLED);
	Slim::Hardware::TriLED::setTriLED( $client, $OFF_COLOR, 1);
}

1;

__END__
