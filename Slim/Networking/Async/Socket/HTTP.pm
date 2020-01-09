package Slim::Networking::Async::Socket::HTTP;


# Logitech Media Server Copyright 2003-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This class contains the socket we use for async HTTP communication

use strict;

use base qw(Net::HTTP::NB Slim::Networking::Async::Socket);

# Avoid IO::Socket's import method
sub import {}

use Socket qw(pack_sockaddr_in sockaddr_in);

# IO::Socket::INET's connect method blocks, so we use our own connect method 
# which is non-blocking.  Based on: http://www.perlmonks.org/?node_id=66135
sub connect {
	@_ == 2 || @_ == 3 or
		die 'usage: $sock->connect(NAME) or $sock->connect(PORT, ADDR)';

	# grab our socket
	my $sock = shift;

	# set to non-blocking
	Slim::Utils::Network::blocking( $sock, 0 );

	# pack the host address
	my $addr = @_ == 1 ? shift : pack_sockaddr_in(@_);

	# pass directly to perl's connect() function,
	# bypassing the call to IO::Socket->connect
	# which usually handles timeouts, blocking
	# and error handling.
	connect($sock, $addr);
	
	# Workaround for an issue in Net::HTTP::Methods where peerport is not yet
	# available during an async connection
	${*$sock}{'AsyncPeerPort'} = (sockaddr_in($addr))[0];

	# return immediately
	return 1;
}

# Net::HTTP::Methods doesn't get the right peerport since we are making an 
# async connection, so we store it ourselves
sub peerport {
	my $self = shift;
	return ${*$self}{'AsyncPeerPort'};
}

# Copy of Net::HTTP::NB's sysread method, so we can handle ICY responses
sub sysread {
    my $self = $_[0];

    if (${*$self}{'httpnb_read_count'}++) {
		${*$self}{'http_buf'} = ${*$self}{'httpnb_save'};
		die "Multi-read\n";
    }

    my $buf;
    my $offset = $_[3] || 0;
    my $n = sysread($self, $_[1], $_[2], $offset);
    ${*$self}{'httpnb_save'} .= substr($_[1], $offset);

	if ( !${*$self}{'parsed_status_line'} ) {
		if ( ${*$self}{'httpnb_save'} =~ /^(HTTP|ICY)/ ) {
			my $icy = ${*$self}{'httpnb_save'} =~ s/^ICY/HTTP\/1.0/;
			${*$self}{'parsed_status_line'} = 1;
			
			if ( $icy ) {
				$n += 5;
				$_[1] =~ s/^ICY/HTTP\/1.0/;
			}
		}
	}

    return $n;
}


sub close {
	my $self = shift;

	# remove self from select loop
	Slim::Networking::Select::removeError($self);
	Slim::Networking::Select::removeRead($self);
	Slim::Networking::Select::removeWrite($self);
	Slim::Networking::Select::removeWriteNoBlockQ($self);

	$self->SUPER::close();
}

1;
