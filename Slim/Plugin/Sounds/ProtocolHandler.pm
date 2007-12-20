package Slim::Plugin::Sounds::ProtocolHandler;

# $Id$

# Handler for forcing loop mode

use strict;
use base 'Slim::Player::Protocols::HTTP';

# No scrobbling
sub audioScrobblerSource { }

# Loop mode only works with direct streaming
sub canDirectStream {
	my ( $class, $client, $url ) = @_;
	
	return $url;
}

sub isAudioURL { 1 }

sub shouldLoop { 1 }

1;