package Slim::Plugin::DigitalInput::ProtocolHandler;

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

# Fake out Slim::Player::Source::openSong() into thinking we're a direct stream.

use strict;
use base qw(FileHandle);

sub new {
	my $class  = shift;
	my $args   = shift;

	my $url    = $args->{'url'};
	my $client = $args->{'client'};

	if ($url !~ /^source:/) {
		return undef;
	}

	return $class->SUPER::new();
}

sub canDirectStream {
	return 1;
}

sub contentType {
	return 'src';
}

1;
