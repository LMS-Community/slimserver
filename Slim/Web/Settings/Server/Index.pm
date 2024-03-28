package Slim::Web::Settings::Server::Index;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('settings/index.html');
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
