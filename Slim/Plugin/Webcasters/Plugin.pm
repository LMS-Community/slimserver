package Slim::Plugin::Webcasters::Plugin;

# $Id$

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

use Slim::Plugin::Webcasters::Plugin::AbsoluteRadio;
use Slim::Plugin::Webcasters::Plugin::AccuRadio;
use Slim::Plugin::Webcasters::Plugin::BBC;
use Slim::Plugin::Webcasters::Plugin::DIFM;
use Slim::Plugin::Webcasters::Plugin::SomaFM;
use Slim::Plugin::Webcasters::Plugin::SkyFM;

sub initPlugin {
	my $class = shift;
	
	# Load other sub-plugins
	Slim::Plugin::Webcasters::Plugin::AbsoluteRadio->initPlugin();
	Slim::Plugin::Webcasters::Plugin::AccuRadio->initPlugin();
	Slim::Plugin::Webcasters::Plugin::BBC->initPlugin();
	Slim::Plugin::Webcasters::Plugin::DIFM->initPlugin();
	Slim::Plugin::Webcasters::Plugin::SomaFM->initPlugin();
	Slim::Plugin::Webcasters::Plugin::SkyFM->initPlugin();
}

sub getDisplayName { 'PLUGIN_WEBCASTERS_MODULE_NAME' }

sub playerMenu { 'RADIO' }

1;