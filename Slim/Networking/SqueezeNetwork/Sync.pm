package Slim::Networking::SqueezeNetwork::Sync;

# Logitech Media Server Copyright 2003-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Networking::SimpleSyncHTTP Slim::Networking::SqueezeNetwork::Base);

# both classes from which we inherit implement a sub url() - therefore we have to implement this little wrapper here
sub url { shift->_url(@_); }

# Override to add session cookie header
sub _createHTTPRequest {
	my ( $self, $type, $url, @args ) = @_;

	if ( my $cookie = $self->getCookie( $self->params('client') ) ) {
		unshift @args, 'Cookie', $cookie;
	}

	$self->SUPER::_createHTTPRequest( $type, $url, @args );
}

1;