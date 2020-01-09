package Slim::Web::HTTP::ClientConn;


# Subclass of HTTP::Daemon::ClientConn that represents a web client

use strict;
use base 'HTTP::Daemon::ClientConn';

# Avoid IO::Socket's import method
sub import {}

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

# Request start time
sub start_time {
	my ( $self, $value ) = @_;
	
	if ( defined $value ) {
		${*$self}{_start} = $value;
	}
	
	return ${*$self}{_start};
}

# Special event that should be returned first (usually /meta/connect)
sub first_event {
	my ( $self, $value ) = @_;
	
	if ( defined $value ) {
		${*$self}{_first_event} = $value;
		return;
	}
	
	# Can only be retrieved once
	return delete ${*$self}{_first_event};
}

1;