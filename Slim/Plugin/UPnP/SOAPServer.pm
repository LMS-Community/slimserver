package Slim::Plugin::UPnP::SOAPServer;

# $Id: /sd/slim/7.6/branches/lms/server/Slim/Plugin/UPnP/SOAPServer.pm 76276 2011-02-01T19:44:19.488696Z andy  $
#
# SOAP handling functions.
# Note that SOAP::Lite is only used for parsing requests and generating responses,
# it does not send or receive directly from the network.
#
# This module is based in part on POE::Component::Server::SOAP

use strict;

use HTTP::Date;
use SOAP::Lite;
use URI::QueryParam;

use Slim::Utils::Log;
use Slim::Web::HTTP;

use Slim::Plugin::UPnP::Common::Utils qw(xmlUnescape);

my $log = logger('plugin.upnp');

# UPnP Errors
my %ERRORS = (
	401 => 'Invalid Action',
	402 => 'Invalid Args',
	501 => 'Action Failed',
	600 => 'Argument Value Invalid',
	601 => 'Argument Value Out of Range',
	605 => 'String Argument Too Long',
);

sub init {
	my $class = shift;
	
	Slim::Web::Pages->addRawFunction(
		qr{plugins/UPnP/.+/control},
		\&processControl,
	);
}

sub shutdown { }

# Receive a raw SOAP control request, verify and process it,
# returning to the caller a data structure containing the
# actual method call and arguments
sub processControl {
	my ( $httpClient, $response ) = @_;
	
	use bytes;
	
	return unless $httpClient->connected;
	
	my $request = $response->request;
	
	# DLNA 7.2.5.6, return HTTP/1.1 regardless of the request version
	$response->protocol('HTTP/1.1');
	
	$response->header( 'Content-Type' => 'text/xml; charset="utf-8"' );
	$response->header( Ext => '' );
	
	$response->remove_header('Server');
	$response->header( Server => Slim::Plugin::UPnP::Discovery->server() );
	$response->header( Date => time2str( time() ) );
	
	# We only handle text/xml content
	if ( !$request->header('Content-Type') || $request->header('Content-Type') !~ m{^text/xml}i ) {
		$log->warn( 'SOAPServer: Invalid content-type for request: ' . $request->header('Content-Type') );
		fault( $httpClient, $response, 401 );
		return;
	}
	
	# We need the method name
	my $soap_method_name = $request->header('SOAPAction');
	if ( !defined $soap_method_name || !length( $soap_method_name ) ) {
		$log->warn('SOAPServer: Missing SOAPAction header');
		fault( $httpClient, $response, 401 );
		return;
	}
	
	# Get the method name
	if ( $soap_method_name !~ /^([\"\']?)(\S+)\#(\S+)\1$/ ) {
		$log->warn('SOAPServer: Missing method name');
		fault( $httpClient, $response, 401 );
		return;
	}

	# Get the uri + method
	my $soapuri = $2;
	my $method  = $3;
	
	# Get service from URL, check for method existence
	my ($service) = $request->uri->path =~ m{plugins/UPnP/(.+)/control};
	$service =~ s{/}{::}g;
	my $serviceClass = "Slim::Plugin::UPnP::$service";
	
	if ( !$serviceClass->can($method) ) {
		$log->warn("SOAPServer: $serviceClass does not implement $method");
		fault( $httpClient, $response, 401 );
		return;
	}
	
	# Get client id from URL
	my $client;
	my $id = $request->uri->query_param('player');
	
	if ( $id ) {
		$client = Slim::Player::Client::getClient($id);
	}
	
	# JRiver Media Center appends invalid null bytes to its HTTP requests
	$request->{_content} =~ s/\0+$//;
	
	# Parse the request
	my $som_object;
	eval { $som_object = SOAP::Deserializer->deserialize( $request->content ) };
	
	if ( $@ ) {
		$log->warn( "SOAPServer: Error parsing request: $@\n" . $request->content );
		fault( $httpClient, $response, 401 );		
		return;
	}
	
	# Extract the body
	my $body = $som_object->body();

	# Remove the top-level method name in the body
	$body = $body->{ $method };

	# If it is an empty string, turn it into undef
	if ( defined $body && !ref $body && $body =~ /^\s*$/ ) {
		$body = undef;
	}
	
	main::DEBUGLOG && $log->is_debug && $log->debug( "Invoking ${serviceClass}->${method}( " . Data::Dump::dump($body) . ' )' );
	
	# Invoke the method
	my @result = eval {	$serviceClass->$method( $client, $body || {}, $request->headers, $request->header('Host') || $request->uri->host ) };
	
	#warn Data::Dump::dump(\@result) . "\n";
	
	if ( $@ ) {
		$log->warn( "SOAPServer: Error invoking ${serviceClass}->${method}: $@" );
		fault( $httpClient, $response, 501, $@ );
		return;
	}
	
	# Check if the method set error values, this is known
	# if the only return value is an array ref
	if ( ref $result[0] eq 'ARRAY' ) {
		$log->warn( "SOAPServer: ${serviceClass}->${method} returned error: " . Data::Dump::dump(\@result) );
		fault( $httpClient, $response, $result[0]->[0], $result[0]->[1] );
		return;
	}
	
	# Return response
	my $s = SOAP::Serializer->new(
		envprefix => 's',
	);
	
	my $content = $s->envelope(
		'response',
		SOAP::Data->new(
			name   => $method . 'Response',
			uri    => $soapuri,
			prefix => 'u',
		),
		@result,
	);
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		#$log->debug( "Result: $content" );
	}
	
	if ( !defined $response->code ) {
		$response->code( $SOAP::Constants::HTTP_ON_SUCCESS_CODE );
	}
	
	$response->header( 'Content-Length' => length($content) );
	
	Slim::Web::HTTP::addHTTPResponse( $httpClient, $response, \$content	);
}

# Construct and send back a fault message
sub fault {
	my ( $httpClient, $response, $error_code, $error_desc ) = @_;
	
	use bytes;
	
	my $s = SOAP::Serializer->new(
		envprefix => 's',
	);
	
	my $desc = $ERRORS{ $error_code };
	if ( $error_desc ) {
		if ( $desc ) {
			$desc .= " ($error_desc)";
		}
		else {
			$desc = $error_desc;
		}
	}
	$desc ||= 'Unknown Error';
	
	
	my $content = $s->envelope(
		'fault',
		$SOAP::Constants::FAULT_CLIENT,
		'UPnPError',
		SOAP::Data->name( UPnPError =>
			\SOAP::Data->value(
				SOAP::Data->name( 
					errorCode => $error_code
				)->type('int'),
				SOAP::Data->name(
					errorDescription => $desc
				)->type('string'),
			),
 		),
	);
	
	$response->code( $SOAP::Constants::HTTP_ON_FAULT_CODE );
	$response->header( 'Content-Length' => length($content) );
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( "UPnP fault: $error_code / " . ( $error_desc || $ERRORS{ $error_code } || 'Unknown Error' ) );
		$log->debug( "Result: $content" );
	}
	
	Slim::Web::HTTP::addHTTPResponse( $httpClient, $response, \$content	);
}

1;