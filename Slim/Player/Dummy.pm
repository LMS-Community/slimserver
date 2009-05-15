# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
package Slim::Player::Dummy;

use strict;
use vars qw(@ISA);
use Slim::Player::Client;

use Slim::Display::NoDisplay;

@ISA = qw(Slim::Player::Client);

sub new {
	my $class = shift;

	my $id = '_dummy_' . Time::HiRes::time();
	
	my $client = $class->SUPER::new($id);
	
	$client->display( Slim::Display::NoDisplay->new($client) );

	return $client;
}

sub init { }

sub string {
	my $client = shift;
	Slim::Utils::Strings::string(@_)
};

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

# SLIM_SERVICE
sub loadPrefs        { }
sub getControllerPIN { }

1;
