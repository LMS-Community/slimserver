package Slim::Web::Settings::Server::Plugins;

# $Id$

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::PluginManager;

sub name {
	return 'PLUGINS';
}

sub page {
	return 'settings/server/plugins.html';
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	# If this is a settings update
	if ($paramRef->{'submit'}) {

		# XXXX - handle install / uninstall / enable / disable

	}

	$paramRef->{'plugins'}  = Slim::Utils::PluginManager->allPlugins;
	$paramRef->{'nosubmit'} = 1;

	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
