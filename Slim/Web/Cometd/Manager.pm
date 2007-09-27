package Slim::Web::Cometd::Manager;

# $Id$

# SqueezeCenter Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This class manages clients and subscriptions

use strict;

use Scalar::Util qw(weaken);
use Tie::RegexpHash;

use Slim::Utils::Log;
use Slim::Utils::Timers;
use Slim::Web::HTTP;

my $log = logger('network.cometd');

sub new {
	my ( $class, %args ) = @_;
	
	tie my %channels, 'Tie::RegexpHash';
	
	my $self = {
		conns    => {},         # client connections
		events   => {},         # clients and their pending events
		channels => \%channels, # all channels and who is subscribed to them
	};
	
	bless $self, ref $class || $class;
}

# Add a new client and connection created during handshake
sub add_client {
	my ( $self, $clid, $httpClient, $httpResponse ) = @_;
	
	$self->{conns}->{$clid} = [ $httpClient, $httpResponse ];
	
	# The per-client event hash holds one pending event per channel
	$self->{events}->{$clid} = {};
	
	$log->debug("add_client: $clid");
	
	return $clid;
}

# Update the connection, i.e. if the client reconnected
sub register_connection {
	my ( $self, $clid, $httpClient, $httpResponse ) = @_;
	
	$self->{conns}->{$clid} = [ $httpClient, $httpResponse ];
	
	$log->debug("register_connection: $clid");
}

sub remove_connection {
	my ( $self, $clid ) = @_;
	
	delete $self->{conns}->{$clid};

	$log->debug("remove_connection: $clid");
}

sub remove_client {
	my ( $self, $clid ) = @_;
	
	delete $self->{conns}->{$clid};
	delete $self->{events}->{$clid};
	
	$self->remove_channels( $clid );
	
	$log->debug("remove_client: $clid");
}

sub is_valid_clid {
	my ( $self, $clid ) = @_;
	
	return exists $self->{events}->{$clid};
}

sub add_channels {
	my ( $self, $clid, $subs ) = @_;

	for my $sub ( @{$subs} ) {
		
		my $re_sub = $sub;
		
		# Turn channel globs into regexes
		# /foo/**, Matches /foo/bar, /foo/boo and /foo/bar/boo. Does not match /foo, /foobar or /foobar/boo
		if ( $re_sub =~ m{^/(.+)/\*\*$} ) {
			$re_sub = qr{^/$1/};
		}
		# /foo/*, Matches /foo/bar and /foo/boo. Does not match /foo, /foobar or /foo/bar/boo.
		elsif ( $re_sub =~ m{^/(.+)/\*$} ) {
			$re_sub = qr{^/$1/[^/]+};
		}
		
		$self->{channels}->{$re_sub} ||= {};
		$self->{channels}->{$re_sub}->{$clid} = 1;
		
		$log->debug("add_channels: $sub ($re_sub)");
	}
	
	return 1;
}

sub remove_channels {
	my ( $self, $clid, $subs ) = @_;
	
	if ( !$subs ) {
		# remove all channels for this client
		for my $channel ( keys %{ $self->{channels} } ) {
			for my $sub_clid ( keys %{ $self->{channels}->{$channel} } ) {
				if ( $clid eq $sub_clid ) {
					delete $self->{channels}->{$channel}->{$clid};
					
					$log->debug("remove_channels for $clid: $channel");
				}
			}
		}
	}
	else {
		for my $sub ( @{$subs} ) {
			
			my $re_sub = $sub;
		
			# Turn channel globs into regexes
			# /foo/**, Matches /foo/bar, /foo/boo and /foo/bar/boo. Does not match /foo, /foobar or /foobar/boo
			if ( $re_sub =~ m{^/(.+)/\*\*$} ) {
				$re_sub = qr{^/$1/};
			}
			# /foo/*, Matches /foo/bar and /foo/boo. Does not match /foo, /foobar or /foo/bar/boo.
			elsif ( $re_sub =~ m{^/(.+)/\*$} ) {
				$re_sub = qr{^/$1/[^/]+};
			}
		
			for my $channel ( keys %{ $self->{channels} } ) {
				if ( $re_sub eq $channel ) {
					delete $self->{channels}->{$channel}->{$clid};
				}
			}
		
			$log->debug("remove_channels for $clid: $sub ($re_sub)");
		}
	}
	
	return 1;
}

sub get_pending_events {
	my ( $self, $clid ) = @_;
	
	my $events = [];
	
	while ( my ($channel, $event) = each %{ $self->{events}->{$clid} } ) {
		push @{$events}, $event;
	}
	
	# Clear all pending events
	$self->{events}->{$clid} = {};
	
	return wantarray ? @{$events} : $events;
}

sub deliver_events {
	my ( $self, $events ) = @_;
	
	if ( ref $events ne 'ARRAY' ) {
		$events = [ $events ];
	}
	
	my @to_send;
	
	for my $event ( @{$events} ) {
		# Find subscriber(s) to this event
		my $channel = $event->{channel};
		
		# Queue up all events for all subscribers
		# Since channels is a regexphash it will automatically match
		# globbed channels
		for my $clid ( keys %{ $self->{channels}->{$channel} } ) {
			push @to_send, $clid;
			
			$log->debug("Sending event on channel $channel to $clid");
		}
	}
	
	# Send everything
	for my $clid ( @to_send ) {	
		my $conns = $self->{conns}->{$clid};
	
		my $conn = $conns->[0];
		my $res  = $conns->[1];
		
		# If we have a connection to send to...
		if ( $conn && $res ) {
			# Add any pending events
			push @{$events}, ( $self->get_pending_events( $clid ) );
		
			if ( $log->is_debug ) {
				$log->debug( 
					  "Delivering events to $clid:\n"
					. Data::Dump::dump( $events )
				);
			}
		
			Slim::Web::Cometd::sendResponse( $conn, $res, $events );
		}
		else {
			# queue the event for later
			$self->{events}->{$clid}->{ $events->[0]->{channel} } = $events->[0];
			
			if ( $log->is_debug ) {
				$log->debug( 'Queued ' . scalar @{$events} . " event(s) for $clid" );
			}
		}
	}
	
	return 1;
}

1;
