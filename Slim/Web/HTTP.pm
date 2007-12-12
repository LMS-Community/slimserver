package Slim::Web::HTTP;

# $Id$

# SqueezeCenter Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use CGI::Cookie;
use Digest::MD5;
use FileHandle;
use File::Basename qw(basename);
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);
use HTTP::Date qw(time2str);
use HTTP::Daemon;
use HTTP::Headers::ETag;
use HTTP::Status;
use MIME::Base64;
use MIME::QuotedPrint;
use Scalar::Util qw(blessed);
use Socket qw(:DEFAULT :crlf);
use Storable qw(thaw);
use Template;
use Tie::RegexpHash;
use URI::Escape;
use YAML::Syck qw(LoadFile);

use Slim::Formats::Playlists::M3U;
use Slim::Networking::mDNS;
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

	# Use our custom Template::Context subclass
	$Template::Config::CONTEXT = 'Slim::Web::Template::Context';
}

use constant defaultSkin => 'Default';
use constant baseSkin	 => 'EN';
use constant HALFYEAR	 => 60 * 60 * 24 * 180;

use constant METADATAINTERVAL => 32768;
use constant MAXCHUNKSIZE     => 32768;

use constant RETRY_TIME       => 0.05; # normal retry time
use constant RETRY_TIME_FAST  => 0.02; # faster retry for streaming pcm on platforms with small pipe buffer
use constant PIPE_BUF_THRES   => 4096; # threshold for switching between retry times

use constant MAXKEEPALIVES    => 30;
use constant KEEPALIVETIMEOUT => 10;

# Package variables

my $openedport = undef;
my $http_server_socket;
my $connected = 0;

our %outbuf = (); # a hash for each writeable socket containing a queue of output segments
                 #   each segment is a hash of a ref to data, an offset and a length

our %lastSegLen = (); # length of last segment

our %sendMetaData   = ();
our %metaDataBytes  = ();
our %streamingFiles = ();
our %peeraddr       = ();
our %peerclient     = ();
our %keepAlives     = ();
our %skinTemplates  = ();
our %skins          = ();

our @templateDirs = ();

# this holds pointers to functions handling a given path
our %pageFunctions = ();
tie %pageFunctions, 'Tie::RegexpHash';

# we bypass most of the template stuff to execute those
our %rawFunctions = ();
tie %rawFunctions, 'Tie::RegexpHash';

# we call these whenever we close a connection
our @closeHandlers = ();

# raw files we serve directly outside the html directory
our %rawFiles = ();
my $rawFilesRegexp = qr//;


our $pageBuild = Slim::Utils::PerfMon->new('Web Page Build', [0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.5, 1, 5]);

our %dangerousCommands;

my $log = logger('network.http');

my $prefs = preferences('server');

# initialize the http server
sub init {

	push @templateDirs, Slim::Utils::OSDetect::dirsFor('HTML');

	# Try and use the faster XS module if it's available.
	Slim::bootstrap::tryModuleLoad('Template::Stash::XS');

	if ($@) {

		# Pure perl is the default, so we don't need to do anything.
		$log->warn("Couldn't find Template::Stash::XS - falling back to pure perl version.");

	} else {

		$log->info("Found Template::Stash::XS!");

		$Template::Config::STASH = 'Template::Stash::XS';
	}

	# Initialize all the web page handlers.
	Slim::Web::Pages::init();

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

sub openport {
	my ($listenerport, $listeneraddr) = @_;

	# start our listener
	$http_server_socket = HTTP::Daemon->new(
		LocalPort => $listenerport,
		LocalAddr => $listeneraddr,
		Listen    => SOMAXCONN,
		ReuseAddr => 1,
		Reuse => 1,
		Timeout   => 0.001,

	) or $log->logdie("Can't setup the listening port $listenerport for the HTTP server: $!");
	
	defined(Slim::Utils::Network::blocking($http_server_socket,0)) || $log->logdie("Cannot set port nonblocking");

	$openedport = $listenerport;

	Slim::Networking::Select::addRead($http_server_socket, \&acceptHTTP);

	$log->info("Server $0 accepting http connections on port $listenerport");

	Slim::Networking::mDNS->addService('_http._tcp', $listenerport);
	Slim::Networking::mDNS->addService('_slimhttp._tcp', $listenerport);
}

sub adjustHTTPPort {

	return unless defined $openedport; # only adjust once init is complete

	# do this on a timer so current page can be updated first and it executed outside select
	Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 0.5, \&_adjustHTTPPortCallback);
}

sub _adjustHTTPPortCallback {

	# if we've already opened a socket, let's close it
	if ($openedport) {

		Slim::Networking::mDNS->removeService('_http._tcp');
		Slim::Networking::mDNS->removeService('_slimhttp._tcp');
		
		$log->info("Closing http server socket");

		Slim::Networking::Select::addRead($http_server_socket, undef);

		$http_server_socket->close();
		undef($http_server_socket);
		$openedport = 0;
	}

	# open new port if specified
	if ($prefs->get('httpport')) {

		Slim::Web::HTTP::openport($prefs->get('httpport'), $::httpaddr);

		# Need to restart mDNS after changing the HTTP port.
		Slim::Networking::mDNS->startAdvertising;
	}
}

sub connectedSocket {
	return $connected;
}

sub acceptHTTP {
	# try and pull the handle
	my $httpClient = $http_server_socket->accept('Slim::Web::HTTP::ClientConn') || do {

		$log->info("Did not accept connection, accept returned nothing");
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

			# this is the timeout for the client connection.
			$httpClient->timeout(KEEPALIVETIMEOUT);

			$peeraddr{$httpClient} = $peer;

			Slim::Networking::Select::addRead($httpClient, \&processHTTP);
			Slim::Networking::Select::addError($httpClient, \&closeStreamingSocket);

			$connected++;

			if ( $log->is_info ) {
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

sub isaSkin {
	my $name = uc shift;

	# return from hash
	return $skins{$name} if $skins{$name};

	# otherwise reload skin hash and try again
	%skins = skins();
	return $skins{$name};
}

sub skins {
	# create a hash of available skins - used for skin override and by settings page
	my $UI = shift; # return format for settings page rather than lookup cache for skins

	my %skinlist = ();

	for my $templatedir (HTMLTemplateDirs()) {

		for my $dir (Slim::Utils::Misc::readDirectory($templatedir)) {

			# reject CVS, html, and .svn directories as skins
			next if $dir =~ /^(?:cvs|html|\.svn)$/i;
			next if $UI && $dir =~ /^x/;
			next if !-d catdir($templatedir, $dir);

			# BUG 4171: Disable dead Default2 skin, in case it was left lying around
			next if $dir =~ /^(?:ExBrowse3|Default2)$/i;

			$log->info("skin entry: $dir");

			if ($dir eq defaultSkin()) {
				$skinlist{ $UI ? $dir : uc $dir } = $UI ? string('DEFAULT_SKIN') : defaultSkin();
			} elsif ($dir eq baseSkin()) {
				$skinlist{ $UI ? $dir : uc $dir } = $UI ? string('BASE_SKIN') : baseSkin();
			} else {
				$skinlist{ $UI ? $dir : uc $dir } = Slim::Utils::Misc::unescape($dir);
			}
		}
	}

	# These skins are depreciated - map to Default in skin hash, don't show on settings page
	if (!$UI) {
		$skinlist{'DEFAULT2'}  = defaultSkin();
		$skinlist{'EXBROWSE3'} = defaultSkin();
	}

	return %skinlist;
}

# Handle an HTTP request
sub processHTTP {
	my $httpClient = shift || return;

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


	$log->info("Reading request...");

	my $request    = $httpClient->get_request();
	# socket half-closed from client
	if (!defined $request) {

		if ( $log->is_info ) {
			$log->info("Client at $peeraddr{$httpClient}:" . $httpClient->peerport . " disconnected. (half-closed)");
		}

		closeHTTPSocket($httpClient);
		return;
	}
	

	if ( $log->is_info ) {
		$log->info(
			"HTTP request: from $peeraddr{$httpClient}:" . $httpClient->peerport . " ($httpClient) for " .
			join(' ', ($request->method(), $request->protocol(), $request->uri()))
		);
	}

	if ( $log->is_debug ) {
		$log->debug("Raw request headers: [\n" . $request->as_string() . "]");
	}

	# this will hold our context and is used to fill templates
	my $params     = {};
	$params->{'userAgent'} = $request->header('user-agent');
	$params->{'browserType'} = Slim::Utils::Misc::detectBrowser($request);

	# this bundles up all our response headers and content
	my $response = HTTP::Response->new();

	# by default, respond in kind.
	$response->protocol($request->protocol());
	$response->request($request);


	# handle stuff we know about or abort
	if ($request->method() eq 'GET' || $request->method() eq 'HEAD' || $request->method() eq 'POST') {

		# Manage authorization
		my $authorized = !$prefs->get('authorize');

		if (my ($user, $pass) = $request->authorization_basic()) {
			$authorized = checkAuthorization($user, $pass);
		}

		# no Valid authorization supplied!
		if (!$authorized) {

			$response->code(RC_UNAUTHORIZED);
			$response->header('Connection' => 'close');
			$response->content_type('text/html');
			$response->content_ref(filltemplatefile('html/errors/401.html', $params));
			$response->www_authenticate(sprintf('Basic realm="%s"', string('SQUEEZECENTER')));

			$httpClient->send_response($response);
			closeHTTPSocket($httpClient);
			return;
		}


		# HTTP/1.1 Persistent connections or HTTP 1.0 Keep-Alives
		# XXX - MAXKEEPALIVES should be a preference
		# This always add a Connection: close header if we want the connection to be closed.
		if (defined $keepAlives{$httpClient} && $keepAlives{$httpClient} >= MAXKEEPALIVES) {

			# This will close the client socket & remove the
			# counter in sendResponse()
			$response->header('Connection' => 'close');

			$log->info("Hit MAXKEEPALIVES, will close connection.");

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
		}

		# extract the URI and raw path
		# the path is modified below for skins and stuff
		my $uri   = $request->uri();
		my $path  = $uri->path();
		
		$log->debug("Raw path is [$path]");

		# break here for raw HTTP code
		# we hand the $response object only, it contains the almost unmodified request
		# we took care above of basic HTTP stuff and authorization
		# $rawFunc shall call addHTTPResponse
		if (my $rawFunc = $rawFunctions{$path}) {

			$log->info("Handling [$path] using raw function");

			if (ref($rawFunc) eq 'CODE') {
				
				# XXX: should this use eval?
				&{$rawFunc}($httpClient, $response);
				return;
			}
		}

		# Set the request time - for If-Modified-Since
		$request->client_date(time());
	
	
		# remove our special X-Slim-CSRF header if present
		$request->remove_header("X-Slim-CSRF");
	
		# store CSRF auth code in fake request header if present
		if (defined($request->uri()) && ($request->uri() =~ m|^(.*)\;cauth\=([0-9a-f]{32})$|) ) {
	
			my $plainURI = $1;
			my $csrfAuth = $2;
	
			if ( $log->is_info ) {
				$log->info("Found CSRF auth token \"$csrfAuth\" in URI \"".$request->uri()."\", so resetting request URI to \"$plainURI\"");
			}
	
			# change the URI so later code doesn't "see" the cauth part
			$request->uri($plainURI);
	
			# store the cauth code in the request object (headers are handy!)
			$request->push_header("X-Slim-CSRF",$csrfAuth);
		}
		
		
		# Read cookie(s)
		if ( my $cookie = $request->header('Cookie') ) {
			$params->{'cookies'} = { CGI::Cookie->parse($cookie) };
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

		# CSRF: make list of params passed by HTTP client
		my %csrfReqParams;

		# XXX - unfortunately SqueezeCenter uses a query form
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
					if ($value ne '*' && $value ne '') {

						$value = Slim::Utils::Unicode::utf8on($value);
						# Bug 5236 - this is breaking strings with some characters
						# in them (eg. Hungarian) 
						#$value = Slim::Utils::Unicode::utf8encode_locale($value);
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

					$log->info("HTTP parameter $name = $value");

					my $csrfName = $name;
					if ( $csrfName eq 'command' ) { $csrfName = 'p0'; }
					if ( $csrfName eq 'subcommand' ) { $csrfName = 'p1'; }
					push @{$csrfReqParams{$csrfName}}, $value;

				} else {

					my $name = Slim::Utils::Misc::unescape($param, 1);

					$params->{$name} = 1;

					$log->info("HTTP parameter $name = 1");

					my $csrfName = $name;
					if ( $csrfName eq 'command' ) { $csrfName = 'p0'; }
					if ( $csrfName eq 'subcommand' ) { $csrfName = 'p1'; }
					push @{$csrfReqParams{$csrfName}}, 1;
				}
			}
		}

		# for CSRF protection, get the query args in one neat string that 
		# looks like a GET querystring value; this should handle GET and POST
		# equally well, only looking at the data that we would act on
		my $csrfProtectionLevel = $prefs->get('csrfProtectionLevel');
		my $queryWithArgs;
		my $queryToTest;
		if ( defined($csrfProtectionLevel) && ($csrfProtectionLevel != 0) ) {
			$queryWithArgs = Slim::Utils::Misc::unescape($request->uri());
			# next lines are ugly hacks to remove any GET args
			$queryWithArgs =~ s|\?.*$||;
			$queryWithArgs .= '?';
			foreach my $n (sort keys %csrfReqParams) {
				foreach my $val ( @{$csrfReqParams{$n}} ) {
					$queryWithArgs .= Slim::Utils::Misc::escape($n) . '=' . Slim::Utils::Misc::escape($val) . '&';
                                }
			}
			# scrub some harmless args
			$queryToTest = $queryWithArgs;
			$queryToTest =~ s/\bplayer=.*?\&//g;
			$queryToTest =~ s/\bplayerid=.*?\&//g;
			$queryToTest =~ s/\bajaxUpdate=\d\&//g;
			$queryToTest =~ s/\?\?/\?/;
		}

		# Stash CSRF token in $params for use in TT templates
		my $providedPageAntiCSRFToken = $params->{pageAntiCSRFToken};
		# pageAntiCSRFToken is a bare token
		$params->{pageAntiCSRFToken} = &makePageToken($request);

		# Skins 
		if ($path) {

			$params->{'webroot'} = '/';

			if ($path =~ s{^/slimserver/}{/}i) {
				$params->{'webroot'} = "/slimserver/"
			}

			$path =~ s|^/+||;

			if ($path =~ m{^(?:html|music|plugins|settings|firmware)/}i || $path =~ $rawFilesRegexp ) {
				# not a skin

			} elsif ($path =~ m|^([a-zA-Z0-9]+)$| && isaSkin($1)) {

				$log->info("Alternate skin $1 requested, redirecting to $uri/ append a slash.");

				$response->code(RC_MOVED_PERMANENTLY);
				$response->header('Location' => $uri . '/');

				$httpClient->send_response($response);

				closeHTTPSocket($httpClient);

				return;

			} elsif ($path =~ m|^(.+?)/.*|) {

				my $desiredskin = $1;

				# Requesting a specific skin, verify and set the skinOverride param
				$log->info("Alternate skin $desiredskin requested");

				my $skinname = isaSkin($desiredskin);
				
				if ($skinname) {

					$log->info("Rendering using $skinname");

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

		if ($params->{'browserType'} eq 'IE' &&
		($params->{'skinOverride'} || $prefs->get('skin')) eq 'Nokia770') 
		{
			$log->debug("Internet Explorer Detected with Nokia Skin, redirecting to Touch");
			$params->{'skinOverride'} = 'Touch';
		}


		# apply CSRF protection logic to "dangerous" commands
		if ( defined($csrfProtectionLevel) && ($csrfProtectionLevel != 0) ) {
			foreach my $dregexp ( keys %dangerousCommands ) {
				if ($queryToTest =~ m|$dregexp| ) {
					if ( ! isRequestCSRFSafe($request,$response,$params,$providedPageAntiCSRFToken) ) {
	
						$log->error("Client requested dangerous function/arguments and failed CSRF Referer/token test, sending 403 denial");
	
						throwCSRFError($httpClient,$request,$response,$params,$queryWithArgs);
						return;
					}
				}
			}
		}
		
		if ( $log->is_debug ) {
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
	if ($log->is_debug) {

		$response->content("");
		$log->debug("Response Headers: [\n" . $response->as_string . "]");
	}

	if ( $log->is_info ) {
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
		$p[$i] = $params->{"p$i"};
	}

	# This is trumped by query parameters 'command' and 'subcommand'.
	# These are passed as the first two command parameters (p0 and p1), 
	# while the rest of the query parameters are passed as third (p3).
	if (defined $params->{'command'} && $path !~ /^memoryusage/) {
		$p[0] = $params->{'command'};
		$p[1] = $params->{'subcommand'};
		$p[2] = join '&', map $_ . '=' . $params->{$_},  keys %{$params};
	}

	if ( $log->is_info ) {
		$log->info("processURL Clients: " . join(" ", Slim::Player::Client::clientIPs()));
	}

	# explicitly specified player (for web browsers or squeezeboxen)
	if (defined($params->{"player"})) {
		$client = Slim::Player::Client::getClient($params->{"player"});
	}

	# is this an HTTP stream?
	if (!defined($client) && ($path =~ /(?:stream\.mp3|stream)$/)) {
	
		my $address = $peeraddr{$httpClient};
	
		$log->info("processURL found HTTP client at address=$address");
	
		$client = Slim::Player::Client::getClient($address);
		
		if (!defined($client)) {

			my $paddr = getpeername($httpClient);

			$log->info("New http client at $address");

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
					
					$client->defaultName( $agent . ' ' . string('FROM') . ' ' . $address );
				}
				else {
					# Just show the IP address if there's no user-agent
					$client->defaultName( $address );
				}
			}
		}

		if (defined($params->{'bitrate'})) {
			# must validate 32 40 48 56 64 80 96 112 128 160 192 224 256 320 CBR
			# set to the closest lower value of its not a match
			my $temprate = $params->{'bitrate'};

			foreach my $i (qw(320 256 244 192 160 128 112 96 80 64 56 48 40 32)) {
				$temprate = $i; 	 
				last if ($i <= $params->{'bitrate'}); 	 
			}

			$prefs->client($client)->set('transcodeBitrate',$temprate); 	 

			$log->info("Setting transcode bitrate to $temprate");

		} else {

			$prefs->client($client)->set('transcodeBitrate',undef);
		}
	}
	
	# player specified from cookie
	if ( !defined $client && $params->{'cookies'} ) {
		if ( my $player = $params->{'cookies'}->{'SqueezeCenter-player'} ) {
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

	# We don't support pipelining, so respond as HTTP 1.0 for now.
	if ($response->protocol =~ /1\.1/) {

		$response->protocol('HTTP/1.0');
	}

	$params->{'player'}   = '';
	$params->{'revision'} = $::REVISION if $::REVISION;
	$params->{'nosetup'}  = 1   if $::nosetup;
	$params->{'noserver'} = 1   if $::noserver;

	# Check for the gallery view cookie.
	if ($params->{'cookies'}->{'SqueezeCenter-albumView'} && 
		$params->{'cookies'}->{'SqueezeCenter-albumView'}->value) {

		$params->{'artwork'} = $params->{'cookies'}->{'SqueezeCenter-albumView'}->value unless defined $params->{'artwork'};
	}

	# Check for the album order cookie.
	if ($params->{'cookies'}->{'SqueezeCenter-orderBy'} && 
		$params->{'cookies'}->{'SqueezeCenter-orderBy'}->value) {

		$params->{'orderBy'} = $params->{'cookies'}->{'SqueezeCenter-orderBy'}->value unless defined $params->{'orderBy'};
	}

	# Check for thumbSize cookie (for Touch, 1-by-1 artwork enlarge/shrink feature)
	if ($params->{'cookies'}->{'SqueezeCenter-thumbSize'} &&
		$params->{'cookies'}->{'SqueezeCenter-thumbSize'}->value) {

			$params->{'thumbSize'} = $params->{'cookies'}->{'SqueezeCenter-thumbSize'}->value unless defined $params->{'thumbSize'};
	}

	if (Slim::Web::Graphics::serverResizesArt()) {
		$params->{'serverResizesArt'} = 1;
	}

	my $path = $params->{"path"};
	my $type = Slim::Music::Info::typeFromSuffix($path, 'htm');

	# lots of people need this
	my $contentType = $params->{'Content-Type'} = $Slim::Music::Info::types{$type};

	if ( $path =~ $rawFilesRegexp ) {
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

	$log->info("Generating response for ($type, $contentType) $path");

	# some generally useful form details...
	if (defined($client) && exists($pageFunctions{$path})) {
		$params->{'player'} = $client->id();
		$params->{'myClientState'} = $client;
		
		# save the player id in a cookie
		my $cookie = CGI::Cookie->new(
			-name    => 'SqueezeCenter-player',
			-value   => $params->{'player'},
			-expires => '+1y',
		);
		$response->headers->push_header( 'Set-Cookie' => $cookie );
	}

	# this might do well to break up into methods
	if ($contentType =~ /(?:image|javascript|css)/) {

		# static content should expire from cache in one hour
		$response->expires( time() + 3600 );
		$response->header('Cache-Control' => 'max-age=3600');
	}

	if ($contentType =~ /text/ && $path !~ /memoryusage/) {

		$params->{'params'} = {};

		filltemplatefile('include.html', $params);

		while (my ($key,$value) = each %{$params->{'params'}}) {

			$params->{$key} = $value;
		}

		delete $params->{'params'};
	}

	if (my $classOrCode = $pageFunctions{$path}) {

		# if we match one of the page functions as defined above,
		# execute that, and hand it a callback to send the data.

		$::perfmon && (my $startTime = Time::HiRes::time());

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
		
		$::perfmon && $startTime && $pageBuild->log(Time::HiRes::time() - $startTime, "Page: $path");

	} elsif ($path =~ /^(?:stream\.mp3|stream)$/o) {

		# short circuit here if it's a slim/squeezebox
		if ($sendMetaData{$httpClient}) {
			$response->header("icy-metaint" => METADATAINTERVAL);
			$response->header("icy-name"    => string('WELCOME_TO_SQUEEZECENTER'));
		}

		my $headers = _stringifyHeaders($response) . $CRLF;

		$metaDataBytes{$httpClient} = - length($headers);
		
		addStreamingResponse($httpClient, $headers);

		return 0;

	} elsif ($path =~ /music\/(\w+)\/(cover|thumb)/ || 
		$path  =~ /\/\w+_(X|\d+)x(X|\d+)
                        (?:_([sSfFpc]))?        # resizeMode, given by a single character
                        (?:_[\da-fA-F]+)? 		# background color, optional
			/x   # extend this to also include any image that gives resizing parameters
		) {

		($body, $mtime, $inode, $size, $contentType) = Slim::Web::Graphics::processCoverArtRequest($client, $path, $params);

	} elsif ($path =~ /music\/(\d+)\/download/) {

		my $obj = Slim::Schema->find('Track', $1);

		if (blessed($obj) && Slim::Music::Info::isSong($obj) && Slim::Music::Info::isFile($obj->url)) {

			$log->info("Opening $obj to stream...");
			
			my $ct = $Slim::Music::Info::types{$obj->content_type()};
			
			sendStreamingFile( $httpClient, $response, $ct, Slim::Utils::Misc::pathFromFileURL($obj->url) );
			
			return 0;
		}

	} elsif ($path =~ /favicon\.ico/) {

		($mtime, $inode, $size) = getFileInfoForStaticContent($path, $params);

		if (contentHasBeenModified($response, $mtime, $inode, $size)) {

			($body, $mtime, $inode, $size) = getStaticContent("html/mypage.ico", $params); 
		}

	} elsif ($path =~ /\.css/) {

		($mtime, $inode, $size) = getFileInfoForStaticContent($path, $params);

		if (contentHasBeenModified($response, $mtime, $inode, $size)) {

			($body, $mtime, $inode, $size) = getStaticContent($path, $params);
		}

	# XXX: log.txt needs to be put back here
	} elsif ($path =~ /(?:status|robots)\.txt/) {

		# if the HTTP client has asked for a text file, then always return the text on the display
		$contentType = "text/plain";

		$response->header("Refresh" => "30; url=$path");
		$response->header("Content-Type" => "text/plain; charset=utf-8");

		if ( $path =~ /status/ ) {
			# This code is deprecated. Jonas Salling is the only user
			# anymore, and we're trying to move him to use the CLI.
			buildStatusHeaders($client, $response, $p);

			if (defined($client)) {
				my $parsed = $client->parseLines($client->curLines());
				my $line1 = $parsed->{line}[0] || '';
				my $line2 = $parsed->{line}[1] || '';
				$$body = $line1 . $CRLF . $line2 . $CRLF;
			}
		}
		elsif ( $path =~ /robots/ ) {
			($body, $mtime, $inode, $size) = getStaticContent($path, $params);
		}

	} elsif ($path =~ /status\.m3u/) {

		# if the HTTP client has asked for a .m3u file, then always return the current playlist as an M3U
		if (defined($client)) {

			my $count = Slim::Player::Playlist::count($client) && do {
				$$body = Slim::Formats::Playlists::M3U->write(\@{Slim::Player::Playlist::playList($client)});
			};
		}

	} elsif ($path =~ /html\//) {
		# content is in the "html" subdirectory within the template directory.

		# if it's HTML then use the template mechanism
		if ($contentType eq 'text/html' || $contentType eq 'text/xml' || $contentType eq 'application/x-java-jnlp-file') {

			# if the path ends with a slash, then server up the index.html file
			$path .= 'index.html' if $path =~ m|/$|;
			$body  = filltemplatefile($path, $params);

		} else {

			($mtime, $inode, $size) = getFileInfoForStaticContent($path, $params);

			if (contentHasBeenModified($response, $mtime, $inode, $size)) {

				# otherwise just send back the binary file
				($body, $mtime, $inode, $size) = getStaticContent($path, $params);
			}
		}

	} elsif ( $path =~ $rawFilesRegexp ) {
		# path is for download of known file outside http directory
		my ($file, $ct);

		for my $key (keys %rawFiles) {

			if ( $path =~ $key ) {

				my $fileinfo = $rawFiles{$key};
				$file = ref $fileinfo->{file} eq 'CODE' ? $fileinfo->{file}->($path) : $fileinfo->{file};
				$ct   = ref $fileinfo->{ct}   eq 'CODE' ? $fileinfo->{ct}->($path)   : $fileinfo->{ct};

				if (!-e $file) { 
					$file = undef;
				}

				last;
			}
		}

		if ($file) {
			# download the file
			$log->info("serving file: $file for path: $path");
			sendStreamingFile( $httpClient, $response, $ct, $file );
			return 0;

		} else {
			# 404 error
			$log->warn("unable to find file for path: $path");

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
			
	} else {
		# who knows why we're here, we just know that something ain't right
		$$body = undef;
	}

	# if there's a reference to an empty value, then there is no valid page at all
	if (!$response->code() || $response->code() ne RC_NOT_MODIFIED) {

		if (defined $body && !defined $$body) {

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

		$size ||= length($$body);

		push @etag, sprintf('%lx', $inode) if $inode;
		push @etag, sprintf('%lx', $size)  if $size;
		push @etag, sprintf('%lx', $mtime) if $mtime;

		$response->etag(join('-', @etag));
	}

	# If we're perl 5.8 or above, always send back utf-8
	# Otherwise, send back the charset from the current locale
	if ($contentType =~ m!^text/(?:html|xml)!) {

		if ($] > 5.007) {
			$contentType .= '; charset=utf-8';
		} else {
			$contentType .= sprintf("; charset=%s", Slim::Utils::Unicode::currentLocale());
		}
	}

	$response->content_type($contentType);

	#if (defined $params->{'refresh'}) {
	#	$response->header('Refresh', $params->{'refresh'});
	#}

	return 0 unless $body;

	# if the reference to the body is itself undefined, then we've started
	# generating the page in the background
	return prepareResponseForSending($client, $params, $body, $httpClient, $response);
}

sub sendStreamingFile {
	my ( $httpClient, $response, $contentType, $file ) = @_;
	
	# Send the file down - and hint to the browser
	# the correct filename to save it as.
	$response->content_type( $contentType );
	$response->content_length( -s $file );
	$response->header('Content-Disposition', 
		sprintf('attachment; filename="%s"', Slim::Utils::Misc::unescape(basename($file)))
	);

	my $headers = _stringifyHeaders($response) . $CRLF;

	my $fh = FileHandle->new($file);
	
	$streamingFiles{$httpClient} = $fh;

	# we are not a real streaming session, so we need to avoid sendStreamingResponse using the random $client stored in
	# $peerclient as this will cause streaming to the real client $client to stop.
	delete $peerclient{$httpClient};

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

			$log->debug("\tifMatch - RC_PRECONDITION_FAILED");
			$response->code(RC_PRECONDITION_FAILED);
		}

	 } else {

		# Else if a valid If-Unmodified-Since request-header field was given
		# AND the requested resource has been modified since the time
		# specified in this field, then the server MUST
		#     respond with a status of 412 (Precondition Failed).
		my $ifUnmodified = $request->if_unmodified_since();

		if ($ifUnmodified && time() > $ifUnmodified) {

			 $log->debug("\tifUnmodified - RC_PRECONDITION_FAILED");

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

			$log->debug("\tifNoneMatch - * - returning 304");
 			$response->code(RC_NOT_MODIFIED);

		} elsif ($etag) {

			if ($request->if_range()) {

				if ($etag ne 'W' && $ifNoneMatch eq $etag) {

					$log->debug("\tETag is not weak and ifNoneMatch eq ETag - returning 304");
					$response->code(RC_NOT_MODIFIED);
				}

			} elsif ($ifNoneMatch eq $etag) {

				$log->debug("\tifNoneMatch eq ETag - returning 304");
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

				if ( $log->is_info ) {
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

	# Set the Content-Length - valid for either HEAD or GET
	$response->content_length(length($$body));
	
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

	$data .= sprintf("%s %s %s%s", $response->protocol(), $code, status_message($code) || "", $CRLF);

	$data .= sprintf("Server: SqueezeCenter (%s - %s)%s", $::VERSION, $::REVISION, $CRLF);

	$data .= $response->headers_as_string($CRLF);

	# hack to make xmms like the audio better, since it appears to be case sensitive on for headers.
	$data =~ s/^(Icy-.+\:)/\L$1/mg; 

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
				
				$outbuf .= '0' . $CRLF;
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
	
	my $emptychunk = "0" . $CRLF;

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

		$log->warn("Not connected with $peeraddr{$httpClient}:$port, closing socket");

		closeHTTPSocket($httpClient);
		return;
	}

	# abort early if we don't have anything.
	if (!$segment) {

		$log->info("No segment to send to $peeraddr{$httpClient}:$port, waiting for next request...");

		# Nothing to send, so we take the socket out of the write list.
		# When we process the next request, it will get put back on.
		Slim::Networking::Select::removeWrite($httpClient); 

		return;
	}

	if (defined $segment->{'data'} && defined ${$segment->{'data'}}) {

		$sentbytes = syswrite($httpClient, ${$segment->{'data'}}, $segment->{'length'}, $segment->{'offset'});
	}

	if ($! == EWOULDBLOCK) {

		$log->info("Would block while sending. Resetting sentbytes for: $peeraddr{$httpClient}:$port");

		if (!defined $sentbytes) {
			$sentbytes = 0;
		}
	}

	if (!defined($sentbytes)) {

		# Treat $httpClient with suspicion
		$log->info("Send to $peeraddr{$httpClient}:$port had error, closing and aborting.");

		closeHTTPSocket($httpClient);

		return;
	}

	# sent incomplete message
	if ($sentbytes < $segment->{'length'}) {

		$segment->{'length'} -= $sentbytes;
		$segment->{'offset'} += $sentbytes;
		unshift @{$outbuf{$httpClient}}, $segment;
		
	} else {
		
		$log->info("Sent $sentbytes to $peeraddr{$httpClient}:$port");

		# sent full message
		if (@{$outbuf{$httpClient}} == 0) {

			# no more messages to send
			$log->info("No more segments to send to $peeraddr{$httpClient}:$port");

			
			# close the connection if requested by the higher God pushing segments
			if ($segment->{'close'} && $segment->{'close'} == 1) {
				
				$log->info("End request, connection closing for: $peeraddr{$httpClient}:$port");

				closeHTTPSocket($httpClient);
			}

		} else {

			$log->info("More segments to send to $peeraddr{$httpClient}:$port");
		}
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

	my $client = Slim::Player::Client::getClient($peerclient{$httpClient});
	
	# when we are streaming a file, we may not have a client, rather it might just be going to a web browser.
	# assert($client);

	my $segment = shift(@{$outbuf{$httpClient}});
	my $streamingFile = $streamingFiles{$httpClient};

	my $silence = 0;
	
	$log->info("sendStreaming response begun...");

	if ($client && 
			$client->isa("Slim::Player::Squeezebox") && 
			defined($httpClient) &&
			(!defined($client->streamingsocket()) || $httpClient != $client->streamingsocket())
		) {

		if ( $log->is_info ) {
			$log->info($client->id . " We're done streaming this socket to client");
		}

		closeStreamingSocket($httpClient);
		return;
	}
	
	if (!$httpClient->connected()) {

		closeStreamingSocket($httpClient);

		$log->info("Streaming client closed connection...");

		return undef;
	}
	
	if (!$streamingFile && $client && $client->isa("Slim::Player::Squeezebox") && 
		(Slim::Player::Source::playmode($client) eq 'stop')) {

		closeStreamingSocket($httpClient);

		$log->info("Squeezebox closed connection...");

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

			$log->info("(silence)");

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

			unshift @{$outbuf{$httpClient}}, \%segment;

		} else {
			my $chunkRef;

			if (defined($streamingFile)) {

				my $chunk = undef;

				$streamingFile->sysread($chunk, MAXCHUNKSIZE);

				if (defined($chunk) && length($chunk)) {

					$chunkRef = \$chunk;

				} else {

					# we're done streaming this stored file, closing connection.
					closeStreamingSocket($httpClient);

					$log->info("we're done streaming this stored file, closing connection....");

					return 0;
				}

			} else {

				$chunkRef = Slim::Player::Source::nextChunk($client, MAXCHUNKSIZE);
			}

			# otherwise, queue up the next chunk of sound
			if ($chunkRef && length($$chunkRef)) {

				if ( $log->is_info ) {
					$log->info("(audio: " . length($$chunkRef) . " bytes)");
				}

				my %segment = ( 
					'data'   => $chunkRef,
					'offset' => 0,
					'length' => length($$chunkRef)
				);

				$lastSegLen{$httpClient} = length($$chunkRef);

				unshift @{$outbuf{$httpClient}},\%segment;

			} else {

				# let's try again after RETRY_TIME
				my $retry = RETRY_TIME;

				if (defined $lastSegLen{$httpClient} && ($lastSegLen{$httpClient} <= PIPE_BUF_THRES) &&
					$client->streamformat() ne 'mp3') {
					# high bit rate on platform with potentially constrained pipe buffer - switch to fast retry
					$retry = RETRY_TIME_FAST;
				}

				$log->info("Nothing to stream, let's wait for $retry seconds...");
				
				Slim::Networking::Select::removeWrite($httpClient);
				
				if ( $httpClient->connected() ) {
					Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $retry, \&tryStreamingLater,($httpClient));
				}
			}
		}

		# try again...
		$segment = shift(@{$outbuf{$httpClient}});
	}
	
	# try to send metadata, if appropriate
	if ($sendMetaData{$httpClient}) {

		# if the metadata would appear in the middle of this message, just send the bit before
		$log->info("metadata bytes: $metaDataBytes{$httpClient}");

		if ($metaDataBytes{$httpClient} == METADATAINTERVAL) {

			unshift @{$outbuf{$httpClient}}, $segment;

			my $url = Slim::Player::Playlist::url($client);

			my $title = $url ? Slim::Music::Info::getCurrentTitle($client, $url) : string('WELCOME_TO_SQUEEZECENTER');
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

			if ( $log->is_info ) {
				$log->info("sending metadata of length $length: '$metastring' (" . length($message) . " bytes)");
			}

		} elsif (defined($segment) && $metaDataBytes{$httpClient} + $segment->{'length'} > METADATAINTERVAL) {

			my $splitpoint = METADATAINTERVAL - $metaDataBytes{$httpClient};
			
			# make a copy of the segment, and point to the second half, to be sent later.
			my %splitsegment = %$segment;

			$splitsegment{'offset'} += $splitpoint;
			$splitsegment{'length'} -= $splitpoint;
			
			unshift @{$outbuf{$httpClient}}, \%splitsegment;
			
			#only send the first part
			$segment->{'length'} = $splitpoint;
			
			$metaDataBytes{$httpClient} += $splitpoint;

			$log->info("splitting message for metadata at $splitpoint");
		
		} elsif (defined $segment) {

			# if it's time to send the metadata, just send the metadata
			$metaDataBytes{$httpClient} += $segment->{'length'};
		}
	}

	if (defined($segment) && $httpClient->connected()) {

		use bytes;

		my $prebytes = $segment->{'length'};
		$sentbytes   = syswrite($httpClient, ${$segment->{'data'}}, $segment->{'length'}, $segment->{'offset'});

		if ($! == EWOULDBLOCK) {
			$sentbytes = 0 unless defined $sentbytes;
		}

		if (defined($sentbytes)) {
			if ($sentbytes < $segment->{'length'}) { #sent incomplete message

				if ($sentbytes) {

					$log->info("sent incomplete chunk, requeuing " . ($segment->{'length'} - $sentbytes). " bytes");
				}

				$metaDataBytes{$httpClient} -= $segment->{'length'} - $sentbytes;

				$segment->{'length'} -= $sentbytes;
				$segment->{'offset'} += $sentbytes;

				unshift @{$outbuf{$httpClient}},$segment;
			}

		} else {

			$log->info("syswrite returned undef: $!");

			closeStreamingSocket($httpClient);

			return undef;
		}

	} else {
		$log->info("\$httpClient is: $httpClient");
		if (exists $peeraddr{$httpClient}) {
			$log->info("\$peeraddr{\$httpClient} is: $peeraddr{$httpClient}");
			$log->info("Got nothing for streaming data to $peeraddr{$httpClient}");
		} else {
			$log->info("\$peeraddr{\$httpClient} is undefined");
		}
		return 0;
	}

	if ($sentbytes) {

		$log->info("Streamed $sentbytes to $peeraddr{$httpClient}");
	}

	return $sentbytes;
}

sub tryStreamingLater {
	my $client     = shift;
	my $httpClient = shift;

	Slim::Networking::Select::addWrite($httpClient, \&sendStreamingResponse, 1);
}

sub nonBreaking {
	my $string = shift;

	$string =~ s/\s/\&nbsp;/g;

	return $string;
}

sub newSkinTemplate {
	my $skin = shift;

	my $baseSkin = baseSkin();

	my @include_path = ();
	my @skinParents  = ();
	my @preprocess   = qw(hreftemplate cmdwrappers);
	my $skinSettings = '';
	
	for my $rootDir (HTMLTemplateDirs()) {

		my $skinConfig = catfile($rootDir, $skin, 'skinconfig.yml');

		if (-r $skinConfig) {

			$skinSettings = eval { LoadFile($skinConfig) };

			if ($@) {
				logError("Could not load skin configuration file: $skinConfig\n$!");
			}

			last;
		}
	}

	if (ref($skinSettings) eq 'HASH') {

		for my $skinParent (@{$skinSettings->{'skinparents'}}) {

			if (my $checkedSkin = isaSkin($skinParent)) {

				next if $checkedSkin eq $skin;
				next if $checkedSkin eq $baseSkin;

				push @skinParents, $checkedSkin;
			}
		}
	}

	my %saw;
	my @dirs = ($skin, @skinParents, $baseSkin);
	foreach my $dir (grep(!$saw{$_}++, @dirs)) {

		foreach my $rootDir (HTMLTemplateDirs()) {

			my $skinDir = catdir($rootDir, $dir);

			if (-d $skinDir) {
				push @include_path, $skinDir;
			}
		}
	}
	
	if (ref($skinSettings) eq 'HASH' && ref $skinSettings->{'preprocess'} eq "ARRAY") {

		for my $checkfile (@{$skinSettings->{'preprocess'}}) {

			my $found = 0;

			DIRS: for my $checkdir (@include_path) {

				if (-r catfile($checkdir,$checkfile)) {

					push @preprocess, $checkfile;

					$found = 1;

					last DIRS;
				}
			}

			if (!$found) {
				$log->warn("$checkfile not found in include path, skipping");
			}
		}
	}

	$skinTemplates{$skin} = Template->new({

		INCLUDE_PATH => \@include_path,
		COMPILE_DIR => templateCacheDir(),
		PLUGIN_BASE => ['Slim::Plugin::TT',"HTML::$skin"],
		PRE_PROCESS => \@preprocess,
		FILTERS => {
			'string'        => \&Slim::Utils::Strings::string,
			'getstring'     => \&Slim::Utils::Strings::getString,
			'nbsp'          => \&nonBreaking,
			'uri'           => \&URI::Escape::uri_escape_utf8,
			'unuri'         => \&URI::Escape::uri_unescape,
			'utf8decode'    => \&Slim::Utils::Unicode::utf8decode,
			'utf8encode'    => \&Slim::Utils::Unicode::utf8encode,
			'utf8on'        => \&Slim::Utils::Unicode::utf8on,
			'utf8off'       => \&Slim::Utils::Unicode::utf8off,
		},

		EVAL_PERL => 1,
		ABSOLUTE  => 1,
	});

	return $skinTemplates{$skin};
}

sub templateCacheDir {

	return catdir( $prefs->get('cachedir'), 'templates' );
}

sub initSkinTemplateCache {
	%skinTemplates = ();
}

# Fills the template file specified as $path, using either the currently
# selected skin, or an override. Returns the filled template string
# these are all very similar

sub filltemplatefile {
	return _generateContentFromFile('fill', @_);
}

sub getStaticContent {
	return _generateContentFromFile('get', @_);
}

sub getFileInfoForStaticContent {
	return _generateContentFromFile('mtime', @_);
}

sub getStaticContentForTemplate {
	return ${_generateContentFromFile('get', @_)};
}

sub _generateContentFromFile {
	my ($type, $path, $params) = @_;

	my $skin = $params->{'skinOverride'} || $prefs->get('skin');

	# Default2 is gone, so redirect to Default.
	if ($skin =~ /^(?:Default2)$/i) {
		$skin = 'Default';
	}
	
	$log->info("generating from $path with type: $type");
	
	# Make sure we have a skin template for fixHttpPath to use.
	my $template = $skinTemplates{$skin} || newSkinTemplate($skin);

	if ($type eq 'fill') {

		my $output = '';

		# Always set the locale
		# The web display will always be UTF-8 for perl 5.8 systems,
		# while it will be in the current locale (likely an
		# iso-8859-*) for perl 5.6 systems.
		if ($] > 5.007) {

			$params->{'LOCALE'} = 'utf-8';

		} else {

			$params->{'LOCALE'} = Slim::Utils::Unicode::currentLocale() || 'iso-8859-1';
		}

		$path = fixHttpPath($skin, $path);

		if (!$template->process($path, $params, \$output)) {

			logError($template->error);
		}

		return \$output;
	}

	my ($content, $mtime, $inode, $size) = _getFileContent($path, $skin, 1, $type eq 'mtime' ? 1 : 0);

	if ($type eq 'mtime') {

		return ($mtime, $inode, $size);
	}

	# some callers want the mtime for last-modified
	if (wantarray()) {
		return ($content, $mtime, $inode, $size);
	} else {
		return $content;
	}
}

# Retrieves the file specified as $path, relative to the 
# INCLUDE_PATH of the given skin.
# Uses binmode to read file if $binary is specified.
# Returns a reference to the file data.

sub _getFileContent {
	my ($path, $skin, $binary, $statOnly) = @_;

	my ($content, $template, $mtime, $inode, $size);

	$path = fixHttpPath($skin, $path) || return;

	$log->info("Reading http file for ($path)");

	open($template, $path);


	if ($template) {
		($inode, $size, $mtime) = (stat($template))[1,7,9];
	}

	# If we only want the file attributes and not the content - close the
	# filehandle before slurping in the bits.
	if ($statOnly && $template) {

		close $template;

	} elsif ($template) {

		local $/ = undef;
		binmode($template) if $binary;
		$content = <$template>;
		close $template;

		if (!length($content) && $log->is_debug) {

			$log->debug("File empty: $path");
		}

	} else {

		logError("Couldn't open: $path");
	}
	
	return (\$content, $mtime, $inode, $size);
}

sub HTMLTemplateDirs {
	return @templateDirs;
}

# Finds the first occurance of a file specified by $path in the
# list of directories in the INCLUDE_PATH of the specified $skin

sub fixHttpPath {
	my $skin = shift;
	my $path = shift;

	my $template = $skinTemplates{$skin} || return undef;
	my $skindirs = $template->context()->{'CONFIG'}->{'INCLUDE_PATH'};

	my $lang     = lc($prefs->get('language'));

	for my $dir (@{$skindirs}) {

		my $fullpath = catdir($dir, $path);

		# We can have $file.$language files that need to be processed.
		my $langpath = join('.', $fullpath, $lang);
		my $found    = '';

		if ($lang ne 'en' && -f $langpath) {

			$found = $langpath;

		} elsif (-r $fullpath) {

			$found = $fullpath;
		}

		if ($found) {

			$log->info("Found path $found");

			return $found;
		}
	} 

	$log->info("Couldn't find path: $path");

	return undef;
}

sub buildStatusHeaders {
	my ($client, $response, $p) = @_;

	my %headers = ();
	
	if ($client) {

		# send headers
		%headers = ( 
			"x-player"		=> $client->id(),
			"x-playername"		=> $client->name(),
			"x-playertracks" 	=> Slim::Player::Playlist::count($client),
			"x-playershuffle" 	=> Slim::Player::Playlist::shuffle($client) ? "1" : "0",
			"x-playerrepeat" 	=> Slim::Player::Playlist::repeat($client),
		);
		
		if ($client->isPlayer()) {
	
			$headers{"x-playervolume"} = int($prefs->client($client)->get('volume') + 0.5);
			$headers{"x-playermode"}   = Slim::Buttons::Common::mode($client) eq "power" ? "off" : Slim::Player::Source::playmode($client);
	
			my $sleep = $client->sleepTime() - Time::HiRes::time();

			$headers{"x-playersleep"}  = $sleep < 0 ? 0 : int($sleep/60);
		}	
		
		if ($client && Slim::Player::Playlist::count($client)) { 

			my $track = Slim::Schema->rs('Track')->objectForUrl(Slim::Player::Playlist::song($client));
	
			$headers{"x-playertrack"} = Slim::Player::Playlist::url($client); 
			$headers{"x-playerindex"} = Slim::Player::Source::currentSongIndex($client) + 1;
			$headers{"x-playertime"}  = Slim::Player::Source::songTime($client);

			if (blessed($track) && $track->can('artist')) {

				my $i = $track->artist();
				$i = $i->name() if ($i);
				$headers{"x-playerartist"} = $i if $i;
		
				$i = $track->album();
				$i = $i->title() if ($i);
				$headers{"x-playeralbum"} = $i if $i;
		
				$i = $track->title();
				$headers{"x-playertitle"} = $i if $i;
		
				$i = $track->genre();
				$i = $i->name() if ($i);
				$headers{"x-playergenre"} = $i if $i;

				$i = $track->secs();				
				$headers{"x-playerduration"} = $i if $i;

				if ($track->coverArt()) {
					$headers{"x-playercoverart"} = "/music/" . $track->id() . "/cover.jpg";
				}
			}
		}
	}

	# include returned parameters if defined
	if (defined $p) {
		for (my $i = 0; $i < scalar @$p; $i++) {
	
			$headers{"x-p$i"} = $p->[$i];
		}
	}
	
	# simple quoted printable encoding
	while (my ($key, $value) = each %headers) {

		if (defined($value) && length($value)) {

			if ($] > 5.007 && Slim::Utils::Unicode::encodingFromString($value) ne 'ascii') {

				$value = Slim::Utils::Unicode::utf8encode($value, 'iso-8859-1');
				$value = encode_qp($value);
			}

			$response->header($key => $value);
		}
	}
}

sub forgetClient {
	my $client = shift;

	if (defined($client->streamingsocket)) {
		closeStreamingSocket($client->streamingsocket);
	}
}

sub closeHTTPSocket {
	my $httpClient = shift;
	my $streaming = shift;
	
	$log->info("Closing HTTP socket $httpClient with $peeraddr{$httpClient}");

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
	delete($lastSegLen{$httpClient}) if (defined $lastSegLen{$httpClient});
	
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
	if ($streaming && Slim::Utils::OSDetect::OS() eq 'win') {
		$httpClient->shutdown(2);
	}

	$httpClient->close();
	undef($httpClient);
	$connected--;
}

sub closeStreamingSocket {
	my $httpClient = shift;
	
	$log->info("Closing streaming socket.");
	
	if (defined $streamingFiles{$httpClient}) {

		$log->info("Closing streaming file.");

		close  $streamingFiles{$httpClient};
		delete $streamingFiles{$httpClient};
	}

	foreach my $client (Slim::Player::Client::clients()) {

		if (defined($client->streamingsocket) && $client->streamingsocket == $httpClient) {
			$client->streamingsocket(undef);
			
			# If this was a stream.mp3 client, auto-forget it
			# The playlist for this client will be maintained for the next
			# time they connect
			if ( $client->isa('Slim::Player::HTTP') ) {
				$log->info("Forgetting stream.mp3 client on disconnect");
				$client->forgetClient();
			}
		}
	}

	closeHTTPSocket($httpClient, 1);

	return;
}

sub checkAuthorization {
	my $username = shift;
	my $password = shift;

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

			my $salt = substr($pwd, 0, 2);
			$ok = 1 if crypt($password, $salt) eq $pwd;
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

sub addPageFunction {
	my ($regexp, $func) = @_;

	$log->info("Adding handler for regular expression /$regexp/");

	$pageFunctions{$regexp} = $func;
}

# addRawFunction
# adds a function to be called when the raw URI matches $regexp
# prototype: function($httpClient, $response), no return value
#            $response is a HTTP::Response object.
sub addRawFunction {
	my ($regexp, $funcPtr) = @_;

	my $funcName = Slim::Utils::PerlRunTime::realNameForCodeRef($funcPtr);
	$log->info("Adding RAW handler: /$regexp/ -> $funcName");

	$rawFunctions{$regexp} = $funcPtr;
}

# addCloseHandler
# defines a function to be called when $httpClient is closed
# prototype: func($httpClient), no return value
sub addCloseHandler{
	my $funcPtr = shift;
	
	my $funcName = Slim::Utils::PerlRunTime::realNameForCodeRef($funcPtr);
	$log->info("Adding Close handler: $funcName");
	
	push @closeHandlers, $funcPtr;
}
	

sub addTemplateDirectory {
	my $dir = shift;

	$log->info("Adding template directory $dir");

	push @templateDirs, $dir if (not grep({$_ eq $dir} @templateDirs));
}


# adds files for downloading via http
# defines a regexp to match the path for downloading a static file outside the http directory
#  $regexp is a regexp to match the request path
#  $file is the file location or a coderef to a function to return it (will be passed the path)
#  $ct is the mime content type, 'text' or 'binary', or a coderef to a function to return it
sub addRawDownload {
	my $regexp = shift || return;
	my $file   = shift || return;
	my $ct     = shift;

	if ($ct eq 'text') {
		$ct = 'text/plain';
	} elsif ($ct eq 'binary' || !$ct) {
		$ct = 'application/octet-stream';
	}

	$rawFiles{$regexp} = {
		'file' => $file,
		'ct'   => $ct,
	};

	my $str = join('|', keys %rawFiles);
	$rawFilesRegexp = qr/$str/;
}


# remove files for downloading via http
sub removeRawDownload {
	my $regexp = shift;
   
	delete $rawFiles{$regexp};
	my $str = join('|', keys %rawFiles);
	$rawFilesRegexp = qr/$str/;
}


# makePageToken: anti-CSRF token at the page level, e.g. token to
# protect use of /settings/server/basic.html
sub makePageToken {
	my $req = shift;
	my $secret = $prefs->get('securitySecret');
	if ( (!defined($secret)) || ($secret !~ m|^[0-9a-f]{32}$|) ) {
		# invalid secret!
		# Prefs.pm should have set this!
		$log->warn("Server unable to verify CRSF auth code due to missing or invalid securitySecret server pref");
		return '';
	}
	# make hash of URI & secret
	# BUG: for CSRF protection level "high", perhaps there should be additional data used for this
	my $uri = Slim::Utils::Misc::unescape($req->uri());
	# strip the querystring, if any
	$uri =~ s/\?.*$//;
	my $hash = Digest::MD5->new;
	# hash based on server secret and URI
	$hash->add($uri);
	$hash->add($secret);
	return $hash->hexdigest();
}

sub isCsrfAuthCodeValid {
	
	my ($req,$params,$providedPageAntiCSRFToken) = @_;
	my $csrfProtectionLevel = $prefs->get('csrfProtectionLevel');

	if (! defined($csrfProtectionLevel) ) {

		# Prefs.pm should have set this!
		$log->warn("Warning: Server unable to determine CRSF protection level due to missing server pref");

		return 0;
	}

	# no protection, so we don't care
	return 1 if ( !$csrfProtectionLevel);

	my $uri  = $req->uri();
	my $code = $req->header("X-Slim-CSRF");

	if ( ! defined($uri) ) {
		return 0;
	}

	my $secret = $prefs->get('securitySecret');

	if ( (!defined($secret)) || ($secret !~ m|^[0-9a-f]{32}$|) ) {

		# invalid secret!
		$log->warn("Server unable to verify CRSF auth code due to missing or invalid securitySecret server pref");

		return 0;
	}

	my $expectedCode = $secret;

	# calculate what the auth code should look like
	my $highHash   = Digest::MD5->new;
	my $mediumHash = Digest::MD5->new;

	# only the "HIGH" cauth code depends on the URI
	$highHash->add($uri);

	# both "HIGH" and "MEDIUM" depend on the securitySecret
	$highHash->add($secret);
	$mediumHash->add($secret);

	# a "HIGH" hash is always accepted
	return 1 if ( defined($code) && ($code eq $highHash->hexdigest()) );

	if ( $csrfProtectionLevel == 1 ) {

		# at "MEDIUM" level, we'll take the $mediumHash, too
		return 1 if ( defined($code) && ($code eq $mediumHash->hexdigest()) );
	}

	# how about a simple page token?
	if ( defined($providedPageAntiCSRFToken) ) {
		if ( &makePageToken($req) eq $providedPageAntiCSRFToken ) {
			return 1;
		}
	} 

	# the code is no good (invalid or MEDIUM hash presented when using HIGH protection)!
	return 0;

}

sub isRequestCSRFSafe {
	
	my ($request,$response,$params,$providedPageAntiCSRFToken) = @_;
	my $rc = 0;

	# XmlHttpRequest test for all the AJAX code in 7.x
	if ($request->header('X-Requested-With') && ($request->header('X-Requested-With') eq 'XMLHttpRequest') ) {
		# good enough
		return 1;
	}

	# referer test from SqueezeCenter 5.4.0 code

	if ($request->header('Referer') && defined($request->header('Referer')) && defined($request->header('Host')) ) {

		my ($host, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($request->header('Referer'));

		# if the Host request header lists no port, crackURL() reports it as port 80, so we should
		# pretend the Host header specified port 80 if it did not

		my $hostHeader = $request->header('Host');

		if ($hostHeader !~ m/:\d{1,}$/ ) { $hostHeader .= ":80"; }

		if ("$host:$port" ne $hostHeader) {

			if ( $log->is_warn ) {
				$log->warn("Invalid referer: [" . join(' ', ($request->method, $request->uri)) . "]");
			}

		} else {

			# looks good
			$rc = 1;
		}

	}

	if ( ! $rc ) {

		# need to also check if there's a valid "cauth" token
		if ( ! isCsrfAuthCodeValid($request,$params,$providedPageAntiCSRFToken) ) {

			$params->{'suggestion'} = "Invalid referrer and no valid cauth code.";

			if ( $log->is_warn ) {
				$log->warn("No valid CSRF auth code: [" . 
					join(' ', ($request->method, $request->uri, $request->header('X-Slim-CSRF')))
				. "]");
			}

		} else {

			# looks good
			$rc = 1;
		}
	}

	return $rc;
}

sub makeAuthorizedURI {

	my ($uri,$queryWithArgs) = @_;
	my $secret = $prefs->get('securitySecret');

	if ( (!defined($secret)) || ($secret !~ m|^[0-9a-f]{32}$|) ) {

		# invalid secret!
		$log->warn("Server unable to compute CRSF auth code URL due to missing or invalid securitySecret server pref");

		return undef;
	}

	my $csrfProtectionLevel = $prefs->get('csrfProtectionLevel');

	if (! defined($csrfProtectionLevel) ) {

		# Prefs.pm should have set this!
		$log->warn("Server unable to determine CRSF protection level due to missing server pref");

		return 0;
	}

	my $hash = Digest::MD5->new;

	if ( $csrfProtectionLevel == 2 ) {

		# different code for each different URI
		$hash->add($queryWithArgs);
	}

	$hash->add($secret);

	return $queryWithArgs . ';cauth=' . $hash->hexdigest();
}

sub throwCSRFError {

	my ($httpClient,$request,$response,$params,$queryWithArgs) = @_;

	# throw 403, we don't this from non-server pages
	# unless valid "cauth" token is present
	$params->{'suggestion'} = "Invalid Referer and no valid CSRF auth code.";

	my $protoHostPort = 'http://' . $request->header('Host');
	my $authURI = makeAuthorizedURI($request->uri(),$queryWithArgs);
	my $authURL = $protoHostPort . $authURI;

	# add a long SGML comment so Internet Explorer displays the page
	my $msg = "<!--" . ( '.' x 500 ) . "-->\n<p>";

	$msg .= string('CSRF_ERROR_INFO'); 
	$msg .= "<br>\n<br>\n<A HREF=\"${authURI}\">${authURL}</A></p>";
	
	my $csrfProtectionLevel = $prefs->get('csrfProtectionLevel');
	
	if ( defined($csrfProtectionLevel) && $csrfProtectionLevel == 1 ) {
		$msg .= string('CSRF_ERROR_MEDIUM');
	}
	
	$params->{'validURL'} = $msg;
	
	# add the appropriate URL in a response header to make automated
	# re-requests easy? (WARNING: this creates a potential Cross Site
	# Tracing sort of vulnerability!

	# (see http://computercops.biz/article2165.html for info on XST)
	# If you enable this, also uncomment the text regarding this on the http.html docs
	#$response->header('X-Slim-Auth-URI' => $authURI);
	
	$response->code(RC_FORBIDDEN);
	$response->content_type('text/html');
	$response->header('Connection' => 'close');
	$response->content_ref(filltemplatefile('html/errors/403.html', $params));

	$httpClient->send_response($response);
	closeHTTPSocket($httpClient);	
}

# CSRF: allow code to indicate it needs protection
#
# The HTML template for protected actions needs to embed an anti-CSRF token. The easiest way
# to do that is include the following once inside each <form>:
# 	<input type="hidden" name="pageAntiCSRFToken" value="[% pageAntiCSRFToken %]">
#
# To protect the settings within the module that handles that page, use the "protect" APIs:
# sub name {
# 	return Slim::Web::HTTP::protectName('BASIC_SERVER_SETTINGS');
# }
# sub page {
# 	Slim::Web::HTTP::protectURI('settings/server/basic.html');
# }
#
# protectURI: takes the same string that a function's page() method returns
sub protectURI {
	my $uri = shift;
	my $regexp = "/${uri}\\b.*\\=";
	$dangerousCommands{$regexp} = 1;
	return $uri;
}
# protectName: takes the same string that a function's name() method returns
sub protectName {
	my $name = shift;
	my $regexp = "\\bpage=${name}\\b";
	$dangerousCommands{$regexp} = 1;
	return $name;
}
#
# normal SqueezeCenter commands can be accessed with URLs like
#   http://localhost:9000/status.html?p0=pause&player=00%3A00%3A00%3A00%3A00%3A00
#   http://localhost:9000/status.html?command=pause&player=00%3A00%3A00%3A00%3A00%3A00
# Use the protectCommand() API to prevent CSRF attacks on commands -- including commands
# not intended for use via the web interface!
#
# protectCommand: takes an array of commands, e.g.
# protectCommand('play')			# protect any command with 'play' as the first command
# protectCommand('playlist', ['add', 'delete'])	# protect the "playlist add" and "playlist delete" commands
# protectCommand('mixer','volume','\d{1,}');	# protect changing the volume (3rd arg has digit) but allow "?" query in 3rd pos
sub protectCommand {
	my @commands = @_;
	my $regexp = '';
	for (my $pos = 0; $pos < scalar(@commands); ++$pos) {
		my $rePart;
		if ( ref($commands[$pos]) eq 'ARRAY' ) {
			$rePart = '\b(';
			my $add = '';
			foreach my $c ( @{$commands[$pos]} ) {
				$rePart .= "${add}p${pos}=$c\\b";
				$add = '|';
			}
			$rePart .= ')';
		} else {
			$rePart = "\\bp${pos}=$commands[$pos]\\b";
		}
		$regexp .= "${rePart}.*?";
	}
	$dangerousCommands{$regexp} = 1;
}
# protect: takes an exact regexp, in case you need more fine-grained protection
#
# Example querystring for server settings:
# /status.html?audiodir=/music&language=EN&page=BASIC_SERVER_SETTINGS&playlistdir=/playlists&rescan=&rescantype=1rescan&saveSettings=Save Settings&useAJAX=1&
sub protect {
	my $regexp = shift;
	$dangerousCommands{$regexp} = 1;
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
