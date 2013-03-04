package Slim::Web::HTTP;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use AnyEvent::Handle;
use CGI::Cookie;
use Digest::SHA1 qw(sha1_base64);
use FileHandle ();
use File::Basename qw(basename);
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);
use HTTP::Date qw(time2str);
use HTTP::Daemon ();
use HTTP::Headers::ETag;
use HTTP::Status qw(
    RC_FORBIDDEN
	RC_PRECONDITION_FAILED
	RC_UNAUTHORIZED
	RC_MOVED_PERMANENTLY
	RC_NOT_FOUND
	RC_METHOD_NOT_ALLOWED
	RC_OK
	RC_NOT_MODIFIED
);

use MIME::Base64;
use MIME::QuotedPrint;
use Scalar::Util qw(blessed);
use Socket qw(:crlf SOMAXCONN SOL_SOCKET SO_SNDBUF inet_ntoa);
use Storable qw(thaw);

use Slim::Networking::Select;
use Slim::Player::HTTP;
use Slim::Music::Info;
use Slim::Utils::Errno;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Unicode;
use Slim::Web::HTTP::ClientConn;
use Slim::Web::Pages;
use Slim::Web::Graphics;
use Slim::Web::JSONRPC;
use Slim::Web::Cometd;
use Slim::Utils::Prefs;

BEGIN {
	# Use Cookie::XS if available
	my $hasCookieXS;

	sub hasCookieXS {
		# Bug 9830, disable Cookie::XS for now as it has a bug
		return 0;
		
		return $hasCookieXS if defined $hasCookieXS;

		$hasCookieXS = 0;
		eval {
			require Cookie::XS;
			$hasCookieXS = 1;
		};

		return $hasCookieXS;
	}
}

use constant HALFYEAR	 => 60 * 60 * 24 * 180;

use constant METADATAINTERVAL => 32768;
use constant MAXCHUNKSIZE     => 32768;

# This used to be 0.05s but the CPU load associated with such fast retries is 
# really noticeable when playing remote streams. I guess that it is possible
# that certain combinations of pipe buffers in a transcoding pipeline
# might get caught by this but I have not been able to think of any - Alan.
use constant RETRY_TIME       => 0.40; # normal retry time

use constant MAXKEEPALIVES    => -1;   # unlimited keepalive requests
use constant KEEPALIVETIMEOUT => 75;

# Package variables

my $openedport = undef;
my $http_server_socket;
my $connected = 0;

our %outbuf = (); # a hash for each writeable socket containing a queue of output segments
                 #   each segment is a hash of a ref to data, an offset and a length

our %sendMetaData   = ();
our %metaDataBytes  = ();
our %streamingFiles = ();
our %peeraddr       = ();
our %peerclient     = ();
our %keepAlives     = ();

my  $skinMgr;

# we call these whenever we close a connection
our @closeHandlers = ();

my $log = logger('network.http');

my $prefs = preferences('server');

# initialize the http server
sub init {

	if ( main::WEBUI ) {
		require Slim::Web::HTTP::CSRF;
		require Slim::Web::Template::SkinManager;
		$skinMgr = Slim::Web::Template::SkinManager->new();

		# Initialize all the web page handlers.
		Slim::Web::Pages::init();
	}
	else {
		require Slim::Web::Template::NoWeb;
		$skinMgr = Slim::Web::Template::NoWeb->new();
	}
	
	# Initialize graphics resizing
	Slim::Web::Graphics::init();
	
	# Initialize JSON RPC
	Slim::Web::JSONRPC::init();
	
	# Initialize Cometd
	Slim::Web::Cometd::init();
}

sub init2 {
	# open HTTP port if specified
	# split into second init function so this can be performed after all server init is complete
	if ($prefs->get('httpport')) {
		Slim::Web::HTTP::openport($prefs->get('httpport'), $::httpaddr);
	} else {
		$openedport = 0; # init complete but no port opened
	}
}

sub getSkinManager {
	return $skinMgr;
}

sub openport {
	my ($listenerport, $listeneraddr) = @_;

	my %tested;
	my $testSocket;
	
	# start our listener
	foreach my $port ($listenerport, 9000..9010, 9100, 8000, 10000) {
		
		next if $tested{$port};
		
		$openedport    = $port;
		$tested{$port} = 1;

		if ( $testSocket = IO::Socket::INET->new(Proto     => "tcp",
				PeerAddr  => 'localhost',
				PeerPort  => $port) )
		{
			$testSocket->close;
		}
		
		else {

			$http_server_socket = HTTP::Daemon->new(
				LocalPort => $port,
				LocalAddr => $listeneraddr,
				Listen    => SOMAXCONN,
				ReuseAddr => 1,
				Reuse => 1,
				Timeout   => 0.001,
			) and last;
		}
		
		$log->error("Can't setup the listening port $port for the HTTP server: $!");
	}
	
	# if none of our ports could be opened, we'll have to give up
	if (!$http_server_socket) {
		
		$log->logdie("Running out of good ideas for the listening port for the HTTP server - giving up.");
	}
	
	defined(Slim::Utils::Network::blocking($http_server_socket,0)) || $log->logdie("Cannot set port nonblocking");

	Slim::Networking::Select::addRead($http_server_socket, \&acceptHTTP);

	main::INFOLOG && $log->info("Server $0 accepting http connections on port $openedport");
	
	if ($openedport != $listenerport) {

		$log->error("Previously configured port $listenerport was busy - we're now using port $openedport instead");

		# we might want to push this message in the user's face
		if (main::ISWINDOWS) {
			$log->error("Please make sure your firewall does allow access to port $openedport!");
		}

		$prefs->set('httpport', $openedport) ;
	}
	
	if ( $listeneraddr ) {
		$prefs->set( httpaddr => $listeneraddr );
	}
}

sub adjustHTTPPort {

	return unless defined $openedport; # only adjust once init is complete

	# do this on a timer so current page can be updated first and it executed outside select
	Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 0.5, \&_adjustHTTPPortCallback);
}

sub _adjustHTTPPortCallback {

	# if we've already opened a socket, let's close it
	if ($openedport) {
		main::INFOLOG && $log->info("Closing http server socket");

		Slim::Networking::Select::removeRead($http_server_socket);

		$http_server_socket->close();
		undef($http_server_socket);
		$openedport = 0;
	}

	# open new port if specified
	if ($prefs->get('httpport')) {
		Slim::Web::HTTP::openport($prefs->get('httpport'), $::httpaddr);
	}
}

sub connectedSocket {
	return $connected;
}

sub acceptHTTP {
	# try and pull the handle
	my $httpClient = $http_server_socket->accept('Slim::Web::HTTP::ClientConn') || do {

		main::INFOLOG && $log->info("Did not accept connection, accept returned nothing");
		return;
	};

	defined(Slim::Utils::Network::blocking($httpClient,0)) || $log->logdie("Cannot set port nonblocking");
	
	binmode($httpClient);
	
	my $peer = $httpClient->peeraddr();

	if ($httpClient->connected() && $peer) {

		$peer = inet_ntoa($peer);

		# Check if source address is valid
		if (!($prefs->get('filterHosts')) ||
		     (Slim::Utils::Network::isAllowedHost($peer))) {
			
			# Timeout for reads from the client.  HTTP::Daemon in get_request
			# will call select(,,,10) but should not block long
			# as we already know the socket is ready for reading
			$httpClient->timeout(10);

			$peeraddr{$httpClient} = $peer;

			Slim::Networking::Select::addRead($httpClient, \&processHTTP);
			Slim::Networking::Select::addError($httpClient, \&closeStreamingSocket);

			$connected++;

			if ( main::INFOLOG && $log->is_info ) {
				$log->info("Accepted connection $connected from $peeraddr{$httpClient}:" . $httpClient->peerport);
			}

		} else {

			$log->warn("Did not accept HTTP connection from $peer, unauthorized source");

			$httpClient->close();
			undef($httpClient);
		}

	} else {

		$log->warn("Did not accept connection, couldn't get peer addr");
	}
}

sub skins {
	$skinMgr->skins(@_);
}

# Handle an HTTP request
sub processHTTP {
	my $httpClient = shift || return;
	
	my $isDebug = ( main::DEBUGLOG && $log->is_debug ) ? 1 : 0;

### OLD ORDER ###
	# Set the request date (write $request)
	# CSRF auth code management (write $request)
	# Read cookies (write $params)
	# Icy-MetaData (write sendMetaData)
	# Create response (from $request but it's a ref so?)
	# Log headers
	# if get/head/post
	## Icy-MetaData (write sendMetaData)
	## Authorization header (returns if nok)
	## Parse URI (write $params)
	## Skins (write params & path, redirected if nok)
	## More CSRF mgmt (looks at the modified path)
	# else
	## Send bad request
### NEW ORDER ###
	# Create response (from $request but it's a ref so?)
	# Log raw headers
	# if get/head/post
	## Authorization header (returns if nok)
	## Persistent connection (write $response $keepAlive)
	## Set the request date (write $request)
	## CSRF auth code management (write $request)
	## Read cookies (write $params)
	## Icy-MetaData (write sendMetaData)
	## Parse URI (write $params)
	## Skins (write params & path, redirected if nok)
	## More CSRF mgmt (looks at the modified path)	
	## Log processed headers
	# else
	## Send bad request
	
	# Store the time we started processing this request
	$httpClient->start_time( Time::HiRes::time() );

	# Remove keep-alive timeout
	Slim::Utils::Timers::killTimers( $httpClient, \&closeHTTPSocket );

	main::DEBUGLOG && $isDebug && $log->info("Reading request...");

	my $request    = $httpClient->get_request(); # XXX this will hang on the rare case a client does not send a full HTTP request
	# socket half-closed from client
	if (!defined $request) {

		my $reason = $httpClient->reason || 'unknown error reading request';
		
		if ( main::INFOLOG && $isDebug ) {
			$log->info("Client at $peeraddr{$httpClient}:" . $httpClient->peerport . " disconnected. ($reason)");
		}

		closeHTTPSocket($httpClient, 0, $reason);
		return;
	}
	

	if ( main::DEBUGLOG && $isDebug ) {
		$log->info(
			"HTTP request: from $peeraddr{$httpClient}:" . $httpClient->peerport . " ($httpClient) for " .
			join(' ', ($request->method(), $request->protocol(), $request->uri()))
		);
	}

	if ( main::DEBUGLOG && $isDebug ) {
		$log->debug("Raw request headers: [\n" . $request->as_string() . "]");
	}

	# this will hold our context and is used to fill templates
	my $params = {};
	$params->{'userAgent'} = $request->header('user-agent');
	$params->{'browserType'} = $skinMgr->detectBrowser($request);

	# this bundles up all our response headers and content
	my $response = HTTP::Response->new();

	$response->protocol('HTTP/1.1');
	$response->request($request);

	# handle stuff we know about or abort
	if ($request->method() eq 'GET' || $request->method() eq 'HEAD' || $request->method() eq 'POST') {

		# Manage authorization
		my $authorized = !$prefs->get('authorize');

		if (my ($user, $pass) = $request->authorization_basic()) {
			$authorized = checkAuthorization($user, $pass, $request);
		}

		# no Valid authorization supplied!
		if (!$authorized) {

			$response->code(RC_UNAUTHORIZED);
			$response->header('Connection' => 'close');
			$response->content_type('text/html');
			$response->content_ref(filltemplatefile('html/errors/401.html', $params));
			$response->www_authenticate(sprintf('Basic realm="%s"', string('SQUEEZEBOX_SERVER')));

			$httpClient->send_response($response);
			closeHTTPSocket($httpClient);
			return;
		}


		# HTTP/1.1 Persistent connections or HTTP 1.0 Keep-Alives
		# XXX - MAXKEEPALIVES should be a preference
		# This always add a Connection: close header if we want the connection to be closed.
		if (MAXKEEPALIVES > 0 && defined $keepAlives{$httpClient} && $keepAlives{$httpClient} >= MAXKEEPALIVES) {

			# This will close the client socket & remove the
			# counter in sendResponse()
			$response->header('Connection' => 'close');

			main::DEBUGLOG && $isDebug && $log->info("Hit MAXKEEPALIVES, will close connection.");

		} else {

			# If the client requests a close or a keep-alive, 
			# set the initial response to the same.
			$response->header('Connection' => $request->header('Connection'));

			if ($httpClient->proto_ge('1.1')) {

				# 1.1 defaults to persistent
				if (!$request->header('Connection') || $request->header('Connection') ne 'close') {
					$keepAlives{$httpClient}++;
				}

			} else {

				# otherwise, it's 1.0, and only if it's not
				# 'close', be persistent
				if ($request->header('Connection') && $request->header('Connection') ne 'close') {
					$keepAlives{$httpClient}++;
				}

				# Put in an explicit close even if there wasn't
				# one passed in. This ensures that the response
				# logic will close the socket.
				else {
					$response->header('Connection' => 'close');

				}
			}
			
			if ( $keepAlives{$httpClient} ) {
				# set the keep-alive timeout
				Slim::Utils::Timers::setTimer(
					$httpClient,
					time() + KEEPALIVETIMEOUT,
					\&closeHTTPSocket,
					0,
					'keep-alive timeout',
				);
			}
		}

		# extract the URI and raw path
		# the path is modified below for skins and stuff
		my $uri   = $request->uri();
		my $path  = $uri->path();
		
		main::DEBUGLOG && $isDebug && $log->debug("Raw path is [$path]");

		# break here for raw HTTP code
		# we hand the $response object only, it contains the almost unmodified request
		# we took care above of basic HTTP stuff and authorization
		# $rawFunc shall call addHTTPResponse
		if (my $rawFunc = Slim::Web::Pages->getRawFunction($path)) {

			main::DEBUGLOG && $isDebug && $log->info("Handling [$path] using raw function");

			if (ref($rawFunc) eq 'CODE') {
				
				# XXX: should this use eval?
				&{$rawFunc}($httpClient, $response);
				return;
			}
		}

		# Set the request time - for If-Modified-Since
		$request->client_date(time());
		
		my $csrfProtectionLevel = main::WEBUI && $prefs->get('csrfProtectionLevel');
	
		if ( main::WEBUI && $csrfProtectionLevel ) {
			# remove our special X-Slim-CSRF header if present
			$request->remove_header("X-Slim-CSRF");
			
			# store CSRF auth code in fake request header if present
			if ( defined($uri) && ($uri =~ m|^(.*)\;cauth\=([0-9a-f]{32})$| ) ) {

				my $plainURI = $1;
				my $csrfAuth = $2;

				if ( main::DEBUGLOG && $isDebug ) {
					$log->info("Found CSRF auth token \"$csrfAuth\" in URI \"" . $uri . "\", so resetting request URI to \"$plainURI\"");
				}

				# change the URI so later code doesn't "see" the cauth part
				$request->uri($plainURI);

				# store the cauth code in the request object (headers are handy!)
				$request->push_header("X-Slim-CSRF",$csrfAuth);
			}
		}
		
		# Dont' process cookies for graphics
		if ($path && $path !~ m/(gif|png)$/i) {
			if ( my $cookie = $request->header('Cookie') ) {
				if ( hasCookieXS() ) {
					# Parsing cookies this way is about 8x faster than using CGI::Cookie directly
					my $cookies = Cookie::XS->parse($cookie);
					$params->{'cookies'} = {
						map {
							$_ => bless {
								name  => $_,
								path  => '/',
								value => $cookies->{ $_ },
							}, 'CGI::Cookie';
						} keys %{ $cookies }
					};
				}
				else {
					$params->{'cookies'} = { CGI::Cookie->parse($cookie) };
				}
			}
		}
		
		# Icy-MetaData
		$sendMetaData{$httpClient} = 0;
		
		if ($request->header('Icy-MetaData')) {
			$sendMetaData{$httpClient} = 1;
		}

		# parse out URI		
		my $query = ($request->method() eq "POST") ? $request->content() : $uri->query();

		$params->{url_query} = $query;

		$params->{content} = $request->content();

		my ($queryWithArgs, $queryToTest, $providedPageAntiCSRFToken);
		# CSRF: make list of params passed by HTTP client
		my %csrfReqParams;
		
		# XXX - unfortunately Logitech Media Server uses a query form
		# that can have a key without a value, yet it's
		# differnet from a key with an empty value. So we have
		# to parse out like this.
		if ($query) {

			foreach my $param (split /\&/, $query) {

				if ($param =~ /([^=]+)=(.*)/) {

					my $name  = Slim::Utils::Misc::unescape($1, 1);
					my $value = Slim::Utils::Misc::unescape($2, 1);

					# We need to turn perl's internal
					# representation of the unescaped
					# UTF-8 string into a "real" UTF-8
					# string with the appropriate magic set.
					if ($value ne '*') {
						$value = Slim::Utils::Unicode::utf8decode($value);
					}

					# Ick. It sure would be nice to use
					# CGI or CGI::Lite
					if (ref($params->{$name}) eq 'ARRAY') {

						push @{$params->{$name}}, $value;

					} elsif (exists $params->{$name}) {

						my $old = delete $params->{$name};

						@{$params->{$name}} = ($old, $value);

					} else {

						$params->{$name} = $value;
					}

					main::DEBUGLOG && $isDebug && $log->info("HTTP parameter $name = $value");

					if ( main::WEBUI && $csrfProtectionLevel ) {
						my $csrfName = $name;
						if ( $csrfName eq 'command' ) { $csrfName = 'p0'; }
						if ( $csrfName eq 'subcommand' ) { $csrfName = 'p1'; }
						push @{$csrfReqParams{$csrfName}}, $value;
					}

				} else {

					my $name = Slim::Utils::Misc::unescape($param, 1);

					$params->{$name} = 1;

					main::DEBUGLOG && $isDebug && $log->info("HTTP parameter $name = 1");

					if ( main::WEBUI && $csrfProtectionLevel ) {
						my $csrfName = $name;
						if ( $csrfName eq 'command' ) { $csrfName = 'p0'; }
						if ( $csrfName eq 'subcommand' ) { $csrfName = 'p1'; }
						push @{$csrfReqParams{$csrfName}}, 1;
					}
				}
			}
		}

		if ( main::WEBUI && $csrfProtectionLevel ) {
			# for CSRF protection, get the query args in one neat string that 
			# looks like a GET querystring value; this should handle GET and POST
			# equally well, only looking at the data that we would act on
			($queryWithArgs, $queryToTest) = Slim::Web::HTTP::CSRF->getQueries($request, \%csrfReqParams);
	
			# Stash CSRF token in $params for use in TT templates
			$providedPageAntiCSRFToken = $params->{pageAntiCSRFToken};
			# pageAntiCSRFToken is a bare token
			$params->{pageAntiCSRFToken} = Slim::Web::HTTP::CSRF->makePageToken($request);
		}

		# Skins 
		if ($path) {

			$params->{'webroot'} = '/';

			if ($path =~ s{^/slimserver/}{/}i) {
				$params->{'webroot'} = "/slimserver/"
			}

			$path =~ s|^/+||;

			if ( !main::WEBUI || $path =~ m{^(?:html|music|video|image|plugins|apps|settings|firmware|clixmlbrowser|imageproxy)/}i || Slim::Web::Pages->isRawDownload($path) ) {
				# not a skin

			} elsif ($path =~ m|^([a-zA-Z0-9]+)$| && $skinMgr->isaSkin($1)) {

				main::DEBUGLOG && $isDebug && $log->info("Alternate skin $1 requested, redirecting to $uri/ append a slash.");

				$response->code(RC_MOVED_PERMANENTLY);
				$response->header('Location' => $uri . '/');

				$httpClient->send_response($response);

				closeHTTPSocket($httpClient);

				return;

			} elsif ($path =~ m|^(.+?)/.*|) {

				my $desiredskin = $1;

				# Requesting a specific skin, verify and set the skinOverride param
				main::DEBUGLOG && $isDebug && $log->info("Alternate skin $desiredskin requested");

				my $skinname = $skinMgr->isaSkin($desiredskin);
				
				if ($skinname) {

					main::DEBUGLOG && $isDebug && $log->info("Rendering using $skinname");

					$params->{'skinOverride'} = $skinname;
					$params->{'webroot'} = $params->{'webroot'} . "$skinname/";

					$path =~ s{^.+?/}{/};
					$path =~ s|^/+||;

				} else {

					# we can either throw a 404 here or just ignore the requested skin
					
					# ignore: commented out
					# $path =~ s{^/.+?/}{/};
					
					# throw 404
					$params->{'suggestion'} = qq(There is no "$desiredskin")
						. qq( skin, try ) . Slim::Utils::Prefs::homeURL() . qq( instead.);

					if ( $log->is_warn ) {
						$log->warn("Invalid skin requested: [" . join(' ', ($request->method, $request->uri)) . "]");
					}
			
					$response->code(RC_NOT_FOUND);
					$response->content_type('text/html');
					$response->header('Connection' => 'close');
					$response->content_ref(filltemplatefile('html/errors/404.html', $params));
			
					$httpClient->send_response($response);
					closeHTTPSocket($httpClient);
					return;
				}
			}

			$params->{"path"} = Slim::Utils::Misc::unescape($path);
			$params->{"host"} = $request->header('Host');
		} 
		
		# BUG: 4911 detect Internet Explorer and redirect if using the Nokia770 skin, as IE will not support the styles
		# Touch is similar in most ways and works nicely with IE
		# BUG: 5093 make sure that Nokia Opera isn't spoofing as IE, causing incorrect redirect

		if ($params->{'browserType'} =~ /^IE\d?$/ &&
		($params->{'skinOverride'} || $prefs->get('skin')) eq 'Nokia770') 
		{
			main::DEBUGLOG && $isDebug && $log->debug("Internet Explorer Detected with Nokia Skin, redirecting to Touch");
			$params->{'skinOverride'} = 'Touch';
		}

		if ( main::WEBUI && $csrfProtectionLevel ) {
			# apply CSRF protection logic to "dangerous" commands
			if (!Slim::Web::HTTP::CSRF->testCSRFToken($httpClient, $request, $response, $params, $queryWithArgs, $queryToTest, $providedPageAntiCSRFToken)) {
				return;
			}
		}
		
		if ( main::DEBUGLOG && $isDebug ) {
			$log->debug("Processed request headers: [\n" . $request->as_string() . "]");
		}

		# process the command
		processURL($httpClient, $response, $params);

	} else {

		if ( $log->is_warn ) {
			$log->warn("Bad Request: [" . join(' ', ($request->method, $request->uri)) . "]");
		}

		$response->code(RC_METHOD_NOT_ALLOWED);
		$response->header('Connection' => 'close');
		$response->content_type('text/html');
		$response->content_ref(filltemplatefile('html/errors/405.html', $params));

		$httpClient->send_response($response);
		closeHTTPSocket($httpClient);
	}

	# what does our response look like?
	if (main::DEBUGLOG && $isDebug) {

		$response->content("");
		$log->debug("Response Headers: [\n" . $response->as_string . "]");
	}
	
	if ( main::DEBUGLOG && $isDebug ) {
		$log->info(
			"End request: keepAlive: [" .
			($keepAlives{$httpClient} || '') .
			"] - waiting for next request for $httpClient on connection = " . ($response->header('Connection') || '') . "\n"
		);
	}
}

# processURL - handles the execution of the HTTP request
sub processURL {
	my ($httpClient, $response, $params) = @_;

	my $output = "";
	my @p = ();
	my $client = undef;
	my $path   = $params->{"path"};

	# Command parameters are query parameters named p0 through pN
	# 	For example:
	#		http://host/status.m3u?p0=playlist&p1=jump&p2=2 
	#		http://host/status.m3u?command=playlist&subcommand=jump&p2=2 
	# This example jumps to the second song in the playlist and sends a playlist as the response
	#
	# If there are multiple players, then they are specified by the player id
	#   For example:
	#		http://host/status.html?p0=mixer&p1=volume&p2=11&player=10.0.1.203:69

	for (my $i = 0; $i <= scalar keys %{$params}; $i++) {
		last unless defined $params->{"p$i"};
		$p[$i] = Slim::Utils::Unicode::utf8encode_locale($params->{"p$i"});
	}

	# This is trumped by query parameters 'command' and 'subcommand'.
	# These are passed as the first two command parameters (p0 and p1), 
	# while the rest of the query parameters are passed as third (p3).
	if (defined $params->{'command'} && $path !~ /^memoryusage/) {
		$p[0] = $params->{'command'};
		$p[1] = $params->{'subcommand'};
		$p[2] = join '&', map $_ . '=' . $params->{$_},  keys %{$params};
	}

	if ( main::INFOLOG && $log->is_info ) {
		$log->info("processURL Clients: " . join(" ", Slim::Player::Client::clientIPs()));
	}

	# explicitly specified player (for web browsers or squeezeboxen)
	if (defined($params->{"player"})) {
		$client = Slim::Player::Client::getClient($params->{"player"});
		
		if ( blessed($client) ) {
			# Update the client's last activity time, since they did something through the web
			$client->lastActivityTime( Time::HiRes::time() );
		}
	}

	# is this an HTTP stream?
	if (!defined($client) && ($path =~ /(?:stream\.mp3|stream)$/)) {
		
		# Bug 14825, allow multiple stream.mp3 clients from the same address with a player param
		my $address = $params->{player} || $peeraddr{$httpClient};
	
		main::INFOLOG && $log->is_info && $log->info("processURL found HTTP client at address=$address");
	
		$client = Slim::Player::Client::getClient($address);
		
		if (!defined($client)) {

			my $paddr = getpeername($httpClient);

			main::INFOLOG && $log->is_info && $log->info("New http client at $address");

			if ($paddr) {
				$client = Slim::Player::HTTP->new($address, $paddr, $httpClient);
				$client->init();
				
				# Give the streaming player a descriptive name such as "Winamp from x.x.x.x"
				if ( $params->{userAgent} ) {
					my ($agent) = $params->{userAgent} =~ m{([^/]+)};
					if ( $agent eq 'NSPlayer' ) {
						$agent = 'Windows Media Player';
					}
					elsif ( $agent eq 'WinampMPEG' ) {
						$agent = 'Winamp';
					}
					
					$client->name( $agent . ' ' . string('FROM') . ' ' . $address );
				}
				
				# Bug 4795
				# If the player has an existing playlist, start playing it without
				# requiring the user to press Play in the web UI
				if ( Slim::Player::Playlist::song($client) &&
					!Slim::Music::Info::isRemoteURL( Slim::Player::Playlist::url($client) )
				) {
					# play if current playlist item is not a remote url
					$client->execute( [ 'play' ] );
				}
			}
		}

		if (defined($params->{'bitrate'})) {
			# must validate 32 40 48 56 64 80 96 112 128 160 192 224 256 320 CBR
			# set to the closest lower value of its not a match
			my $temprate = $params->{'bitrate'};

			foreach my $i (qw(320 256 224 192 160 128 112 96 80 64 56 48 40 32)) {
				$temprate = $i; 	 
				last if ($i <= $params->{'bitrate'}); 	 
			}

			$prefs->client($client)->set('transcodeBitrate',$temprate); 	 

			main::INFOLOG && $log->is_info && $log->info("Setting transcode bitrate to $temprate");

		} else {

			$prefs->client($client)->set('transcodeBitrate',undef);
		}
	}
	
	# player specified from cookie
	if ( !defined $client && $params->{'cookies'} ) {
		if ( my $player = $params->{'cookies'}->{'Squeezebox-player'} ) {
			$client = Slim::Player::Client::getClient( $player->value );
		}
	}

	# if we don't have a player specified, just pick one if there is one...
	$client = Slim::Player::Client::clientRandom() if !defined $client;

	if (blessed($client) && $client->can('id')) {

		$peerclient{$httpClient} = $client->id;
	}

	if ($client && $client->isa("Slim::Player::SLIMP3")) {

		$params->{'playermodel'} = 'slimp3';
	} elsif ($client && $client->isa("Slim::Player::Transporter")) {

		$params->{'playermodel'} = 'transporter';
	} else {

		$params->{'playermodel'} = 'squeezebox';
	}

	my @callbackargs = ($client, $httpClient, $response, $params);

	# only execute a command if we have a command.
	if (defined($p[0])) {

		if (defined($params->{"player"}) && $params->{"player"} eq "*") {

			for my $client2 (Slim::Player::Client::clients()) {

				next if $client eq $client2;

				$client2->execute(\@p);
			}
		}

		Slim::Control::Request::executeRequest($client, \@p, \&generateHTTPResponse, \@callbackargs);

	} else {

		generateHTTPResponse(@callbackargs);
	}
}

=pod

=head1 Send the response to the client

=cut

sub generateHTTPResponse {
	my ($client, $httpClient, $response, $params, $p) = @_;

	# this is a scalar ref because of the potential size of the body.
	# not sure if it actually speeds things up considerably.
	my ($body, $mtime, $inode, $size); 

	# default to 200
	$response->code(RC_OK);

	$params->{'player'}   = '';
	$params->{'revision'} = $::REVISION if $::REVISION;
	$params->{'nosetup'}  = 1   if $::nosetup;
	$params->{'noserver'} = 1   if $::noserver;

	# Check for the gallery view cookie.
	if ($params->{'cookies'}->{'Squeezebox-albumView'} && 
		$params->{'cookies'}->{'Squeezebox-albumView'}->value) {

		$params->{'artwork'} = $params->{'cookies'}->{'Squeezebox-albumView'}->value unless defined $params->{'artwork'};
	}

	# Check for the album order cookie.
	if ($params->{'cookies'}->{'Squeezebox-orderBy'} && 
		$params->{'cookies'}->{'Squeezebox-orderBy'}->value) {

		$params->{'orderBy'} = $params->{'cookies'}->{'Squeezebox-orderBy'}->value unless defined $params->{'orderBy'};
	}

	# Check for thumbSize cookie (for Touch, 1-by-1 artwork enlarge/shrink feature)
	if ($params->{'cookies'}->{'Squeezebox-thumbSize'} &&
		$params->{'cookies'}->{'Squeezebox-thumbSize'}->value) {

			$params->{'thumbSize'} = $params->{'cookies'}->{'Squeezebox-thumbSize'}->value unless defined $params->{'thumbSize'};
	}

	if (Slim::Web::Graphics::serverResizesArt()) {
		$params->{'serverResizesArt'} = 1;
	}

	my $path = $params->{"path"};
	my $type = Slim::Music::Info::typeFromSuffix($path, 'htm');

	# lots of people need this
	my $contentType = $params->{'Content-Type'} = $Slim::Music::Info::types{$type};

	if ( Slim::Web::Pages->isRawDownload($path) ) {
		$contentType = 'application/octet-stream';
	}
	
	if ( $path =~ /(?:music|video|image)\/[0-9a-f]+\/download/ ) {
		# Avoid generating templates for download URLs
		$contentType = 'application/octet-stream';
	}

	# setup our defaults
	$response->content_type($contentType);
	#$response->expires(0);

	# short-circuit if we don't have a content type to respond to.
	unless (defined($contentType)) {

		return 0 if $path =~ /status/i;

		$response->code(RC_NOT_FOUND);

		$body = filltemplatefile('html/errors/404.html', $params);

		return prepareResponseForSending(
			$client,
			$params,
			$body,
			$httpClient,
			$response,
		);
	}

	main::INFOLOG && $log->is_info && $log->info("Generating response for ($type, $contentType) $path");

	# some generally useful form details...
	my $classOrCode = Slim::Web::Pages->getPageFunction($path);
	
	if (defined($client) && $classOrCode) {
		$params->{'player'} = $client->id();
		$params->{'myClientState'} = $client;
		
		# save the player id in a cookie
		my $cookie = CGI::Cookie->new(
			-name    => 'Squeezebox-player',
			-value   => $params->{'player'},
			-expires => '+1y',
		);
		$response->headers->push_header( 'Set-Cookie' => $cookie );
	}

	# this might do well to break up into methods
	if ($contentType =~ /(?:image|javascript|css)/ || $path =~ /html\//) {
 
		my $max = 60 * 60;
		
		# increase expiry to a week for static content, but not cover art
		unless ($contentType =~ /image/ && $path !~ /html\//) {
			$max = $max * 24 * 7;
		}
		
 		# static content should expire from cache in one hour
		$response->expires( time() + $max );
		$response->header('Cache-Control' => 'max-age=' . $max);
	}

	if ($contentType =~ /text/ && $path !~ /(?:json|memoryusage)/) {

		$params->{'params'} = {};

		filltemplatefile('include.html', $params);

		while (my ($key,$value) = each %{$params->{'params'}}) {

			$params->{$key} = $value;
		}

		delete $params->{'params'};
	}
	
	# Static files handled here, stream them out to the browser to avoid wasting memory
	my $isStatic = 0;
	if ( $path =~ /favicon\.ico/ ) {
		$path = 'html/mypage.ico';
		$isStatic = 1;
	}
	elsif ( $path =~ /\.css|\.js(?!on)|robots\.txt/ ) {
		$isStatic = 1;
	}
	elsif (    $path =~ m{html/} 
			&& $path !~ /\/\w+_(X|\d+)x(X|\d+)
                    (?:_([sSfFpc]))?        # resizeMode, given by a single character
                    (?:_[\da-fA-F]+)? 		# background color, optional
		/x   # extend this to also include any image that gives resizing parameters
	) {
		if ( $contentType ne 'text/html' && $contentType ne 'text/xml' && $contentType ne 'application/x-java-jnlp-file' ) {
			$isStatic = 1;
		}
	}
	
	if ( $isStatic ) {
		($mtime, $inode, $size) = getFileInfoForStaticContent($path, $params);

		if (contentHasBeenModified($response, $mtime, $inode, $size)) {

			$params->{contentAsFh} = 1;

			# $body contains a filehandle for static content
			$body = getStaticContent($path, $params);
		}
	}
	else {
		if ($classOrCode) {

			# if we match one of the page functions as defined above,
			# execute that, and hand it a callback to send the data.
			
			$params->{'imageproxy'} = Slim::Networking::SqueezeNetwork->url(
				"/public/imageproxy"
			);

			main::PERFMON && (my $startTime = AnyEvent->time);

			if (ref($classOrCode) eq 'CODE') {

				# XXX: should this use eval?

				$body = &{$classOrCode}(
					$client,
					$params,
					\&prepareResponseForSending,
					$httpClient,
					$response,
				);

			} elsif ($classOrCode->can('handler')) {

				# Pull the player ID out and create a client from it
				# if we need to use it for player settings. 
				if (exists $params->{'playerid'} && $classOrCode->needsClient) {

					$client = Slim::Player::Client::getClient($params->{'playerid'});
				}

				$body = $classOrCode->handler(
					$client,
					$params,
					\&prepareResponseForSending,
					$httpClient,
					$response,
				);
			}
		
			main::PERFMON && $startTime && Slim::Utils::PerfMon->check('web', AnyEvent->time - $startTime, "Page: $path");

		} elsif ($path =~ /^(?:stream\.mp3|stream)$/o) {
			# Bug 15380, return correct content-type depending on what we're streaming
			if ( my $sc = $client->controller()->songStreamController() ) {
				if ( my $song = $sc->song() ) {
					my $type = $song->streamformat();
					$response->content_type( $Slim::Music::Info::types{$type} );
				}
			}

			# short circuit here if it's a slim/squeezebox
			if ($sendMetaData{$httpClient}) {
				$response->header("icy-metaint" => METADATAINTERVAL);
				$response->header("icy-name"    => string('WELCOME_TO_SQUEEZEBOX_SERVER'));
			}
			
			main::INFOLOG && $log->is_info && $log->info("Disabling keep-alive for stream.mp3");
			delete $keepAlives{$httpClient};
			Slim::Utils::Timers::killTimers( $httpClient, \&closeHTTPSocket );
			$response->header( Connection => 'close' );

			my $headers = _stringifyHeaders($response) . $CRLF;

			$metaDataBytes{$httpClient} = - length($headers);
		
			addStreamingResponse($httpClient, $headers);

			return 0;

		} elsif ($path =~ m{(?:image|music|video)/([^/]+)/(cover|thumb)} || 
			$path =~ m{^(?:plugins/cache/icons|imageproxy)} || 
			$path =~ /\/\w+_(X|\d+)x(X|\d+)
	                        (?:_([mpsSfFco]))?        # resizeMode, given by a single character
	                        (?:_[\da-fA-F]+)? 		# background color, optional
				/x   # extend this to also include any image that gives resizing parameters
			) {

			main::PERFMON && (my $startTime = AnyEvent->time);
			
			# Bug 15723, We need to track if we have an async artwork request so 
			# we don't return data out of order
			my $async = 0;
			my $sentResponse = 0;

			($body, $mtime, $inode, $size, $contentType) = Slim::Web::Graphics::artworkRequest(
				$client, 
				$path, 
				$params,
				sub {
					$sentResponse = 1;
					prepareResponseForSending(@_);
					
					if ( $async ) {
						main::INFOLOG && $log->is_info && $log->info('Async artwork request done, enable read');
						Slim::Networking::Select::addRead($httpClient, \&processHTTP);
					}
				},
				$httpClient,
				$response,
			);
			
			# If artworkRequest did not directly call the callback, we are in an async request
			if ( !$sentResponse ) {
				main::INFOLOG && $log->is_info && $log->info('Async artwork request pending, pause read');
				Slim::Networking::Select::removeRead($httpClient);
				$async = 1;
			}
			
			main::PERFMON && $startTime && Slim::Utils::PerfMon->check('web', AnyEvent->time - $startTime, "Page: $path");
			
			return;

		# return quickly with a 404 if web UI is disabled
		} elsif ( !main::WEBUI && (
			   $path =~ /status\.m3u/
			|| $path =~ /status\.txt/
			|| $path =~ /(server|scanner|perfmon|log)\.(?:log|txt)/
		) ) {
			$response->content_type('text/html');
			$response->code(RC_NOT_FOUND);
		
			$body = filltemplatefile('html/errors/404.html', $params);
		
			return prepareResponseForSending(
				$client,
				$params,
				$body,
				$httpClient,
				$response,
			);

		} elsif ($path =~ /(?:music|video|image)\/([0-9a-f]+)\/download/) {
			# Bug 10730
			my $id = $1;
			
			if ( $path =~ /music|video/ ) {
				main::INFOLOG && $log->is_info && $log->info("Disabling keep-alive for large file download");
				delete $keepAlives{$httpClient};
				Slim::Utils::Timers::killTimers( $httpClient, \&closeHTTPSocket );
				$response->header( Connection => 'close' );
			}
			
			# Reject bad getContentFeatures requests (DLNA 7.4.26.5)
			if ( my $gcf = $response->request->header('getContentFeatures.dlna.org') ) {
				if ( $gcf ne '1' ) {
					$response->code(400);
					$response->headers->remove_content_headers;
					$httpClient->send_response($response);
					closeHTTPSocket($httpClient);
					return 0;
				}
			}

			if ( $path =~ /music/ ) {
				if ( downloadMusicFile($httpClient, $response, $id) ) {
					return 0;
				}
			}
			elsif ( $path =~ /video/ ) {
				if ( downloadVideoFile($httpClient, $response, $id) ) {
					return 0;
				}
			}
			elsif ( $path =~ /image/ ) {
				if ( downloadImageFile($httpClient, $response, $id) ) {
					return 0;
				}
			}

		} elsif ($path =~ /(server|scanner|perfmon|log)\.(?:log|txt)/) {

			if ( main::WEBUI ) {
				($contentType, $body) = Slim::Web::Pages::Common->logFile($params, $response, $1);
			}
		
		} elsif ($path =~ /status\.txt/) {

			if ( main::WEBUI ) {
				($contentType, $body) = Slim::Web::Pages::Common->statusTxt($client, $httpClient, $response, $params, $p);
			}
		
		} elsif ($path =~ /status\.m3u/) {

			if ( main::WEBUI ) {
				$$body = Slim::Web::Pages::Common->statusM3u($client);
			}

		} elsif ($path =~ /html\//) {

			# content is in the "html" subdirectory within the template directory.
			# if it's HTML then use the template mechanism
			if ($contentType eq 'text/html' || $contentType eq 'text/xml' || $contentType eq 'application/x-java-jnlp-file') {

				# if the path ends with a slash, then server up the index.html file
				$path .= 'index.html' if $path =~ m|/$|;
				$body  = filltemplatefile($path, $params);

			}

		} elsif ( Slim::Web::Pages->isRawDownload($path) ) {
			
			# path is for download of known file outside http directory
			my ($file, $ct);

			my $rawFiles = Slim::Web::Pages->getRawFiles();

			for my $key (keys %$rawFiles) {

				if ( $path =~ $key ) {

					my $fileinfo = $rawFiles->{$key};
					$file = ref $fileinfo->{file} eq 'CODE' ? $fileinfo->{file}->($path) : $fileinfo->{file};
					$ct   = ref $fileinfo->{ct}   eq 'CODE' ? $fileinfo->{ct}->($path)   : $fileinfo->{ct};

					if (!-e $file) { 
						$file = undef;
					}

					last;
				}
			}

			if ($file) {
				# disable keep-alive for raw files, this is needed to prevent
				# Jive downloads from timing out
				if ( $keepAlives{$httpClient} ) {
					main::INFOLOG && $log->is_info && $log->info("Disabling keep-alive for raw file $file");
					delete $keepAlives{$httpClient};
					Slim::Utils::Timers::killTimers( $httpClient, \&closeHTTPSocket );					
					$response->header( Connection => 'close' );
				}
				
				# download the file
				main::INFOLOG && $log->is_info && $log->info("serving file: $file for path: $path");
				sendStreamingFile( $httpClient, $response, $ct, $file );
				return 0;

			} else {
				# 404 error
				$log->is_warn && $log->warn("unable to find file for path: $path");

				$response->content_type('text/html');
				$response->code(RC_NOT_FOUND);

				$body = filltemplatefile('html/errors/404.html', $params);

				return prepareResponseForSending(
					$client,
					$params,
					$body,
					$httpClient,
					$response,
				);
			}
			
		} elsif ( $path =~ /anyurl/ ) {
			main::DEBUGLOG && $log->is_debug && $log->debug('anyurl - parameters processed, return dummy content to prevent 404');
			$$body = 'anyurl processed';
			
		} else {
			# who knows why we're here, we just know that something ain't right
			$$body = undef;
		}
	}

	# if there's a reference to an empty value, then there is no valid page at all
	if (!$response->code() || $response->code() ne RC_NOT_MODIFIED) {

		if (defined $body && ref $body eq 'SCALAR' && !defined $$body) {

			$response->code(RC_NOT_FOUND);
			$body = filltemplatefile('html/errors/404.html', $params);
		}

		return 0 unless $body;

	} else {

		# Set the body to nothing, so the length() check won't fail.
		$$body = "";
	}

	# Tell the browser not to reload the playlist unless it's changed.
	# XXXX - not fully baked. Need more testing.
	if (0 && !defined $mtime && defined $client && ref($client->currentPlaylistRender())) {

		$mtime = $client->currentPlaylistRender()->[0] || undef;

		if (defined $mtime) {
			$response->expires($mtime + 60);
		}
	}

	# Create an ETag based on the mtime, file size and inode of the
	# content. This will allow us us to send back 304 (Not Modified)
	# headers. Very similar to how Apache does it.
	#
	# ETags can and should get smarter with our dynamic data - because we
	# know when it was updated, we can change the ETag. Until that
	# happens, only enable it for static content - ie: when an mtime exists.
	if (defined $mtime) {

		# for our static content
		$response->last_modified($mtime) if defined $mtime;

		my @etag = ();

		if ( !defined $size ) {
			if ( ref $body eq 'SCALAR' ) {
				$size = length($$body);
			}
			elsif ( ref $body eq 'FileHandle' ) {
				$size = (stat $body)[7];
			}
		}

		push @etag, sprintf('%lx', $inode) if $inode;
		push @etag, sprintf('%lx', $size)  if $size;
		push @etag, sprintf('%lx', $mtime) if $mtime;

		$response->etag(join('-', @etag));
	}

	# treat js.html differently - need the html ending to have it processed by TT,
	# but browser should consider it javascript
	if ( $path =~ /js(?:-browse)?\.html/i) {
		$contentType = 'application/x-javascript';
	}

	$response->content_type($contentType);

	#if (defined $params->{'refresh'}) {
	#	$response->header('Refresh', $params->{'refresh'});
	#}

	return 0 unless $body;
	
	if ( ref $body eq 'FileHandle' ) {
		$response->content_length( $size );
		
		my $headers = _stringifyHeaders($response) . $CRLF;

		$streamingFiles{$httpClient} = $body;

		# we are not a real streaming session, so we need to avoid sendStreamingResponse using the random $client stored in
		# $peerclient as this will cause streaming to the real client $client to stop.
		delete $peerclient{$httpClient};

		addStreamingResponse($httpClient, $headers);
		
		return;
	}

	# if the reference to the body is itself undefined, then we've started
	# generating the page in the background
	return prepareResponseForSending($client, $params, $body, $httpClient, $response);
}

sub sendStreamingFile {
	my ( $httpClient, $response, $contentType, $file, $objOrHash ) = @_;
	
	# Send the file down - and hint to the browser
	# the correct filename to save it as.
	my $size = -s $file;
	
	$response->content_type( $contentType );
	$response->content_length( $size );
	$response->header('Content-Disposition', 
		sprintf('attachment; filename="%s"', Slim::Utils::Misc::unescape(basename($file)))
	);
	
	my $fh = FileHandle->new($file);
	
	# Range/TimeSeekRange
	my $range   = $response->request->header('Range');
	my $tsrange = $response->request->header('TimeSeekRange.dlna.org');
	
	# If a Range is already provided, ignore TimeSeekRange
	my $isTSR;
	if ( $tsrange && !$range ) {
		# Translate TimeSeekRange into byte range
		my $valid = 0;
		
		my $formatClass = blessed($objOrHash) ? Slim::Formats->classForFormat($objOrHash->content_type) : undef;
		
		# Ignore TimeSeekRange unless we have a valid format class (currently this only supports audio)
		if ( $formatClass && Slim::Formats->loadTagFormatForType($objOrHash->content_type) && $formatClass->can('findFrameBoundaries') ) {
			# Valid is: npt=(start time)-(end time)
			# A time may be either a fractional seconds (sss.fff), or hhh:mm:ss.fff
			# End is optional
			if ( $tsrange =~ /^npt=([^-]+)-([^\s]*)$/ ) {
				my $start = $1 || 0;
				my $end   = $2;
			
				my $startbytes = 0;
				my $endbytes = $size - 1;
			
				if ( $start =~ /:/ ) {
					my ($h, $m, $s) = split /:/, $start;
					$start = ($h * 3600) + ($m * 60) + $s;
				}
				
				if ( $start > 0 ) {
					$startbytes = $formatClass->findFrameBoundaries($fh, undef, $start);
					main::DEBUGLOG && $log->is_debug && $log->debug("TimeSeekRange.dlna.org: Found start byte offset $startbytes for time $start");
				}
			
				if ( $end ) {
					if ( $end =~ /:/ ) {
						my ($h, $m, $s) = split /:/, $end;
						$end = ($h * 3600) + ($m * 60) + $s;
					}
					
					$endbytes = $formatClass->findFrameBoundaries($fh, undef, $end);
					main::DEBUGLOG && $log->is_debug && $log->debug("TimeSeekRange.dlna.org: Found end offset $endbytes for time $end");
				}
				
				if ( $startbytes == -1 && $endbytes == -1 ) {
					# DLNA 7.4.40.8, a valid time range syntax but out of range for the media
					$response->code(416);
				}
				else {
					# If only the end is -1, assume it was seeking too near the end, and set it to $size
					if ($endbytes == -1) {
						$endbytes = $size - 1;
					}
				}
				
				if ( $startbytes >= 0 && $endbytes >= 0 ) {
					# Create a valid Range request, which will be handled by the below range code
					$range = "bytes=${startbytes}-${endbytes}";
					$isTSR = 1;
					$valid = 1;
					
					my $duration = $objOrHash->secs;
					$end ||= $duration;
					$response->header( 'TimeSeekRange.dlna.org' => "npt=${start}-${end}/${duration} bytes=${startbytes}-${endbytes}/${size}" );
					
					# If npt is "0-" don't perform a range request
					if ($start == 0 && $end == $duration) {
						$range = undef;
					}
				}
			}
			else {
				# DLNA 7.4.40.9, bad npt format is a 400 error
				$response->code(400);
			}
		}
		
		if ( !$valid ) {
			$log->warn("Invalid TimeSeekRange.dlna.org request: $tsrange");
			$response->code(406) unless $response->code >= 400;
			$response->headers->remove_content_headers;
			$httpClient->send_response($response);
			closeHTTPSocket($httpClient);
			return;
		}
	}
	
	# Support Range requests
	if ( $range ) {
		# Only support a single range request, and no support for suffix requests
		if ( $range =~ m/^bytes=(\d+)-(\d+)?$/ ) {
			my $first = $1 || 0;
			my $last  = $2 || $size - 1;
			my $total = $last - $first + 1;
			
			if ( $first > $size ) {
				# invalid (past end of file)
				$response->code(416);
				$response->headers->remove_content_headers;
				$httpClient->send_response($response);
				closeHTTPSocket($httpClient);
				return;
			}
			
			if ( $total < 1 ) {
				# invalid (first > last)
				$response->code(400);
				$response->headers->remove_content_headers;
				$httpClient->send_response($response);
				closeHTTPSocket($httpClient);
				return;
			}
		
			if ( $last >= $size ) {
				$last = $size - 1;
			}
		
			main::DEBUGLOG && $log->is_debug && $log->debug("Handling Range request: $first-$last");
		
			seek $fh, $first, 0;
		
			if ( $isTSR ) { # DLNA 7.4.40.7 A time seek uses 200 status and doesn't include Content-Range, ugh
				$response->code(200);
			}
			else {
				$response->code( 206 );
				$response->header( 'Content-Range' => "bytes $first-$last/$size" );
			}
			$response->content_length( $total );
		
			# Save total value for use later in sendStreamingResponse
			${*$fh}{rangeTotal}   = $total;
			${*$fh}{rangeCounter} = 0;
		}
	}
	
	# Respond to realTimeInfo.dlna.org (DLNA 7.4.72)
	if ( $response->request->header('realTimeInfo.dlna.org') ) {
		$response->header( 'realTimeInfo.dlna.org' => 'DLNA.ORG_TLAG=*' );
	}

	my $headers = _stringifyHeaders($response) . $CRLF;
	
	# For a range request, reduce rangeCounter to account for header size
	if ( ${*$fh}{rangeTotal} ) {
		${*$fh}{rangeCounter} -= length $headers;
	}
	
	$streamingFiles{$httpClient} = $fh;

	# we are not a real streaming session, so we need to avoid sendStreamingResponse using the random $client stored in
	# $peerclient as this will cause streaming to the real client $client to stop.
	delete $peerclient{$httpClient};
	
	# Disable metadata in case this client sent an Icy-Metadata header
	$sendMetaData{$httpClient} = 0;

	addStreamingResponse($httpClient, $headers);
}

sub contentHasBeenModified {
	my $response = shift;
	my $mtime    = shift || $response->last_modified() || 0;

	my $request  = $response->request();
	my $method   = $request->method();

	# From Apache:
	#
	# Check for conditional requests --- note that we only want to do
	# this if we are successful so far and we are not processing a
	# subrequest or an ErrorDocument.
	#
	# The order of the checks is important, since ETag checks are supposed
	# to be more accurate than checks relative to the modification time.

	# If an If-Match request-header field was given
	# AND the field value is not "*" (meaning match anything)
	# AND if our strong ETag does not match any entity tag in that field,
	#     respond with a status of 412 (Precondition Failed).
	my $ifMatch = $request->if_match();
	my $etag    = $response->etag();

	my $ifModified  = $request->if_modified_since();
	my $requestTime = $request->client_date();

	if ($ifMatch) {

		if ($ifMatch ne '*' && (!$etag || $etag eq 'W' || $etag ne $ifMatch)) {

			main::DEBUGLOG && $log->is_debug && $log->debug("\tifMatch - RC_PRECONDITION_FAILED");
			$response->code(RC_PRECONDITION_FAILED);
		}

	} else {

		# Else if a valid If-Unmodified-Since request-header field was given
		# AND the requested resource has been modified since the time
		# specified in this field, then the server MUST
		#     respond with a status of 412 (Precondition Failed).
		my $ifUnmodified = $request->if_unmodified_since();

		if ($ifUnmodified && time() > $ifUnmodified) {

			 main::DEBUGLOG && $log->is_debug && $log->debug("\tifUnmodified - RC_PRECONDITION_FAILED");

			 $response->code(RC_PRECONDITION_FAILED);
		}
	}

	# return early.
	if ($response->code() eq RC_PRECONDITION_FAILED) {

		return 1;
	}

	# If an If-None-Match request-header field was given
	# AND the field value is "*" (meaning match anything)
	#     OR our ETag matches any of the entity tags in that field, fail.
	#
	# If the request method was GET or HEAD, failure means the server
	#    SHOULD respond with a 304 (Not Modified) response.
	# For all other request methods, failure means the server MUST
	#    respond with a status of 412 (Precondition Failed).
	#
	# GET or HEAD allow weak etag comparison, all other methods require
	# strong comparison.  We can only use weak if it's not a range request.
	my $ifNoneMatch = $request->if_none_match();

	if ($ifNoneMatch) {

		if ($ifNoneMatch eq '*') {

			main::DEBUGLOG && $log->is_debug && $log->debug("\tifNoneMatch - * - returning 304");
			$response->code(RC_NOT_MODIFIED);

		} elsif ($etag) {

			if ($request->if_range()) {

				if ($etag ne 'W' && $ifNoneMatch eq $etag) {

					main::DEBUGLOG && $log->is_debug && $log->debug("\tETag is not weak and ifNoneMatch eq ETag - returning 304");
					$response->code(RC_NOT_MODIFIED);
				}

			} elsif ($ifNoneMatch eq $etag) {

				main::DEBUGLOG && $log->is_debug && $log->debug("\tifNoneMatch eq ETag - returning 304");
				$response->code(RC_NOT_MODIFIED);
			}
		}

	} else {

		# Else if a valid If-Modified-Since request-header field was given
		# AND it is a GET or HEAD request
		# AND the requested resource has not been modified since the time
		# specified in this field, then the server MUST
		#    respond with a status of 304 (Not Modified).
		# A date later than the server's current request time is invalid.

		my $ifModified  = $request->if_modified_since();
		my $requestTime = $request->client_date();

		if ($ifModified && $requestTime && $mtime) {

			if (($ifModified >= $mtime) && ($ifModified <= $requestTime)) {

				if ( main::INFOLOG && $log->is_info ) {
					$log->info(sprintf("Content at: %s has not been modified - returning 304.", $request->uri));
				}

				$response->code(RC_NOT_MODIFIED);
			}
		}
 	}
 
 	if ($response->code() eq RC_NOT_MODIFIED) {

 		for my $header (qw(Content-Length Content-Type Last-Modified)) {
 			$response->remove_header($header);
 		}

		return 0;
 	}

	return 1;
}

sub prepareResponseForSending {
	my ($client, $params, $body, $httpClient, $response) = @_;

	use bytes;
	
	# Trap empty content
	$body ||= \'';

	# Set the Content-Length - valid for either HEAD or GET
	$response->content_length(length($$body));

	# bug 7498: add charset to content type if needed
	# If we're perl 5.8 or above, always send back utf-8
	# Otherwise, send back the charset from the current locale
	my $contentType = $response->content_type; 

	if ($contentType =~ m!^text/(?:html|xml)!) {

		$contentType .= '; charset=utf-8';
	}

	$response->content_type($contentType);

	$response->header( Date => time2str(time) );

	# If we're already a 304 - that means we've already checked before the static content fetch.
	if ($response->code() ne RC_NOT_MODIFIED) {

		contentHasBeenModified($response);
	}

	# buffer our response, including headers, and we have no more data
	addHTTPResponse($httpClient, $response, $body, 1, 0);

	return 0;
}

# XXX - ick ick
sub _stringifyHeaders {
	my $response = shift;

	my $code = $response->code();
	my $data = '';

	$data .= sprintf("%s %s %s%s", $response->protocol(), $code, HTTP::Status::status_message($code) || "", $CRLF);

	$data .= sprintf("Server: Logitech Media Server (%s - %s)%s", $::VERSION, $::REVISION, $CRLF);

	$data .= $response->headers_as_string($CRLF);

	# hack to make xmms like the audio better, since it appears to be case sensitive on for headers.
	$data =~ s/^(Icy-.+\:)/\L$1/mg; 
	
	# hack for Reciva Internet Radios which glitch on metadata unless the
	# icy-name header comes before icy-metaint, so make sure icy-metaint
	# is the last of the headers.
	$data =~ s/^(icy-metaint:[^\n]*\n)(.+)/$2$1/ms;

	return $data;
}

# addHTTPResponse
# buffers an HTTP response $response with body $body for $httpClient
#  $response is used to get the headers and the desired chunking/closing behaviour
#  headers are sent if $sendheaders is 1 (the default)
#  if chunking is used, a last chunk is sent if Connection:Close or $more is 0 (the default)

# Example for normal use
#  addHTPPResponse($httpClient, $response, $body, 1, 0)
#   buffers headers and body, chunked or not, closing or not

# Example for chunking use
#  1. addHTTPResponse($client, $response, $body, 1, 1)
#   buffers headers and first body part
#  2. addHTTPResponse($client, $response, $body, 0, 1)
#   buffers more body
#  3. addHTTPResponse($client, $response, $body, 0, 0)
#   buffers more body and last chunk (or close)

sub addHTTPResponse {
	my $httpClient  = shift;
	my $response    = shift;
	my $body        = shift;
	my $sendheaders = shift;
	my $more        = shift || 0;

	# determine our closing/chunking behaviour
	# code above is responsible to set the headers right...
	my $close   = 0;
	my $chunked = 0;

	# if we have more, don't close now!
	if (!$more && $response->header('Connection') && $response->header('Connection') =~ /close/i) {

		$close = 1;
	}

	if ($response->header('Transfer-Encoding') && $response->header('Transfer-Encoding') =~ /chunked/i) {

		$chunked = 1;
	}

	# Force byte semantics on $body and length($$body) - otherwise we'll
	# try to write out multibyte characters with invalid byte lengths in
	# sendResponse() below.
	use bytes;
	
	# Collect all our output into one chunk, to reduce TCP packets
	my $outbuf;

	# First add the headers, if requested
	if (!defined($sendheaders) || $sendheaders == 1) {
		
		# Add a header displaying the time it took us to serve this request
		$response->header( 'X-Time-To-Serve' => ( Time::HiRes::time() - $httpClient->start_time ) );

		$outbuf .= _stringifyHeaders($response) . $CRLF;
	}

	# And now the body.
	# Don't send back any content on a HEAD or 304 response.
	if ($response->request()->method() ne 'HEAD' && 
		$response->code() ne RC_NOT_MODIFIED &&
		$response->code() ne RC_PRECONDITION_FAILED) {
		
		# use chunks if we have a transfer-encoding that says so
		if ($chunked) {
			
			# add chunk...
			$outbuf .= sprintf("%X", length($$body)) . $CRLF . $$body . $CRLF;
			
			# add a last empty chunk if we're closing the connection or if there's nothing more
			if ($close || !$more) {
				
				$outbuf .= '0' . $CRLF . $CRLF;
			}

		} else {

			$outbuf .= $$body;
		}
	}
	
	push @{$outbuf{$httpClient}}, {
		'data'     => \$outbuf,
		'offset'   => 0,
		'length'   => length($outbuf),
		'close'    => $close,
	};

	Slim::Networking::Select::addWrite($httpClient, \&sendResponse);
}

sub addHTTPLastChunk {
	my $httpClient = shift;
	my $close = shift;
	
	my $emptychunk = "0" . $CRLF . $CRLF;

	push @{$outbuf{$httpClient}}, {
		'data'     => \$emptychunk,
		'offset'   => 0,
		'length'   => length($emptychunk),
		'close'    => $close,
	};
	
	Slim::Networking::Select::addWrite($httpClient, \&sendResponse);
}

# sendResponse
# callback for write select
# pops a data segment for the given httpclient and sends it
# optionally closes the connection *if* there's no more segments.
# expects segments to be hashrefs with items 'data', 'offset', 'length' and 'close'
sub sendResponse {
	my $httpClient = shift;

	use bytes;

	my $segment    = shift(@{$outbuf{$httpClient}});
	my $sentbytes  = 0;
	my $port       = $httpClient->peerport();

	# abort early if we're not connected
	if (!$httpClient->connected) {

		$log->is_warn && $log->warn("Not connected with $peeraddr{$httpClient}:$port, closing socket");

		closeHTTPSocket($httpClient, 0, 'not connected');
		return;
	}

	# abort early if we don't have anything.
	if (!$segment) {

		main::INFOLOG && $log->is_info && $log->info("No segment to send to $peeraddr{$httpClient}:$port, waiting for next request...");

		# Nothing to send, so we take the socket out of the write list.
		# When we process the next request, it will get put back on.
		Slim::Networking::Select::removeWrite($httpClient); 

		return;
	}

	if (defined $segment->{'data'} && defined ${$segment->{'data'}}) {

		$sentbytes = syswrite($httpClient, ${$segment->{'data'}}, $segment->{'length'}, $segment->{'offset'});
	}

	if (!defined $sentbytes && $! == EWOULDBLOCK) {
		main::INFOLOG && $log->is_info && $log->info("Would block while sending. Resetting sentbytes for: $peeraddr{$httpClient}:$port");
		$sentbytes = 0;
	}

	if (!defined($sentbytes)) {

		# Treat $httpClient with suspicion
		main::INFOLOG && $log->is_info && $log->info("Send to $peeraddr{$httpClient}:$port had error ($!), closing and aborting.");

		closeHTTPSocket($httpClient, 0, "$!");

		return;
	}

	# sent incomplete message
	if ($sentbytes < $segment->{'length'}) {

		$segment->{'length'} -= $sentbytes;
		$segment->{'offset'} += $sentbytes;
		unshift @{$outbuf{$httpClient}}, $segment;
		
	} else {
		
		main::INFOLOG && $log->is_info && $log->info("Sent $sentbytes to $peeraddr{$httpClient}:$port");

		# sent full message
		if (@{$outbuf{$httpClient}} == 0) {

			# no more messages to send
			main::INFOLOG && $log->is_info && $log->info("No more segments to send to $peeraddr{$httpClient}:$port");

			
			# close the connection if requested by the higher God pushing segments
			if ($segment->{'close'} && $segment->{'close'} == 1) {
				
				main::INFOLOG && $log->is_info && $log->info("End request, connection closing for: $peeraddr{$httpClient}:$port");

				closeHTTPSocket($httpClient);
				return;
			}
			else {
				# Check for additional pipelined GET or HEAD requests we need to process
				# We also support pipelined cometd requets, even though this is against the HTTP RFC
				if ( ${*$httpClient}{httpd_rbuf} ) {
					if ( ${*$httpClient}{httpd_rbuf} =~ m{^(?:GET|HEAD|POST /cometd)} ) {
						main::INFOLOG && $log->is_info && $log->info("Pipelined request found, processing");
						processHTTP($httpClient);
						return;
					}
					elsif ( $log->is_info ) {
						main::INFOLOG && $log->info( "Not handling pipelined request:\n" . ${*$httpClient}{httpd_rbuf} );
					}
				}
			}

		} else {

			main::INFOLOG && $log->is_info && $log->info("More segments to send to $peeraddr{$httpClient}:$port");
		}
		
		# Reset keep-alive timer
		Slim::Utils::Timers::killTimers( $httpClient, \&closeHTTPSocket );
		Slim::Utils::Timers::setTimer(
			$httpClient,
			time() + KEEPALIVETIMEOUT,
			\&closeHTTPSocket,
			0,
			'keep-alive timeout',
		);
	}
}

=pod

=head1 These two routines handle HTTP streaming of audio (a la ShoutCast and IceCast)

=cut

sub addStreamingResponse {
	my $httpClient = shift;
	my $message    = shift;
	
	my %segment = ( 
		'data'   => \$message,
		'offset' => 0,
		'length' => length($message)
	);

	push @{$outbuf{$httpClient}}, \%segment;

	# Set the kernel's send buffer to be higher so that there is less
	# chance of audio skipping if/when we block elsewhere in the code.
	# 
	# Check to make sure that our target size isn't smaller than the
	# kernel's default size.
	if (unpack('I', getsockopt($httpClient, SOL_SOCKET, SO_SNDBUF)) < (MAXCHUNKSIZE * 2)) {

		setsockopt($httpClient, SOL_SOCKET, SO_SNDBUF, (MAXCHUNKSIZE * 2));
	}
	
	# we aren't going to read from this socket anymore so don't select on it...
	Slim::Networking::Select::removeRead($httpClient);

	if (my $client = Slim::Player::Client::getClient($peerclient{$httpClient})) {

		$client->streamingsocket($httpClient);

		my $newpeeraddr = getpeername($httpClient);
	
		$client->paddr($newpeeraddr) if $newpeeraddr;
	}
	
	Slim::Networking::Select::addWrite($httpClient, \&sendStreamingResponse, 1);
}

sub clearOutputBuffer {
	my $client = shift;

	delete $outbuf{$client->id};
}

sub sendStreamingResponse {
	my $httpClient = shift;
	my $sentbytes;

	my $client;
	
	my $isInfo = ( main::INFOLOG && $log->is_info ) ? 1 : 0;
	
	if ( $peerclient{$httpClient} ) {
		$client = Slim::Player::Client::getClient($peerclient{$httpClient});
	}
	
	# when we are streaming a file, we may not have a client, rather it might just be going to a web browser.
	# assert($client);
	
	my $outbuf = $outbuf{$httpClient};
	my $segment = shift(@$outbuf);
	my $streamingFile = $streamingFiles{$httpClient};

	my $silence = 0;
	
	main::INFOLOG && $isInfo && $log->info("sendStreaming response begun...");
	
	# Keep track of where we need to stop if this is a range request
	my $rangeTotal;
	my $rangeCounter;
	if ( $streamingFile && ${*$streamingFile}{rangeTotal} ) {
		$rangeTotal   = ${*$streamingFile}{rangeTotal};
		$rangeCounter = ${*$streamingFile}{rangeCounter};
		
		main::DEBUGLOG && $log->is_debug && $log->debug( "  range request, sending $rangeTotal bytes ($rangeCounter sent)" );
	}

	if (   !$httpClient->connected()
		|| ($client && $client->isa("Slim::Player::Squeezebox")
			&& (   !defined($client->streamingsocket())
			    || $httpClient != $client->streamingsocket()
				|| (!$streamingFile && $client->isStopped()) # XXX is the !$streamingFile test superfluous
				)
			)
		)
	{
		main::INFOLOG && $isInfo &&
			$log->info(($client ? $client->id : ''), " Streaming connection closed");

		closeStreamingSocket($httpClient);
		return undef;
	}
	
	if (!defined($streamingFile) && $client && $client->isa("Slim::Player::HTTP") && 
		((Slim::Player::Source::playmode($client) ne 'play') || (Slim::Player::Playlist::count($client) == 0))) {

		$silence = 1;
	}
	
	# if we don't have anything in our queue, then get something
	if (!defined($segment)) {

		# if we aren't playing something, then queue up some silence
		if ($silence) {

			main::INFOLOG && $isInfo && $log->info("(silence)");

			my $bitrate = Slim::Utils::Prefs::maxRate($client);
			my $silence = undef;

			if ($bitrate == 320 || $bitrate == 0) { 

				$silence = getStaticContent("html/silence.mp3");

			} else {

				$silence = getStaticContent("html/lbrsilence.mp3");
			}

			my %segment = ( 
				'data'   => $silence,
				'offset' => 0,
				'length' => length($$silence)
			);

			unshift @$outbuf, \%segment;

		} else {
			my $chunkRef;

			if (defined($streamingFile)) {

				my $chunk = undef;
				my $len   = MAXCHUNKSIZE;
				
				# Reduce len if needed for a range request
				if ( $rangeTotal && ( $rangeCounter + $len > $rangeTotal ) ) {
					$len = $rangeTotal - $rangeCounter;
					main::DEBUGLOG && $log->is_debug && $log->debug( "Reduced read length to $len for range request" );
				}

				if ( $len ) {
					$streamingFile->sysread( $chunk, $len );
				}

				if (defined($chunk) && length($chunk)) {

					$chunkRef = \$chunk;

				} else {

					# we're done streaming this stored file, closing connection.
					closeStreamingSocket($httpClient);

					return 0;
				}

			} else {
				# bug 10534
				if (!$client) {
					closeStreamingSocket($httpClient);
					main::INFOLOG && $log->info("Abandoning orphened streaming connection");
					return 0;
				} 

				$chunkRef = $client->nextChunk(MAXCHUNKSIZE, sub {tryStreamingLater(shift, $httpClient);});
			}

			# otherwise, queue up the next chunk of sound
			if ($chunkRef) {
					
				if (length($$chunkRef)) {
	
					if ( main::INFOLOG && $isInfo ) {
						$log->info("(audio: " . length($$chunkRef) . " bytes)");
					}
	
					my %segment = ( 
						'data'   => $chunkRef,
						'offset' => 0,
						'length' => length($$chunkRef)
					);
	
					unshift @$outbuf,\%segment;
					
				} else {
					main::INFOLOG && $log->info("Found an empty chunk on the queue - dropping the streaming connection.");
					forgetClient($client);
					return undef;
				}

			} else {

				# let's try again after RETRY_TIME - not really necessary as we are selecting on source, ...
				my $retry = RETRY_TIME;

				main::INFOLOG && $isInfo && $log->info("Nothing to stream, let's wait for $retry seconds...");
				
				Slim::Networking::Select::removeWrite($httpClient);
				
				Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $retry, \&tryStreamingLater,($httpClient));
			}
		}

		# try again...
		$segment = shift(@$outbuf);
	}
	
	# try to send metadata, if appropriate
	if ($sendMetaData{$httpClient}) {

		# if the metadata would appear in the middle of this message, just send the bit before
		main::INFOLOG && $isInfo && $log->info("metadata bytes: $metaDataBytes{$httpClient}");

		if ($metaDataBytes{$httpClient} == METADATAINTERVAL) {

			unshift @$outbuf, $segment;

			my $url = Slim::Player::Playlist::url($client);

			my $title = $url ? Slim::Music::Info::getCurrentTitle($client, $url) : string('WELCOME_TO_SQUEEZEBOX_SERVER');
			$title =~ tr/'/ /;

			my $metastring = "StreamTitle='" . $title . "';";
			my $length = length($metastring);

			$metastring .= chr(0) x (16 - ($length % 16));
			$length = length($metastring) / 16;

			my $message = chr($length) . $metastring;

			my %segment = ( 
				'data'   => \$message,
				'offset' => 0,
				'length' => length($message)
			);

			$segment = \%segment;
			
			$metaDataBytes{$httpClient} = 0;

			if ( main::INFOLOG && $isInfo ) {
				$log->info("sending metadata of length $length: '$metastring' (" . length($message) . " bytes)");
			}

		} elsif (defined($segment) && $metaDataBytes{$httpClient} + $segment->{'length'} > METADATAINTERVAL) {

			my $splitpoint = METADATAINTERVAL - $metaDataBytes{$httpClient};
			
			# make a copy of the segment, and point to the second half, to be sent later.
			my %splitsegment = %$segment;

			$splitsegment{'offset'} += $splitpoint;
			$splitsegment{'length'} -= $splitpoint;
			
			unshift @$outbuf, \%splitsegment;
			
			#only send the first part
			$segment->{'length'} = $splitpoint;
			
			$metaDataBytes{$httpClient} += $splitpoint;

			main::INFOLOG && $isInfo && $log->info("splitting message for metadata at $splitpoint");
		
		} elsif (defined $segment) {

			# if it's time to send the metadata, just send the metadata
			$metaDataBytes{$httpClient} += $segment->{'length'};
		}
	}

	if (defined($segment)) {

		use bytes;

		my $prebytes = $segment->{'length'};
		$sentbytes   = syswrite($httpClient, ${$segment->{'data'}}, $segment->{'length'}, $segment->{'offset'});

		if (!defined $sentbytes && $! == EWOULDBLOCK) {
			$sentbytes = 0;
		}

		if (defined($sentbytes)) {
			if ($sentbytes < $segment->{'length'}) { #sent incomplete message

				if ($sentbytes) {

					main::INFOLOG && $isInfo && $log->info("sent incomplete chunk, requeuing " . ($segment->{'length'} - $sentbytes). " bytes");
				}

				$metaDataBytes{$httpClient} -= $segment->{'length'} - $sentbytes;

				$segment->{'length'} -= $sentbytes;
				$segment->{'offset'} += $sentbytes;

				unshift @$outbuf,$segment;
			}

		} else {

			main::INFOLOG && $isInfo && $log->info("syswrite returned undef: $!");

			closeStreamingSocket($httpClient);

			return undef;
		}

	} else {
		if ( main::INFOLOG && $isInfo ) {
			$log->info("\$httpClient is: $httpClient");
			if (exists $peeraddr{$httpClient}) {
				$log->info("\$peeraddr{\$httpClient} is: $peeraddr{$httpClient}");
				$log->info("Got nothing for streaming data to $peeraddr{$httpClient}");
			} else {
				$log->info("\$peeraddr{\$httpClient} is undefined");
			}
		}
		return 0;
	}

	if ($sentbytes) {

		main::INFOLOG && $isInfo && $log->info("Streamed $sentbytes to $peeraddr{$httpClient}");
		
		# Update sent counter if this is a range request
		if ( $rangeTotal ) {	
			${*$streamingFile}{rangeCounter} += $sentbytes;
		}
	}

	return $sentbytes;
}

sub tryStreamingLater {
	my $client     = shift;
	my $httpClient = shift;

	if ( defined $client->streamingsocket() && $httpClient == $client->streamingsocket() ) {

		# Bug 10085 - This might be a callback for an old connection  
		# which we decided to close after establishing the timer, so
		# only kill the timer if we were called for the active streaming connection;
		# otherwise we might kill the timer related to the next connection too.
		Slim::Utils::Timers::killTimers($client, \&tryStreamingLater);
	}

	# Bug 14740 - always call sendStreamingResponse so we ensure the socket gets closed
	Slim::Networking::Select::addWrite($httpClient, \&sendStreamingResponse, 1);
}

sub forgetClient {
	my $client = shift;

	if (defined($client->streamingsocket)) {
		closeStreamingSocket($client->streamingsocket);
	}
}

sub closeHTTPSocket {
	my ( $httpClient, $streaming, $reason ) = @_;
	
	$reason ||= 'closed normally';
	
	main::INFOLOG && $log->is_info && $log->info("Closing HTTP socket $httpClient with $peeraddr{$httpClient}:" . ($httpClient->peerport || 0). " ($reason)");
	
	Slim::Utils::Timers::killTimers( $httpClient, \&closeHTTPSocket );

	Slim::Networking::Select::removeRead($httpClient);
	Slim::Networking::Select::removeWrite($httpClient);
	Slim::Networking::Select::removeError($httpClient);

	# clean up the various caches
	delete($outbuf{$httpClient});
	delete($sendMetaData{$httpClient});
	delete($metaDataBytes{$httpClient});
	delete($peeraddr{$httpClient});
	delete($keepAlives{$httpClient});
	delete($peerclient{$httpClient});
	
	# heads up to handlers, if any
	for my $func (@closeHandlers) {
		if (ref($func) eq 'CODE') {
		
			# XXX: should this use eval?
			&{$func}($httpClient);
		}
	}
	
	
	# Fix for bug 1289. A close on its own wasn't always actually
	# sending a FIN or RST packet until significantly later for
	# streaming connections. The call to shutdown seems to be a
	# little more assertive about closing the socket. Windows-only
	# for now, but could be considered for other platforms and
	# non-streaming connections.
	if (main::ISWINDOWS) {
		$httpClient->shutdown(2);
	}

	$httpClient->close();
	undef($httpClient);
	$connected--;
}

sub closeStreamingSocket {
	my $httpClient = shift;
	
	if (defined $streamingFiles{$httpClient}) {

		main::INFOLOG && $log->is_info && $log->info("Closing streaming file.");

		close  $streamingFiles{$httpClient};
		delete $streamingFiles{$httpClient};
	}

	foreach my $client (Slim::Player::Client::clients()) {

		if (defined($client->streamingsocket) && $client->streamingsocket == $httpClient) {
			$client->streamingsocket(undef);
		}
	}
	
	# Close socket unless it's keep-alive
	if ( $keepAlives{$httpClient} ) {
		main::INFOLOG && $log->is_info && $log->info('Keep-alive on streaming socket');
		Slim::Networking::Select::addRead($httpClient, \&processHTTP);
		Slim::Networking::Select::removeWrite($httpClient);
	}
	else {
		main::INFOLOG && $log->is_info && $log->info('Closing streaming socket');
		closeHTTPSocket($httpClient, 1);
	}

	return;
}

sub checkAuthorization {
	my $username = shift;
	my $password = shift;
	my $request = shift;

	my $ok = 0;

	# No authorization needed
	if (!$prefs->get('authorize')) {

		$ok = 1;
		return $ok;
	}

	if ($username eq $prefs->get('username')) {

		my $pwd  = $prefs->get('password');

		if ($pwd eq $password && $pwd eq '') {

			$ok = 1;

		} else {

			$ok = (sha1_base64( $password ) eq $pwd);

			# bug 11003 - try crypt if sha1 fails, keep backwards compatibility
			# this should be removed some releases after 7.4
			if (!$ok) {
				my $salt = substr($pwd, 0, 2);
				$ok = (crypt($password, $salt) eq $pwd);
			}
		}
		
		# Check for scanner progress request
		if ( !$ok && $pwd eq $password ) {
			if ( $request->header('X-Scanner') ) {
				$ok = 1;
			}
		}

	} else {

		foreach my $client (Slim::Player::Client::clients()) {

			if (defined($client->password()) && $client->password() eq $password) {
				$ok = 1;
				last;
			}
		}
	}

	return $ok;
}

# addCloseHandler
# defines a function to be called when $httpClient is closed
# prototype: func($httpClient), no return value
sub addCloseHandler{
	my $funcPtr = shift;
	
	if ( main::INFOLOG && $log->is_info ) {
		my $funcName = Slim::Utils::PerlRunTime::realNameForCodeRef($funcPtr);
		$log->info("Adding Close handler: $funcName");
	}
	
	push @closeHandlers, $funcPtr;
}
	

# Fills the template file specified as $path, using either the currently
# selected skin, or an override. Returns the filled template string
# these are all very similar

sub filltemplatefile {
	return $skinMgr->_generateContentFromFile('fill', @_);
}

sub getStaticContent {
	return $skinMgr->_generateContentFromFile('get', @_);
}

sub getFileInfoForStaticContent {
	return $skinMgr->_generateContentFromFile('mtime', @_);
}

sub getStaticContentForTemplate {
	return ${$skinMgr->_generateContentFromFile('get', @_)};
}


sub addTemplateDirectory {
	$skinMgr->addTemplateDirectory(@_);
}

sub fixHttpPath {
	$skinMgr->fixHttpPath(@_);
}

# the following subs have been moved to Slim::Web::Pages in SC 7.4
# backwards compatibility should be removed at some reasonable point
sub addPageFunction {
	logBacktrace("Slim::Web::HTTP::addPageFunction() is deprecated - please use Slim::Web::Pages->addPageFunction() instead");
	Slim::Web::Pages->addPageFunction(@_);
}

sub addRawFunction {
	logBacktrace("Slim::Web::HTTP::addRawFunction() is deprecated - please use Slim::Web::Pages->addRawFunction() instead");
	Slim::Web::Pages->addRawFunction(@_);
}

sub addRawDownload {
	logBacktrace("Slim::Web::HTTP::addRawDownload() is deprecated - please use Slim::Web::Pages->addRawDownload() instead");
	Slim::Web::Pages->addRawDownload(@_);
}

sub removeRawDownload {
	logBacktrace("Slim::Web::HTTP::removeRawDownload() is deprecated - please use Slim::Web::Pages->removeRawDownload() instead");
	Slim::Web::Pages->removeRawDownload(@_);
}

sub protectURI { if ( main::WEBUI ) {
	logBacktrace("Slim::Web::HTTP::protectURI() is deprecated - please use Slim::Web::HTTP::CSRF->protectURI() instead");
	Slim::Web::HTTP::CSRF->protectURI(@_);
} }

sub protectName { if ( main::WEBUI ) {
	logBacktrace("Slim::Web::HTTP::protectName() is deprecated - please use Slim::Web::HTTP::CSRF->protectName() instead");
	Slim::Web::HTTP::CSRF->protectName(@_);
} }

sub protectCommand { if ( main::WEBUI ) {
	logBacktrace("Slim::Web::HTTP::protectCommand() is deprecated - please use Slim::Web::HTTP::CSRF->protectCommand() instead");
	Slim::Web::HTTP::CSRF->protectCommand(@_);
} }

sub protect { if ( main::WEBUI ) {
	logBacktrace("Slim::Web::HTTP::protect() is deprecated - please use Slim::Web::HTTP::CSRF->protect() instead");
	Slim::Web::HTTP::CSRF->protect(@_);
} }

sub downloadMusicFile {
	my ($httpClient, $response, $id) = @_;
	
	# Support transferMode.dlna.org (DLNA 7.4.49)
	my $tm = $response->request->header('transferMode.dlna.org') || 'Streaming';
	if ( $tm =~ /^(?:Streaming|Background)$/i ) {
		$response->header( 'transferMode.dlna.org' => $tm );
	}
	else {
		$response->code(406);
		$response->headers->remove_content_headers;
		$httpClient->send_response($response);
		closeHTTPSocket($httpClient);
		return;
	}

	my $obj = Slim::Schema->find('Track', $id);

	if (blessed($obj) && Slim::Music::Info::isSong($obj) && Slim::Music::Info::isFile($obj->url)) {
		
		# Bug 8808, support transcoding if a file extension is provided
		my $uri    = $response->request->uri;
		my $isHead = $response->request->method eq 'HEAD';
		
		if ( my ($outFormat) = $uri =~ m{download\.([^\?]+)} ) {				
			$outFormat = 'flc' if $outFormat eq 'flac';
			
			if ( $obj->content_type ne $outFormat ) {
				if ( main::TRANSCODING ) {
					# Also support LAME bitrate/quality
					my ($bitrate) = $uri =~ m{bitrate=(\d+)};
					my ($quality) = $uri =~ m{quality=(\d)};
					$quality = 9 unless $quality =~ /^[0-9]$/;
					
					# Use aif because DLNA specifies big-endian format
					$outFormat = 'aif' if $outFormat =~ /^(?:aiff?|wav)$/;
				
					my ($transcoder, $error) = Slim::Player::TranscodingHelper::getConvertCommand2(
						$obj,
						undef, # content-type will be determined from $obj
						['F'], # File stream mode
						[],
						[],
						$outFormat,
						$bitrate || 0,
					);
				
					if ( !$transcoder ) {
						$log->error("Couldn't transcode " . $obj->url . " to $outFormat: $error");
					
						$response->code(400);
						$response->headers->remove_content_headers;				
						addHTTPResponse($httpClient, $response, \'', 1, 0);
						return 1;
					}
		
					my $command = Slim::Player::TranscodingHelper::tokenizeConvertCommand2(
						$transcoder, $obj->path, $obj->url, undef, $quality
					);
				
					if ( !$command ) {
						$log->error("Couldn't create transcoder command-line for " . $obj->url . " to $outFormat");
					
						$response->code(400);
						$response->headers->remove_content_headers;					
						addHTTPResponse($httpClient, $response, \'', 1, 0);
						return 1;
					}
				
					my $in;
					my $out;
					my $done = 0;
					
					if ( !$isHead ) {
						main::INFOLOG && $log->is_info && $log->info("Opening transcoded download (" . $transcoder->{profile} . "), command: $command");
						
						# Bug: 4318
						# On windows ensure a child window is not opened if $command includes transcode processes
						if (main::ISWINDOWS) {
							Win32::SetChildShowWindow(0);
						 	$in = FileHandle->new;
							my $pid = $in->open($command);
					
							# XXX Bug 15650, this sets the priority of the cmd.exe process but not the actual
							# transcoder process(es).
							my $handle;
							if ( Win32::Process::Open( $handle, $pid, 0 ) ) {
								$handle->SetPriorityClass( Slim::Utils::OS::Win32::getPriorityClass() || Win32::Process::NORMAL_PRIORITY_CLASS() );
							}
					
							Win32::SetChildShowWindow();
						} else {
							$in = FileHandle->new($command);
						}
					
						Slim::Utils::Network::blocking($in, 0);
					}
				
					if ($outFormat eq 'aif') {
						# Construct special PCM content-type
						$response->content_type( 'audio/L16;rate=' . $obj->samplerate . ';channels=' . $obj->channels );
					}
					else {
						$response->content_type( $Slim::Music::Info::types{$outFormat} );
					}
				
					# Tell client range requests are not supported
					$response->header( 'Accept-Ranges' => 'none' );
					
					my $filename = Slim::Utils::Misc::pathFromFileURL($obj->url);
					$filename =~ s/\..+$/\.$outFormat/;
					$response->header('Content-Disposition', 
						sprintf('attachment; filename="%s"', basename($filename))
					);
				
					my $is11 = $response->request->protocol eq 'HTTP/1.1';
				
					if ($is11) {
						# Use chunked TE for HTTP/1.1 clients
						$response->header( 'Transfer-Encoding' => 'chunked' );
					}
					
					# Add DLNA HTTP header, with ORG_CI to indicate transcoding, and lack of ORG_OP to indicate no seeking
					my $dlna;
					if ( $outFormat eq 'mp3' ) {
						$dlna = 'DLNA.ORG_PN=MP3;DLNA.ORG_CI=1;DLNA.ORG_FLAGS=01700000000000000000000000000000';
					}
					elsif ( $outFormat eq 'aif' ) {
						$dlna = 'DLNA.ORG_PN=LPCM;DLNA.ORG_CI=1;DLNA.ORG_FLAGS=01700000000000000000000000000000';
					}
					if ($dlna) {
						$response->header( 'contentFeatures.dlna.org' => $dlna );
					}
				
					my $headers = _stringifyHeaders($response) . $CRLF;

					# non-blocking stream $pipeline to $httpClient
					my $writer; $writer = sub {
						if ($headers) {
							syswrite $httpClient, $headers;
							undef $headers;
							
							if ($isHead) {
								$done = 1;
							}
						}
						
						if ($done) {
							$out && $out->destroy;
							$in && $in->close;
							
							if ( $httpClient->opened() ) {
								closeHTTPSocket($httpClient);
							}
							return;
						}
					
						if ($in) {
							# Try to read some data from the pipeline
							my $len = sysread $in, my $buf, 32 * 1024;
							if ( !defined $len ) {
								my $w; $w = AnyEvent->io( fh => $in, poll => 'r', cb => sub {
									undef $w;
									$in && $writer->();
								} );
							}
							elsif ( $len == 0 ) {
								$done = 1;
						
								if ($is11) {
									# Add last empty chunk
									$out->push_write( '0' . $CRLF . $CRLF );
								}
								else {
									$writer->(); # clean up & close
								}
							}
							else {
								if ($is11) {
									$out->push_write( sprintf("%X", length($buf)) . $CRLF . $buf . $CRLF );
								}
								else {
									$out->push_write($buf);
								}
							}
						}
					};
					
					$out = AnyEvent::Handle->new(
						fh         => $httpClient,
						linger     => 0,
						timeout    => 300,
						on_timeout => sub {
							main::INFOLOG && $log->is_info && $log->info("Timing out transcoded download for $httpClient");
							$done = 1;
							$writer->();
						},
						on_error   => sub {
							my ($hdl, $fatal, $msg) = @_;
							main::INFOLOG && $log->is_info && $log->info("Transcoded download error: $msg");
							$done = 1;
							$writer->();
						},						    
					);
					
					# Bug 17212, Must add callback after object creation - references to $out within the $writer callback were
					# failing when the on_drain callback was passed as a constructor argument
					$out->on_drain($writer);
				
					return 1;
				}
				else {
					# Transcoding is not enabled, return 400
					$log->error("Transcoding is not enabled for " . $obj->url . " to $outFormat");
				
					$response->code(400);	
					$response->headers->remove_content_headers;				
					addHTTPResponse($httpClient, $response, \'', 1, 0);
					return 1;
				}
			}
		}
		
		main::INFOLOG && $log->is_info && $log->info("Opening $obj for download...");
			
		my $ct = $Slim::Music::Info::types{$obj->content_type()};
		
		# Add DLNA HTTP header
		if ( my $pn = $obj->dlna_profile ) {
			my $canseek = ($pn eq 'MP3' || $pn =~ /^WMA/);
			my $dlna = "DLNA.ORG_PN=${pn};DLNA.ORG_OP=" . ($canseek ? '11' : '01') . ";DLNA.ORG_FLAGS=01700000000000000000000000000000";
			$response->header( 'contentFeatures.dlna.org' => $dlna );
		}
		
		Slim::Web::HTTP::sendStreamingFile( $httpClient, $response, $ct, Slim::Utils::Misc::pathFromFileURL($obj->url), $obj );
			
		return 1;
	}
	
	return;
}

sub downloadVideoFile {
	my ($httpClient, $response, $id) = @_;

	require Slim::Schema::Video;
	my $video = Slim::Schema::Video->findhash($id);

	if ($video) {
		# Add DLNA HTTP header
		if ( my $pn = $video->{dlna_profile} ) {
			my $dlna = "DLNA.ORG_PN=${pn};DLNA.ORG_OP=01;DLNA.ORG_FLAGS=01700000000000000000000000000000";
			$response->header( 'contentFeatures.dlna.org' => $dlna );
		}
		
		# Support transferMode.dlna.org (DLNA 7.4.49)
		my $tm = $response->request->header('transferMode.dlna.org') || 'Streaming';
		if ( $tm =~ /^(?:Streaming|Background)$/i ) {
			$response->header( 'transferMode.dlna.org' => $tm );
		}
		else {
			$response->code(406);
			$response->headers->remove_content_headers;
			$httpClient->send_response($response);
			closeHTTPSocket($httpClient);
			return;
		}
				
		Slim::Web::HTTP::sendStreamingFile( $httpClient, $response, $video->{mime_type}, Slim::Utils::Misc::pathFromFileURL($video->{url}), $video );
		return 1;
	}
	
	return;
}

sub downloadImageFile {
	my ($httpClient, $response, $hash) = @_;

	require Slim::Schema::Image;
	my $image = Slim::Schema::Image->findhash($hash);

	if ($image) {
		# Add DLNA HTTP header
		if ( my $pn = $image->{dlna_profile} ) {
			my $dlna = "DLNA.ORG_PN=${pn};DLNA.ORG_OP=01;DLNA.ORG_FLAGS=00f00000000000000000000000000000";
			$response->header( 'contentFeatures.dlna.org' => $dlna );
		}
		
		# Support transferMode.dlna.org (DLNA 7.4.49)
		my $tm = $response->request->header('transferMode.dlna.org') || 'Interactive';
		if ( $tm =~ /^(?:Interactive|Background)$/i ) {
			$response->header( 'transferMode.dlna.org' => $tm );
		}
		else {
			$response->code(406);
			$response->headers->remove_content_headers;
			$httpClient->send_response($response);
			closeHTTPSocket($httpClient);
			return;
		}
				
		Slim::Web::HTTP::sendStreamingFile( $httpClient, $response, $image->{mime_type}, Slim::Utils::Misc::pathFromFileURL($image->{url}), $image );
		return 1;
	}
	
	return;
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
