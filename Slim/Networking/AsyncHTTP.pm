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

use Data::Dump ();
use HTTP::Headers;
use Net::DNS;
use Net::IP;
use Scalar::Util qw(blessed);
use Socket qw(:DEFAULT :crlf);

use Slim::Networking::Select;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

our $nameserver;

# At startup time, we need to query all available nameservers to make sure
# we use a valid server during bgsend() calls
sub init {
	my $class = shift;
	
	my $res = Net::DNS::Resolver->new;
	$res->tcp_timeout( 10 );
	$res->udp_timeout( 10 );
	
	my @ns = $res->nameservers();
	
	# domain to check
	my $domain = 'www.google.com';
	
	for my $ns ( @ns ) {
		$::d_http_async && msg("AsyncHTTP: Verifying if we can use nameserver $ns...\n");

		$::d_http_async && msg("  Testing lookup of $domain\n");
		$res->nameservers( $ns );
		my $packet = $res->send( $domain, 'A' );
		if ( defined $packet ) {
			if ( scalar $packet->answer > 0 ) {
				$::d_http_async && msg("  Lookup successful, using $ns for DNS lookups\n");
				$nameserver = $ns;
				return;
			}
		}
		
		$::d_http_async && msg("  Lookup failed\n");
	}
	
	msg("AysncHTTP: No DNS servers responded, you may have trouble with network connections.  Please check your network settings.\n");
}

# we override new in case we are using a proxy
sub new {
	my $class = shift;
	my %args  = @_;

	# Don't bother resolving localhost
	if ( $args{'Host'} =~ /^localhost$/i ) {
		$args{'PeerAddr'} = '127.0.0.1';
	}
	
	# Timeout defaults to the Radio Station Timeout pref
	$args{'Timeout'} ||= Slim::Utils::Prefs::get('remotestreamtimeout') || 10;
	
	# Skip async DNS if we know the IP address
	if ( $args{'PeerAddr'} || Net::IP::ip_is_ipv4( $args{'Host'} ) ) {
		
		$class->nonBlockingConnect( %args );
	}
	else {
		
		my $resolver = Net::DNS::Resolver->new;
		if ( defined $nameserver ) {
			$resolver->nameservers( $nameserver );
		}
		
		$::d_http_async && msgf("AsyncHTTP: Starting async DNS lookup for [%s] using server [%s] [timeout %d]\n",
			$args{'Host'},
			($resolver->nameservers)[0],
			$args{'Timeout'},
		);
		
		my $bgsock   = $resolver->bgsend( $args{'Host'} );
		
		if ( !defined $bgsock ) {
			my $host  = $args{'Host'};
			my $error = $resolver->errorstring;
			errorMsg("AsyncHTTP: Couldn't resolve IP address for $host: $error\n");
			
			# Call back to the caller's error handler
			my $ecb    = $args{'errorCallback'};
			my $cbArgs = $args{'callbackArgs'} || [];
			if ( $ecb ) {
				$ecb->( undef, @{ $cbArgs } );
			}
			
			return;
		}
		
		# We need to access the resolver again..
		${*$bgsock}{'resolver'}  = $resolver;
		
		# Save our information
		${*$bgsock}{'asynchttp'} = $class;
		${*$bgsock}{'httpArgs'}  = \%args;
		
		Slim::Networking::Select::addError($bgsock, \&dnsErrorCallback);
		Slim::Networking::Select::addRead($bgsock, \&dnsAnswerCallback);
		
		# handle the DNS timeout by using our own timer
		Slim::Utils::Timers::setTimer(
			$bgsock,
			Time::HiRes::time + $args{'Timeout'},
			\&dnsErrorCallback
		);
	}
}

sub dnsErrorCallback {
	my $bgsock = shift;
	
	Slim::Networking::Select::removeError($bgsock);
	Slim::Networking::Select::removeRead($bgsock);	
	
	my $host = ${*$bgsock}{'httpArgs'}->{'Host'};	
	errorMsg("AsyncHTTP: Couldn't resolve IP address for: $host\n");
	
	# Call back to the caller's error handler
	my $ecb = ${*$bgsock}{'httpArgs'}->{'errorCallback'};
	my $args = ${*$bgsock}{'httpArgs'}->{'callbackArgs'} || [];
	if ( $ecb ) {
		$ecb->( $bgsock, @{ $args } );
	}
	
	$bgsock->close;
	undef $bgsock;
	
	return;
}

sub dnsAnswerCallback {
	my $bgsock = shift;
	
	my $resolver = ${*$bgsock}{'resolver'};
	my $packet   = $resolver->bgread($bgsock);
	
	if ( blessed($packet) && $packet->can('answer') ) {
		
		for my $answer ( $packet->answer ) {

			if ( blessed($answer) && $answer->isa('Net::DNS::RR::A') ) {
				
				# kill the timeout timer
				Slim::Utils::Timers::killTimers($bgsock, \&dnsErrorCallback);

				Slim::Networking::Select::removeError($bgsock);
				Slim::Networking::Select::removeRead($bgsock);				
				
				my $addr = $answer->address;
				
				my $class = ${*$bgsock}{'asynchttp'};
				my $args  = ${*$bgsock}{'httpArgs'};
				
				$::d_http_async && msgf("AsyncHTTP: Resolved %s to [%s]\n",
					$args->{'Host'},
					$addr,
				);		
				
				$bgsock->close;
				undef $bgsock;
				
				$class->nonBlockingConnect( %{$args}, PeerAddr => $addr );
				
				return 1;
			}
		}
	}
	
	return 0;
}

sub nonBlockingConnect {
	my $class = shift;
	my %args  = @_;
	
	my $self;
	
	my $server = $args{'Host'};
	my $proxy  = Slim::Utils::Prefs::get('webproxy');
	
	# callbacks
	my $write_cb = delete $args{'writeCallback'};
	my $error_cb = delete $args{'errorCallback'};
	my $args_cb  = delete $args{'callbackArgs'} || [];

	# Don't proxy for localhost requests.
	if ($proxy && $server ne 'localhost' && $server ne '127.0.0.1') {

		my $host = $args{'Host'};
		my $port = $args{'PeerPort'};
		my $addr = $args{'PeerAddr'};
		
		$::d_http_async && msg("AsyncHTTP: Using proxy to connect to $host:$port\n");

		# create instance using proxy server and port
		my ($pserver, $pport) = split /:/, $proxy;

		$args{'Host'} = $args{'PeerAddr'} = $pserver;
		$args{'PeerPort'} = $pport || 80;
		
		# Allow reuse of existing socket on redirects
		if ( ref $class ) {
			$self = $class->http_configure(\%args);
		}
		else {
			$self = $class->SUPER::new(%args);
		}

		# now remember the original host and port, we'll need them to format the request
		${*$self}{'httpasync_host'} = $host;
		${*$self}{'httpasync_port'} = $port;
		${*$self}{'httpasync_addr'} = $addr;

	} else {
		
		my $port = $args{'PeerPort'};
		$::d_http_async && msg("AsyncHTTP: Connecting to $server:$port\n");
		
		# Allow reuse of existing socket on redirects
		if ( ref $class ) {
			$self = $class->http_configure(\%args);
		}
		else {
			$self = $class->SUPER::new(%args);
		}
	}
	
	# save callback info since we are non-blocking
	${*$self}{'httpasync_state'} = {
		'write_cb' => $write_cb,
		'error_cb' => $error_cb,
		'args_cb'  => $args_cb,
		'state'    => 'init',
	};
	
	# Wait for activity in select
	Slim::Networking::Select::addError($self, \&connectError);
	Slim::Networking::Select::addWrite($self, \&connectCallback);
	
	return $self;
}

# Net::HTTP::Methods doesn't get the right peerport since we are making an 
# async connection, so we store it ourselves
sub peerport {
	my $self = shift;
	return ${*$self}{'AsyncPeerPort'};
}

# IO::Socket::INET's connect method blocks, so we use our own connect method 
# which is non-blocking.  Based on: http://www.perlmonks.org/?node_id=66135
sub connect {
	@_ == 2 || @_ == 3 or
		die 'usage: $sock->connect(NAME) or $sock->connect(PORT, ADDR)';
	
	# grab our socket
	my $sock = shift;
	
	# set to non-blocking
	$sock->blocking(0);
	
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
	
	# handle the timeout by using our own timer
	my $timeout = ${*$sock}{'io_socket_timeout'} || 10;
	Slim::Utils::Timers::setTimer(
		$sock,
		Time::HiRes::time + $timeout,
		\&connectError
	);
	
	# return immediately
	return 1;
}

# The connect failed
sub connectError {
	my $self = shift;
	
	# remove our initial selects
	Slim::Networking::Select::removeError($self);
	Slim::Networking::Select::removeWrite($self);
	
	# Kill the timeout timer
	Slim::Utils::Timers::killTimers($self, \&connectError);
	
	# close the socket
	$self->close;
	
	$::d_http_async && msg("AsyncHTTP: timed out, failed to connect\n");
	
	my $state = ${*$self}{'httpasync_state'};
	$state->{'state'} = 'error';
	
	my $ecb = $state->{'error_cb'};
	if ( $ecb ) {
		$ecb->( $self, @{ $state->{'args_cb'} } );
	}
}

# The connect is ready to accept a request
sub connectCallback {
	my $self = shift;
	
	# Kill the timeout timer
	Slim::Utils::Timers::killTimers($self, \&connectError);
	
	# check that we are actually connected
	if ( !$self->connected ) {
		return $self->connectError;
	}
	
	# remove our initial selects
	Slim::Networking::Select::removeError($self);
	Slim::Networking::Select::removeWrite($self);
	
	$::d_http_async && msg("AsyncHTTP: connected, ready to write request\n");
	
	my $state = ${*$self}{'httpasync_state'};
	$state->{'state'} = 'connected';
	
	my $cb = $state->{'write_cb'};
	if ( $cb ) {
		$cb->( $self, @{ $state->{'args_cb'} } );
	}
}

# override to handle proxy
# TODO: make username, password easy to provide. For now, caller can explicitly include Authorization header
sub format_request {
	my $self = shift;
	my $method = shift;
	my $path = shift;

	my $host = ${*$self}{'http_host'};

	# Don't proxy for localhost requests.
	if (Slim::Utils::Prefs::get('webproxy') && ${*$self}{'httpasync_host'}) {

		$path = "http://".${*$self}{'httpasync_host'}.":".${*$self}{'httpasync_port'} . $path;
		
		$host = ${*$self}{'httpasync_host'};
	}

	# pull out POST body
	my $body = '';
	if ( @_ % 2 ) {
		$body = pop @_;
	}

	# more headers copied from Slim::Player::Protocol::HTTP
	my %headers = (
		'Host'          => $host,
		'User-Agent'    => Slim::Utils::Misc::userAgentString(),
		'Accept'        => "*/*",
		'Cache-Control' => "no-cache",
		'Connection'    => "close",
		'Icy-Metadata'  => 1,
		@_,
	);
	
	return $self->SUPER::format_request($method => $path, %headers, $body);
}

# don't use write_request.  Use write_request_async instead.
sub write_request {
	my $self = shift;

	assert(0, "Called ". __PACKAGE__ ."::write_request.  You should call write_request_async instead!\n");

	$self->SUPER::write_request(@_);
}

sub write_request_async {
	my $self = shift;
	
	my $request;
	if ( @_ == 1 ) {

		# if we get one param, it's the full request
		$request = shift;
	}
	else {
	
		# multiple params pass through format_request
		# TODO: add support for proxies and authentication
		$request = $self->format_request(@_);
	}

	$::d_http_async && msg("AsyncHTTP: Sending request:\n$request\n\n");
	
	# write request in non-blocking fashion
	# this method will return immediately
	Slim::Networking::Select::writeNoBlock($self, \$request);
	Slim::Networking::Select::addError($self, \&errorCallback);
}

sub read_response_headers_async {
	my $self = shift;
	my $callback = shift;
	my $args = shift;

	my $state = {
		'callback' => $callback,
		'args'     => $args,
		'state'    => 'headers-read',
	};

	${*$self}{'httpasync_state'} = $state;
	
	$::d_http_async && msg("AsyncHTTP: State: headers-read\n");

	Slim::Networking::Select::addError($self, \&errorCallback);
	Slim::Networking::Select::addRead($self, \&readHeaderCallback);
}

# don't use.  Use _async version instead.
sub read_entity_body {
	my $self = shift;

	assert(0, "Called ". __PACKAGE__ ."::read_entity_body.  You should call read_entity_body_async instead!\n");

	$self->SUPER::read_entity_body(@_);
}

sub read_entity_body_async {
	my $self = shift;
	my $callback = shift;
	my $args = shift;
	my $bufsize = shift || 1024;

	my $state = {
		'callback' => $callback,
		'args'     => $args,
		'bufsize'  => $bufsize,
		'body'     => '',
		'state'    => 'body-read',
	};

	${*$self}{'httpasync_state'} = $state;
	
	$::d_http_async && msg("AsyncHTTP: State: body-read\n");

	Slim::Networking::Select::addError($self, \&errorCallback);
	Slim::Networking::Select::addRead($self, \&readBodyCallback);
}

# readCallback is called by select loop when our socket has data
sub readHeaderCallback {
	my $self = shift;

	my $state = ${*$self}{'httpasync_state'};

	# Wrap call to base in an eval to prevent dying. An error should
	# result in an error callback invocation for the next layer up.
	my ($code, $mess, @h) = eval { $self->SUPER::read_response_headers };

	if ($@) {
		$::d_http_async && msg("AsyncHTTP: Error reading headers: $@\n");
		$self->errorCallback();
		return;
	}

	if ($code) {
		# headers complete, remove ourselves from select loop
		Slim::Networking::Select::removeError($self);
		Slim::Networking::Select::removeRead($self);

		$state->{'state'}   = 'headers-done';
		$state->{'code'}    = $code;
		$state->{'mess'}    = $mess;
		
		my $headers = HTTP::Headers->new( @h );	
		$state->{'headers'} = $headers;
		
		if ( $::d_http_async ) {
			msg("AsyncHTTP: Headers read. code: $code status: $mess\n");
			warn Data::Dump::dump($headers) . "\n";
		}

		# all headers complete.  Call callback
		if (defined $state->{'callback'} && ref($state->{'callback'}) eq 'CODE') {

			$state->{'callback'}($state->{'args'}, undef, $code, $mess, $headers);
		}
	}

	# else, we will be called again later, after all headers are read
}

# Copy of Net::HTTP::NB's sysread method, so we can handle ICY 200 OK responses
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
			my $icy = ${*$self}{'httpnb_save'} =~ s/ICY 200 OK/HTTP\/1.0 200 OK/;
			${*$self}{'parsed_status_line'} = 1;
			
			if ( $icy ) {
				$n += 5;
				$_[1] =~ s/ICY 200 OK/HTTP\/1.0 200 OK/;
			}
		}
	}

    return $n;
}

# readCallback is called by select loop when our socket has data
sub readBodyCallback {
	my $self = shift;

	my $state = ${*$self}{'httpasync_state'};
	my $result = $self->SUPER::read_entity_body(my $buf, $state->{'bufsize'});

	$state->{'body'} .= $buf;

	if ($result == 0) {
		# if here, we've reached the end of the body

		# remove self from select loop
		Slim::Networking::Select::removeError($self);
		Slim::Networking::Select::removeRead($self);

		$::d_http_async && msgf("AsyncHTTP: Body read for fileno: %d\n", fileno($self));
		
		$state->{state} = 'body-done';
		
		$::d_http_async && msg("AsyncHTTP: State: body-done\n");

		if (defined $state->{'callback'} && ref($state->{'callback'}) eq 'CODE') {

			$state->{'callback'}($state->{'args'}, undef, $state->{'body'});
		}
	}

	# else we will be called again when the next buffer has been read
}

sub errorCallback {
	my $self = shift;

	my $state = ${*$self}{'httpasync_state'};
	$state->{'state'} = 'error';

	$self->close();

	$::d_http_async && msgf("AsyncHTTP: Error!! for fileno: %d\n", fileno($self));

	if (defined $state->{'callback'} && ref($state->{'callback'}) eq 'CODE') {

		$state->{'callback'}($state->{'args'}, 1);
	}	
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

This class is based upon C<Net::HTTP> and C<Net::HTTP::NB>.  It is for use
within the SlimServer only, as it is integrated within the SlimServer select
loop.  It allows plugins to make HTTP requests in a non-blocking fashion, thus
not interfering with the responsiveness of the SlimServer while waiting for
the request to complete.

This class is an instance of Socket, and it provides a relatively
low level API.  If all you need is to request a page from a web
site, take a look at SimpleAsyncHTTP.

=cut

