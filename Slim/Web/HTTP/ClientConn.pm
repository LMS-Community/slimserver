package Slim::Web::HTTP::ClientConn;

# $Id$

# Subclass of HTTP::Daemon::ClientConn that represents a web client

use strict;
use base 'HTTP::Daemon::ClientConn';

sub sent_headers {
	my ( $self, $value ) = @_;
	
	if ( defined $value ) {
		${*$self}{_sent_headers} = $value;
	}
	
	return ${*$self}{_sent_headers};
}

# Cometd client id
sub clid {
	my ( $self, $value ) = @_;

	if ( defined $value ) {
		${*$self}{_clid} = $value;
	}

	return ${*$self}{_clid};
}

# Cometd transport type
sub transport {
	my ( $self, $value ) = @_;

	if ( defined $value ) {
		${*$self}{_transport} = $value;
	}

	return ${*$self}{_transport};
}	

1;