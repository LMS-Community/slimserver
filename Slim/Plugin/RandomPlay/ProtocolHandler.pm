package Slim::Plugin::RandomPlay::ProtocolHandler;

# $Id

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;

use Slim::Plugin::RandomPlay::Plugin;

sub overridePlayback {
	my ( $class, $client, $url ) = @_;

	if ($url !~ m|^randomplay://(.*)$|) {
		return undef;
	}

	$client->execute(["randomplay", "$1"]);
	
	return 1;
}

sub canDirectStream { 0 }

sub contentType {
	return 'rnd';
}

sub isRemote { 0 }

sub getIcon {
	return Slim::Plugin::RandomPlay::Plugin->_pluginDataFor('icon');
}

1;
