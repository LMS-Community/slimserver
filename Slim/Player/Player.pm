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
use Slim::Player::Client;

package Slim::Player::Player;

@ISA = ("Slim::Player::Client");

sub new {
	my $class = shift;
	my $client = Slim::Player::Client->new( @_ );
	bless $client, $class;

	return $client;
}

sub init {
	my $client = shift;
	# fire it up!
	Slim::Player::Client::power($client,Slim::Utils::Prefs::clientGet($client, 'power'));
	Slim::Player::Client::startup($client);
                
	# start the screen saver
	Slim::Buttons::ScreenSaver::screenSaver($client);
}

sub update {
	my $client = shift;
	Slim::Display::Animation::killAnimation($client);
	Slim::Hardware::VFD::vfdUpdate($client, Slim::Display::Display::curLines($client));
}	

sub model {
	return 'slimp3';
}

sub type {
	return 'player';
}

1;

