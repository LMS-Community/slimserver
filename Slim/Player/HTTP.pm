# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
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

@ISA = qw(Slim::Player::Client);

sub new {
	my ($class, $id, $paddr, $tcpsock) = @_;
	
	my $client = Slim::Player::Client->new($id, $paddr);

	$client->streamingsocket($tcpsock);

	bless $client, $class;

	return $client;
}

sub init {
	my $client = shift;
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
sub power 	   	{ Slim::Web::HTTP::clearOutputBuffer(shift); 1 }
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
sub vfdmodel	{ 'http' }
sub vfd			{ undef }

1;
