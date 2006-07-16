package Slim::Networking::Async::HTTP;

# $Id$

# SlimServer Copyright (c) 2003-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This class provides an async HTTP implementation.

use strict;
use warnings;

BEGIN {
	my $hasSSL;

	sub hasSSL {
		return $hasSSL if defined $hasSSL;
		
		$hasSSL = 0;
		eval { 
			require Slim::Networking::Async::Socket::HTTPS;
			$hasSSL = 1;
		};
		if ($@) {
			msg("Async::HTTP: Unable to load IO::Socket::SSL, will try connecting to SSL servers in non-SSL mode\n");
		}
		
		return $hasSSL;
	}
}

use base 'Slim::Networking::Async';

use HTTP::Headers;
use HTTP::Request;
use HTTP::Response;
use MIME::Base64 qw(encode_base64);
use MPEG::Audio::Frame;
use URI;

use Slim::Networking::Async::Socket::HTTP;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

__PACKAGE__->mk_classaccessors( qw(
	uri request response
) );

# Body buffer size
__PACKAGE__->mk_classaccessor( bufsize => 1024 );

# Max redirects to follow
__PACKAGE__->mk_classaccessor( maxRedirect => 3 );

sub new_socket {
	my $self = shift;
	
	if ( my $proxy = $self->use_proxy ) {
		$::d_http_async && msg("Async::HTTP: Using proxy $proxy to connect\n");
	
		my ($pserver, $pport) = split /:/, $proxy;
	
		return Slim::Networking::Async::Socket::HTTP->new(
			@_,
			PeerAddr => $pserver,
			PeerPort => $pport || 80,
		);
	}
	
	# Create SSL socket if URI is https
	if ( $self->request->uri->scheme eq 'https' ) {
		if ( hasSSL() ) {
			return Slim::Networking::Async::Socket::HTTPS->new( @_ );
		}
		else {
			# change the request to port 80
			$self->request->uri->scheme( 'http' );
			$self->request->uri->port( 80 );
			
			my %args = @_;
			$args{PeerPort} = 80;
			
			$::d_http_async && msg("Async::HTTP: Warning: trying HTTP request to HTTPS server\n");
			
			return Slim::Networking::Async::Socket::HTTP->new( %args );
		}
	}
	else {
		return Slim::Networking::Async::Socket::HTTP->new( @_ );
	}
}

sub use_proxy {
	my $self = shift;
	
	# Proxy will be used for non-local HTTP requests
	if ( my $proxy = Slim::Utils::Prefs::get('webproxy') ) {
		my $host   = $self->request->uri->host;
		my $scheme = $self->request->uri->scheme;
		if ( $scheme ne 'https' && $host !~ /(?:localhost|127.0.0.1)/ ) {
			return $proxy;
		}
	}
	
	return;
}

sub send_request {
	my ( $self, $args ) = @_;
	
	if ( $args->{maxRedirect} ) {
		$self->maxRedirect( $args->{maxRedirect} );
	}
	
	$self->request( 
		$args->{request}
		||
		HTTP::Request->new( $args->{method} => $args->{url} )
	);
	
	if ( !$self->request->protocol ) {
		$self->request->protocol( 'HTTP/1.0' );
	}
	
	$self->add_headers();
	
	$self->write_async( {
		host        => $self->request->uri->host,
		port        => $self->request->uri->port,
		content_ref => \&_format_request,
		skipDNS     => ( $self->use_proxy ) ? 1 : 0,
		onError     => \&_http_error,
		onRead      => \&_http_read,
		passthrough => [ $args ],
	} );
}

# add standard request headers
sub add_headers {
	my $self = shift;
	
	my $headers = $self->request->headers;
	
	# handle basic auth if username, password provided
	if ( my $userinfo = $self->request->uri->userinfo ) {
		$headers->init_header( Authorization => 'Basic ' . encode_base64( $userinfo ) );
	}
	
	my $host = $self->request->uri->host;
	if ( $self->request->uri->port != 80 ) {
		$host .= ':' . $self->request->uri->port;
	}

	# Host doesn't use init_header so it will be changed if we're redirecting
	$headers->header( Host => $host );
	
	$headers->init_header( 'User-Agent'    => Slim::Utils::Misc::userAgentString() );
	$headers->init_header( Accept          => '*/*' );
	$headers->init_header( 'Cache-Control' => 'no-cache' );
	$headers->init_header( Connection      => 'close' );
	$headers->init_header( 'Icy-Metadata'  => 1 );
}

sub read_mpeg_frames {
	my ( $self, $args ) = @_;
	
	if ( $self->socket && $args->{onFrame} ) {
		
		my $max = $args->{maxFrames} || 20;
		while ( my $frame = MPEG::Audio::Frame->read( $self->socket ) ) {
			last unless --$max;
			
			my $onFrame = $args->{onFrame};
			$onFrame->( $frame );
		}
		
		if ( $args->{disconnect} ) {
			$self->disconnect;
		}
	}
}

sub _format_request {
	my $self = shift;
	
	my $fullpath = $self->request->uri->path_query;
	$fullpath = "/$fullpath" unless $fullpath =~ /^\//;
	
	# Proxy requests require full URL
	if ( $self->use_proxy ) {
		$fullpath = $self->request->uri->as_string;
	}
	
	my @h;
	$self->request->headers->scan( sub {
		my ($k, $v) = @_;
		$k =~ s/^://;
		$v =~ s/\n/ /g;
		push @h, $k, $v;
	} );
	
	my $content_ref = $self->request->content_ref;
	if ( ref $content_ref ) {
		if ( my $length = length $$content_ref ) {
			push @h, 'Content-Length' => $length;
		}
	}
	
	my $request = $self->socket->format_request(
		$self->request->method,
		$fullpath,
		@h,
	);
	
	# add POST body
	if ( ref $content_ref ) {
		$request .= $$content_ref;
	}
	
	return \$request;
}

# After reading headers, some callers may want to continue and
# read the body
sub read_body {
	my $self = shift;
	my $args = shift;

	$self->socket->set( passthrough => [ $self, $args ] );
	
	Slim::Networking::Select::addError( $self->socket, \&_http_socket_error );
	Slim::Networking::Select::addRead( $self->socket, \&_http_read_body );
}

sub _http_socket_error {
	my ( $socket, $self, $args ) = @_;
	
	$self->disconnect;
	
	return $self->_http_error( "Error on HTTP socket: $!", $args );
}

sub _http_error {
	my ( $self, $error, $args ) = @_;
	
	$self->disconnect;

	if ( my $ecb = $args->{onError} ) {
		my $passthrough = $args->{passthrough} || [];
		$ecb->( $self, $error, @{$passthrough} );
	}
}

sub _http_read {
	my ( $self, $args ) = @_;
	
	my ($code, $mess, @h) = eval { $self->socket->read_response_headers };
	
	if ($@) {
		$::d_http_async && msg("Async::HTTP: Error reading headers: $@\n");
		$self->_http_error( "Error reading headers: $@", $args );
		return;
	}
	
	if ($code) {
		# headers complete, remove ourselves from select loop
		Slim::Networking::Select::removeError( $self->socket );
		Slim::Networking::Select::removeRead( $self->socket );
		
		# do we have a previous response from a redirect?
		my $previous = [];
		if ( $self->response ) {
			if ( $self->response->previous ) {
				$previous = $self->response->previous;
			}
			push @{$previous}, $self->response->clone;
		}
		
		my $headers = HTTP::Headers->new;
		while ( @h ) {
			my ($k, $v) = splice @h, 0, 2;
			$headers->push_header( $k => $v );
		}
		$self->response( HTTP::Response->new( $code, $mess, $headers ) );
		
		# Save previous response
		$self->response->previous( $previous );
		
		if ( $::d_http_async ) {
			msg("Async::HTTP: Headers read. code: $code status: $mess\n");
			warn Data::Dump::dump( $self->response->headers ) . "\n";
		}
		
		if ( $code !~ /[23]\d\d/ ) {
			return $self->_http_error( $self->response->status_line, $args );
		}
		
		# Handle redirects
		if ( $code =~ /30[12]/ ) {
			
			# check max redirects
			if ( scalar @{$previous} < $self->maxRedirect ) {
				
				$self->disconnect;
			
				# change the request object to the new location
				delete $args->{request};
				$self->request->uri(
					URI->new_abs( $self->response->header('Location'), $self->request->uri )
				);
				
				$::d_http_async && msgf("Async::HTTP: Redirecting to %s\n",
					$self->request->uri->as_string,
				);
			
				$self->send_request( {
					request => $self->request,
					%{$args},
				} );
			
				return;
			}
			else {
				$::d_http_async && msg("Async::HTTP: Redirection limit exceeded\n");
				
				$self->disconnect;
				
				if ( my $cb = $args->{onError} ) {
					my $passthrough = $args->{passthrough} || [];
					return $cb->( $self, 'Redirection limit exceeded', @{$passthrough} );
				}
				
				return;
			}
		}
		
		# Does the caller want a callback on headers?
		if ( my $cb = $args->{onHeaders} ) {
			my $passthrough = $args->{passthrough} || [];
			return $cb->( $self, @{$passthrough} );
		}
		
		# if not, keep going and read the body
		$self->socket->set( passthrough => [ $self, $args ] );
		
		Slim::Networking::Select::addError( $self->socket, \&_http_socket_error );
		Slim::Networking::Select::addRead( $self->socket, \&_http_read_body );
	}
}

sub _http_read_body {
	my ( $socket, $self, $args ) = @_;
	
	my $result = $socket->read_entity_body( my $buf, $self->bufsize );

	# Add buffer to Response object
	$self->response->add_content( $buf );
	
	if ( !defined $result || $result == 0 ) {
		# if here, we've reached the end of the body
		
		# close and remove the socket
		$self->disconnect;
		
		$::d_http_async && msg("Async::HTTP: Body read\n");
		
		if ( my $cb = $args->{onBody} ) {
			my $passthrough = $args->{passthrough} || [];
			$cb->( $self, @{$passthrough} );
		}
	}
}

1;