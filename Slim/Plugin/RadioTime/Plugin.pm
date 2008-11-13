package Slim::Plugin::RadioTime::Plugin;

# $Id: Plugin.pm 11021 2006-12-21 22:28:39Z dsully $

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
use base qw(Slim::Plugin::OPMLBased);

use Slim::Plugin::RadioTime::Metadata;

sub initPlugin {
	my $class = shift;
	
	# Initialize metadata handler
	Slim::Plugin::RadioTime::Metadata->init();
}

sub getDisplayName { 'PLUGIN_RADIOTIME_MODULE_NAME' }

sub playerMenu { undef }

1;