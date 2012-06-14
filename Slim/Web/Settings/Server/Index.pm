package Slim::Web::Settings::Server::Index;

# $Id: UserInterface.pm 13299 2007-09-27 08:59:36Z mherger $

# Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

sub new {
	my $class = shift;
	
	# register the settings page as the main landing page when local players are not supported
	if (!main::LOCAL_PLAYERS) {
		Slim::Web::Pages->addPageFunction(qr/^$/, sub {$class->handler(@_)});
	}
	
	return $class->SUPER::new(@_);	
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('settings/index.html');
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
