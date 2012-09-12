# Copyright 2001-2011 Logitech.
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
	if ( main::SLIM_SERVICE ) {
		require SDI::Service::Player::SqueezeNetworkClient;
		push @ISA, qw(SDI::Service::Player::SqueezeNetworkClient);
	}
	else {
		require Slim::Player::Client;
		push @ISA, qw(Slim::Player::Client);
	}
}

{
	__PACKAGE__->mk_accessor('rw', qw(authenticator server));
}

sub new {
	my ( $class, $id ) = @_;
	
	my $client = $class->SUPER::new($id);
	
	$client->display( Slim::Display::NoDisplay->new($client) );
	
	# Load strings for display
	$client->display->displayStrings(Slim::Utils::Strings::clientStrings($client));

	return $client;
}

use Slim::Player::DelegatedPlaylist;

sub getPlaylist {
	my $client = shift;
	
	if (my $p = $client->_playlist) {return $p;}
	
	return $client->_playlist(Slim::Player::DelegatedPlaylist->new($client));
}

sub isLocalPlayer { 0 }

# dummy methods
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

# SLIM_SERVICE
sub getControllerPIN { }

1;
