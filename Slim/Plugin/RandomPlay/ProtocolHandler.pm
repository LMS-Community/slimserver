package Slim::Plugin::RandomPlay::ProtocolHandler;

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

use Slim::Plugin::RandomPlay::Plugin;

sub new {
	my $class  = shift;
	my $args   = shift;

	my $url    = $args->{'url'};
	my $client = $args->{'client'};

	if ($url !~ m|^randomplay://(.*)$|) {
		return undef;
	}

	$client->execute(["randomplay", "$1"]);

	return $class;
}

sub canDirectStream { 0 }

sub contentType {
	return 'rnd';
}

sub getIcon {
	return Slim::Plugin::RandomPlay::Plugin->_pluginDataFor('icon');
}

1;
