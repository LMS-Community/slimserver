package Slim::Web::Settings::Server::Index;

# $Id: UserInterface.pm 13299 2007-09-27 08:59:36Z mherger $

# SqueezeCenter Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

sub page {
	return Slim::Web::HTTP::protectURI('settings/index.html');
}

sub handler {
	my ($class, $client, $paramRef) = @_;
	
	$paramRef->{firstLevelItems} = [
		'BASIC_SERVER_SETTINGS',
		'ITUNES',
		'PLUGIN_PODCAST',
		'SQUEEZENETWORK_SETTINGS',
		'INTERFACE_SETTINGS',
		'SETUP_GROUP_PLUGINS',
		'SERVER_STATUS'
	];
	
	$paramRef->{'additionalLinks'} = \%Slim::Web::Pages::additionalLinks;

	return Slim::Web::HTTP::filltemplatefile($class->page, $paramRef);
}

1;

__END__
