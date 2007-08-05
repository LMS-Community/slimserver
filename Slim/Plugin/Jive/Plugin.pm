package Slim::Plugin::Jive::Plugin;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Plugin::Base);

use HTTP::Status;
use JSON::XS qw(from_json);
use JSON;
use Scalar::Util qw(blessed);

use Slim::Utils::Log;
#use Slim::Utils::Misc;
#use Slim::Utils::Prefs;
#use Slim::Utils::Strings qw(string);
use Data::Dumper;


=head1 NAME

Plugins::Jive::Plugin

=head1 SYNOPSIS

Provides a JSON-RPC API over HTTP

=cut


#local $JSON::UTF8 = 1;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.jive',
	'defaultLevel' => 'WARN',
	'description'  => getDisplayName(),
});

my %procedures = (
	'system.describe'     => \&describeProcedure,
	'slim.request'        => \&requestProcedure,
	'slim.playermenu'     => \&playermenuProcedure, #remove me once branch is merged
);

our %contexts = ();

################################################################################
# PLUGIN CODE
################################################################################
=head1 METHODS

=head2 initPlugin()

Plugin init. Registers the URI we're handling with the HTTP code.

=cut
sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin();
	
	# add our handler
	Slim::Web::HTTP::addRawFunction('plugins/Jive/jive.js', \&processRequest);
	
	# add our close handler, we want to be called if a connection closes to
	# clear our contexts.
	Slim::Web::HTTP::addCloseHandler(\&closeHandler);
	
	# register our functions
	
#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F

    Slim::Control::Request::addDispatch(['menu', '_index', '_quantity'], 
        [0, 1, 1, \&menuQuery]);

}

=head2 getDisplayName()

Returns plugin name

=cut
sub getDisplayName {
	return 'PLUGIN_JIVE';
}

################################################################################
# REQUESTS
################################################################################
=head2 processRequest( httpClient, httpResponse)

This is the callback from the HTTP code if the URI of the request matches the
one we've registered. We're passed the HTTP client object and a HTTP response
object.
Decode the request as JSON-RPC, following protocols 1.0 and proposed 1.1.

=cut
sub processRequest {
	my ($httpClient, $httpResponse) = @_;

	$log->debug("processRequest($httpClient)");
	
	# make sure we're connected
	if (!$httpClient->connected()) {
		$log->warn("Aborting, client not connected! ($httpClient)");
		return;
	}
	
	# cancel any previous subscription on this connection
	# we must have a context defined and a subscription defined
	if (defined($contexts{$httpClient}) && 
		Slim::Control::Request::unregisterAutoExecute($httpClient)) {
	
		# we want to send a last chunk to close the connection as per HTTP...
		# a subscription is essentially a never ending response: we're receiving here
		# a new request (aka pipelining) so we want to be nice and close the previous response
		
		# we cannot have a subscription if this is not a long lasting, keep-open, chunked connection.
		
		Slim::Web::HTTP::addHTTPLastChunk($httpClient, 0);
	}
	
	# create a hash to store our context
	my $context = {};
	$context->{'httpClient'} = $httpClient;
	$context->{'httpResponse'} = $httpResponse;

	# assume we're dealing with JSON 1.0
	$context->{'jsonversion'} = 0;
	
	# get the request data
	# JSON 1.0 supports POST
	# JSON 1.1 supports POST and GET
	my $requestmethod = $httpResponse->request()->method();
	my $input;
	
	if ($requestmethod eq 'POST') {

		$input = $httpResponse->request()->content();
		
	} elsif ($requestmethod eq 'GET') {
		
		# not supported, but should for json 1.1
		$context->{'jsonversion'} = 1;		

	}
	
	if (!$input) {

		# No data
		# JSON 1.0 => close connection
		# JSON 1.1 => 500 Internal server error
		$log->warn("Request has no body! => 400 error");

		# FIXME: no server template for 500. Send 400 instead.
		
		$httpResponse->code(RC_BAD_REQUEST);
		$httpResponse->content_type('text/html');
		$httpResponse->header('Connection' => 'close');

		Slim::Web::HTTP::addHTTPResponse($httpClient, $httpResponse, Slim::Web::HTTP::filltemplatefile('html/errors/400.html'), 1);
		return;
	}

	# FIXME: because we don't parse the GET input for JSON 1.1, we never reach
	# here if the request is not POST.

	# parse the input
	my $procedure;
	$log->debug("Request raw input: [$input]");

	if ($requestmethod eq 'POST') {

		# Convert JSON to Perl
		# FIXME: JSON 1.0 accepts multiple requests ? How do we parse that efficiently?
		$procedure = from_json($input);
		
	} elsif ($requestmethod eq 'GET') {
		
		# FIXME: not supported, but should for json 1.1
		# should parse $procedure from $input	
	}	
	

	# validate the request
	# We must get a JSON object, i.e. a hash
	if (ref($procedure) ne 'HASH') {
		
		$log->warn("Request is not a JSON object => returning error 124");
		
		# return error
		writeJSONError($context, 124, 'Bad call');
		return;
	}
	$context->{'procedure'} = $procedure;


	# process the request
	$log->info(sub {
		use Data::Dumper; 
		return "JSON parsed procedure: " . Data::Dumper::Dumper($procedure); 
		});

	# determine JSON protocol
	my $version = $procedure->{'version'};
	my $id = $procedure->{'id'};
	
	if (!$id && !$version) {
		
		$log->warn("Request has neither id not version => returning error 123");

		# return error, not JSON 1.0 nor 1.1
		writeJSONError($context, 123, 'Not JSON-RPC 1.0 or 1.1');
		return;
	
	} elsif (!$version || $version eq '1.0') {
		
		# JSON 1.0 request
		$context->{'jsonversion'} = 0;

	} elsif ($version eq '1.1') {
		
		# JSON 1.1 request
		$context->{'jsonversion'} = 1;

	} elsif ($version ne '1.1') {
		
		# return error, not JSON 1.0 nor 1.1
		$log->warn("Request has strange version => returning error 123");
		
		writeJSONError($context, 123, 'Not JSON-RPC 1.0 or 1.1');
		return;
	} 
	
	# figure out the method wanted
	my $method = $procedure->{'method'};
	my $funcPtr = $procedures{$method};
	
	if (!$funcPtr) {

		# return error, not a known procedure
		$log->warn("Unknown procedure requested: $method => returning error 123");
		
		writeJSONError($context, 123, 'Procedure not found');
		return;

	} elsif (ref($funcPtr) ne 'CODE') {

		# return internal server error
		$log->error("Procedure $method refers to non CODE ??? => returning error 123");
		
		writeJSONError($context, 123, 'Service error');
		return;
	}
	
	
	# parse the parameters
	my $params = $procedure->{'params'};
	my $paramsType = ref($params);

	if ($paramsType ne 'ARRAY' && $paramsType ne 'HASH') {
		
		# error, params is an array or an object
		$log->warn("Procedure $method has params being neither ARRAY nor HASH => returning error 123");
		writeJSONError($context, 123, 'Bad call');
		return;
		
	} elsif ($version eq '1.0' && $paramsType ne 'ARRAY') {
		
		# error, params is an array for 1.0
		$log->warn("Procedure $method is JSON 1.0 but has non ARRAY params => returning error 123");
		writeJSONError($context, 123, 'Bad call for JSON 1.0');
		return;
	}
				
	# FIXME: accept a hash here for params (JSON 1.1)

	# Check our operational mode using our X-Jive header
	# We must be delaing with a 1.1 client because X-Jive uses chunked transfers
	# We must not be closing the connection
	if (defined(my $xjive = $httpResponse->request()->header('X-Jive')) &&
		$httpClient->proto_ge('1.1') &&
		$httpResponse->header('Connection') !~ /close/i) {
	
		$log->info("Operating in x-jive mode for procedure $method and client $httpClient");
		$context->{'x-jive'} = 1;
		$httpResponse->header('X-Jive' => 'Jive')
	}
	
	# store our context. It'll get erased by the callback in HTTP.pm through closeHandler
	$contexts{$httpClient} = $context;
	
	# remember we need to send headers. We'll reset this once sent.
	$context->{'sendheaders'} = 1;
	
	# jump to the code handling desired method. It is responsible to send a suitable output
	eval { &{$funcPtr}($context); };

	if ($@) {
		my $funcName = Slim::Utils::PerlRunTime::realNameForCodeRef($funcPtr);
		$log->error("While trying to run function coderef [$funcName]: [$@]");
		$log->error(sub { return "JSON parsed procedure: " . Data::Dumper::Dumper($procedure); } );
		writeJSONError($context, 123, 'Service error');
		return;
		
	}
}

sub writeJSONError {
	my ($context, $errCode, $errText) = @_;
	
	$log->debug("writeJSONError($errText)");
	# return a JSON formatted error
	# JSON 1.0 => error field, copy id, result is null
	# JSON 1.1 => error hash with more info
	# we may be called before we have determined the version!
	
	# create an object for the response
	my $response = {};

	# add ID if we have it
	if (defined(my $id = $context->{'procedure'}->{'id'})) {
		$response->{'id'} = $id;
	}

	# add version and error if we're JSON 1.1
	if ($context->{'jsonversion'} == 1) {
		$response->{'version'} = '1.1';
		$response->{'error'} = {
			'name'    => 'JSONRPCError',
        	'code'    => $errCode,
        	'message' => $errText};
	} else {
		$response->{'error'} = $errText;
	}
	
	# while not strictly allowed, neither JSON specs forbids to add the
	# request data to the response...
	$response->{'params'} = $context->{'procedure'}->{'params'};
	$response->{'method'} = $context->{'procedure'}->{'method'};

	# send the error
	writeResponse($context, $response);
}


sub generateJSONResponse {
	my $context = shift;
	my $result = shift;

	$log->debug("generateJSONResponse()");

	# create an object for the response
	my $response = {};
	
	# add ID if we have it
	if (defined(my $id = $context->{'procedure'}->{'id'})) {
		$response->{'id'} = $id;
	}
	
	# add version if we're JSON 1.1
	if ($context->{'jsonversion'} == 1) {
		$response->{'version'} = '1.1';
	}
	
	# add result
	$response->{'result'} = $result;
	
	# while not strictly allowed, neither JSON specs forbids to add the
	# request data to the response...
	$response->{'params'} = $context->{'procedure'}->{'params'};
	$response->{'method'} = $context->{'procedure'}->{'method'};

	writeResponse($context, $response);
}

=head2 writeResponse()

Writes an JSON RPC response to the httpClient

=cut
sub writeResponse {
	my $context = shift;
	my $responseRef = shift;
	
	my $httpClient   = $context->{'httpClient'};
	my $httpResponse = $context->{'httpResponse'};

	$log->info(sub { return "JSON response: " . Data::Dumper::Dumper($responseRef); } );
	
	# Don't waste CPU cycles if we're not connected
	if (!$httpClient->connected()) {
		$log->warn("Client disconnected in writeResponse!");
		return;
	}

	# convert Perl object into JSON
	# FIXME: Use JSON here because JSON::XS does not like tied ordered hashes...
	my $jsonResponse = objToJson($responseRef, {utf8 => 1});
	$jsonResponse = Slim::Utils::Unicode::encode('utf8', $jsonResponse);

	$log->debug("JSON raw response: [$jsonResponse]");

	$httpResponse->code(RC_OK);
	
	# set a content type to 1.1 proposed value. Should work with 1.0 as it is not specified
	$httpResponse->content_type('application/json');
	
	use bytes;
	
	# send the headers only once
	my $sendheaders = $context->{'sendheaders'};
	if ($sendheaders) {
		$context->{'sendheaders'} = 0;
	}
	
	# in xjive mode, use chunked mode without a last chunk (i.e. we always have $more)
	my $xjive = $context->{'x-jive'};
	
	if ($xjive) {
		$httpResponse->header('Transfer-Encoding' => 'chunked');
	} else {
		$httpResponse->content_length(length($jsonResponse));
	}
	
	if ($sendheaders) {
	
		$log->debug("Response headers: [\n" . $httpResponse->as_string . "]");
	}

	Slim::Web::HTTP::addHTTPResponse($httpClient, $httpResponse, \$jsonResponse, $sendheaders, $xjive);
}

=head2 closeHandler( $httpClient )

Deletes all our references to the $httpClient
Called by Slim::Web::HTTP

=cut
sub closeHandler {
	my $httpClient = shift;

	if ( defined $contexts{$httpClient} ) {
		$log->debug("Closing any subscriptions for $httpClient");
	
		Slim::Control::Request::unregisterAutoExecute($httpClient);
		delete $contexts{$httpClient};
	}
}

################################################################################
# JSON PROCEDURES
################################################################################

sub describeProcedure {
	my $context = shift;

	$log->debug("describeProcedure()");

	generateJSONResponse($context, [ keys %procedures ]);
}


=head2 requestProcedure()

Handles 'slim.request' calls. Creates a request object and executes it.

=cut

sub requestProcedure {
	my $context = shift;

	# get the JSON-RPC params
	my $reqParams = $context->{'procedure'}->{'params'};

	$log->debug( sub { return "requestProcedure(" . Data::Dumper::Dumper($reqParams) . ")" } );
	
	# current style : [<player>, [cmd]]
	# proposed style: [{player:xxx, cmdarray:[xxx], params:{xxx}}, {}]
	# benefit: more than one command in single request
	# HOW DOES RECEIVER PARSE???
	
	my $commandargs = $reqParams->[1];

	if (!$commandargs || ref($commandargs) ne 'ARRAY') {

		$log->error("commandargs undef or not an array!");
		writeJSONError($context, 123, 'Bad commandargs');
		return;
	}

	my $playername = scalar ($reqParams->[0]);
	my $client     = Slim::Player::Client::getClient($playername);
	my $clientid = blessed($client) ? $client->id() : undef;
	
	if ($clientid) {

		$log->info("Parsing command: Found client [$clientid]");
	}

	# create a request
	my $request = Slim::Control::Request->new($clientid, $commandargs);

	if ($request->isStatusDispatchable) {
		
		# fix the encoding and/or manage charset param
		$request->fixEncoding();

		# remember we're the source and the $httpClient
		$request->source('JIV');
		$request->connectionID($context->{'httpClient'});
		
		if ($context->{'x-jive'}) {
			# set this in case the query can be subscribed to
			$request->autoExecuteCallback(\&requestWrite);
		}	
		
		$log->info("Dispatching...");

		$request->execute();
		
		if ($request->isStatusError()) {

			$log->error("Request failed with error: " . $request->getStatusText);
			writeJSONError($context, 123, 'Bad request');
			return;

 		} else {
 		
 			# handle async commands
 			if ($request->isStatusProcessing()) {
 				
 				$log->info("Request is async: will be back");
 						
 				# add our write routine as a callback
 				$request->callbackParameters(\&requestWrite);
 				return;
			}
			
			# the request was successful and is not async, send results back to caller!
			requestWrite($request, $context->{'httpClient'}, $context);
		}
		
	} else {

		$log->error("request not dispatchable!");
		writeJSONError($context, 123, 'Bad request');
	}	
}

=head2 requestWrite( $request $httpClient, $context)

Writes a request downstream. $httpClient and $context are retrieved if not
provided (from the request->connectionID and from the contexts array, respectively)

=cut
sub requestWrite {
	my $request = shift;
	my $httpClient = shift;
	my $context = shift;

	#$log->debug("requestWrite()");
	
	if (!$httpClient) {
		
		# recover our http client
		$httpClient = $request->connectionID();
	}
	
	if (!$context) {
	
		# recover our beloved context
		$context = $contexts{$httpClient};
		
		if (!$context) {
			$log->error("Context not found in requestWrite!!!!");
			return;
		}
	} else {

		if (!$httpClient) {
			$log->error("httpClient not found in requestWrite!!!!");
			return;
		}
	}

	# this should never happen, we've normally been forwarned by the closeHandler
	if (!$httpClient->connected()) {
		$log->info("Client no longer connected in requestWrite");
		closeHandler($httpClient);
		return;
	}

	generateJSONResponse($context, $request->{'_results'});
}

=head2 playermenuProcedure()

Handles 'slim.playermenu' calls. For now returns a standard menu.

=cut
# FIXME: REMOVE ME ONCE BRANCH IS MERGED
sub playermenuProcedure {
	my $context = shift;

	my $reqParams = $context->{'procedure'}->{'params'};

	$log->debug( sub { return "playermenuProcedure(" . Data::Dumper::Dumper($reqParams) . ")" } );

	my $playername = scalar ($reqParams->[0]);
	my $client     = Slim::Player::Client::getClient($playername);
	my $clientid = blessed($client) ? $client->id() : undef;
	
	if ($clientid) {

		$log->info("Parsing command: Found client [$clientid]");
	}

	my $menu = {};
		
	$menu->{'@items'} = [
		{
			'title' => 'Now Playing',
			'action' => 'browse',
			'hierarchy' => ['status', 'info'],
		},
		{
			'title' => Slim::Utils::Strings::string('BROWSE_BY_ALBUM'), #'Albums',
			'action' => 'browse',
			'hierarchy' => ['album', 'track', 'info'],
		},
		{
			'title' => Slim::Utils::Strings::string('BROWSE_BY_ARTIST'), #'Artists',
			'action' => 'browse',
			'hierarchy' => ['contributor', 'album', 'track', 'info'],
		},
		{
			'title' => Slim::Utils::Strings::string('BROWSE_BY_GENRE'), #'Genres',
			'action' => 'browse',
			'hierarchy' => ['genre', 'contributor', 'album', 'track', 'info'],
		},
		{
			'title' => Slim::Utils::Strings::string('BROWSE_BY_YEAR'), #'Years',
			'action' => 'browse',
			'hierarchy' => ['year', 'album', 'track', 'info'],
		},
		{
			'title' => Slim::Utils::Strings::string('BROWSE_NEW_MUSIC'), #'New Music',
			'action' => 'browse',
			'hierarchy' => ['age', 'track', 'info'],
		},
# 		{
# 			'title' => 'Favorites',
# 			'action' => '',
# 		},
		{
			'title' => 'Playlists',
			'action' => 'browse',
			'hierarchy' => ['playlist', 'playlisttrack', 'info'],			
		},
# 		{
# 			'title' => 'Search',
# 			'action' => 'items',
# 			'@items' => [
# 				{
# 					'title' => 'Artists',
# 					'action' => '',
# 				},
# 				{
# 					'title' => 'Albums',
# 					'action' => '',
# 				},
# 			],
# 		},
		{
			'title' => 'Internet Radio',
			'action' => 'browse',
			'hierarchy' => ['radios'],			
		},
# 		{
# 			'title' => 'Settings',
# 			'action' => ''
# 		},
		{
			'title' => 'Exit',
			'action' => 'exit',
		},
	];
		
	generateJSONResponse($context, $menu);
}


######
# CLI QUERIES

# handles the "menu" query
sub menuQuery {
	my $request = shift;
 
	$log->debug("Begin Function");
 
	if ($request->isNotQuery([['menu']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
#	my $client        = $request->client();
	my $index         = $request->getParam('_index');
	my $quantity      = $request->getParam('_quantity');

	my @menu = (
		{
			'text' => Slim::Utils::Strings::string('BROWSE_BY_ALBUM'),
			'actions' => {
				'go' => {
					'cmd' => ['albums'],
					'params' => {
						'menu' => 'track',
					},
				},
			},
			'window' => {
				'menuStyle' => 'album',
			},
		},
		{
			'text' => Slim::Utils::Strings::string('BROWSE_BY_ARTIST'),
			'actions' => {
				'go' => {
					'cmd' => ['artists'],
					'params' => {
						'menu' => 'album',
					},
				},
			},
		},
		{
			'text' => Slim::Utils::Strings::string('BROWSE_BY_GENRE'),
			'actions' => {
				'go' => {
					'cmd' => ['genres'],
					'params' => {
						'menu' => 'artist',
					},
				},
			},
		},
		{
			'text' => Slim::Utils::Strings::string('BROWSE_BY_YEAR'),
			'actions' => {
				'go' => {
					'cmd' => ['years'],
					'params' => {
						'menu' => 'album',
					},
				},
			},
		},
		{
			'text' => Slim::Utils::Strings::string('BROWSE_NEW_MUSIC'),
			'actions' => {
				'go' => {
					'cmd' => ['albums'],
					'params' => {
						'menu' => 'track',
						'sort' => 'new',
					},
				},
			},
			'window' => {
				'menuStyle' => 'album',
			},
		},
		{
			'text' => 'Favorites',
			'actions' => {
				'go' => {
					'cmd' => ['favorites', 'items'],
					'params' => {
						'menu' => 'favorites',
					},
				},
			},
		},
		{
			'text' => Slim::Utils::Strings::string('BROWSE_MUSIC_FOLDER'),
			'actions' => {
				'go' => {
					'cmd' => ['musicfolder'],
					'params' => {
						'menu' => 'musicfolder',
					},
				},
			},
		},
		{
			'text' => Slim::Utils::Strings::string('SAVED_PLAYLISTS'),
			'actions' => {
				'go' => {
					'cmd' => ['playlists'],
					'params' => {
						'menu' => 'track',
					},
				},
			},
		},
		{
			'text' => Slim::Utils::Strings::string('SEARCHMUSIC'),
			'count' => 4,
			'offset' => 0,
			'item_loop' => [
				{
					'text' => Slim::Utils::Strings::string('ARTISTS'),
					'input' => 3,
					'actions' => {
						'go' => {
							'cmd' => ['artists'],
							'params' => {
								'menu' => 'album',
								'search' => '__INPUT__',
							},
						},
					},
					'window' => {
						'text' => Slim::Utils::Strings::string('SEARCHFOR_ARTISTS'),
					},
				},
				{
					'text' => Slim::Utils::Strings::string('ALBUMS'),
					'input' => 3,
					'actions' => {
						'go' => {
							'cmd' => ['albums'],
							'params' => {
								'menu' => 'track',
								'search' => '__INPUT__',
							},
						},
					},
					'window' => {
						'text' => Slim::Utils::Strings::string('SEARCHFOR_ALBUMS'),
						'menuStyle' => 'album',
					},
				},
				{
					'text' => Slim::Utils::Strings::string('SONGS'),
					'input' => 3,
					'actions' => {
						'go' => {
							'cmd' => ['tracks'],
							'params' => {
								'menu' => 'track',
								'search' => '__INPUT__',
							},
						},
					},
					'window' => {
						'text' => Slim::Utils::Strings::string('SEARCHFOR_SONGS'),
					},
				},
				{
					'text' => Slim::Utils::Strings::string('PLAYLISTS'),
					'input' => 3,
					'actions' => {
						'go' => {
							'cmd' => ['playlists'],
							'params' => {
								'menu' => 'track',
								'search' => '__INPUT__',
							},
						},
					},
					'window' => {
						'text' => Slim::Utils::Strings::string('SEARCHFOR_PLAYLISTS'),
					},
				},
			],
		},
		{
			'text' => 'Internet Radio',
			'actions' => {
				'go' => {
					'cmd' => ['radios'],
					'params' => {
						'menu' => 'radio',
					},
				},
			},
		},
	);

	my $numitems = scalar(@menu);

	$request->addResult("count", $numitems);

	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $numitems);

	if ($valid) {
		
		my $cnt = 0;
		$request->addResult('offset', $start);

		for my $eachmenu (@menu[$start..$end]) {			
			$request->setResultLoopHash('item_loop', $cnt, $eachmenu);
			$cnt++;
		}
	}

	$request->setStatusDone();
}

1;
