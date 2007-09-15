package Slim::Web::Cometd::Manager;

# $Id$

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This class manages clients and subscriptions

use strict;

use Scalar::Util qw(weaken);

use Slim::Utils::Log;
use Slim::Utils::Timers;
use Slim::Web::HTTP;

my $log = logger('network.cometd');

sub new {
	my ( $class, %args ) = @_;
	
	my $self = {
		clients => {},
	};
	
	bless $self, ref $class || $class;
}

# Register a new clid created during handshake
sub register_clid {
	my ( $self, $clid ) = @_;
	
	$self->{clients}->{$clid} = {
		pending_events       => {},    # stores most recent event per channel
		to_unsubscribe       => {},    # channels to unsubscribe from
		streaming_connection => undef, # streaming connection to use
		streaming_response   => undef, # response object for streaming
	};
	
	return $clid;
}

sub is_valid_clid {
	my ( $self, $clid ) = @_;
	
	return exists $self->{clients}->{$clid};
}

sub unsubscribe {
	my ( $self, $clid, $subs ) = @_;
	
	my $client = $self->{clients}->{$clid};
	
	for my $sub ( @{$subs} ) {
		$client->{to_unsubscribe}->{$sub} = 1;
	}
	
	return 1;
}

sub should_unsubscribe_from {
	my ( $self, $clid, $sub ) = @_;
	
	return exists $self->{clients}->{$clid}->{to_unsubscribe}->{$sub};
}

sub remove_unsubscribe_from {
	my ( $self, $clid, $sub ) = @_;
	
	delete $self->{clients}->{$clid}->{to_unsubscribe}->{$sub};
}

sub remove_client {
	my ( $self, $clid ) = @_;
	
	delete $self->{clients}->{$clid};
	
	return 1;
}

sub get_pending_events {
	my ( $self, $clid ) = @_;
	
	my $client = $self->{clients}->{$clid};
	
	my $events = [];
	
	while ( my ($subscription, $event) = each %{ $client->{pending_events} } ) {
		push @{$events}, $event;
	}
	
	# Clear all pending events
	$client->{pending_events} = {};
	
	return wantarray ? @{$events} : $events;
}

sub register_streaming_connection {
	my ( $self, $clid, $conn, $res ) = @_;
	
	my $client = $self->{clients}->{$clid};
	
	$client->{streaming_connection} = $conn;
	$client->{streaming_response}   = $res;
}

sub unregister_connection {
	my ( $self, $clid, $conn ) = @_;
	
	my $client = $self->{clients}->{$clid};
	
	if ( $conn->transport eq 'streaming' ) {	
		if ( $client->{streaming_connection} eq $conn ) {
			delete $client->{streaming_connection};
			delete $client->{streaming_response};
		}
	}
	elsif ( $conn->transport eq 'polling' ) {
		# XXX: todo
	}
}

sub has_connections {
	my ( $self, $clid ) = @_;
	
	my $client = $self->{clients}->{$clid};
	
	return 1 if exists $client->{streaming_connection};
	
	return 0;
}

sub deliver_events {
	my ( $self, $clid, $events ) = @_;
	
	my $client = $self->{clients}->{$clid};
	
	my $conn = $client->{streaming_connection};
	my $res  = $client->{streaming_response};
	
	if ( $conn && $res ) {
		# If we have a streaming connection to send to...
		
		# Prepend all queued events, if any
		unshift @{$events}, ( $self->get_pending_events( $clid ) );
		
		if ( $log->is_debug ) {
			$log->debug( 
				  "Delivering events to $clid:\n"
				. Data::Dump::dump( $events )
			);
		}
		
		Slim::Web::Cometd::sendResponse( $conn, $res, $events );
	}
	
	return 1;
}

1;
