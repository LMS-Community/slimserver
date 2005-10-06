package Slim::Networking::SimpleAsyncHTTP;

# $Id$

# SlimServer Copyright (c) 2003-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# this class provides non-blocking http requests from SlimServer.
# That is, use this class for your http requests to ensure that
# SlimServer does not become unresponsive, or allow music to pause,
# while your code waits for a response

# This class is intended for plugins and other code needing simply to
# process the result of an http request.  If you have more complex
# needs, i.e. handle an http stream, or just interested in headers,
# take a look at HttpAsync.

# more documentation at end of file.

use strict;

use Slim::Networking::AsyncHTTP;
use Slim::Utils::Misc;

sub new {
	my $class    = shift;
	my $callback = shift;
	my $errorcb  = shift;
	my $params   = shift || {};

	my $self = {
		'cb'     => $callback,
		'ecb'    => $errorcb,
		'params' => $params,
	};

	return bless $self, $class;
}

sub params {
	my ($self, $key, $value) = @_;

	if (!defined($key)) {

		return $self->{'params'};

	} elsif ($value) {

		$self->{'params'}->{$key} = $value;

	} else {

		return $self->{'params'}->{$key};
	}
}

sub get {
	my $self = shift;

	$self->_createHTTPRequest('GET', @_);
}

sub post {
	my $self = shift;

	$self->_createHTTPRequest('POST', @_);
}

# Parameters are passed to Net::HTTP::NB::formatRequest, meaning you
# can override default headers, and pass in content.
# Examples:
# $http->post("www.somewhere.net", 'conent goes here');
# $http->post("www.somewhere.net", 'Content-Type' => 'application/x-foo', 'Other-Header' => 'Other Value', 'conent goes here');
sub _createHTTPRequest {
	my $self = shift;
	my $type = shift;
	my $url  = shift;

	$self->{'url'} = $url;

	$::d_http_async && msg("SimpleAsyncHTTP: ${type}ing $url\n");
	
	# start asynchronous get
	# we'll be called back when its done.
	my ($server, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($url);

	# even though we've set non-blocking.  This call could block on a
	# system call to inet_ntoa.  That is, DNS lookups still block.
	my $http = Slim::Networking::AsyncHTTP->new(
		Host     => $server,
		PeerPort => $port
	);

	# error if we failed to connect
	if (!$http) {
		$self->{'error'} = "Failed to connect to $server:$port.  Perl's error is '$!'.\n";
		&{$self->{'ecb'}}($self);
		return;
	}

	# TODO: handle basic auth if username, password provided
	$http->write_request_async($type => $path, @_);
	
	$http->read_response_headers_async(\&headerCB, {
		'simple' => $self,
		'socket' => $http,
	});

	$self->{'socket'} = $http;
}

sub headerCB {
	my ($state, $error, $code, $mess, %h) = @_;
	
	my $self = $state->{'simple'};
	my $http = $state->{'socket'};

	$::d_http_async && msgf("SimpleAsyncHTTP: status for %s is %s - fileno: %d\n", $self->{'url'}, ($mess || $code), fileno($http));

	# verbose debug
	#use Data::Dumper;
	#print Dumper(\%h);

	# handle http redirect
	my $location = $h{'Location'} || $h{'location'};

	if (defined $location) {

		$::d_http_async && msg("SimpleAsyncHTTP: redirecting to $location.  Original URL ". $self->{'url'} . "\n");

		$self->get($location);

		$http->close();

		return;
	}

	if ($error) {

		&{$self->{'ecb'}}($self);

	} else {

		$self->{'code'}    = $code;
		$self->{'mess'}    = $mess;
		$self->{'headers'} = \%h;

		# headers read OK, get the body
		$http->read_entity_body_async(\&bodyCB, {
			'simple' => $self,
			'socket' => $http
		});
	}
}

sub bodyCB {
	my ($state, $error, $content) = @_;

	my $self = $state->{'simple'};
	my $http = $state->{'socket'};

	if ($error) {

		&{$self->{'ecb'}}($self);

	} else {

		$self->{'content'} = $content;

		&{$self->{'cb'}}($self);
	}	
}

sub content {
	my $self = shift;

	return $self->{'content'};
}

sub headers {
	my $self = shift;

	return $self->{'headers'};
}

sub url {
	my $self = shift;

	return $self->{'url'};
}

sub error {
	my $self = shift;

	return $self->{'error'};
}

sub close {
	my $self = shift;

	if ($self->{'socket'}) {

		$self->{'socket'}->close;
	}
}

sub DESTROY {
	my $self = shift;

	$::d_http_async && msgf("SimpleAsyncHTTP(%s) destroy called.\n", $self->url);

	$self->close;
}

1;

__END__

=head NAME

Slim::Networking::SimpleAsyncHTTP - asynchronous non-blocking HTTP client

=head SYNOPSIS

use Slim::Networking::SimpleAsyncHTTP

sub exampleErrorCallback {
    my $http = shift;

    print("Oh no! An error!\n");
}

sub exampleCallback {
    my $http = shift;

    my $content = $http->content();

    my $data = $http->params('mydata');

    print("Got the content and my data.\n");
}


my $http = Slim::Networking::SimpleAsyncHTTP->new(\&exampleCallback, \&exampleErrorCallback, {
		'mydata' => 'foo'
	   });

# sometime after this call, our exampleCallback will be called with the result
$http->get("http://www.slimdevices.com");

# that's all folks.

=head1 DESCRIPTION

This class provides a way within the SlimServer to make an http
request in an asynchronous, non-blocking way.  This is important
because the server will remain responsive and continue streaming audio
while your code waits for the response.

=cut

