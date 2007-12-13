package Slim::Networking::Async::DNS;

# $Id$

# SqueezeCenter Copyright 2003-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This class handles async DNS lookups, falling back to OpenDNS if the
# user's nameservers are all failing.  It will also cache lookups for
# TTL.

use strict;

use Net::DNS;
use Scalar::Util qw(blessed);
use Socket qw(unpack_sockaddr_in inet_ntoa);
use Tie::Cache::LRU;

use Slim::Networking::Select;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Timers;

# User's working local nameservers
my $LocalDNS = [];

# OpenDNS servers to use if we can't find a working local nameserver
my $OpenDNS = [ '208.67.222.222', '208.67.220.220' ];

# OpenDNS default nxdomain IPs
my $OpenDNS_Default = {};

# Outstanding sockets are kept here
my $Sockets = {};

# Cached lookups
tie my %cache, 'Tie::Cache::LRU', 100;

# If local servers start failing, we will remember
# and use OpenDNS for a while
my $Local_Fail       = 0;
my $Local_Fail_Retry = 3600; # how long until we retry failing local servers

my $log = logger('network.asyncdns');

# At startup time, we need to query all available nameservers to make sure
# we use a valid server during bgsend() calls
sub init {
	my $class = shift;

	my $res = Net::DNS::Resolver->new;

	$res->tcp_timeout( 5 );
	$res->udp_timeout( 5 );
	
	my @ns = $res->nameservers();
	
	my $valid_servers = [];
	
	for my $ns ( @ns ) {
		
		# domain to check
		my $domain = ('a'..'m')[ int(rand(13)) ] . '.root-servers.net';

		$log->debug("Verifying if we can use nameserver $ns...");
		$log->debug("  Testing lookup of $domain");

		$res->nameservers( $ns );

		my $packet = $res->send( $domain, 'A' );

		if ( blessed($packet) ) {

			if ( scalar $packet->answer > 0 ) {

				$log->debug("  Lookup successful, using $ns for DNS lookups");

				push @{$LocalDNS}, $ns;

				next;
			}
		}
		
		$log->debug("  Lookup failed");
	}

	if ( !scalar @{$LocalDNS} ) {
		logWarning("No DNS servers responded, falling back to OpenDNS.");
	}
	
	# Grab the OpenDNS default nxdomain IPs, so we can exclude them from results
	for my $ns ( @{$OpenDNS} ) {
		$res->nameservers( $ns );
	
		my $packet = $res->send( 'www.invalid', 'A' );
	
		if ( blessed($packet) ) {
			for my $answer ( $packet->answer ) {
				if ( blessed($answer) && $answer->isa('Net::DNS::RR::A') ) {
					$OpenDNS_Default->{ $answer->address } = 1;
					$log->debug( "Found an OpenDNS default nxdomain IP: " . $answer->address );
				}
			}
		}
	}
}

sub resolve {
	my ( $class, $args ) = @_;
	
	my $host    = $args->{host};
	my $timeout = $args->{timeout} || 5; # XXX: Use a shorter timeout?
	
	# Check cache
	if ( exists $cache{ $host } ) {
		if ( $cache{ $host }->{expires} > time() ) {
			my $addr = $cache{ $host }->{addr};
			$log->debug( "Using cached DNS response $addr for $host" );
			
			if ( my $cb = $args->{cb} ) {
				my $pt = $args->{pt} || [];
				$cb->( $addr, @{$pt} );
			}
			return;
		}
		else {
			delete $cache{ $host };
		}
	}
	
	# if no local DNS, fallback to OpenDNS
	if ( !$args->{opendns} && !scalar @{$LocalDNS} ) {
		$log->debug( 'No working local DNS servers, falling back to OpenDNS' );
		$args->{opendns} = 1;
	}
	
	# if local servers failed recently, use OpenDNS
	if ( !$args->{opendns} && $Local_Fail && $Local_Fail > time() ) {
		$log->debug( 'Local DNS servers failed recently, preferring OpenDNS' );
		$args->{opendns} = 1;
	}
	
	my $servers = $args->{opendns} ? $OpenDNS : $LocalDNS;

	if ( $log->is_debug ) {
		$log->debug( 
			sprintf( "Starting async DNS lookup for [%s] using server(s) [%s]", $host, join( ', ', @{$servers} ) )
		);
	}
	
	# Index each individual resolve call by host and timestamp
	my $key = $host . '|' . Time::HiRes::time();
	$Sockets->{$key} = {};
	
	# Resolve the host using all local DNS servers in parallel, first response wins
	for my $ns ( @{$servers} ) {

		my $resolver = Net::DNS::Resolver->new(
			nameservers => [ $ns ],
			debug       => $log->is_debug,
		);
	
		my $bgsock = $resolver->bgsend( $host );
	
		if ( !defined $bgsock ) {
			my $error = $resolver->errorstring;

			$log->error("DNS server $ns couldn't resolve IP address for $host: $error");
			
			next;
		}
		
		# Remember all sockets used for this query, so we can kill them on first response
		$Sockets->{$key}->{"$bgsock"} = $bgsock;
		
		# Save passthrough args
		${*$bgsock}{passthrough} = [ $key, $args, $resolver ];
	
		Slim::Networking::Select::addError( $bgsock, \&_dns_error);
		Slim::Networking::Select::addRead( $bgsock, \&_dns_read );
	}
	
	# handle the DNS timeout by using our own timer
	Slim::Utils::Timers::setTimer(
		$key,
		Time::HiRes::time() + $timeout,
		\&_dns_timeout,
		$args,
	);
}

sub _dns_timeout {
	my ( $key, $args ) = @_;
	
	# All queries timed out
	my ($host) = split /\|/, $key;
	
	$log->debug( "DNS lookup(s) timed out for $host" );
	
	for my $sockname ( keys %{ $Sockets->{$key} } ) {
		my $sock = $Sockets->{$key}->{$sockname};
		if ( defined $sock ) {
			Slim::Networking::Select::removeError($sock);
			Slim::Networking::Select::removeRead($sock);
			$sock->close;
			undef $sock;
			delete $Sockets->{$key}->{$sockname};
		}
	}
	
	delete $Sockets->{$key};
	
	# retry with OpenDNS if we weren't already using them
	if ( !$args->{opendns} ) {
		$log->debug( 'Retrying lookup using OpenDNS' );
		$Local_Fail = time() + $Local_Fail_Retry;
		$args->{opendns} = 1;
		__PACKAGE__->resolve( $args );
	}
	else {
		# OpenDNS also timed out, return an error
		$log->debug( 'OpenDNS timed out, giving up' );
	
		if ( my $ecb = $args->{ecb} ) {
			my $pt = $args->{pt} || [];
			$ecb->( @{$pt} );
		}
	}
}

sub _dns_read {
	my ( $bgsock, $key, $args, $resolver ) = @_;
	
	# Stop watching this socket
	Slim::Networking::Select::removeError($bgsock);
	Slim::Networking::Select::removeRead($bgsock);
	
	my $packet = $resolver->bgread($bgsock);
	
	if ( blessed($packet) && $packet->can('answer') ) {
		
		for my $answer ( $packet->answer ) {
			
			if ( blessed($answer) && $answer->isa('Net::DNS::RR::A') ) {
						
				my $addr = $answer->address;
				my $ttl  = $answer->ttl;
				
				if ( exists $OpenDNS_Default->{ $addr } ) {
					$log->debug( $args->{host} . ' resolved to OpenDNS default nxdomain IP, ignoring' );
					next;
				}
				
				if ( $log->is_debug ) {
					my ($host, $ts) = split /\|/, $key;
					my $diff = sprintf( "%d", ( Time::HiRes::time() - $ts ) * 1000 );
					
					$log->debug( "Resolved $host to $addr (ttl $ttl), request took $diff ms" );
				}
				
				# We got a good response, remove the timeout timer and dump all other queries
				Slim::Utils::Timers::killTimers( $key, \&_dns_timeout );
		
				for my $sockname ( keys %{ $Sockets->{$key} } ) {
					my $sock = $Sockets->{$key}->{$sockname};
					if ( defined $sock ) {
						Slim::Networking::Select::removeError($sock);
						Slim::Networking::Select::removeRead($sock);
						$sock->close;
						undef $sock;
						delete $Sockets->{$key}->{$sockname};
					}
				}

				delete $Sockets->{$key};
				
				# cache lookup for ttl
				if ( $ttl ) {
					$cache{ $args->{host} } = {
						addr    => $addr,
						expires => time() + $ttl,
					};
				}
				
				# If this was looked up on a local server, unset Local_Fail
				if ( !$args->{opendns} ) {
					$Local_Fail = 0;
				}
				
				if ( my $cb = $args->{cb} ) {
					my $pt = $args->{pt} || [];
					$cb->( $addr, @{$pt} );
				}
				
				return;
			}
		}
	}
	
	# failed, treat it as an error
	_dns_error( $bgsock, $key, $args, $resolver );
}

sub _dns_error {
	my ( $bgsock, $key, $args, $resolver ) = @_;
	
	my $bgsock_name = "$bgsock";
	$log->debug( "DNS error on socket $bgsock for " . $args->{host} );
	
	Slim::Networking::Select::removeError($bgsock);
	Slim::Networking::Select::removeRead($bgsock);
	
	$bgsock->close;
	undef $bgsock;
	
	# Check for other active sockets
	my $wait = 0;
	for my $sockname ( keys %{ $Sockets->{$key} } ) {
		my $sock = $Sockets->{$key}->{$sockname};
		
		if ( $sockname eq $bgsock_name ) {
			delete $Sockets->{$key}->{$sockname};
			next;
		}
		
		if ( defined $sock ) {
			# at least one socket is still active, we'll wait for it
			$log->debug( "Waiting for other outstanding requests on socket $sock..." );
			$wait = 1;
		}
	}
	
	return if $wait;
	
	# All requests failed, remove the timeout timer and handle the failure here
	Slim::Utils::Timers::killTimers( $key, \&_dns_timeout );
	
	# Fallback to OpenDNS first
	if ( !$args->{opendns} ) {
		$log->debug( 'Retrying lookup using OpenDNS' );
		
		$Local_Fail = time() + $Local_Fail_Retry;
		$args->{opendns} = 1;
		
		__PACKAGE__->resolve( $args );
	}
	else {
		# OpenDNS failed, return an error
		$log->debug( 'OpenDNS failed to resolve, giving up' );
		
		if ( my $ecb = $args->{ecb} ) {
			my $pt = $args->{pt} || [];
			$ecb->( @{$pt} );
		}
	}
}

1;