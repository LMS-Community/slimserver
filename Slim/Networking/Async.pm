package Slim::Networking::Async;

# $Id$

# SlimServer Copyright (c) 2003-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This is a base class for all asynchronous network operations performed
# by SlimServer.

use strict;
use warnings;

use base qw(Class::Data::Accessor);

use Data::Dump ();	# because Data::Dump is able to dump typeglob objects (sockets)
use Net::DNS;
use Net::IP;
use Scalar::Util qw(blessed weaken);
use Socket;

use Slim::Networking::Select;
use Slim::Utils::Misc;

__PACKAGE__->mk_classaccessors( qw(
	nameserver socket
) );

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
		$::d_http_async && msg("Async: Verifying if we can use nameserver $ns...\n");

		$::d_http_async && msg("  Testing lookup of $domain\n");
		$res->nameservers( $ns );
		my $packet = $res->send( $domain, 'A' );
		if ( defined $packet ) {
			if ( scalar $packet->answer > 0 ) {
				$::d_http_async && msg("  Lookup successful, using $ns for DNS lookups\n");
				$class->nameserver( $ns );
				return;
			}
		}
		
		$::d_http_async && msg("  Lookup failed\n");
	}
	
	msg("Aysnc: No DNS servers responded, you may have trouble with network connections.  Please check your network settings.\n");
}

sub new {
	my $class = shift;
	
	return bless {}, $class;
}

sub open {
	my ( $self, $args ) = @_;
	
	# Don't bother resolving localhost
	if ( $args->{Host} =~ /^localhost$/i ) {
		$args->{PeerAddr} = '127.0.0.1';
	}
	elsif ( $args->{Host} !~ /\./ ) {	
		# Resolve names without periods directly so we can support hosts files
		if ( my $addr = scalar gethostbyname( $args->{Host} ) ) {
			$args->{PeerAddr} = inet_ntoa( $addr );
		}
	}
	
	# Timeout defaults to the Radio Station Timeout pref
	$args->{Timeout} ||= Slim::Utils::Prefs::get('remotestreamtimeout') || 10;

	# Skip async DNS if we know the IP address or are using a proxy (skipDNS)
	if ( $args->{skipDNS} || $args->{PeerAddr} || Net::IP::ip_is_ipv4( $args->{Host} ) ) {
		return $self->connect( $args );
	}

	my $resolver = Net::DNS::Resolver->new;
	if ( $self->nameserver ) {
		$resolver->nameservers( $self->nameserver );
	}
	
	$::d_http_async && msgf("Async: Starting async DNS lookup for [%s] using server [%s] [timeout %d]\n",
		$args->{Host},
		($resolver->nameservers)[0],
		$args->{Timeout},
	);
	
	my $bgsock = $resolver->bgsend( $args->{Host} );
	
	if ( !defined $bgsock ) {
		my $host  = $args->{Host};
		my $error = $resolver->errorstring;
		errorMsg("Async: Couldn't resolve IP address for $host: $error\n");
		
		# Call back to the caller's error handler
		if ( my $ecb = $args->{onError} ) {
			my $passthrough = $args->{passthrough} || [];
			$ecb->( $self, "Couldn't resolve IP address for $host: $error", @{$passthrough} );
		}
		
		return;
	}
	
	${*$bgsock}{passthrough} = [ $self, $args, $resolver ];
	
	Slim::Networking::Select::addError( $bgsock, \&_dns_error);
	Slim::Networking::Select::addRead( $bgsock, \&_dns_read );
	
	# handle the DNS timeout by using our own timer
	Slim::Utils::Timers::setTimer(
		$bgsock,
		Time::HiRes::time + $args->{Timeout},
		\&_dns_error,
		$self,
		$args,
		$resolver,
	);
}

sub _dns_error {
	my ( $bgsock, $self, $args, $resolver ) = @_;
	
	Slim::Utils::Timers::killTimers( $bgsock, \&_dns_error );
	
	Slim::Networking::Select::removeError($bgsock);
	Slim::Networking::Select::removeRead($bgsock);
	
	my $host = $args->{Host};
	errorMsg("Async: Couldn't resolve IP address for: $host\n");
	
	# Call back to the caller's error handler
	if ( my $ecb = $args->{onError} ) {
		my $passthrough = $args->{passthrough} || [];
		$ecb->( $self, "Couldn't resolve IP address for: $host", @{$passthrough} );
	}
	
	$bgsock->close;
	undef $bgsock;
	
	$self->disconnect;
	
	return;
}

sub _dns_read {
	my ( $bgsock, $self, $args, $resolver ) = @_;
	
	Slim::Utils::Timers::killTimers( $bgsock, \&_dns_error );

	Slim::Networking::Select::removeError($bgsock);
	Slim::Networking::Select::removeRead($bgsock);
	
	my $packet = $resolver->bgread($bgsock);
	
	if ( blessed($packet) && $packet->can('answer') ) {
		
		for my $answer ( $packet->answer ) {

			if ( blessed($answer) && $answer->isa('Net::DNS::RR::A') ) {		
				
				my $addr = $answer->address;
				
				$args->{PeerAddr} = $addr;
								
				$::d_http_async && msgf("Async: Resolved %s to [%s]\n",
					$args->{Host},
					$addr,
				);
				
				$bgsock->close;
				undef $bgsock;
				
				return $self->connect( $args );
			}
		}
	}
	
	return;
}

sub connect {
	my ( $self, $args ) = @_;
	
	my $host = $args->{Host};
	my $port = $args->{PeerPort};

	$::d_http_async && msg("Async: Connecting to $host:$port\n");

	my $socket = $self->new_socket( %{$args} );
	
	$socket->set( passthrough => [ $self, $args ] );
	
	Slim::Networking::Select::addError( $socket, \&_connect_error );
	Slim::Networking::Select::addWrite( $socket, \&_async_connect );
	
	# handle the timeout by using our own timer
	Slim::Utils::Timers::setTimer(
		$socket,
		Time::HiRes::time + $args->{'Timeout'},
		\&_connect_error,
		$self,
		$args,
	);

	return;
}

sub _connect_error {
	my ( $socket, $self, $args ) = @_;
	
	# Kill the timeout timer
	Slim::Utils::Timers::killTimers( $socket, \&_connect_error );

	$::d_http_async && msg("Async: Failed to connect: $!\n");

	# close the socket
	$socket->close;
	undef $socket;
	
	my $ecb = $args->{onError};
	if ( $ecb ) {
		my $passthrough = $args->{passthrough} || [];
		$ecb->( $self, 'Connect timed out', @{$passthrough} );
	}
}

sub _async_connect {
	my ( $socket, $self, $args ) = @_;
	
	# Kill the timeout timer
	Slim::Utils::Timers::killTimers( $socket, \&_connect_error );
	
	# check that we are actually connected
	if ( !$socket->connected ) {
		return _connect_error( $socket, $self, $args );
	}
	
	# remove our initial selects
	Slim::Networking::Select::removeError($socket);
	Slim::Networking::Select::removeWrite($socket);
	
	$self->socket( $socket );
	
	$::d_http_async && msg("Async: connected, ready to write request\n");

	if ( my $cb = $args->{onConnect} ) {
		my $passthrough = $args->{passthrough} || [];
		$cb->( @{$passthrough} );
	}
}

sub write_async {
	my ( $self, $args ) = @_;

	# Connect if necessary
	if ( !$self->socket ) {	
		return $self->open( {
			Host        => $args->{host},
			PeerPort    => $args->{port},
			skipDNS     => $args->{skipDNS},
			onConnect   => \&write_async,
			onError     => \&_async_error,
			passthrough => [ $self, $args ],
		} );
	}
	
	# Get the content to send, using a coderef if necessary
	my $content_ref = $args->{content_ref};
	if ( ref $content_ref eq 'CODE' ) {
		$content_ref = $content_ref->( $self );
	}
	
	$::d_http_async && msg("Async: Sending:\n" . $$content_ref );
	
	$self->socket->set( passthrough => [ $self, $args ] );

	Slim::Networking::Select::addError( $self->socket, \&_async_error );
	Slim::Networking::Select::addRead( $self->socket, \&_async_read );
	Slim::Networking::Select::writeNoBlock( $self->socket, $content_ref );
	
	# Timeout if we never get any data
	Slim::Utils::Timers::setTimer(
		$self->socket,
		Time::HiRes::time + $self->socket->get( 'io_socket_timeout' ),
		\&_async_error,
		'Timed out waiting for data',
		$self,
		$args,
	);
}

sub disconnect {
	my $self = shift;
	
	if ( $self->socket ) {
		$self->socket->close;
		undef $self->{socket};
	}
}

sub _async_error {
	my ( $socket, $error, $self, $args ) = @_;
	
	Slim::Utils::Timers::killTimers( $socket, \&_async_error );
	
	$self->disconnect;
	
	$::d_http_async && msg("Async: $error\n");
	
	if ( my $ecb = $args->{onError} ) {
		my $passthrough = $args->{passthrough} || [];
		$ecb->( $self, $error, @{$passthrough} );
	}
}

sub _async_read {
	my ( $socket, $self, $args ) = @_;
	
	Slim::Utils::Timers::killTimers( $socket, \&_async_error );
	
	if ( my $cb = $args->{onRead} ) {
		my $passthrough = $args->{passthrough} || [];
		$cb->( $self, @{$passthrough} );
	}
}

sub DESTROY {
	my $self = shift;
	
	$self->disconnect;
}

1;