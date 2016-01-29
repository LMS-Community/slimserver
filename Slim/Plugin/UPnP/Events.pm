package Slim::Plugin::UPnP::Events;

# $Id: /sd/slim/7.6/branches/lms/server/Slim/Plugin/UPnP/Events.pm 75368 2010-12-16T04:09:11.731914Z andy  $
#
# Eventing functions

use strict;

use HTTP::Daemon;
use HTTP::Date;
use URI;
use URI::QueryParam;
use UUID::Tiny ();

use Slim::Networking::Async;
use Slim::Networking::Select;
use Slim::Utils::Errno;
use Slim::Utils::Log;
use Slim::Utils::Timers;

use Slim::Plugin::UPnP::Common::Utils qw(xmlEscape);

my $log = logger('plugin.upnp');

# Server socket
my $SERVER;

# subscriptions
my %SUBS = ();

sub init {
	my $class = shift;
	
	# We can't use Slim::Web::HTTP for GENA requests because
	# they aren't really HTTP.  Open up a new socket for these requests
	# on a random port number.
	$SERVER = HTTP::Daemon->new(
		Listen    => SOMAXCONN,
		ReuseAddr => 1,
		Reuse     => 1,
		Timeout   => 1,
	);
	
	if ( !$SERVER ) {
		$log->error("Unable to open UPnP GENA server socket: $!");
		return;
	}
	
	Slim::Networking::Select::addRead( $SERVER, \&accept );
	
	main::DEBUGLOG && $log->debug( 'GENA listening on port ' . $SERVER->sockport );
	
	return 1;
}

sub port { $SERVER->sockport }

sub shutdown {
	my $class = shift;
	
	Slim::Networking::Select::removeRead($SERVER);
	
	$SERVER = undef;
}

# Event subscription messages
sub accept {
	my $sock = shift;
	
	my $httpClient = $sock->accept || return;
	
	if ( $httpClient->connected() ) {
		Slim::Utils::Network::blocking( $httpClient, 0 );
		$httpClient->timeout(10);
		Slim::Networking::Select::addRead( $httpClient, \&request );
	}
}

sub request {
	my $httpClient = shift;
	
	my $request = $httpClient->get_request;
	
	if ( !defined $request ) {
		closeHTTP($httpClient);
		return;
	}
	
	my $response;
	my $uuid;
	
	$log->is_debug && $log->debug( $request->method . ' ' . $request->uri );
	
	if ( $request->method eq 'SUBSCRIBE' ) {
		($response, $uuid) = subscribe($request);
	}
	elsif ( $request->method eq 'UNSUBSCRIBE' ) {
		$response = unsubscribe($request);
	}
	
	${*$httpClient}{passthrough} = [ $response, $uuid ];
	
	Slim::Networking::Select::addWrite( $httpClient, \&sendResponse );
}

sub sendResponse {
	my ( $httpClient, $response, $uuid, $len, $off ) = @_;
	
	if ( !$httpClient->connected ) {
		closeHTTP($httpClient);
		return;
	}
	
	use bytes;
	
	my $sent = 0;
	$off   ||= 0;
	
	if ( !defined $len ) {
		$len = length($response);
	}
	
 	$sent = syswrite $httpClient, $response, $len, $off;

	if ( $! == EWOULDBLOCK ) {
		if ( !defined $sent ) {
			$sent = 0;
		}
	}
	
	if ( !defined $sent ) {
		$log->is_debug && $log->debug( "sendResponse failed: $!" );
		closeHTTP($httpClient);
		return;
	}
	
	if ( $sent < $len ) {		
		$len -= $sent;
		$off += $sent;
		
		$log->is_debug && $log->debug( "sent partial response: $sent ($len left)" );
		
		# Next time we're called, pass through new len/off values
		${*$httpClient}{passthrough} = [ $response, $uuid, $len, $off ];
	}
	else {
		# After we're done sending, if we have a uuid, flag it as an active subscription
		if ( $uuid ) {
			$log->is_debug && $log->debug( "Sub $uuid is now active" );
			$SUBS{ $uuid }->{active} = 1;
		}
		
		closeHTTP($httpClient);
		return;
	}
}

sub closeHTTP {
	my $httpClient = shift;
	
	Slim::Networking::Select::removeRead($httpClient);
	Slim::Networking::Select::removeWrite($httpClient);
	
	$httpClient->close;
}

sub subscribe {
	my $request = shift;
	
	my $uuid;
	my $timeout;
	
	if ( my $sid = $request->header('Sid') ) {
		# Renewal
		($uuid)    = $sid =~ /uuid:([^\s]+)/;
		($timeout) = $request->header('Timeout') =~ /Second-(\d+)/i;
		
		if ( !defined $timeout ) {
			$timeout = 300;
		}
		
		if ( $request->header('NT') || $request->header('Callback') ) {
			return error('400 Bad Request');
		}
		
		if ( !$uuid || !exists $SUBS{ $uuid } ) {
			return error('412 Precondition Failed');
		}
		
		$log->is_debug && $log->debug( "Renewed: $uuid ($timeout sec)" );
		
		# Refresh the timer
		Slim::Utils::Timers::killTimers( $uuid, \&expire );
		Slim::Utils::Timers::setTimer( $uuid, time() + $timeout, \&expire );
	}
	else {
		# Subscribe
		
		# Verify request is correct
		if ( !$request->header('NT') || $request->header('NT') ne 'upnp:event' ) {
			return error('400 Bad Request');
		}
		
		# Verify player param
		my $client;
		my $id = $request->uri->query_param('player');

		if ( $id ) {
			$client = Slim::Player::Client::getClient($id);
			if ( !$client ) {
				return error('500 Invalid Player');
			}
		}
		
		# Verify callback is present
		if ( !$request->header('Callback') ) {
			return error('412 Missing Callback');
		}
		
		my @callbacks = $request->header('Callback') =~ /<([^>]+)>/g;
		($timeout)    = $request->header('Timeout') =~ /Second-(\d+)/i;
		
		if ( !scalar @callbacks ) {
			return error('412 Missing Callback');
		}
		
		if ( !defined $timeout ) {
			$timeout = 300;
		}
		
		my ($service) = $request->uri->path =~ m{plugins/UPnP/(.+)/eventsub};
		$service =~ s{/}{::}g;
		my $serviceClass = "Slim::Plugin::UPnP::$service";
		
		$uuid = uc( UUID::Tiny::create_UUID_as_string( UUID::Tiny::UUID_V4() ) );
		
		$SUBS{ $uuid } = {
			active    => 0, # Sub is not active until we send it to the subscriber
			client    => $client ? $client->id : 0,
			service   => $serviceClass,
			callbacks => \@callbacks,
			expires   => time() + $timeout,
			key       => -1, # will get increased to 0 when first sent
		};
		
		# Set a timer to expire this subscription
		Slim::Utils::Timers::killTimers( $uuid, \&expire );
		Slim::Utils::Timers::setTimer( $uuid, time() + $timeout, \&expire );
		
		main::INFOLOG && $log->is_info && $log->info( "Subscribe: $uuid ($serviceClass) ($timeout sec) -> " . join(', ', @callbacks) );
		
		# Inform the service of the subscription for this client
		# The service will send the initial event state by calling notify()
		$serviceClass->subscribe( $client, $uuid );
	}
	
	my $response = join "\x0D\x0A", (
		'HTTP/1.1 200 OK',
		'Date: ' . time2str( time() ),
		'Server: ' . Slim::Plugin::UPnP::Discovery->server,
		'Content-Length: 0',
		'SID: uuid:' . $uuid,
		'Timeout: Second-' . $timeout,
		'', '',
	);
	
	return ($response, $uuid);
}

sub unsubscribe {
	my $request = shift;
	
	my $uuid;
	
	if ( $request->header('NT') || $request->header('Callback') ) {
		return error('400 Bad Request');
	}
	
	if ( my $sid = $request->header('Sid') ) {
		($uuid) = $sid =~ /uuid:([^\s]+)/;
		
		if ( !$uuid || !exists $SUBS{ $uuid } ) {
			return error('412 Precondition Failed');
		}
		
		# Verify player param
		my $client;
		my $id = $request->uri->query_param('player');

		if ( $id ) {
			$client = Slim::Player::Client::getClient($id);
			if ( !$client ) {
				return error('500 Invalid Player');
			}
		}
		
		Slim::Utils::Timers::killTimers( $uuid, \&expire );
		
		# Inform the service of the unsubscription for this client
		my $serviceClass = $SUBS{ $uuid }->{service};
		
		main::INFOLOG && $log->is_info && $log->info( "Unsubscribe: $uuid ($serviceClass)" );
		
		$serviceClass->unsubscribe( $client );
		
		delete $SUBS{ $uuid };
		
		my $response = join "\x0D\x0A", (
			'HTTP/1.1 200 OK',
			'', '',
		);

		return $response;
	}
	else {
		return error('400 Bad Request');
	}
}

sub error {
	my $error = shift;
	
	$log->error( 'Subscribe/unsubscribe error: ' . $error );
	
	return join "\x0D\x0A", (
		'HTTP/1.1 ' . $error,
		'Date: ' . time2str( time() ),
		'Server: ' . Slim::Plugin::UPnP::Discovery->server,
		'', '',
	);
}

# Notify for either a UUID or a clientid
sub notify {
	my ( $class, %args ) = @_;
	
	my $service = $args{service};
	my $id      = $args{id};
	my $data    = $args{data};
	
	# Construct notify XML
	my $wrapper = qq{<?xml version="1.0"?>
<e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0">
};

	while ( my ($k, $v) = each %{$data} ) {
		$wrapper .= "  <e:property><$k>" . xmlEscape($v) . "</$k></e:property>\n";
	}
	
	$wrapper .= "</e:propertyset>\n";
	
	while ( my ($uuid, $sub) = each %SUBS ) {
		# $id may be either a client id or a UUID
		if ( $id eq $sub->{client} || $id eq $uuid ) {
			if ( $service eq $sub->{service} ) {
				# Increase send key
				if ( $sub->{key} == 4294967295 ) {
					$sub->{key} = 1;
				}
				else {
					$sub->{key}++;
				}
			
				sendNotify( $uuid, $sub, $wrapper );
			}
		}
	}
}

sub sendNotify {
	my ( $uuid, $sub, $xml ) = @_;
	
	# Has the subscription been unsubscribed?
	if ( !exists $SUBS{ $uuid } ) {
		return;
	}
	
	# If this subscription is not yet active,
	# i.e. it is new and the response to the initial
	# subscribe request has not yet been sent,
	# we must wait before sending anything
	if ( !$SUBS{ $uuid }->{active} ) {
		$log->is_debug && $log->debug( "Delaying notify for $uuid, not yet active" );
		Slim::Utils::Timers::setTimer( $uuid, Time::HiRes::time() + 0.2, \&sendNotify, $sub, $xml );
		return;
	}
	
	use bytes;
	
	my $url = $sub->{callbacks}->[0];
	
	my $uri = URI->new($url);
	my $host = $uri->host;
	my $port = $uri->port || 80;

	my $notify = join "\x0D\x0A", (
		'NOTIFY ' . $uri->path_query . ' HTTP/1.1',
		"Host: $host:$port",
		'Content-Type: text/xml; charset="utf-8"',
		'Content-Length: ' . length($xml),
		'NT: upnp:event',
		'NTS: upnp:propchange',
		'SID: uuid:' . $uuid,
		'SEQ: ' . $sub->{key},
		'',
		$xml,
	);
	
	if ( main::INFOLOG && $log->is_info ) {
		$log->info( "Notifying to $host:$port for " . $sub->{client} . " / " . $sub->{service} );
		main::DEBUGLOG && $log->is_debug && $log->debug($notify);
	}
	
	# XXX use AnyEvent::Socket instead?
	
	my $async = Slim::Networking::Async->new;
	$async->write_async( {
		host        => $uri->host,
		port        => $uri->port,
		content_ref => \$notify,
		Timeout     => 30,
		onError     => sub {
			main::DEBUGLOG && $log->is_debug && $log->debug( 'Event failed to notify to ' . $uri->host . ':' . $uri->port . ': ' . $_[1] );
			# XXX: try next callback URL, may not be required per DLNA
		},
		onRead      => sub {
			my $a = shift;
			
			sysread $a->socket, my $res, 1024;
			
			Slim::Networking::Select::removeError( $a->socket );
			Slim::Networking::Select::removeRead( $a->socket );
			
			$a->disconnect;
			
			main::DEBUGLOG && $log->is_debug && $log->debug( 'Event notified OK' );
		},
	} );
}

sub expire {
	my $uuid = shift;
	
	if ( exists $SUBS{ $uuid } ) {
		# Inform the service of the unsubscription for this client
		my $serviceClass = $SUBS{ $uuid }->{service};
		my $clientid     = $SUBS{ $uuid }->{client};
		
		my $client = Slim::Player::Client::getClient($clientid);
		$serviceClass->unsubscribe( $client );
	
		delete $SUBS{ $uuid };
		
		$log->is_debug && $log->debug( "Expired $uuid ($serviceClass)" );
	}
}

1;