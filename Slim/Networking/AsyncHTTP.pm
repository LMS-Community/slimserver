package Slim::Networking::AsyncHTTP;

# $Id$

# SlimServer Copyright (c) 2003-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# this class provides non-blocking http requests from SlimServer.
# That is, use this class for your http requests to ensure that
# SlimServer does not become unresponsive, or allow music to pause,
# while your code waits for a response.

# This class is an instance of Socket, and it provides a relatively
# low level API.  If all you need is to request a page from a web
# site, take a look at SimpleAsyncHTTP.

# more documentation at end of file.

use strict;
use base qw(Net::HTTP::NB);
use Socket qw(:DEFAULT :crlf);

use IO::Select;
use Slim::Utils::Misc;

# we override new in case we are using a proxy
sub new {
	my $class = shift;
	my %args  = @_;
	
	my $server = $args{'Host'};
	my $proxy   = Slim::Utils::Prefs::get('webproxy');
	# Don't proxy for localhost requests.
	if ($proxy && $server ne 'localhost' && $server ne '127.0.0.1') {
		my $host = $args{'Host'};
		my $port = $args{'PeerPort'};
		
		$::d_http_async && msg("AsyncHTTP: Using proxy to connect to $host:$port\n");

		# create instance using proxy server and port
		my ($pserver, $pport) = split /:/, $proxy;
		$args{'Host'} = $pserver;
		$args{'PeerPort'} = $pport || 80;
		my $self = $class->SUPER::new(%args);
		# now remember the original host and port, we'll need them to format the request
		${*self}{'httpasync_host'} = $host;
		${*self}{'httpasync_port'} = $port;
		return $self;
	} else {
		$::d_http_async && msg("AsyncHTTP: Connecting to $server\n");
		return $class->SUPER::new(%args);
	}
}

# override to handle proxy
# TODO: make username, password easy to provide. For now, caller can explicitly include Authorization header
sub format_request {
    my $self = shift;
    my $method = shift;
    my $path = shift;

	my %headers;

	my $proxy   = Slim::Utils::Prefs::get('webproxy');
	# Don't proxy for localhost requests.
	if ($proxy && ${*self}{'httpasync_host'}) {
		$path = "http://".${*self}{'httpasync_host'}.":".${*self}{'httpasync_port'} . $path;
		$headers{'Host'} = ${*self}{'httpasync_host'};
	}

	# more headers copied from Slim::Player::Protocol::HTTP
	$headers{'User-Agent'} = "iTunes/3.0 ($^O; SlimServer $::VERSION)";
	$headers{'Accept'} = "*/*";
	$headers{'Cache-Control'} = "no-cache";
	$headers{'Connection'} = "close";
	$headers{'Icy-Metadata'} = "1";

	# when calling SUPER::format_request, include @_ after %headers, so caller may override defaults
	# @_ may contain additional headers and content
	return $self->SUPER::format_request($method=>$path, %headers, @_);
}

# don't use write_request.  Use write_request_async instead.
sub write_request {
	assert(0, "Called ". __PACKAGE__ ."::write_request.  You should call write_request_async instead!\n");

	my $self = shift;
	$self->SUPER::write_request(@_);
}

sub write_request_async {
	my $self = shift;

	# TODO: add support for proxies and authentication
	my $request = $self->format_request(@_);

	$::d_http_async && msg("AsyncHTTP: Sending request:\n$request\n\n");

	# write request in non-blocking fashion
	# this method will return immediately
	Slim::Networking::Select::writeNoBlock(
		$self,
		\$request
	);
}

# don't use.  Use _async version instead.
sub read_response_headers {
	assert(0, "Called ". __PACKAGE__ ."::read_response_headers.  You should call read_response_headers_async instead!\n");

	my $self = shift;
	$self->SUPER::read_response_headers(@_);
}

sub read_response_headers_async {
	my $self = shift;
	my $callback = shift;
	my $args = shift;

	my $state = {callback => $callback,
				 args => $args};

	${*self}{'httpasync_state'} = $state;

	Slim::Networking::Select::addError(
		$self,
		\&errorCallback
	);
	Slim::Networking::Select::addRead(
		$self,
		\&readHeaderCallback
	);

}

# don't use.  Use _async version instead.
sub read_entity_body {
	assert(0, "Called ". __PACKAGE__ ."::read_entity_body.  You should call read_entity_body_async instead!\n");

	my $self = shift;
	$self->SUPER::read_entity_body(@_);
}
sub read_entity_body_async {
	my $self = shift;
	my $callback = shift;
	my $args = shift;
	my $bufsize = shift || 1024;

	my $state = {
		callback => $callback,
		args => $args,
		bufsize => $bufsize,
		body => '',
	};

	${*self}{'httpasync_state'} = $state;

	Slim::Networking::Select::addError(
		$self,
		\&errorCallback
	);
	Slim::Networking::Select::addRead(
		$self,
		\&readBodyCallback
	);

}

# readCallback is called by select loop when our socket has data
sub readHeaderCallback {
	my $self = shift;

	my $state = ${*self}{'httpasync_state'};

	my($code, $mess, %h) = $self->SUPER::read_response_headers;
	if ($code) {
		# headers complete, remove ourselves from select loop
		Slim::Networking::Select::addError($self);
		Slim::Networking::Select::addRead($self);

		$::d_http_async && msg("AsyncHTTP: Headers read.  status=$mess\n");

		# all headers complete.  Call callback
		if ($state->{callback}) {
			$state->{callback}($state->{args}, undef, $code, $mess, %h);
		}
	}

	# else, we will be called again later, after all headers are read
}

# readCallback is called by select loop when our socket has data
sub readBodyCallback {
	my $self = shift;

	my $state = ${*self}{'httpasync_state'};
	my $buf;
	my $result = $self->SUPER::read_entity_body($buf,
												$state->{bufsize});
	$state->{body} .= $buf;

	if ($result == 0) {
		# if here, we've reached the end of the body

		# remove self from select loop
		Slim::Networking::Select::addError($self);
		Slim::Networking::Select::addRead($self);

		$::d_http_async && msg("AsyncHTTP: Body read\n");

		# callback
		if ($state->{callback}) {
			$state->{callback}($state->{args}, undef, $state->{body});
		}

	}
	# else we will be called again when the next buffer has been read

}

sub errorCallback {
	my $self = shift;

	my $state = ${*self}{'httpasync_state'};

	# remove self from select loop
	Slim::Networking::Select::addError($self);
	Slim::Networking::Select::addRead($self);

	$::d_http_async && msg("AsyncHTTP: Error!!\n\n");

	# callback
	if ($state->{callback}) {
		$state->{callback}($state->{args}, 1);
	}	
}

sub close {
	my $self = shift;

	$self->SUPER::close();
	# remove self from select loop
	Slim::Networking::Select::addError($self);
	Slim::Networking::Select::addRead($self);
	Slim::Networking::Select::addWrite($self);
	
}

1;

__END__

=head NAME

Slim::Networking::AsyncHTTP - asynchronous non-blocking HTTP client

=head SYNOPSIS

use Slim::Networking::AsyncHTTP

sub testHeaderCallback {
	my $socket = shift;	
	my $error = shift;
	my ($code, $mess, %h) = @_;
	msg("in HeaderCallback, status is ".$mess."\n");

	# now we can read the body...
	$socket->read_entity_body_async(\&testBodyCallback, $socket);
}

sub testBodyCallback {
	my $socket = shift;
	my $error = shift;
	my $body = shift;

	msg("in BodyCallback, content length is ".length($body)."\n");
}


my $s = Slim::Networking::AsyncHTTP->new(Host => "www.slimdevices.com");

$s->write_request_async(
	GET => "/"
);

$s->read_response_headers_async(\&testHeaderCallback, $s);

=head1 DESCRIPTION

This class is based upon C<Net::HTTP> and C<Net::HTTP::NB>.  It is for use within the SlimServer only, as it is integrated within the SlimServer select loop.  It allows plugins to make HTTP requests in a non-blocking fashion, thus not interfering with the responsiveness of the SlimServer while waiting for the request to complete.

This class is an instance of Socket, and it provides a relatively
low level API.  If all you need is to request a page from a web
site, take a look at SimpleAsyncHTTP.

=cut

