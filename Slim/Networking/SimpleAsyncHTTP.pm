package Slim::Networking::SimpleAsyncHTTP;

# Logitech Media Server Copyright 2003-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# this class provides non-blocking http requests from Logitech Media Server.
# That is, use this class for your http requests to ensure that
# Logitech Media Server does not become unresponsive, or allow music to pause,
# while your code waits for a response

# This class is intended for plugins and other code needing simply to
# process the result of an http request.  If you have more complex
# needs, i.e. handle an http stream, or just interested in headers,
# take a look at HttpAsync.

# more documentation at end of file.

use strict;

use base qw(Slim::Networking::SimpleHTTP::Base);

use Slim::Networking::Async::HTTP;
use Slim::Utils::Log;

my $log = logger('network.asynchttp');

sub init {}

sub new {
	my $class = shift;

	my $self = $class->SUPER::new();

	$self->cb(shift);
	$self->ecb(shift);
	$self->_params( shift || {} );
	$self->_log($log);

	return $self;
}

sub hasSSL {
	Slim::Networking::Async::HTTP->hasSSL()
}

# Parameters are passed to Net::HTTP::NB::formatRequest, meaning you
# can override default headers, and pass in content.
# Examples:
# $http->post("www.somewhere.net", 'content goes here');
# $http->post("www.somewhere.net", 'Content-Type' => 'application/x-foo', 'Other-Header' => 'Other Value', 'conent goes here');
sub _createHTTPRequest {
	my $self = shift;

	my ($request, $timeout) = $self->SUPER::_createHTTPRequest(@_);

	# in case of a cached response we'd return without any response data
	return unless $request && $timeout;

	my $params = $self->_params || {};

	my $http = Slim::Networking::Async::HTTP->new( $self->_params );
	$http->send_request( {
		request     => $request,
		maxRedirect => $params->{maxRedirect},
		saveAs      => $params->{saveAs},
		Timeout     => $timeout,
		onError     => \&onError,
		onBody      => \&onBody,
		passthrough => [ $self ],
	} );
}

sub onError {
	my ( $http, $error, $self ) = @_;

	my $uri = $http->request->uri;

	# If we have a cached copy of this request, we can use it
	if ( $self->cachedResponse ) {

		$log->warn("Failed to connect to $uri, using cached copy. ($error)");

		return $self->sendCachedResponse();
	}
	else {
		$log->warn("Failed to connect to $uri ($error)");
	}

	$self->error( $error );

	main::PERFMON && (my $now = AnyEvent->time);

	$self->ecb->( $self, $error, $http->response );

	main::PERFMON && $now && Slim::Utils::PerfMon->check('async', AnyEvent->time - $now, undef, $self->ecb);

	return;
}

sub onBody {
	my ( $http, $self ) = @_;

	my $req = $http->request;
	my $res = $http->response;

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug(sprintf("status for %s is %s", $self->url, $res->status_line ));
	}

	$self->code( $res->code );
	$self->mess( $res->message );
	$self->headers( $res->headers );

	if ( !$http->saveAs ) {

		my $params = $self->_params;
		my $client = $params->{params}->{client};

		# Check if we are cached and got a "Not Modified" response
		if ( my $response = $self->isNotModifiedResponse($res) ) {
			return $self->sendCachedResponse();
		}

		$self->processResponse($res);
	}

	main::DEBUGLOG && $log->debug("Done");

	main::PERFMON && (my $now = AnyEvent->time);

	$self->cb->( $self );

	main::PERFMON && $now && Slim::Utils::PerfMon->check('async', AnyEvent->time - $now, undef, $self->cb);

	return;
}

sub sendCachedResponse {
	my $self = shift;

	$self->prepareCachedResponse();

	main::PERFMON && (my $now = AnyEvent->time);

	$self->cb->( $self );

	main::PERFMON && $now && Slim::Utils::PerfMon->check('async', AnyEvent->time - $now, undef, $self->cb);

	return;
}

# some helpers to keep backwards compatibility
*_cacheKey = \&Slim::Networking::SimpleHTTP::Base::_cacheKey;
*hasZlib = \&Slim::Networking::SimpleHTTP::Base::hasZlib;

sub close { }

1;

__END__

=head1 NAME

Slim::Networking::SimpleAsyncHTTP - asynchronous non-blocking HTTP client

=head1 SYNOPSIS

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


my $http = Slim::Networking::SimpleAsyncHTTP->new(
	\&exampleCallback,
	\&exampleErrorCallback,
	{
		mydata'  => 'foo',
		cache    => 1,		# optional, cache result of HTTP request
		expires  => '1h',	# optional, specify the length of time to cache
		options  => { key/value },  # optional set of key/value pairs for the underlying socket
		socks    => { key/value },  # optional use of socks tunnel
	}
);

# sometime after this call, our exampleCallback will be called with the result
$http->get("http://www.slimdevices.com");

# that's all folks.

=head1 DESCRIPTION

This class provides a way within the Logitech Media Server to make an http
request in an asynchronous, non-blocking way.  This is important
because the server will remain responsive and continue streaming audio
while your code waits for the response.

=cut
