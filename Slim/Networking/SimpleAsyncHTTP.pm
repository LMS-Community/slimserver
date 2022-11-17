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

sub init {
=pod
	Slim::Networking::Slimproto::addHandler( HTTP => \&playerHTTPResponse );
	Slim::Networking::Slimproto::addHandler( HTTE => \&playerHTTPError );
=cut
}

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

=pod
	# Use the player for making the HTTP connection if requested
	if ( my $client = $params->{usePlayer} ) {
		# We still have to do DNS lookups in SC unless
		# we have an IP host
		if ( Slim::Utils::Network::ip_is_ipv4( $request->uri->host ) ) {
			sendPlayerRequest( $request->uri->host, $self, $client, $request );
		}
		else {
			my $dns = Slim::Networking::Async->new;
			$dns->open( {
				Host        => $request->uri->host,
				onDNS       => \&sendPlayerRequest,
				onError     => \&onError,
				passthrough => [ $self, $client, $request ],
			} );
		}
		return;
	}
=cut
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

	$self->ecb->( $self, $error );

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

=pod
sub sendPlayerRequest {
	my ( $ip, $self, $client, $request ) = @_;

	# Set protocol
	$request->protocol( 'HTTP/1.0' );

	# Add headers
	my $headers = $request->headers;

	my $host = $request->uri->host;
	my $port = $request->uri->port;
	if ( $port != 80 ) {
		$host .= ':' . $port;
	}

	# Fix URI to be relative
	# XXX: Proxy support
	my $fullpath = $request->uri->path_query;
	$fullpath = "/$fullpath" unless $fullpath =~ /^\//;
	$request->uri( $fullpath );

	# Host doesn't use init_header so it will be changed if we're redirecting
	$headers->header( Host => $host );

	$headers->init_header( 'User-Agent'    => Slim::Utils::Misc::userAgentString() );
	$headers->init_header( Accept          => '*/*' );
	$headers->init_header( 'Cache-Control' => 'no-cache' );
	$headers->init_header( Connection      => 'close' );
	$headers->init_header( 'Icy-Metadata'  => 1 );

	if ( $request->content ) {
		$headers->init_header( 'Content-Length' => length( $request->content ) );
	}

	# Maintain state for http callback
	$client->httpState( {
		cb      => \&gotPlayerResponse,
		ip      => $ip,
		port    => $port,
		request => $request,
		self    => $self,
	} );

	my $requestStr = $request->as_string("\015\012");

	my $limit = $self->{params}->{limit} || 0;

	my $data = pack( 'NnCNn', Slim::Utils::Network::intip($ip), $port, 0, $limit, length($requestStr) );
	$data   .= $requestStr;

	$client->sendFrame( http => \$data );

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug(
			  "Using player " . $client->id
			. " to send request to $ip:$port (limit $limit):\n" . $request->as_string
		);
	}
}

sub gotPlayerResponse {
	my ( $body_ref, $self, $request ) = @_;

	if ( length $$body_ref ) {
		# Buffer body chunks
		$self->{_body} .= $$body_ref;

		main::DEBUGLOG && $log->is_debug && $log->debug('Buffered ' . length($$body_ref) . ' bytes of player HTTP response');
	}
	else {
		# Response done
		# Turn the response into an HTTP::Response and handle as usual
		my $response = HTTP::Response->parse( delete $self->{_body} );

		# XXX: No support for redirects yet

		my $http = Slim::Networking::Async::HTTP->new();
		$http->request( $request );
		$http->response( $response );

		onBody( $http, $self );
	}
}

sub playerHTTPResponse {
	my ( $client, $data_ref ) = @_;

	my $state = $client->httpState;

	$state->{cb}->( $data_ref, $state->{self}, $state->{request} );
}

sub playerHTTPError {
	my ( $client, $data_ref ) = @_;

	my $reason = unpack 'C', $$data_ref;

	# disconnection reasons
	my %reasons = (
		0   => 'Connection closed normally',              # TCP_CLOSE_FIN
		1   => 'Connection reset by local host',          # TCP_CLOSE_LOCAL_RST
		2   => 'Connection reset by remote host',         # TCP_CLOSE_REMOTE_RST
		3   => 'Connection is no longer able to work',    # TCP_CLOSE_UNREACHABLE
		4   => 'Connection timed out',                    # TCP_CLOSE_LOCAL_TIMEOUT
		255 => 'Connection in use',
	);

	my $error = $reasons{$reason};

	my $state = $client->httpState;
	my $self  = $state->{self};

	# Retry if connection was in use
	if ( $reason == 255 ) {
		main::DEBUGLOG && $log->is_debug && $log->debug( "Player HTTP connection was in use, retrying..." );

		Slim::Utils::Timers::setTimer(
			undef,
			Time::HiRes::time() + 0.5,
			sub {
				my $requestStr = $state->{request}->as_string("\015\012");

				my $limit = $self->{params}->{limit} || 0;

				my $data = pack( 'NnCNn', Slim::Utils::Network::intip( $state->{ip} ), $state->{port}, 0, $limit, length($requestStr) );
				$data   .= $requestStr;

				$client->sendFrame( http => \$data );
			},
		);

		return;
	}

	main::DEBUGLOG && $log->is_debug && $log->debug( "Player HTTP error: $error [$reason]" );

	$self->error( $error );

	$self->ecb->( $self, $error );
}
=cut

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
