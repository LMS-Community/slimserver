package Slim::Plugin::MusicMagic::ProtocolHandler;

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

sub overridePlayback {
	my ( $class, $client, $url ) = @_;

	if ($url !~ m|^mood://(.*)$|) {
		return undef;
	}

	$client->execute(["musicip", "mix", "mood:$1"]);
	$client->execute(["musicip", "play"]);

	return 1;
}

sub canDirectStream { 0 }

sub isRemote { 0 }

sub contentType {
	return 'mood';
}

sub getIcon {
	return 'plugins/MusicMagic/html/images/icon.png';
}

1;
