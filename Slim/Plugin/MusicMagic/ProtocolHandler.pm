package Slim::Plugin::MusicMagic::ProtocolHandler;

# $Id

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use base qw(FileHandle);

sub new {
	my $class  = shift;
	my $args   = shift;

	my $url    = $args->{'url'};
	my $client = $args->{'client'};

	if ($url !~ m|^mood://(.*)$|) {
		return undef;
	}

	$client->execute(["musicip", "mix", "mood:$1"]);
	$client->execute(["musicip", "play"]);

	return $class;
}

sub canDirectStream {
	return 0;
}

sub isAudioUrl {
	return 1;
}

sub contentType {
	return 'mood';
}

sub getIcon {
	return 'plugins/MusicMagic/html/images/icon.png';
}

1;
