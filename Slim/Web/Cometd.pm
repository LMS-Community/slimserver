package Slim::Web::Cometd;

# $Id$

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This class provides an implementation of the Cometd Bayeux protocol
# The primary purpose is for handling Jive connections, but it may also
# be used in the future for real-time updates to the web interface.
#
# Some of this code is thanks to David Davis' cometd-perl implementation.
#
# Current protocol documentation is available at
# http://svn.xantus.org/shortbus/trunk/bayeux/bayeux.html

use strict;

use bytes;
use Digest::SHA1 qw(sha1_hex);
use HTTP::Date;
use JSON;
use JSON::XS qw(from_json);
use Scalar::Util qw(blessed);
use URI::Escape qw(uri_unescape);

use Slim::Control::Request;
use Slim::Web::Cometd::Manager;
use Slim::Web::HTTP;
use Slim::Utils::Log;
use Slim::Utils::Network;
use Slim::Utils::Timers;

my $log = logger('network.cometd');

my $manager = Slim::Web::Cometd::Manager->new;

use constant PROTOCOL_VERSION => '1.0';
use constant RETRY_DELAY      => 5000;

sub init {
	Slim::Web::HTTP::addRawFunction( '/cometd', \&handler );
	Slim::Web::HTTP::addCloseHandler( \&closeHandler );
}

sub handler {
	my ( $httpClient, $httpResponse ) = @_;
	
	# make sure we're connected
	if ( !$httpClient->connected ) {
		$log->warn("Aborting, client not connected: $httpClient");
		return;
	}
	
	my $req = $httpResponse->request;
	my $ct	= $req->content_type;
	
	my ( $params, %ops );
	
	if ( $ct && $ct eq 'text/json' ) {
		# POST
		if ( my $content = $req->content ) {
			$ops{message} = $content;
		}
	}
	elsif ( $ct && $ct eq 'application/x-www-form-urlencoded' ) {
		# POST or GET
		if ( my $content = $req->content ) {
			$params = $content;
		}
		elsif ( $req->uri =~ m{\?message=} ) {
			$params = ( $req->uri =~ m{\?(.*)} )[ 0 ];
		}
	}
	
	if ( $params && $params =~ m{=} ) {
		# uri param ?message=[json]
		%ops = map {
			my ( $k, $v ) = split( '=' );
			uri_unescape( $k ) => uri_unescape( $v )
		} split( '&', $params );
	}
	elsif ( $params ) {
		# uri param ?[json]
		$ops{message} = $params;
	}
	
	if ( !$ops{message} ) {
		sendResponse( 
			$httpClient,
			$httpResponse,
			[ { successful => JSON::False, error => 'no bayeux message found' } ]
		);
		return;
	}

	my $objs = eval { from_json( $ops{message} ) };
	if ( $@ ) {
		sendResponse( 
			$httpClient,
			$httpResponse,
			[ { successful => JSON::False, error => "$@" } ]
		);
		return;
	}
	
	if ( ref $objs ne 'ARRAY' ) {
		sendResponse( 
			$httpClient,
			$httpResponse,
			[ { successful => JSON::False, error => 'bayeux message not an array' } ]
		);
		return;
	}
	
	if ( $log->is_debug ) {
		$log->debug( "Cometd request: " . Data::Dump::dump( $objs ) );
	}
	
	my $clid;
	my $events = [];
	my @errors;
	
	for my $obj ( @{$objs} ) {		
		if ( ref $obj ne 'HASH' ) {
			sendResponse( 
				$httpClient,
				$httpResponse,
				[ { successful => JSON::False, error => 'bayeux event not a hash' } ]
			);
			return;
		}
		
		if ( !$clid ) {
			# specified clientId and authToken
			if ( $obj->{clientId} ) {
				$clid = $obj->{clientId};
			}
			elsif ( $obj->{channel} eq '/meta/handshake' ) {
				$clid = new_uuid();
				$manager->register_clid( $clid );
			}
			else {
				push @errors, [ $obj->{channel}, 'clientId not supplied' ];
			}
			
			# Register client with HTTP connection
			if ( $clid ) {
				$httpClient->clid( $clid );
			}
		}
		
		last if @errors;
		
		if ( $obj->{channel} eq '/meta/handshake' ) {

			push @{$events}, {
				channel					 => '/meta/handshake',
				version					 => PROTOCOL_VERSION,
				supportedConnectionTypes => [ 'long-polling', 'streaming' ],
				clientId				 => $clid,
				successful				 => JSON::True,
				advice					 => {
					reconnect => 'retry',     # one of "none", "retry", "handshake", "recover"
					interval  => RETRY_DELAY, # retry delay in ms
				},
			};			
		}
		elsif ( $obj->{channel} eq '/meta/connect' ) {
			
			if ( !$manager->is_valid_clid( $clid ) ) {
				# Invalid clientId, send advice to re-handshake
				
				push @{$events}, {
					channel    => '/meta/connect',
					clientId   => undef,
					successful => JSON::False,
					timestamp  => time2str( time() ),
					error      => 'invalid clientId',
					advice     => {
						reconnect => 'handshake',
						interval  => 0,
					}
				};
			}
			else {
				# Valid clientId
				
				push @{$events}, {
					channel    => '/meta/connect',
					clientId   => $clid,
					successful => JSON::True,
					timestamp  => time2str( time() ),
				};
			
				# Add any additional pending events
				push @{$events}, ( $manager->get_pending_events( $clid ) );
			
				if ( $obj->{connectionType} eq 'streaming' ) {
					# Streaming connections use chunked transfer encoding
					$httpResponse->header( 'Transfer-Encoding' => 'chunked' );
				
					# Tell HTTP client our transport
					$httpClient->transport( 'streaming' );
				
					# Tell the manager about the streaming connection
					$manager->register_streaming_connection(
						$clid, $httpClient, $httpResponse
					);
				}
				else {
					$httpClient->transport( 'polling' );
				
					# XXX: todo
				}
			}
		}
		elsif ( $obj->{channel} eq '/meta/reconnect' ) {
			
			if ( !$manager->is_valid_clid( $clid ) ) {
				# Invalid clientId, send advice to recover
				
				push @{$events}, {
					channel    => '/meta/reconnect',
					successful => JSON::False,
					timestamp  => time2str( time() ),
					error      => 'invalid clientId',
					advice     => {
						reconnect => 'recover',
						interval  => 0,
					}
				};
			}
			else {
				# Valid clientId, reconnect them
				
				$log->debug( "Client reconnected: $clid" );
				
				push @{$events}, {
					channel    => '/meta/reconnect',
					successful => JSON::True,
					timestamp  => time2str( time() ),
				};
				
				# Add any additional pending events
				push @{$events}, ( $manager->get_pending_events( $clid ) );
			
				# Remove disconnect timer
				Slim::Utils::Timers::killTimers( $clid, \&disconnectClient );
				
				if ( $obj->{connectionType} eq 'streaming' ) {
					# Streaming connections use chunked transfer encoding
					$httpResponse->header( 'Transfer-Encoding' => 'chunked' );
				
					# Tell HTTP client our transport
					$httpClient->transport( 'streaming' );
				
					# Tell the manager about the streaming connection
					$manager->register_streaming_connection(
						$clid, $httpClient, $httpResponse
					);
				}
				else {
					$httpClient->transport( 'polling' );
				
					# XXX: todo
				}
			}	
		}
		elsif ( $obj->{channel} eq '/meta/disconnect' ) {
			
			if ( !$manager->is_valid_clid( $clid ) ) {
				# Invalid clientId, send error
				
				push @{$events}, {
					channel    => '/meta/disconnect',
					clientId   => undef,
					successful => JSON::False,
					error      => 'invalid clientId',
				};
			}
			else {
				# Valid clientId, disconnect them
				
				push @{$events}, {
					channel    => '/meta/disconnect',
					clientId   => $clid,
					successful => JSON::True,
					timestamp  => time2str( time() ),
				};
				
				# Close the connection after this response
				$httpResponse->header( Connection => 'close' );
			
				disconnectClient( $clid );
			}
		}
		elsif ( $obj->{channel} eq '/meta/subscribe' ) {
			
			# We expect all our subscribe events to contain 'ext'
			# values that correspond to requests
			my $request      = $obj->{ext}->{'slim.request'};
			my $subscription = $obj->{subscription};
			
			if ( $request && $subscription ) {
				my $result = handleRequest( {
					clid     => $clid, 
					cmd      => $request, 
					channel  => $obj->{channel}, 
					id       => $subscription,
					response => 1,
				} );
				
				if ( $result->{error} ) {
					push @errors, [ $obj->{channel}, $result->{error} ];
				}
				else {
					push @{$events}, {
						channel      => '/meta/subscribe',
						clientId     => $clid,
						successful   => JSON::True,
						subscription => $subscription, # XXX: out of spec but should be sent!
						ext          => $obj->{ext},
					};
					
					# If the request was not async, we can add it now
					if ( exists $result->{data} ) {
						push @{$events}, $result;
					}
				}
			}
			else {
				if ( !$request ) {
					push @errors, [ $obj->{channel}, 'slim.request ext key not found' ];
				}
				elsif ( !$subscription ) {
					push @errors, [ $obj->{channel}, 'subscription key not found' ];
				}
			}
		}
		elsif ( $obj->{channel} eq '/meta/unsubscribe' ) {
			my $subscriptions = $obj->{subscription};
			
			# a channel name or a channel pattern or an array of channel names and channel patterns.
			if ( !ref $subscriptions ) {
				$subscriptions = [ $subscriptions ];
			}
			
			# We can't actually unsubscribe here because we need a request object
			# but we can tell the manager to dump them the next time they are
			# received
			$manager->unsubscribe( $clid, $subscriptions );
			
			for my $sub ( @{$subscriptions} ) {
				push @{$events}, {
					channel      => '/meta/unsubscribe',
					clientId     => $clid,
					subscription => $sub,
					successful   => JSON::True,
				};
			}
		}			
		elsif ( $obj->{channel} eq '/slim/request' ) {
			
			# A non-subscription request
			my $request = $obj->{data};
			my $id      = $obj->{id} || new_uuid(); # unique id for this request
			
			if ( $request && $id ) {
				my $result = handleRequest( {
					clid     => $clid, 
					cmd      => $request,
					channel  => $obj->{channel}, 
					id       => $id,
					response => ( $obj->{ext} && $obj->{ext}->{'no-response'} ) ? 0 : 1,
				} );
				
				if ( $result->{error} ) {
					push @errors, [ $obj->{channel}, $result->{error} ];
				}
				else {
					# If the caller does not want a response, they will set ext->{'no-response'}
					if ( $obj->{ext} && $obj->{ext}->{'no-response'} ) {
						# do nothing
						$log->debug('Not sending response to request, caller does not want it');
					}
					else {
						# This response is optional, but we do it anyway
						push @{$events}, {
							channel    => '/slim/request',
							clientId   => $clid,
							id         => $id,
							successful => JSON::True,
							ext        => $obj->{data},
						};
					
						# If the request was not async, we can add it now
						if ( exists $result->{data} ) {
							push @{$events}, $result;
						}
					}
				}
			}
		}
	}
	
	if ( @errors ) {
		my $out = [];
		
		for my $error ( @errors ) {
			push @{$out}, {
				channel    => $error->[0],
				successful => JSON::False,
				error      => $error->[1],
			};
		}
		
		sendResponse(
			$httpClient, $httpResponse, $out,
		);
		
		return;
	}
	
	sendResponse(
		$httpClient, $httpResponse, $events,
	);
}

sub sendResponse {
	my ( $httpClient, $httpResponse, $out ) = @_;
	
	$httpResponse->code( 200 );
	$httpResponse->header( Expires => '-1' );
	$httpResponse->header( Pragma => 'no-cache' );
	$httpResponse->header( 'Cache-Control' => 'no-cache' );
	$httpResponse->header( 'Content-Type' => 'application/json' );
	
	$out = eval { objToJson( $out, { utf8 => 1, autoconv => 0 } ) };
	$out = Slim::Utils::Unicode::encode('utf8', $out);
	if ( $@ ) {
		$out = objToJson( [ { successful => JSON::False, error => "$@" } ] );
	}
	
	my $sendheaders = 1; # should we send headers?
	my $chunked     = 0; # is this a chunked connection?
	
	if ( $httpResponse->header('Transfer-Encoding') ) {
		$chunked = 1;
		
		# Have we already sent headers on this connection?
		if ( $httpClient->sent_headers ) {
			$sendheaders = 0;
		}
		else {
			$httpClient->sent_headers(1);
		}
	}
	else {
		$httpResponse->header( 'Content-Length', length $out );
		$sendheaders = 1;
	}
	
	if ( $log->is_debug ) {
		if ( $sendheaders ) {
			$log->debug( "Sending Cometd Response:\n" 
				. $httpResponse->as_string . $out
			);
		}
		else {
			$log->debug( "Sending Cometd chunk:\n" . $out );
		}
	}
	
	Slim::Web::HTTP::addHTTPResponse(
		$httpClient, $httpResponse, \$out, $sendheaders, $chunked,
	);
}

sub handleRequest {
	my $args = shift;
	
	my $clid     = $args->{clid};
	my $cmd      = $args->{cmd};
	my $channel  = $args->{channel};
	my $id       = $args->{id};
	my $response = defined $args->{response} ? $args->{response} : 1;
	
	my $args = $cmd->[1];

	if ( !$args || ref $args ne 'ARRAY' ) {
		return { error => 'invalid slim.request arguments, array expected' };
	}
	
	my $clientid;
	
	if ( my $mac = $cmd->[0] ) {
		my $client   = Slim::Player::Client::getClient($mac);
		$clientid = blessed($client) ? $client->id : undef;
	}
	
	# create a request
	my $request = Slim::Control::Request->new( $clientid, $args );
	
	if ( $request->isStatusDispatchable ) {
		# fix the encoding and/or manage charset param
		$request->fixEncoding;
		
		# remember channel, request id and client id
		$request->source( "$channel|$id" );
		$request->connectionID( $clid );
		
		if ( $response ) {
			$request->autoExecuteCallback( \&requestCallback );
		}
		
		$request->execute();
		
		if ( $request->isStatusError ) {
			return { error => 'request failed with error: ' . $request->getStatusText };
		}
		
		# handle async commands
		if ( $request->isStatusProcessing ) {
			if ( $response ) {
				# Only set a callback if the caller wants a response
				$request->callbackParameters( \&requestCallback );
			
				$log->debug( "Request for $channel / $id is async, will callback" );
			}
			else {
				$log->debug( "Request for $channel / $id is async, but caller does not care about the response" );
			}
			
			return { ok => 1 };
		}
		
		# the request was successful and is not async
		$log->debug( "Request for $channel / $id is not async" );
		
		if ( $channel eq '/meta/subscribe' ) {
			$channel = $id;
			$id      = undef;
		}
		
		return {
			channel   => $channel,
			id        => $id,
			data      => $request->getResults,
			timestamp => time2str( time() ),
		};
	}
	else {
		return { error => 'invalid slim.request: ' . $request->getStatusText };
	}
}

sub requestCallback {
	my $request = shift;
	
	my $clid           = $request->connectionID;
	my ($channel, $id) = split /\|/, $request->source, 2;
	
	$log->debug( "requestCallback got results for $clid / $channel / $id" );
	
	if ( $channel eq '/meta/subscribe' ) {
		$channel = $id;
		$id      = undef;
	}
	
	# Do we need to unsubscribe from this request?
	if ( $manager->should_unsubscribe_from( $clid, $channel ) ) {
		$log->debug( "requestCallback: unsubscribing from $clid / $channel" );
		
		$request->removeAutoExecuteCallback();
			
		return;
	}
	
	# Construct event response
	my $events = [ {
		channel   => $channel,
		id        => $id,
		data      => $request->getResults,
		timestamp => time2str( time() ),
	} ];
	
	# Deliver request results via Manager
	$manager->deliver_events( $clid, $events );
}

sub closeHandler {
	my $httpClient = shift;

	# unregister connection from manager
	my $clid = $httpClient->clid || return;
	
	if ( $log->is_debug ) {
		$log->debug( "Lost connection, clid: $clid, transport: " . $httpClient->transport );
	}
	
	$manager->unregister_connection( $clid, $httpClient );
	
	Slim::Utils::Timers::setTimer(
		$clid,
		Time::HiRes::time() + ( ( RETRY_DELAY / 1000 ) * 2 ),
		\&disconnectClient,
	);
}

sub disconnectClient {
	my $clid = shift;
	
	# Clean up only if this client has no other connections
	if ( $manager->is_valid_clid( $clid) && !$manager->has_connections( $clid ) ) {
		$log->debug( "Disconnect for $clid, removing subscriptions" );
	
		# Remove any subscriptions for this client
		Slim::Control::Request::unregisterAutoExecute( $clid );
	
		# Remove client from manager
		$manager->remove_client( $clid );
	}
}

# Create a new UUID
sub new_uuid {
	return sha1_hex( Time::HiRes::time() . $$ . Slim::Utils::Network::hostName() );
}

1;