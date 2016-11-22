package Slim::Web::Cometd;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
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
use HTTP::Date;
use JSON::XS::VersionOneAndTwo;
use Scalar::Util qw(blessed);
use URI::Escape qw(uri_unescape);

use Slim::Control::Request;
use Slim::Web::Cometd::Manager;
use Slim::Web::HTTP;
use Slim::Utils::Compress;
use Slim::Utils::Log;
use Slim::Utils::Timers;

my $log = logger('network.cometd');

my $manager = Slim::Web::Cometd::Manager->new;

# Map channels to callback closures
my %subCallbacks = ();

# requests that we need to unsubscribe from
my %toUnsubscribe = ();

use constant PROTOCOL_VERSION => '1.0';
use constant RETRY_DELAY      => 5000;

use constant LONG_POLLING_INTERVAL => 0;     # client can request again immediately
use constant LONG_POLLING_TIMEOUT  => 60000; # server will wait up to 60s for events to send
use constant LONG_POLLING_AUTOKILL => 180000; # server waits 3m for new poll before auto disconnecting client

# indicies used for $conn in handler()
use constant HTTP_CLIENT      => 0;
use constant HTTP_RESPONSE    => 1;

sub init {
	Slim::Web::Pages->addRawFunction( '/cometd', \&webHandler );
	Slim::Web::HTTP::addCloseHandler( \&webCloseHandler );
}

# Handler for CLI requests
sub cliHandler {
	my ( $socket, $message ) = @_;
	
	# Tell the CLI plugin to notify us on disconnect for this socket
	Slim::Plugin::CLI::Plugin::addDisconnectHandler( $socket, \&cliCloseHandler );
	
	handler( [ $socket, undef ], $message );
}

# Handler for web requests
sub webHandler {
	my ( $httpClient, $httpResponse ) = @_;
	
	# make sure we're connected
	if ( !$httpClient->connected ) {
		$log->warn("Aborting, client not connected: $httpClient");
		return;
	}
	
	my $req = $httpResponse->request;
	my $ct	= $req->content_type;
	
	my ( $params, %ops );
	
	if ( $ct && $ct =~ m{^(?:text|application)/json} ) {
		# POST as plain JSON
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
	
	handler( [ $httpClient, $httpResponse ], $ops{message} );
}

sub handler {
	my ( $conn, $message ) = @_;
	
	if ( !$message ) {
		sendResponse( 
			@{$conn},
			[ { successful => JSON::XS::false, error => 'no bayeux message found' } ]
		);
		return;
	}

	my $objs = eval { from_json( $message ) };
	if ( $@ ) {
		sendResponse( 
			@{$conn},
			[ { successful => JSON::XS::false, error => "$@" } ]
		);
		return;
	}
	
	if ( ref $objs ne 'ARRAY' ) {
		if ( $log->is_warn ) {
			$log->warn( 'Got Cometd request that is not an array: ', (main::DEBUGLOG && $log->is_debug) ? Data::Dump::dump($objs) : '' );
		}
		
		sendResponse( 
			@{$conn},
			[ { successful => JSON::XS::false, error => 'bayeux message not an array' } ]
		);
		return;
	}
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		my $peer = $conn->[HTTP_CLIENT]->peerhost . ':' . $conn->[HTTP_CLIENT]->peerport;
		$log->debug( "Cometd request ($peer): " . Data::Dump::dump( $objs ) );
	}
	
	my $clid;
	my $events = [];
	my @errors;
	my $delayedResponse; # false if we want to call sendResponse at the end of this method
	
	for my $obj ( @{$objs} ) {		
		if ( ref $obj ne 'HASH' ) {
			sendResponse( 
				@{$conn},
				[ { successful => JSON::XS::false, error => 'bayeux event not a hash' } ]
			);
			return;
		}
		
		if ( !$clid ) {
			# specified clientId
			if ( $obj->{clientId} ) {
				$clid = $obj->{clientId};
			}
			elsif ( $obj->{channel} eq '/meta/handshake' ) {
				$clid = Slim::Utils::Misc::createUUID(); 
				$manager->add_client( $clid );
			}
			elsif ( $obj->{channel} =~ m{^/slim/(?:subscribe|request)} && $obj->{data} ) {
				# Pull clientId out of response channel
				($clid) = $obj->{data}->{response} =~ m{/([0-9a-f]{8})/};
			}
			elsif ( $obj->{channel} =~ m{^/slim/unsubscribe} && $obj->{data} ) {
				# Pull clientId out of unsubscribe
				($clid) = $obj->{data}->{unsubscribe} =~ m{/([0-9a-f]{8})/};
			}
			
			# Register client with HTTP connection
			if ( $clid ) {
				if ( ref $conn eq 'ARRAY' ) {
					$conn->[HTTP_CLIENT]->clid( $clid );
				}
			}
			else {
				push @errors, {
					channel => $obj->{channel},
					error   => 'No clientId found',
					id      => $obj->{id},
				};
				
				# No point in trying to process requests without a clientId
				# Given that we are not sending advice to the client, the pending
				# requests may just get dropped but what can we do?
				$log->error('Invalid request without clientId - discarding remaining requests in packet');
				last;
			}
		}
		
		# Detect the language Jive wants content returned in
		my ($lang, $ua);
		if ( ref $conn ) {
			if ( my $al = $conn->[HTTP_RESPONSE]->request->header('Accept-Language') ) {
				$lang = uc $al;
			}

			# Detect the user agent
			$ua = $conn->[HTTP_RESPONSE]->request->header('X-User-Agent') || $conn->[HTTP_RESPONSE]->request->header('User-Agent');
		}
		
		# If a client sends any request and we do not have a valid clid record
		# because the streaming connection has been lost for example, re-handshake them
		if ( !$manager->is_valid_clid( $clid ) ) {
			# Invalid clientId, send advice to re-handshake
			push @{$events}, {
				channel    => $obj->{channel},
				clientId   => undef,
				successful => JSON::XS::false,
				timestamp  => time2str( time() ),
				error      => 'invalid clientId',
				advice     => {
					reconnect => 'handshake',
					interval  => 0,
				}
			};
			
			last;
		}
		
		if ( $obj->{channel} eq '/meta/handshake' ) {
			
			my $advice = {
				reconnect => 'retry',               # one of "none", "retry", "handshake"
				interval  => LONG_POLLING_INTERVAL, # initial interval is 0 to support long-polling's connect request
				timeout   => LONG_POLLING_TIMEOUT,
			};
				
			push @{$events}, {
				channel					 => '/meta/handshake',
				version					 => PROTOCOL_VERSION,
				supportedConnectionTypes => [ 'long-polling', 'streaming' ],
				clientId				 => $clid,
				successful				 => JSON::XS::true,
				advice					 => $advice,
			};			
		}
		elsif ( $obj->{channel} =~ qr{^/meta/(?:re)?connect$} ) {
			main::DEBUGLOG && $log->debug( "Client (re-)connected: $clid" );
			
			my $streaming = $obj->{connectionType} eq 'streaming' ? 1 : 0;

			# We want the /meta/(re)connect response to always be the first event
			# sent in the response, so it's stored in the special first_event slot
			$conn->[HTTP_CLIENT]->first_event( {
				channel    => $obj->{channel},
				clientId   => $clid,
				successful => JSON::XS::true,
				timestamp  => time2str( time() ),
				advice     => {
					interval => $streaming ? RETRY_DELAY : 0, # update interval for streaming mode
				},
			} );
			
			# Remove disconnect timer, as a connect is basically the same as a reconnect
			Slim::Utils::Timers::killTimers( $clid, \&disconnectClient );
			
			# register this connection with the manager
			$manager->register_connection( $clid, $conn );
			
			if ( $streaming ) {					
				if ( ref $conn eq 'ARRAY' ) {
					# HTTP-specific connection stuff
					# Streaming connections use chunked transfer encoding
					$conn->[HTTP_RESPONSE]->header( 'Transfer-Encoding' => 'chunked' );
		
					# Tell HTTP client our transport
					$conn->[HTTP_CLIENT]->transport( 'streaming' );
				}
			}
			else {
				# Long-polling
				$conn->[HTTP_CLIENT]->transport( 'long-polling' );
				
				my $timeout = LONG_POLLING_TIMEOUT;
				
				# Client can override timeout
				if ( $obj->{advice} && exists $obj->{advice}->{timeout} ) {
					$timeout = $obj->{advice}->{timeout};
				}
				
				# If we have pending messages for this client, send immediately
				if ( $manager->has_pending_events($clid) ) {
					main::DEBUGLOG && $log->is_debug && $log->debug('Sending long-poll response immediately');				
					$timeout = 0;
				}
				
				# Hold the connection open while we wait for events
				# If timeout is 0, sendResponse will be called as soon as all
				# events in the request have been processed
				main::DEBUGLOG && $log->is_debug && $log->debug("Waiting ". ($timeout / 1000) . " seconds on long-poll connection");
					
				Slim::Utils::Timers::setTimer(
					$conn->[HTTP_CLIENT],
					Time::HiRes::time() + ($timeout / 1000),
					\&sendResponse,
					$conn->[HTTP_RESPONSE],
				);
				
				$delayedResponse = 1;
			}
		}
		elsif ( $obj->{channel} eq '/meta/disconnect' ) {
			
			# disconnect them				
			push @{$events}, {
				channel    => '/meta/disconnect',
				clientId   => $clid,
				successful => JSON::XS::true,
				timestamp  => time2str( time() ),
			};
			
			if ( ref $conn eq 'ARRAY' ) {
				# Close the connection after this response
				$conn->[HTTP_RESPONSE]->header( Connection => 'close' );
			}
		
			disconnectClient( $clid );
		}
		elsif ( $obj->{channel} eq '/meta/subscribe' ) {
			
			my $subscriptions = $obj->{subscription};
		
			# a channel name or a channel pattern or an array of channel names and channel patterns.
			if ( !ref $subscriptions ) {
				$subscriptions = [ $subscriptions ];
			}
		
			$manager->add_channels( $clid, $subscriptions );
		
			for my $sub ( @{$subscriptions} ) {
				push @{$events}, {
					channel      => '/meta/subscribe',
					clientId     => $clid,
					successful   => JSON::XS::true,
					subscription => $sub,
				};
			}
		}
		elsif ( $obj->{channel} eq '/meta/unsubscribe' ) {
			
			my $subscriptions = $obj->{subscription};
		
			# a channel name or a channel pattern or an array of channel names and channel patterns.
			if ( !ref $subscriptions ) {
				$subscriptions = [ $subscriptions ];
			}
		
			$manager->remove_channels( $clid, $subscriptions );
		
			for my $sub ( @{$subscriptions} ) {
				push @{$events}, {
					channel      => '/meta/unsubscribe',
					clientId     => $clid,
					subscription => $sub,
					successful   => JSON::XS::true,
				};
			}
		}
		elsif ( $obj->{channel} eq '/slim/subscribe' ) {
			# A request to execute & subscribe to some Logitech Media Server event
			
			# A valid /slim/subscribe message looks like this:
			# {
			#   channel  => '/slim/subscribe',
			#   id       => <unique id>,
			#   data     => {
			#     response => '/slim/serverstatus', # the channel all messages should be sent back on
			#     request  => [ '', [ 'serverstatus', 0, 50, 'subscribe:60' ],
			#     priority => <value>, # optional priority value, is passed-through with the response
			#   }
			
			# If the request array doesn't contain 'subscribe:foo' the request will be treated
			# as a normal subscription using Request::subscribe()
			
			my $id       = $obj->{id};
			my $request  = $obj->{data}->{request};
			my $response = $obj->{data}->{response};
			my $priority = $obj->{data}->{priority};
			
			if ( $request && $response ) {
				# We expect the clientId to be part of the response channel
				my ($responseClid) = $response =~ m{/([0-9a-f]{8})/};
				
				my $result = handleRequest( {
					id       => $id,
					request  => $request,
					response => $response,
					priority => $priority,
					clid     => $responseClid,
					type     => 'subscribe',
					lang     => $lang,
					ua       => $ua,
				} ); 
				
				if ( $result->{error} ) {
					
					my $error = {
						channel => '/slim/subscribe', 
						error   => $result->{error},
						id      => $id,
					};
					
					push @errors, $error;

					if ($result->{'errorNeedClient'}) {
						$log->error('errorNeedsClient: ', join(', ', $request->[0], @{$request->[1]}));
						# Force reconnect because client not connected.
						# We should not need to force a new handshake, just a reconnect.
						# Any successful subscribes will have the acknowledgements in the $events queue
						# and others will be retried by the client unpon reconnect.
						# Let the client pick the interval to give SlimProto a chance to reconnect.
						$error->{'advice'} = {
							reconnect => 'retry',
						};
						
						# The client will stop processing responses after this error with reconnect advice
						# so stop processing further requests.
						last;
					}
						
				}
				else {
					push @{$events}, {
						channel      => '/slim/subscribe',
						clientId     => $clid,
						successful   => JSON::XS::true,
						id           => $id,
					};
					
					# Remove this subscription from pending unsubscribes, if any
					delete $toUnsubscribe{$response};
					
					# If the request was not async, tell the manager to deliver the results to all subscribers
					if ( exists $result->{data} ) {
						if ( $conn->[HTTP_CLIENT]->transport && $conn->[HTTP_CLIENT]->transport eq 'long-polling' ) {
							push @{$events}, $result;
							
							# We might be in delayed response mode, but we don't want to delay
							# this non-async data
							$delayedResponse = 0;
						}
						else {
							$manager->deliver_events( $result );
						}
					}
				}
			}
			elsif ( !$request ) {
				push @errors, {
					channel => '/slim/subscribe',
					error   => 'request data key not found',
					id      => $id,
				};
			}
			elsif ( !$response ) {
				push @errors, {
					channel => '/slim/subscribe',
					error   => 'response data key not found',
					id      => $id,
				};
			}
		}
		elsif ( $obj->{channel} eq '/slim/unsubscribe' ) {
			# A request to unsubscribe from a Logitech Media Server event, this is not the same as /meta/unsubscribe
			
			# A valid /slim/unsubscribe message looks like this:
			# {
			#   channel  => '/slim/unsubscribe',
			#   data     => {
			#     unsubscribe => '/slim/serverstatus',
			#   }
			
			my $unsub = $obj->{data}->{unsubscribe};
			
			# If this subscription was a normal subscribe, we can unsubscribe now
			if ( my $callback = delete $subCallbacks{$unsub} ) {
				# this was a normal subscribe, so we have to call unsubscribe()
				main::DEBUGLOG && $log->debug( "Request::unsubscribe( $callback )" );

				Slim::Control::Request::unsubscribe( $callback );
			}
			else {
				# Add it to our list of pending unsubscribe events
				# It will be removed the next time we get a requestCallback for it
				$toUnsubscribe{$unsub} = 1;
			}
			
			push @{$events}, {
				channel      => '/slim/unsubscribe',
				clientId     => $clid,
				id           => $obj->{id},
				successful   => JSON::XS::true,
				data         => $obj->{data},
			};
		}
		elsif ( $obj->{channel} eq '/slim/request' ) {
			# A request to execute a one-time Logitech Media Server event
			
			# A valid /slim/request message looks like this:
			# {
			#   channel  => '/slim/request',
			#   id       => <unique id>, (optional)
			#   data     => {
			#     response => '/slim/<clientId>/request',
			#     request  => [ '', [ 'menu', 0, 100, ],
			#     priority => <value>, # optional priority value, is passed-through with the response
			#   }
			
			my $id       = $obj->{id};
			my $request  = $obj->{data}->{request};
			my $response = $obj->{data}->{response};
			my $priority = $obj->{data}->{priority};
			
			if ( $request && $response ) {
				# We expect the clientId to be part of the response channel
				my ($responseClid) = $response =~ m{/([0-9a-f]{8})/};
				
				my $result = handleRequest( {
					id       => $id,
					request  => $request,
					response => $response,
					priority => $priority,
					clid     => $responseClid,
					type     => 'request',
					lang     => $lang,
					ua       => $ua,
				} );
				
				if ( $result->{error} ) {
					push @errors, {
						channel => '/slim/request',
						error   => $result->{error},
						id      => $id,
					};
				}
				else {
					# If the caller does not want the response, id will be undef
					if ( !$id ) {
						# do nothing
						main::DEBUGLOG && $log->debug('Not sending response to request, caller does not want it');
					}
					else {
						# This response is optional, but we do it anyway
						push @{$events}, {
							channel    => '/slim/request',
							clientId   => $clid,
							successful => JSON::XS::true,
							id         => $id,
						};
					
						# If the request was not async, tell the manager to deliver the results to all subscribers
						if ( exists $result->{data} ) {
							if ( $conn->[HTTP_CLIENT]->transport && $conn->[HTTP_CLIENT]->transport eq 'long-polling' ) {
								push @{$events}, $result;
							}
							else {
								$manager->deliver_events( $result );
							}
						}
					}
				}
			}
			elsif ( !$request ) {
				push @errors, {
					channel => '/slim/request',
					error   => 'request data key not found',
					id      => $id,
				};
			}
			elsif ( !$response ) {
				push @errors, {
					channel => '/slim/request',
					error   => 'response data key not found',
					id      => $id,
				};
			}
		}
		else {
			# Any other channel, except special /service/* channel 
			if ( $obj->{channel} !~ q{^/service/} ) {
				$manager->deliver_events( [ $obj ] );
			}
			
			push @{$events}, {
				channel      => $obj->{channel},
				id           => $obj->{id},
				successful   => JSON::XS::true,
			};
		}
	}
	
	if ( @errors ) {		
		for my $error ( @errors ) {
			$error->{successful} = JSON::XS::false;
						
			push @{$events}, $error;
		}
	}
	
	if ( $delayedResponse ) {
		# Used for long-polling, sendResponse will be called by a timer.
		# We need to queue the events it will send
		$manager->queue_events( $clid, $events );
	}
	else {
		sendResponse( @{$conn}, $events );
	}
}

sub sendResponse {
	my ( $httpClient, $httpResponse, $out ) = @_;
	
	$out ||= [];
	
	# Add any additional pending events
	push @{$out}, ( $manager->get_pending_events( $httpClient->clid ) );
	
	# Add special first event for /meta/(re)connect if set
	# Note: calling first_event will remove the event from httpClient
	if ( my $first = $httpClient->first_event ) {
		unshift @{$out}, $first;
	}
	
	if ($httpResponse) {
		if ( $httpClient->transport && $httpClient->transport eq 'long-polling' ) {
			# Finish a long-poll cycle by sending all pending events and removing the timer			
			Slim::Utils::Timers::killTimers($httpClient, \&sendResponse);
		}
		
		sendHTTPResponse( $httpClient, $httpResponse, $out );
	}
	else {
		# For CLI, don't send anything if there are no events
		if ( scalar @{$out} ) {
			sendCLIResponse( $httpClient, $httpResponse, $out );
		}
	}
}

sub sendHTTPResponse {
	my ( $httpClient, $httpResponse, $out ) = @_;
	
	my $isDebug = main::DEBUGLOG && $log->is_debug;
	
	$httpResponse->code( 200 );
	$httpResponse->header( Expires => '-1' );
	$httpResponse->header( Pragma => 'no-cache' );
	$httpResponse->header( 'Cache-Control' => 'no-cache' );
	$httpResponse->header( 'Content-Type' => 'application/json' );
	
	if ( $httpClient->transport && $httpClient->transport eq 'long-polling' ) {
		# Remove the active connection info from manager until
		# the client makes a new /meta/(re)?connect request
		$manager->remove_connection( $httpClient->clid );

		# Forcibly disconnect the client if we don't receive a new poll request.
		# A new connect/reconnect will cancel this timer.
		# Prevents excessive build up of queued events for a quiescent client,
		# or a client that terminates without issuing 'meta/disconnect'.
		Slim::Utils::Timers::setTimer(
			$httpClient->clid,
			Time::HiRes::time() + ( LONG_POLLING_AUTOKILL / 1000),
			\&disconnectClient,
		);
	}
	
	$out = eval { to_json($out) };
	if ( $@ ) {
		$out = to_json( [ { successful => JSON::XS::false, error => "$@" } ] );
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
		# gzip if requested (unless debugging or less than 150 bytes)
		if ( !$isDebug && Slim::Utils::Compress::hasZlib() && (my $ae = $httpResponse->request->header('Accept-Encoding')) ) {
			my $len = length($out);
			if ( $ae =~ /gzip/ && $len > 150 ) {
				my $output = '';
				if ( Slim::Utils::Compress::gzip( { in => \$out, out => \$output } ) ) {
					$out = $output;
					$httpResponse->header( 'Content-Encoding' => 'gzip' );
					$httpResponse->header( Vary => 'Accept-Encoding' );
				}
			}
		}
		
		$httpResponse->header( 'Content-Length', length $out );
	}
	
	Slim::Web::HTTP::addHTTPResponse(
		$httpClient, $httpResponse, \$out, $sendheaders, $chunked,
	);
	
	if ( main::DEBUGLOG && $isDebug ) {
		my $peer = $httpClient->peerhost . ':' . $httpClient->peerport;
		if ( $sendheaders ) {
			$log->debug( "Sending Cometd response ($peer):\n" 
				. $httpResponse->as_string . $out
			);
		}
		else {
			$log->debug( "Sending Cometd chunk ($peer):\n" . $out );
		}
	}
}

sub sendCLIResponse {
	my ( $socket, $out ) = @_;
	
	$out = eval { to_json($out) };
	if ( $@ ) {
		$out = to_json( [ { successful => JSON::XS::false, error => "$@" } ] );
	}
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( "Sending Cometd CLI chunk:\n" . $out );
	}
	
	Slim::Plugin::CLI::Plugin::cli_request_write( $out, $socket );
}

sub handleRequest {
	my $params = shift;
	
	my $id       = $params->{id} || 0;
	my $cmd      = $params->{request};
	my $response = $params->{response};
	my $priority = $params->{priority} || '';
	my $clid     = $params->{clid};
	
	my $type     = $params->{type};
	my $lang     = $params->{lang};
	my $ua       = $params->{ua};
	
	my $mac  = $cmd->[0];
	my $args = $cmd->[1];

	if ( $type eq 'subscribe' ) {
		# If args doesn't contain a 'subscribe' key, treat it as a normal subscribe
		# call and not a request + subscribe
		my $isRequest = grep { /^subscribe:/ } @{$args};
		
		if ( !$isRequest ) {
			if ( defined $cmd->[1] ) {
				$cmd = [ $cmd->[1] ];
			}
			
			if ( main::DEBUGLOG && $log->is_debug ) {
				$log->debug( 'Treating request as plain subscription: ' . Data::Dump::dump($cmd) );
			}
		
			my $callback = sub {
				my $request = shift;
				
				if ( $mac && $request->client ) {
					# Make sure this notification is for the right client
					
					return unless $mac eq $request->client->id;
				}
				
				$request->source( "$response|$id|$priority|$clid" );
			
				requestCallback( $request );
			};
		
			# Need to store this callback for use later in unsubscribe
			$subCallbacks{ $response } = $callback;
			
			Slim::Control::Request::subscribe( $callback, $cmd );
		
			main::DEBUGLOG && $log->debug( "Subscribed for $response, callback $callback" );
		
			return { ok => 1 };
		}
	}
	
	if ( !$args || ref $args ne 'ARRAY' ) {
		return { error => 'invalid request arguments, array expected' };
	}
	
	my $client;
	my $clientid;
	
	if ( my $mac = $cmd->[0] ) {
		$client   = Slim::Player::Client::getClient($mac);
		$clientid = blessed($client) ? $client->id : undef;
		
		# Special case, allow menu requests with a disconnected client
		if ( !$clientid && $args->[0] eq 'menu' ) {
			# set the clientid anyway, will trigger special handling in S::C::Request to store as diconnected clientid
			$clientid = $mac;
		}
		
		if ( $client ) {
			# Update the client's last activity time, since they did something through Comet
			$client->lastActivityTime( Time::HiRes::time() );
		}
	}
	
	# create a request
	my $request = Slim::Control::Request->new( $clientid, $args );
	
	if ( $request->isStatusDispatchable ) {
		# fix the encoding and/or manage charset param
		$request->fixEncoding;
		
		# remember the response channel, request id, and priority
		$request->source( "$response|$id|$priority|$clid" );
		
		# Only set a callback if the caller wants a response
		if ( $id ) {
			$request->connectionID($clid);
			$request->autoExecuteCallback( \&requestCallback );
		}
		
		# Set language override for this request
		if ( $client ) {
			if ( $lang ) {
				$client->languageOverride( $lang );
			}
			
			# XXX: this could be more specific, i.e. iPeng
			$client->controlledBy('squeezeplay');
		}
		elsif ( $lang ) {
			$request->setLanguageOverride($lang);
		}
		
		if ( $ua && $client ) {
			$client->controllerUA($ua);
		}
		
		# Finish is called when request is done to reset language and controlledBy
		my $finish = sub {
			if ( $client ) {
				$client->languageOverride(undef);
				$client->controlledBy(undef);
				$client->controllerUA(undef);
			}
		};
		
		$request->execute();
		
		if ( $request->isStatusError ) {
			$finish->();
			return { error => 'request failed with error: ' . $request->getStatusText };
		}
		
		# If user doesn't care about the response, return nothing
		if ( !$id ) {
			main::DEBUGLOG && $log->debug( "Request for $response, but caller does not care about the response" );
			
			$finish->();
			return { ok => 1 };
		}
		
		# handle async commands
		if ( $request->isStatusProcessing ) {
			# Only set a callback if the caller wants a response
			$request->callbackParameters( sub {
				requestCallback(@_);
				$finish->();
			} );
			
			main::DEBUGLOG && $log->debug( "Request for $response / $id is async, will callback" );
			
			return { ok => 1 };
		}
		
		# the request was successful and is not async
		main::DEBUGLOG && $log->debug( "Request for $response / $id is not async" );
		
		$finish->();
		
		return {
			channel => $response,
			id      => $id,
			data    => $request->getResults,
			ext     => {
				priority => $priority,
			},
		};
	}
	else {
		return {
			error           => 'invalid request: ' . $request->getStatusText,
			errorNeedClient => $request->isStatusNeedsClient(),
		};
	}
}

sub requestCallback {
	my $request = shift;
	
	my ($channel, $id, $priority, $clid) = split (/\|/, $request->source, 4);
	
	main::DEBUGLOG && $log->debug( "requestCallback got results for $channel / $id" );
	
	# Do we need to unsubscribe from this request?
	if ( delete $toUnsubscribe{ $channel } ) {
		main::DEBUGLOG && $log->debug( "requestCallback: unsubscribing from $channel" );
		
		$request->removeAutoExecuteCallback();
		
		return;
	}
	
	my $data = $request->getResults;
	
	if ( exists $subCallbacks{ $channel } ) {
		# If the request was a normal subscribe, we need to use renderAsArray
		$data = [ $request->renderAsArray ];
	}
	
	# Construct event response
	my $events = [ {
		channel   => $channel,
		id        => $id,
		data      => $data,
		ext       => {
			priority => $priority,
		},
	} ];
	
	# Queue request results via Manager
	$manager->queue_events( $clid, $events );
	
	# It's possible for multiple callbacks to be triggered, for example
	# a 'power' event will send both serverstatus and playerstatus data.
	# To allow these to batch together, we need to use a timer to call
	# deliver_events
	Slim::Utils::Timers::setTimer( undef, Time::HiRes::time() + 0.2, sub {
		$manager->deliver_events( [], $clid );
	} );
}

sub webCloseHandler {
	my $httpClient = shift;
	
	# unregister connection from manager
	if ( my $clid = $httpClient->clid ) {
		my $transport = $httpClient->transport || 'none';
			
		if ( main::DEBUGLOG && $log->is_debug ) {
			my $peer = $httpClient->peerhost . ':' . $httpClient->peerport;
			$log->debug( "Lost connection from $peer, clid: $clid, transport: $transport" );
		}

		# Make sure the connection we lost is the current (newest) connection
		# we are using. This was the source of a bug with long-polling because
		# browsers can use either of 2 connections for any given request.

		# A client using long-polling may never be detected here, as it does not have an
		# 'active' connection after a response is sent. Autokill handled in sendHTTPResponse.
		my $conn = $manager->get_connection($clid);
		if ( $conn && $conn->[HTTP_CLIENT] == $httpClient ) {
			$manager->remove_connection( $clid );
			
			if ( $transport eq 'long-polling' ) {
				Slim::Utils::Timers::killTimers($httpClient, \&sendResponse);
			}
			
			Slim::Utils::Timers::setTimer(
				$clid,
				Time::HiRes::time() + ( ( RETRY_DELAY / 1000 ) * 2 ),
				\&disconnectClient,
			);
		}
		else {
			main::DEBUGLOG && $log->is_debug && $log->debug('Not the active connection, ignoring');
		}
	}
}

sub cliCloseHandler {
	my $socket = shift;
	
	my $clid = $manager->clid_for_connection( $socket );
	
	if ( $clid ) {
		if ( main::DEBUGLOG && $log->is_debug ) {
			my $peer = $socket->peerhost . ':' . $socket->peerport;
			$log->debug( "Lost CLI connection from $peer, clid: $clid" );
		}
	
		$manager->remove_connection( $clid );
	
		Slim::Utils::Timers::setTimer(
			$clid,
			Time::HiRes::time() + ( ( RETRY_DELAY / 1000 ) * 2 ),
			\&disconnectClient,
		);
	}
	else {
		if ( main::DEBUGLOG && $log->is_debug ) {
			my $peer = $socket->peerhost . ':' . $socket->peerport;
			$log->debug( "No clid found for CLI connection from $peer" );
		}
	}
}

sub disconnectClient {
	my $clid = shift;
	
	# Clean up this client's data
	if ( $manager->is_valid_clid( $clid) ) {
		main::DEBUGLOG && $log->debug( "Disconnect for $clid, removing subscriptions" );
	
		# Remove any subscriptions for this client, 
		Slim::Control::Request::unregisterAutoExecute( $clid );
			
		main::DEBUGLOG && $log->debug("Unregistered all auto-execute requests for client $clid");
		
		# Remove any normal subscriptions for this client
		for my $channel ( keys %subCallbacks ) {
			if ( $channel =~ m{/$clid/} ) {
				my $callback = delete $subCallbacks{ $channel };
				Slim::Control::Request::unsubscribe( $callback );
				
				main::DEBUGLOG && $log->debug( "Unsubscribed from callback $callback for $channel" );
			}
		}
	
		# Remove client from manager
		$manager->remove_client( $clid );
	}
}

1;
