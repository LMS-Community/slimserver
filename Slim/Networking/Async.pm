package Slim::Networking::Async;


# Logitech Media Server Copyright 2003-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This is a base class for all asynchronous network operations performed
# by Logitech Media Server.

use strict;

use base qw(Slim::Utils::Accessor);

use Scalar::Util qw(blessed weaken);
use Socket qw(inet_ntoa);
use Errno qw(EWOULDBLOCK EAGAIN);

use Slim::Networking::Async::DNS;
use Slim::Networking::Async::Socket::HTTP;
use Slim::Networking::Select;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $log = logger('network.asynchttp');

__PACKAGE__->mk_accessor( rw => 'socket' );

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
	$args->{Timeout} ||= preferences('server')->get('remotestreamtimeout');

	# Skip async DNS if we know the IP address or are using a proxy (skipDNS)
	if ( $args->{skipDNS} || $args->{PeerAddr} || Slim::Utils::Network::ip_is_ipv4( $args->{Host} ) ) {
		
		# If caller only wanted to lookup the DNS, callback now
		if ( my $onDNS = $args->{onDNS} ) {
			my $pt = $args->{passthrough} || [];
			$onDNS->( $args->{PeerAddr} || $args->{Host}, @{$pt} );
			return;
		}
		
		return $self->connect( $args );
	}
	
	# Perform an async DNS lookup
	Slim::Networking::Async::DNS->resolve( {
		host    => $args->{Host},
		cb      => \&_dns_ok,
		ecb     => \&_dns_error,
		pt      => [ $self, $args ],
	} );
}

sub _dns_ok {
	my ( $addr, $self, $args ) = @_;
	
	$args->{PeerAddr} = $addr;
				
	# If caller only wanted to lookup the DNS, callback now
	if ( my $onDNS = $args->{onDNS} ) {
		my $pt = $args->{passthrough} || [];
		$onDNS->( $args->{PeerAddr} || $args->{Host}, @{$pt} );
		return;
	}
				
	return $self->connect( $args );
}

sub _dns_error {
	my ( $self, $args ) = @_;
	
	my $host = $args->{Host};

	# Call back to the caller's error handler
	if ( my $ecb = $args->{onError} ) {
		my $passthrough = $args->{passthrough} || [];
		$ecb->( $self, "Couldn't resolve IP address for: $host", @{$passthrough} );
	}
	else {
		$log->error("Couldn't resolve IP address for: $host");
	}
	
	$self->disconnect;
}

sub connect {
	my ( $self, $args ) = @_;
	
	my $host = $args->{Host};
	my $port = $args->{PeerPort};

	main::DEBUGLOG && $log->debug("Connecting to $host:$port");

	my $socket = $self->new_socket( %{$args} );
	
	# Bug 5673, avoid a crash if socket is undef
	if ( !defined $socket ) {
		$log->error("Failed to connect to $host:$port, because\n$@");
		_connect_error( $socket, $self, $args );
		return;
	}
	
	$socket->set( passthrough => [ $self, $args ] );
	
	Slim::Networking::Select::addError( $socket, \&_connect_error );
	Slim::Networking::Select::addWrite( $socket, \&_async_connect );
	
	# handle the timeout by using our own timer
	Slim::Utils::Timers::setTimer(
		$socket,
		Time::HiRes::time() + $args->{'Timeout'},
		\&_connect_error,
		$self,
		$args,
	);

	return;
}

# Default to an HTTP socket, it is suitable for any TCP connection
sub new_socket {
	my $self = shift;
	
	return Slim::Networking::Async::Socket::HTTP->new( @_ );
}

sub _connect_error {
	my ( $socket, $self, $args ) = @_;
	
	# Kill the timeout timer
	Slim::Utils::Timers::killTimers( $socket, \&_connect_error );
	
	# close the socket
	if ( defined $socket ) {
		$socket->close;
		undef $socket;
	}
	
	my $ecb = $args->{onError};
	if ( $ecb ) {
		my $passthrough = $args->{passthrough} || [];
		$ecb->( $self, "Connect timed out: $!", @{$passthrough} );
	}
	else {
		$log->error("Failed to connect: $!");
	}
}

sub _async_connect {
	my ( $socket, $self, $args ) = @_;

	# on Windows $! might not be cleared when socket is not yet connected
	# and whatever was previous value is kept, making the test below fail
	# by clearing it, we force underlying to redefine it.
	$! = undef;
	
	# check that we are actually connected
	if ( !$socket->connected ) {
		if ($socket->isa('Slim::Networking::Async::Socket::HTTPS') && ($! == EWOULDBLOCK || $! == EAGAIN)) {
			# The TLS handshake is not yet complete.  Retry later.
			return;
		}
		else {
			# remove our initial selects
			Slim::Networking::Select::removeError($socket);
			Slim::Networking::Select::removeWrite($socket);
			return _connect_error( $socket, $self, $args );
		}
	}

	# Kill the timeout timer
	Slim::Utils::Timers::killTimers( $socket, \&_connect_error );
	
	# remove our initial selects
	Slim::Networking::Select::removeError($socket);
	Slim::Networking::Select::removeWrite($socket);
	
	$self->socket( $socket );
	
	main::DEBUGLOG && $log->is_debug && $log->debug($self->socket, ' => ', fileno($self->socket), " connected, ready to write request");

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
			Timeout     => $args->{Timeout},
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

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug("Sending: [" . $$content_ref . "]");
	}

	$self->socket->set( passthrough => [ $self, $args ] );

	Slim::Networking::Select::addError( $self->socket, \&_async_error );
	Slim::Networking::Select::addRead( $self->socket, \&_async_read );
	Slim::Networking::Select::writeNoBlock( $self->socket, $content_ref );
	
	# Timeout if we never get any data
	Slim::Utils::Timers::setTimer(
		$self->socket,
		Time::HiRes::time() + $self->socket->get( 'io_socket_timeout' ),
		\&_async_error,
		'Timed out waiting for data',
		$self,
		$args,
	);
}

sub disconnect {
	my $self = shift;
	
	if ( $self->socket ) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Close ", $self->socket, ' => ', fileno($self->socket));
		$self->socket->close;
		
		# Bug 12276: undef the socket so that tests for its presence will fail
		$self->socket(undef);
	}
}

sub _async_error {
	my ( $socket, $error, $self, $args ) = @_;
	
	Slim::Utils::Timers::killTimers( $socket, \&_async_error );
	
	$self->disconnect;
	
	if ( my $ecb = $args->{onError} ) {
		my $passthrough = $args->{passthrough} || [];
		$ecb->( $self, $error, @{$passthrough} );
	}
	else {
		$log->error("Error: $error");
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
