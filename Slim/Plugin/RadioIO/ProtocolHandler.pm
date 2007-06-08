package Slim::Plugin::RadioIO::ProtocolHandler;

# $Id$

# SlimServer Copyright (c) 2001-2004 Vidur Apparao, Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use base qw(Slim::Player::Protocols::HTTP);

use Scalar::Util qw(blessed);

use Slim::Player::Source;

sub new {
	my $class  = shift;
	my $args   = shift;

	my $url    = $args->{url};
	my $client = $args->{client};

	if ( $url !~ m{^radioio://(.*?)\.mp3} ) {
		return;
	}
	
	my $url = Slim::Plugin::RadioIO::Plugin::getHTTPURL($1) || return;

	my $sock = $class->SUPER::new( {
		url    => $url,
		client => $client
	} ) || return;
}

sub canDirectStream {
	my ($self, $client, $url) = @_;

	if ( $url =~ m{^radioio://(.*?)\.mp3} ) {
		return Slim::Plugin::RadioIO::Plugin::getHTTPURL($1);
	}

	return;
}

sub getHTTPURL {
	my ( $self, $url ) = @_;
	
	return $self->canDirectStream( undef, $url );
}

1;
