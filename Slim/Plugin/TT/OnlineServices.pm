package Slim::Plugin::TT::OnlineServices;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Template::Plugin);

my $services;

sub load {
	my ($class, $context) = @_;

	if (Slim::Utils::PluginManager->isEnabled('Slim::Plugin::OnlineLibrary::Plugin')) {
		require Slim::Plugin::OnlineLibrary::Plugin;
		$services = 1;
	}

	return $class;
}

sub getIconForId {
	my ($class, $id) = @_;

	return unless $services;

	return Slim::Plugin::OnlineLibrary::Plugin->getServiceIcon($id);
};

1;