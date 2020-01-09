package Slim::Plugin::LineIn::ProtocolHandler;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;

use Slim::Utils::Log;

my $log = logger('player.source');

sub overridePlayback {
	my ( $class, $client, $url ) = @_;
	
	main::DEBUGLOG && $log->debug( "Switching to line in $url" );
	
	$client->setLineIn($url);

	return 1;
}

sub canDirectStream {
	return 1;
}

sub contentType {
	return 'src';
}

sub isRemote { 0 }

1;
