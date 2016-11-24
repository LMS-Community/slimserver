package Slim::Networking::Async::HTTP;

# $Id$

# Logitech Media Server Copyright 2003-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This class provides an async HTTP implementation.

use strict;

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
use HTTP::Cookies;
use MIME::Base64 qw(encode_base64);
use URI;
use File::Spec::Functions qw(catdir);

use Slim::Networking::Async::Socket::HTTP;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

use constant BUFSIZE   => 16 * 1024;
use constant MAX_REDIR => 7;

my $prefs = preferences('server');

my $cookieJar;

my $log = logger('network.asynchttp');

__PACKAGE__->mk_accessor( rw => qw(
	uri request response saveAs fh timeout maxRedirect
) );

sub init {
	$cookieJar = HTTP::Cookies->new( file => catdir($prefs->get('cachedir'), 'cookies.dat'), autosave => 1 );
}

sub new_socket {
	my $self = shift;
	
	if ( my $proxy = $self->use_proxy ) {

		main::INFOLOG && $log->info("Using proxy $proxy to connect");
	
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
			
			$log->warn("Warning: trying HTTP request to HTTPS server");
			
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
	if ( my $proxy = $prefs->get('webproxy') ) {
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
	
	$self->maxRedirect( $args->{maxRedirect} || MAX_REDIR );
	
	if ( $args->{Timeout} ) {
		$self->timeout( $args->{Timeout} );
	}
	
	# option to save directly to a file
	if ( $args->{saveAs} ) {
		$self->saveAs( $args->{saveAs} );
	}
	
	$self->request( 
		$args->{request}
		||
		HTTP::Request->new( $args->{method} => $args->{url} )
	);
	
	if ( $self->request->uri !~ /^https?:/i ) {
		my $error = 'Cannot request non-HTTP URL ' . $self->request->uri;
		return $self->_http_error( $error, $args );
	}
	
	if ( !$self->request->protocol ) {
		$self->request->protocol( 'HTTP/1.0' );
	}
	
	# XXX until we support chunked encoding, force 1.0
	$self->request->protocol('HTTP/1.0');
	
	$self->add_headers();
	
	$self->write_async( {
		host        => $self->request->uri->host,
		port        => $self->request->uri->port,
		content_ref => \&_format_request,
		Timeout     => $self->timeout,
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
		$headers->header( Authorization => 'Basic ' . encode_base64( $userinfo, '' ) );
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
	
	if ( $headers->header('User-Agent') !~ /^NSPlayer/ ) {
		$headers->init_header( 'Icy-Metadata' => 1 );
	}

	# Add cookies
	if ( !main::SCANNER ) {
		$cookieJar->add_cookie_header( $self->request );
	}
}

# allow people to access our cookie jar
sub cookie_jar {
	return $cookieJar;
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
	
	# Add POST body if any
	my $content_ref = $self->request->content_ref;
	if ( ref $content_ref ) {
		push @h, $$content_ref;
	}
	
	# XXX until we support chunked encoding, force 1.0
	$self->socket->http_version('1.0');
	
	my $request = $self->socket->format_request(
		$self->request->method,
		$fullpath,
		@h,
	);
	
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
	
	Slim::Utils::Timers::killTimers( $socket, \&_http_socket_error );
	
	$self->disconnect;
	
	return $self->_http_error( "Error on HTTP socket: $!", $args );
}

sub _http_error {
	my ( $self, $error, $args ) = @_;
	
	if ( $self->fh ) {
		$self->fh->close;
	}
	
	$self->disconnect;

	# Bug 8801, Only print an error if the caller doesn't have an onError handler	
	if ( my $ecb = $args->{onError} ) {
		my $passthrough = $args->{passthrough} || [];
		$ecb->( $self, $error, @{$passthrough} );
	}
	else {
		$log->error("Error: [$error]");
	}
}

sub _http_read {
	my ( $self, $args ) = @_;
	
	my ($code, $mess, @h) = eval { $self->socket->read_response_headers };
	
	if ($@) {
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
		
		$self->response->request( $self->request );

		# Save cookies
		$cookieJar->extract_cookies( $self->response );
		
		if ( main::DEBUGLOG && $log->is_debug ) {

			$log->debug("Headers read. code: $code status: $mess");
			$log->debug( Data::Dump::dump( $self->response->headers ) );
		}
		
		if ( $code !~ /[23]\d\d/ ) {
			return $self->_http_error( $self->response->status_line, $args );
		}
		
		# Handle redirects
		if ( $code =~ /^30[1237]$/ ) {

			my $location = $self->response->header('Location');
			
			# check max redirects
			if ( $location && scalar @{$previous} < $self->maxRedirect ) {
				
				$self->disconnect;
			
				# change the request object to the new location
				delete $args->{request};
				$self->request->uri(
					URI->new_abs( $location, $self->request->uri )
				);
				
				if ( main::INFOLOG && $log->is_info ) {
					$log->info(sprintf("Redirecting to %s", $self->request->uri->as_string));
				}
				
				# Does the caller want to modify redirecting URLs?
				if ( $args->{onRedirect} ) {
					my $passthrough = $args->{passthrough} || [];
					$args->{onRedirect}->( $self->request, @{$passthrough} );
				}
			
				$self->send_request( {
					request => $self->request,
					%{$args},
				} );
			
				return;
			}
			else {
				my $error = 'Redirection without location';
				
				if ($location) {
					$error = ($location =~ /^https/ && !hasSSL()) ? "Can't connect to https URL lack of IO::Socket::SSL: $location" : 'Redirection limit exceeded';
				}

				$log->warn($error);
				
				$self->disconnect;
				
				if ( my $cb = $args->{onError} ) {
					my $passthrough = $args->{passthrough} || [];
					return $cb->( $self, $error, @{$passthrough} );
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
		
		# Timer in case the server never sends any body data
		my $timeout = $self->timeout || $prefs->get('remotestreamtimeout');
		Slim::Utils::Timers::setTimer( $self->socket, Time::HiRes::time() + $timeout, \&_http_socket_error, $self, $args );
		
		Slim::Networking::Select::addError( $self->socket, \&_http_socket_error );
		Slim::Networking::Select::addRead( $self->socket, \&_http_read_body );
	}
}

sub _http_read_body {
	my ( $socket, $self, $args ) = @_;
	
	Slim::Utils::Timers::killTimers( $socket, \&_http_socket_error );
	Slim::Utils::Timers::killTimers( $socket, \&_http_read_timeout );
	
	my $result = $socket->read_entity_body( my $buf, BUFSIZE );

	if ( $result ) {
		main::DEBUGLOG && $log->debug("Read body: [$result] bytes");
	}
	
	# Are we saving directly to a file?
	if ( $result && $self->saveAs && !$self->fh ) {
		open my $fh, '>', $self->saveAs or do {
			return $self->_http_error( 'Unable to open ' . $self->saveAs . " for writing: $!", $args );
		};

		binmode $fh;
		
		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug("Writing response directly to " . $self->saveAs);
		}
		
		$self->fh( $fh );
	}
	
	if ( $result && $self->saveAs ) {
		# Write directly to a file
		$self->fh->write( $buf, length $buf ) or do {
			return $self->_http_error( 'Unable to write to ' . $self->saveAs . ": $!", $args );
		};
	}
	elsif ( $args->{onStream} ) {
		# The caller wants a callback on every chunk of data streamed
		my $pt   = $args->{passthrough} || [];
		my $more = $args->{onStream}->( $self, \$buf, @{$pt} );
		
		# onStream callback can signal to stop the stream by returning false
		if ( !$more ) {
			$result = 0;
		}
	}
	else {
		# Add buffer to Response object
		$self->response->add_content( $buf );
	}
	
	# Does the caller want us to quit reading early (i.e. for mp3 frames)?
	if ( $args->{readLimit} && length( $self->response->content ) >= $args->{readLimit} ) {
		
		# close and remove the socket
		$self->disconnect;
		
		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug(sprintf("Body read (stopped after %d bytes)", length( $self->response->content )));
		}
		
		if ( my $cb = $args->{onBody} ) {
			my $passthrough = $args->{passthrough} || [];
			return $cb->( $self, @{$passthrough} );
		}
	}
	
	if ( !defined $result || $result == 0 ) {
		# if here, we've reached the end of the body
		
		# close and remove the socket
		$self->fh->close if $self->fh;
		$self->disconnect;
		
		main::DEBUGLOG && $log->debug("Body read");
		
		if ( my $cb = $args->{onBody} ) {
			my $passthrough = $args->{passthrough} || [];
			$cb->( $self, @{$passthrough} );
		}
	}
	else {
		# More body data to read
		
		# Some servers may never send EOF, but we want to return whatever data we've read
		my $timeout = $self->timeout || $prefs->get('remotestreamtimeout');
		Slim::Utils::Timers::setTimer( $socket, Time::HiRes::time() + $timeout, \&_http_read_timeout, $self, $args );
	}
}

sub _http_read_timeout {
	my ( $socket, $self, $args ) = @_;
	
	$log->warn("Timed out waiting for more body data, returning what we have");
	
	Slim::Networking::Select::removeError( $socket );
	Slim::Networking::Select::removeRead( $socket );
	
	# close and remove the socket
	$self->fh->close if $self->fh;
	$self->disconnect;
	
	if ( my $cb = $args->{onBody} ) {
		my $passthrough = $args->{passthrough} || [];
		$cb->( $self, @{$passthrough} );
	}
}

1;
