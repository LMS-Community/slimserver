package Slim::Networking::Async::DNS;

# $Id$

# Logitech Media Server Copyright 2003-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This class handles async DNS lookups.  It will also cache lookups for
# TTL.

use strict;

use AnyEvent::DNS;
use Tie::Cache::LRU;

use Slim::Utils::Log;
use Slim::Utils::Misc;

# Cached lookups
tie my %cache, 'Tie::Cache::LRU', 100;

my $log = logger('network.asyncdns');

BEGIN {
	# Disable AnyEvent::DNS's use of OpenDNS
	@AnyEvent::DNS::DNS_FALLBACK = ();
}

sub init { }

my $lastResolverReset = 0;

sub resolve {
	my ( $class, $args ) = @_;
	
	my $host = $args->{host};
	
	# Check cache
	if ( exists $cache{ $host } ) {
		if ( $cache{ $host }->{expires} > time() ) {
			my $addr = $cache{ $host }->{addr};
			main::DEBUGLOG && $log->is_debug && $log->debug( "Using cached DNS response $addr for $host" );
			
			$args->{cb}->( $addr, @{ $args->{pt} || [] } );
			return;
		}
		else {
			delete $cache{ $host };
		}
	}
	
	AnyEvent::DNS::resolver->resolve( $host => 'a', sub {
		my $res = shift;
		
		if ( !$res ) {
			# Lookup failed
			main::DEBUGLOG && $log->is_debug && $log->debug("Lookup failed for $host");

			# reset resolver configuration if we fail the lookup - it might be due to a configuration change
			# Windows resolver initialization is ugly - don't run it too often...
			if ( $host =~ /(?:squeezenetwork|mysqueezebox|radiotime|tunein)/ && $lastResolverReset < time - (main::ISWINDOWS ? 300 : 15) ) {
				main::DEBUGLOG && $log->is_debug && $log->debug("Reset DNS resolver to pick up new configuration");
				$lastResolverReset = time;
				$AnyEvent::DNS::RESOLVER = undef;
			}
			
			$args->{ecb} && $args->{ecb}->( @{ $args->{pt} || [] } );
			return;
		}
		
		my $addr = $res->[3];
		my $ttl	 = $res->[4];
		
		main::DEBUGLOG && $log->is_debug && $log->debug( "Got DNS response $addr for $host (ttl $ttl)" );
		
		# cache lookup for ttl
		if ( $ttl ) {
			$cache{$host} = {
				addr    => $addr,
				expires => AnyEvent->now + $ttl,
			};
		}
		
		$args->{cb}->( $addr, @{ $args->{pt} || [] } );
	} );
}

# Return value from cache, used to replace gethostbyname calls
sub cached {
	my ( $class, $host ) = @_;
	
	if ( my $cached = $cache{$host} ) {
		main::DEBUGLOG && $log->is_debug && $log->debug( "Using cached DNS response $cached->{addr} for $host" );
		
		return $cached->{addr};
	}
	
	return;
}

1;