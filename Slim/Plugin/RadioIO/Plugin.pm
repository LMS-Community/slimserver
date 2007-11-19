package Slim::Plugin::RadioIO::Plugin;

# $Id: Plugin.pm 7196 2006-04-28 22:00:45Z andy $

# SqueezeCenter Copyright (c) 2001-2007 Vidur Apparao, Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Networking::SqueezeNetwork;

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(
		feed           => Slim::Networking::SqueezeNetwork->url('/api/radioio/v1/opml'),
		tag            => 'radioio',
		'icon-id'      => 'html/images/ServiceProviders/radioio.png',
		menu           => 'radio',
	);
}

sub playerMenu () {
	return 'RADIO';
}

sub getDisplayName {
	return 'PLUGIN_RADIOIO_MODULE_NAME';
}

1;
