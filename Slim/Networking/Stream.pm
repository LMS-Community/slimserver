package Slim::Networking::Stream;

# $Id$

# SlimServer Copyright (c) 2003-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This class is similar to SimpleAsyncHTTP, but deals with streaming HTTP

# XXX: All the async modules need to be refactored at some point, they are a bit of a mess

use strict;

use base qw(Class::Accessor::Fast);

use Slim::Networking::AsyncHTTP;
use Slim::Utils::Misc;

use HTTP::Date ();
use MIME::Base64 qw(encode_base64);

__PACKAGE__->mk_accessors( qw/
	url
	args
	server
	port
	path
	user
	password
	error
	socket
	redirect_from
	code
	mess
	headers
	content_type
	bodyref
/ );

# Open a connection to a stream
sub open {
	my ( $self, $url, $args ) = @_;
		
	my ($server, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($url);
	
	$self->url     ( $url );
	$self->args    ( $args );
	$self->server  ( $server );
	$self->port    ( $port );
	$self->path    ( $path );
	$self->user    ( $user );
	$self->password( $password );
	
	my $timeout 
		=  $args->{'Timeout'} 
		|| Slim::Utils::Prefs::get('remotestreamtimeout')
		|| 10;
	
	Slim::Networking::AsyncHTTP->new(
		Host     => $server,
		PeerPort => $port,
		Timeout  => $timeout,
		
		errorCallback => \&errorCallback,
		writeCallback => \&writeCallback,
		callbackArgs  => [ $self ],
	);
}

sub errorCallback {
	my $http = shift;
	my $self = shift;

	my $server = $self->server;
	my $port   = $self->port;
	
	$self->error( "Failed to connect to $server:$port.  Perl's error is '$!'.\n" );
	
	my $ecb = $self->args->{'onError'} || sub {};
	$ecb->( $self );
}

sub writeCallback {
	my $http = shift;
	my $self = shift;
	
	$self->socket( $http );
	
	# if the caller requested an onOpen event, pass back to them
	if ( my $onOpen = $self->args->{'onOpen'} ) {
		return $onOpen->( $self );
	}
	
	# Otherwise, continue and make the request
	
	# handle basic auth if username, password provided
	my @headers = ();
	if ( $self->user || $self->password ) {
		unshift @headers, (
			'Authorization' => 'Basic ' . encode_base64( $self->user . ":" . $self->password ),
		);
	}
	
	# Only GET supported
	$http->write_request_async( GET => $self->path, @headers );
	
	$http->read_response_headers_async(
		\&headerCB, 
		{
			'self' => $self,
		}
	);
}

sub headerCB {
	my ($state, $error, $code, $mess, $headers) = @_;
	
	# Don't leak the reference to ourselves.
	my $self = delete $state->{'self'};

	if ( $error || !ref $headers ) {
		$self->error( $error );
		my $ecb = $self->args->{'onError'} || sub {};
		return $ecb->( $self );
	}

	$::d_http_async && msgf("Async Stream: status for %s is %s\n", $self->{'url'}, ($mess || $code));

	# verbose debug
	# use Data::Dumper;
	# print Dumper($headers);

	# handle http redirect
	my $location = $headers->header('Location');

	if (defined $location) {

		$::d_http_async && msg("Async Stream: redirecting to $location.  Original URL ". $self->url . "\n");
		
		$self->socket->close;
		
		$self->{redirect_from} ||= [];
		push @{ $self->{redirect_from} }, $self->url;
		
		return $self->open( $location, $self->args );
	}

	$self->code   ( $code );
	$self->mess   ( $mess );
	$self->headers( $headers );
	$self->content_type( $headers->content_type );
	
	if ( my $onHeaders = $self->args->{'onHeaders'} ) {
		return $onHeaders->( $self );
	}
}

sub readBody {
	my ( $self, $callback ) = @_;
	
	$self->{'_body_callback'} = $callback;
	
	$self->socket->read_entity_body_async(
		\&bodyCB, 
		{
			'self' => $self,
		}
	);
}

sub bodyCB {
	my ($state, $error, $content) = @_;

	# Don't leak the reference to ourselves.
	my $self = delete $state->{'self'};

	if ($error) {
		$self->error( $error );
		my $ecb = $self->args->{'onError'} || sub {};
		return $ecb->( $self );

	} 
	else {
		$self->bodyref( \$content );

		my $cb = delete $self->{'_body_callback'};
		$cb->( $self );
	}
}

sub close {
	my $self = shift;

	if (defined $self->{'socket'} && fileno($self->{'socket'})) {
		
		$::d_http_async && msgf("Stream Async: closing socket for [%s]\n", $self->url);

		$self->{'socket'}->close;
	}
}

sub DESTROY {
	my $self = shift;

	$self->close;
}

1;

__END__