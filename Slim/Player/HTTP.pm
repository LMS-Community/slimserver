# SqueezeCenter Copyright (c) 2001-2007 Logitech.
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

use strict;
use vars qw(@ISA);
use Slim::Player::Client;

use Slim::Display::NoDisplay;

@ISA = qw(Slim::Player::Client);

sub new {
	my ($class, $id, $paddr, $tcpsock) = @_;
	
	my $client = Slim::Player::Client->new($id, $paddr);

	$client->streamingsocket($tcpsock);

	bless $client, $class;

	$client->display( Slim::Display::NoDisplay->new($client) );

	return $client;
}

sub init {
	my $client = shift;
	$client->SUPER::init();
	push @{$client->modeParameterStack}, {};
	$client->startup();
}

sub bytesReceived {
	my $client = shift;
	return @_ ? $client->songBytes(shift) : $client->songBytes();
}

sub connected { 
	my $client = shift;

	return ($client->streamingsocket() && $client->streamingsocket->connected()) ? 1 : 0;
}

# dummy methods
sub update		{ }
sub isPlayer		{ 0 }
sub stop		{ Slim::Web::HTTP::clearOutputBuffer(shift); 1 }
sub play		{ Slim::Web::HTTP::clearOutputBuffer(shift); 1 }
sub pause		{ Slim::Web::HTTP::clearOutputBuffer(shift); 1 }
sub playout		{ 1 }
sub resume		{ 1 }
sub volume		{ 1 }
sub fade_volume		{ 1 }
sub bufferFullness	{ 0 }
sub formats		{ 'mp3' }
sub model		{ 'http' }
sub decoder		{ 'http' }
sub vfd			{ undef }

sub power {
	my $client = shift;
	my $toggle = shift;

	if ($toggle) {
		Slim::Web::HTTP::clearOutputBuffer($client);
	}

	return 1;
}

1;
