# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# This class represents a disconnected player, that is, a player we
# probably know something about but is not currently connected.  We
# can use this to still obtain prefs for the player, such as enabled apps.
#

package Slim::Player::Disconnected;

use strict;
use vars qw(@ISA);
use Slim::Player::Client;

use Slim::Display::NoDisplay;

BEGIN {
	require Slim::Player::Client;
	push @ISA, qw(Slim::Player::Client);
}

sub new {
	my ( $class, $id ) = @_;
	
	my $client = $class->SUPER::new($id);
	
	$client->display( Slim::Display::NoDisplay->new($client) );
	
	# Load strings for display
	$client->display->displayStrings(Slim::Utils::Strings::clientStrings($client));

	return $client;
}

# dummy methods
sub hidden         { 1 }
sub bytesReceived  { }
sub connected      { 0 }
sub update         { }
sub isPlayer       { 0 }
sub stop           { }
sub play           { }
sub pause          { }
sub rebuffer       { 1 }
sub resume         { 1 }
sub volume         { 1 }
sub fade_volume    { 1 }
sub bufferFullness { 0 }
sub formats        { }
sub model          { 'dummy' }
sub modelName      { 'Dummy Client' }
sub decoder        { }
sub vfd            { undef }
sub canPowerOff    { 0 }

1;
