package Slim::Web::HTTP;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Digest::MD5;
use FileHandle;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);
use HTTP::Daemon;
use HTTP::Status;
use MIME::Base64;
use HTML::Entities;
use Socket qw(:DEFAULT :crlf);
use Sys::Hostname;
use Template;
use Tie::RegexpHash;
use URI::Escape;
use Slim::Networking::mDNS;
use Slim::Networking::Select;
use Slim::Player::HTTP;
use Slim::Music::Info;

use Slim::Web::EditPlaylist;
use Slim::Web::History;
use Slim::Web::Pages;

use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);

# constants
BEGIN {
	if ($^O =~ /Win32/) {
		*EWOULDBLOCK = sub () { 10035 };
		*EINPROGRESS = sub () { 10036 };
	} else {
		require Errno;
		import Errno qw(EWOULDBLOCK EINPROGRESS);
	}

	if ($] > 5.007) {
		require Encode;
	}
}

use constant defaultSkin => 'Default';
use constant baseSkin	 => 'EN';
use constant HALFYEAR	 => 60 * 60 * 24 * 180;

use constant METADATAINTERVAL => 32768;
use constant MAXCHUNKSIZE     => 32768;
use constant RETRY_TIME	      => 0.05;

use constant MAXKEEPALIVES    => 30;
use constant KEEPALIVETIMEOUT => 10;

# Package variables

our %templatefiles = ();

my $openedport = 0;
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

my $mdnsIDslimserver;
my $mdnsIDhttp;

our @templateDirs = ();

our %pageFunctions = ();
tie %pageFunctions, 'Tie::RegexpHash';

our %dangerousCommands = (
	# name of command => regexp for URI patterns that make it dangerous
	# e.g.
	#	\&Slim::Web::Pages::status => '\bp0=rescan\b'
	# means inisist on CSRF protection for the status command *only*
	# if the URL includes p0=rescan
	\&Slim::Web::Setup::setup_HTTP => '.',
	\&Slim::Web::EditPlaylist::editplaylist => '.',
	\&Slim::Web::Pages::status => '(p0=debug|p0=pause|p0=stop|p0=play|p0=sleep|p0=playlist|p0=mixer|p0=display|p0=button|p0=rescan|(p0=(|player)pref\b.*p2=[^\?]|p2=[^\?].*p0=(|player)pref))',
);

# initialize the http server
sub init {

	if (Slim::Utils::OSDetect::OS() eq 'mac') {
		push @templateDirs, $ENV{'HOME'} . "/Library/SlimDevices/html/";
		push @templateDirs, "/Library/SlimDevices/html/";
	}

	push @templateDirs, catdir($Bin, 'HTML');

	#
	%pageFunctions = (
		qr/^$/				=> \&Slim::Web::Pages::home,
		qr/^index\.(?:htm|xml)/		=> \&Slim::Web::Pages::home,
		qr/^browseid3\.(?:htm|xml)/	=> \&Slim::Web::Pages::browseid3,
		qr/^browsedb\.(?:htm|xml)/	=> \&Slim::Web::Pages::browsedb,
		qr/^browse\.(?:htm|xml)/	=> \&Slim::Web::Pages::browser,
		qr/^edit_playlist\.(?:htm|xml)/	=> \&Slim::Web::EditPlaylist::editplaylist,  # Needs to be before playlist
		qr/^firmware\.(?:html|xml)/	=> \&Slim::Web::Pages::firmware,
		qr/^hitlist\.(?:htm|xml)/	=> \&Slim::Web::History::hitlist,
		qr/^home\.(?:htm|xml)/		=> \&Slim::Web::Pages::home,
		qr/^playlist\.(?:htm|xml)/	=> \&Slim::Web::Pages::playlist,
		qr/^search\.(?:htm|xml)/	=> \&Slim::Web::Pages::search,
		qr/^advanced_search\.(?:htm|xml)/ => \&Slim::Web::Pages::advancedSearch,
		qr/^songinfo\.(?:htm|xml)/	=> \&Slim::Web::Pages::songInfo,
		qr/^status_header\.(?:htm|xml)/	=> \&Slim::Web::Pages::status_header,
		qr/^status\.(?:htm|xml)/	=> \&Slim::Web::Pages::status,
		qr/^setup\.(?:htm|xml)/		=> \&Slim::Web::Setup::setup_HTTP,
		qr/^update_firmware\.(?:htm|xml)/ => \&Slim::Web::Pages::update_firmware,
		qr/^livesearch\.(?:htm|xml)/    => \&Slim::Web::Pages::livesearch,
	);

	# pull in the memory usage module if requested.
	if ($::d_memory) {

		eval "use Slim::Utils::MemoryUsage";

		if ($@) {
			print "Couldn't load Slim::Utils::MemoryUsage - error: [$@]\n";
		} else {
			$pageFunctions{qr/^memoryusage\.html.*/} = \&Slim::Web::Pages::memory_usage;
		}
	}

	# Try and use the faster XS module if it's available.
	eval { require Template::Stash::XS };

	if ($@) {

		# Pure perl is the default, so we don't need to do anything.
		$::d_http && msg("Couldn't find Template::Stash::XS - falling back to pure perl version.\n");

	} else {

		$::d_http && msg("Found Template::Stash::XS!\n");

		$Template::Config::STASH = 'Template::Stash::XS';
	}

	# this initializes the %fieldInfo structure
	Slim::Web::Pages::init();

	idle();
}

# other people call us externally.
*escape   = \&URI::Escape::uri_escape_utf8;

# don't use the external one because it doesn't know about the difference between a param and not...
#*unescape = \&URI::Escape::unescape;
sub unescape {
	my $in      = shift;
	my $isParam = shift;

	$in =~ s/\+/ /g if $isParam;
	$in =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

	return $in;
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

	) or die "can't setup the listening port $listenerport for the HTTP server: $!";
	
	defined(Slim::Utils::Misc::blocking($http_server_socket,0)) || die "Cannot set port nonblocking";

	$openedport = $listenerport;
	Slim::Networking::Select::addRead($http_server_socket, \&acceptHTTP);
	
	$::d_http && msg("Server $0 accepting http connections on port $listenerport\n");
	
	$mdnsIDhttp = Slim::Networking::mDNS::advertise(Slim::Utils::Prefs::get('mDNSname'), '_http._tcp', $listenerport);
	$mdnsIDslimserver = Slim::Networking::mDNS::advertise(Slim::Utils::Prefs::get('mDNSname'), '_slimhttp._tcp', $openedport);
}

sub checkHTTP {

	# check to see if our HTTP port has changed, and return if we haven't
	if ($openedport == Slim::Utils::Prefs::get('httpport')) {
		return;
	}

	# if we've already opened a socket, let's close it
	if ($openedport) {

		if ($mdnsIDslimserver) { Slim::Networking::mDNS::stopAdvertise($mdnsIDslimserver); };
		if ($mdnsIDhttp) { Slim::Networking::mDNS::stopAdvertise($mdnsIDhttp); };
		
		$::d_http && msg("closing http server socket\n");
		Slim::Networking::Select::addRead($http_server_socket, undef);
		$http_server_socket->close();
		undef($http_server_socket);
		$openedport = 0;
	}

	# if we've got an HTTP port specified, open it up!
	if (Slim::Utils::Prefs::get('httpport')) {
		Slim::Web::HTTP::openport(Slim::Utils::Prefs::get('httpport'), $::httpaddr, $Bin);
	}
}

# TODO: Turn this back on
#		my $tcpReadMaximum = Slim::Utils::Prefs::get("tcpReadMaximum");
#		my $streamWriteMaximum = Slim::Utils::Prefs::get("tcpWriteMaximum");

sub idle {
	# check to see if the HTTP settings have changed
	checkHTTP();
}

sub connectedSocket {
	return $connected;
}

sub acceptHTTP {
	# try and pull the handle
	my $httpClient = $http_server_socket->accept() || do {
		$::d_http && msg("Did not accept connection, accept returned nothing\n");
		return;
	};

	defined(Slim::Utils::Misc::blocking($httpClient,0)) || die "Cannot set port nonblocking";
	
	binmode($httpClient);
	
	my $peer = $httpClient->peeraddr();

	if ($httpClient->connected() && $peer) {

		$peer = inet_ntoa($peer);

		# Check if source address is valid
		if (!(Slim::Utils::Prefs::get('filterHosts')) ||
		     (Slim::Utils::Misc::isAllowedHost($peer))) {

			# this is the timeout for the client connection.
			$httpClient->timeout(KEEPALIVETIMEOUT);

			$peeraddr{$httpClient} = $peer;
			Slim::Networking::Select::addRead($httpClient, \&processHTTP);
			Slim::Networking::Select::addError($httpClient, \&closeStreamingSocket);
			$connected++;
			$::d_http && msg("Accepted connection $connected from ". $peeraddr{$httpClient} . "\n");

		} else {

			$::d_http && msg("Did not accept HTTP connection from $peer, unauthorized source\n");
			$httpClient->close();
			undef($httpClient);
		}

	} else {

		$::d_http && msg("Did not accept connection, couldn't get peer addr\n");
	}
}

sub isaSkin {
	my $name = shift;
	my %skins = Slim::Web::Setup::skins();
	for my $skin (keys %skins) {
		return $skin if $name =~ /^($skin)$/i;
	}
	return undef;
}

# Handle an HTTP request
sub processHTTP {
	my $httpClient = shift || return;

	my $params     = {};
	my $request    = $httpClient->get_request();
	$::d_http && msg("reading request...\n");

	# socket half-closed from client
	if (!defined $request) {
		$::d_http && msg("Client at " . $peeraddr{$httpClient} . " disconnected. (half-closed)\n\n");

		closeHTTPSocket($httpClient);
		return;
	}

	$::d_http && msg(
		"HTTP request: from " . $peeraddr{$httpClient} . " ($httpClient) for " .
		join(' ', ($request->method(), $request->protocol(), $request->uri()), "\n")
	);

	# remove our special X-Slim-CSRF header if present
	$request->remove_header("X-Slim-CSRF");

	# store CSRF auth code in fake request header if present
	if (defined($request->uri()) && ($request->uri() =~ m|^(.*)\;cauth\=([0-9a-f]{32})$|) ) {
		my $plainURI = $1;
		my $csrfAuth = $2;
		$::d_http && msg("Found CSRF auth token \"$csrfAuth\" in URI \"".$request->uri()."\", so resetting request URI to \"$plainURI\"\n");
		# change the URI so later code doesn't "see" the cauth part
		$request->uri($plainURI);
		# store the cauth code in the request object (headers are handy!)
		$request->push_header("X-Slim-CSRF",$csrfAuth);
	}

	# this bundles up all our response headers and content
	my $response = HTTP::Response->new();

	# respond in kind.
	$response->protocol($request->protocol());
	$response->request($request);

	if ($::d_http_verbose) {
		msg("Request Headers: [\n" . $request->as_string() . "]\n");
	}

	if ($request->method() eq 'GET' || $request->method() eq 'HEAD') {

		$sendMetaData{$httpClient} = 0;
		
		if ($request->header('Icy-MetaData')) {
			$sendMetaData{$httpClient} = 1;
		}
		
		# authorization header.
		my $authorized = !Slim::Utils::Prefs::get('authorize');

		if (my ($user, $pass) = $request->authorization_basic()) {
			$authorized = checkAuthorization($user, $pass);
		}

		# no Valid authorization supplied!
		if (!$authorized) {

			$response->code(RC_UNAUTHORIZED);
			$response->header('Connection' => 'close');
			$response->content_type('text/html');
			$response->content_ref(filltemplatefile('html/errors/401.html', $params));
			$response->www_authenticate(sprintf('Basic realm="%s"', string('SLIMSERVER')));

			$httpClient->send_response($response);
			closeHTTPSocket($httpClient);
			return;
		}

		# parse out URI:
		my $uri   = $request->uri();
		my $path  = $uri->path();
		my $query = $uri->query();
		$params->{url_query} = $query;

		# XXX - unfortunately slimserver uses a query form
		# that can have a key without a value, yet it's
		# differnet from a key with an empty value. So we have
		# to parse out like this.
		if ($query) {

			foreach my $param (split /\&/, $query) {

				if ($param =~ /([^=]+)=(.*)/) {

					my $name  = unescape($1, 1);
					my $value = unescape($2, 1);

					# We need to turn perl's internal
					# representation of the unescaped
					# UTF-8 string into a "real" UTF-8
					# string with the appropriate magic set.
					if ($value ne '*' && $value ne '' && $] > 5.007) {

						$value = eval { Encode::decode_utf8($value) } || $value;
					}

					$params->{$name} = $value;

					$::d_http && msg("HTTP parameter $name = $value\n");

				} else {

					my $name = unescape($param, 1);

					$params->{$name} = 1;

					$::d_http && msg("HTTP parameter from $name = 1\n");
				}
			}
		}

		# 
		if ($path) {

			$params->{'webroot'} = '/';

			if ($path =~ s{^/slimserver/}{/}i) {
				$params->{'webroot'} = "/slimserver/"
			}
			
			if ($path =~ m|/([a-zA-Z0-9]+)$| && isaSkin($1)) {
					$::d_http && msg("Alternate skin $1 requested, redirecting to $uri/ append a slash.\n");
					$response->code(RC_MOVED_PERMANENTLY);
					$response->header('Location' => $uri . '/');
					$httpClient->send_response($response);
					closeHTTPSocket($httpClient);
					return;
			} elsif ($path =~ m|^/(.+?)/.*| && $path !~ m{^/(?:html|music|plugins)/}i) {

				my $desiredskin = $1;

				# Requesting a specific skin, verify and set the skinOverride param
				$::d_http && msg("Alternate skin $desiredskin requested\n");

				my $skinname = isaSkin($desiredskin);
				
				if ($skinname) {
					$::d_http && msg("Rendering using $skinname\n");
					$params->{'skinOverride'} = $skinname;
					$params->{'webroot'} = $params->{'webroot'} . "$skinname/";
					$path =~ s{^/.+?/}{/};
				} else {
					# we can either throw a 404 here or just ignore the requested skin
					
					# ignore: commented out
					# $path =~ s{^/.+?/}{/};
					
					# throw 404
					$params->{'suggestion'} = qq(There is no "$desiredskin")
						. qq( skin, try ) . HomeURL() . qq( instead.);
					$::d_http && msg("Invalid skin requested: [" . join(' ', ($request->method(), $request->uri())) . "]\n");
			
					$response->code(RC_NOT_FOUND);
					$response->content_type('text/html');
					$response->header('Connection' => 'close');
					$response->content_ref(filltemplatefile('html/errors/404.html', $params));
			
					$httpClient->send_response($response);
					closeHTTPSocket($httpClient);
					return;
				}
			}

			$path =~ s|^/+||;
			$params->{"path"} = unescape($path);
			$params->{"host"} = $request->header('Host');
		}

		# apply CSRF protection logic to "dangerous" commands
		foreach my $d ( keys %dangerousCommands ) {

			my $dregexp = $dangerousCommands{$d};

			if ($params->{"path"} && $pageFunctions{$params->{"path"}} && $pageFunctions{$params->{"path"}} eq $d && $request->uri() =~ m|$dregexp| ) {

				if ( ! isRequestCSRFSafe($request,$response) ) {

					$::d_http && msg("client requested dangerous function/arguments and failed CSRF Referer/token test, sending 403 denial\n");
					throwCSRFError($httpClient,$request,$response,$params);
					return;

				}
			}
		}

		# HTTP/1.1 Persistent connections or HTTP 1.0 Keep-Alives
		# XXX - MAXKEEPALIVES should be a preference
		if (defined $keepAlives{$httpClient} && $keepAlives{$httpClient} >= MAXKEEPALIVES) {

			# This will close the client socket & remove the
			# counter in sendResponse()
			$response->header('Connection' => 'close');
			$::d_http && msg("Hit MAXKEEPALIVES, will close connection.\n");

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
		# process the commands
		processURL($httpClient, $response, $params);

	} else {

		$::d_http && msg("Bad Request: [" . join(' ', ($request->method(), $request->uri())) . "]\n");

		$response->code(RC_METHOD_NOT_ALLOWED);
		$response->header('Connection' => 'close');
		$response->content_type('text/html');
		$response->content_ref(filltemplatefile('html/errors/405.html', $params));

		$httpClient->send_response($response);
		closeHTTPSocket($httpClient);
	}

	# what does our response look like?
	if ($::d_http_verbose) {
		$response->content("");
		msg("Response Headers: [\n" . $response->as_string() . "]\n");
	}

	$::d_http && msg(
		"End request: keepAlive: [" .
		($keepAlives{$httpClient} || '') .
		"] - waiting for next request on connection = " . ($response->header('Connection') || '') . "\n\n"
	);
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
	# This example jumps to the second song in the playlist and sends a playlist as the response
	#
	# If there are multiple players, then they are specified by the player id
	#   For example:
	#		http://host/status.html?p0=mixer&p1=volume&p2=11&player=10.0.1.203:69

	for (my $i = 0; $i <= scalar keys %{$params}; $i++) {
		last unless defined $params->{"p$i"};
		$p[$i] = $params->{"p$i"};
	}

	# This is trumped by query parameters 'command' and 'sub'.
	# These are passed as the first two command parameters (p0 and p1), 
	# while the rest of the query parameters are passed as third (p3).
	if (defined $params->{'command'}) {
		$p[0] = $params->{'command'};
		$p[1] = $params->{'sub'};
		$p[2] = join '&', map $_ . '=' . $params->{$_},  keys %{$params};
	}

	$::d_http && msg("processURL Clients: " . join(" ", Slim::Player::Client::clientIPs()) . "\n");

	# explicitly specified player (for web browsers or squeezeboxen)
	if (defined($params->{"player"})) {
		$client = Slim::Player::Client::getClient($params->{"player"});
	}

	# is this an HTTP stream?
	if (!defined($client) && ($path =~ /(?:stream\.mp3|stream)$/)) {
	
		my $address = $peeraddr{$httpClient};
	
		$::d_http && msg("processURL found HTTP client at address=$address\n");
	
		$client = Slim::Player::Client::getClient($address);
		
		if (!defined($client)) {

			my $paddr = getpeername($httpClient);
			$::d_http && msg ("new http client at $address\n");

			if ($paddr) {
				$client = Slim::Player::HTTP->new($address, $paddr, $httpClient);
				$client->init();
			}
		}

		if (defined($params->{'bitrate'})) {
			# must validate 32 40 48 56 64 80 96 112 128 160 192 224 256 320 CBR
			#set to the closest lower value of its not a match
			my $temprate = $params->{'bitrate'};

			foreach my $i (320, 256, 244, 192, 160, 128, 112, 96, 80, 64, 56, 48, 40, 32) {
				$temprate = $i; 	 
				last if ($i <= $params->{'bitrate'}); 	 
			}

			Slim::Utils::Prefs::clientSet($client,'transcodeBitrate',$temprate); 	 
			$::d_http && msg("Setting transcode bitrate to $temprate\n"); 	 

		} else {
				Slim::Utils::Prefs::clientSet($client,'transcodeBitrate',undef);
		}
	}

	# if we don't have a player specified, just pick one if there is one...
	if (!defined($client) && Slim::Player::Client::clientCount() > 0) {
		$client = (Slim::Player::Client::clients())[0];
	}

	$peerclient{$httpClient} = $client;

	if ($client && $client->isa("Slim::Player::SLIMP3")) {

		$params->{'playermodel'} = 'slimp3';
	} else {
		$params->{'playermodel'} = 'squeezebox';
	}

	my @callbackargs = ($client, $httpClient, $response, $params);

	# only execute a command on the client if there is one and if we have a command.
	if (defined($client) && defined($p[0])) {

		if (defined($params->{"player"}) && $params->{"player"} eq "*") {

			for my $client2 (Slim::Player::Client::clients()) {
				next if $client eq $client2;
				Slim::Control::Command::execute($client2, \@p);
			}
		}

		Slim::Control::Command::execute($client, \@p, \&generateHTTPResponse, \@callbackargs);

	} else {

		generateHTTPResponse(@callbackargs);
	}
}

=pod

=HEAD1 Send the response to the client

=cut

sub generateHTTPResponse {
	my ($client, $httpClient, $response, $params) = @_;

	# this is a scalar ref because of the potential size of the body.
	# not sure if it actually speeds things up considerably.
	my ($body, $mtime); 

	# default to 200
	$response->code(RC_OK);

	$params->{'player'} = '';
	$params->{'nosetup'} = 1   if $::nosetup;
	$params->{'noserver'} = 1   if $::noserver;

	my $path = $params->{"path"};
	my $type = Slim::Music::Info::typeFromSuffix($path, 'htm');

	# lots of people need this
	my $contentType = $params->{'Content-Type'} = $Slim::Music::Info::types{$type};

	# setup our defaults
	$response->content_type($contentType);
	$response->expires(0);

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

	$::d_http && msg("Generating response for ($type, $contentType) $path\n");

	# some generally useful form details...
	if (defined($client)) {
		$params->{'player'} = $client->id();
		$params->{'myClientState'} = $client;
	}

	# this might do well to break up into methods
	if ($contentType =~ /image/) {

		# images should expire from cache one year from now
		$response->expires(time() + HALFYEAR);
		$response->header('Cache-Control' => sprintf('public; max-age=%d', HALFYEAR));
	}

	if ($contentType =~ /text/) {
		$params->{'params'} = {};
		filltemplatefile('include.html', $params);

		while (my ($key,$value) = each %{$params->{'params'}}) {
			$params->{$key} = $value;
		}

		delete $params->{'params'};
	}

	if (ref($pageFunctions{$path}) eq 'CODE') {

		# if we match one of the page functions as defined above,
		# execute that, and hand it a callback to send the data.
		$body = &{$pageFunctions{$path}}(
			$client,
			$params,
			\&prepareResponseForSending,
			$httpClient,
			$response,
		);

	} elsif ($path =~ /^(?:stream\.mp3|stream)$/o) {

		# short circuit here if it's a slim/squeezebox
		if ($sendMetaData{$httpClient}) {
			$response->header("icy-metaint" => METADATAINTERVAL);
			$response->header("icy-name"    => string('WELCOME_TO_SLIMSERVER'));
		}

		my $headers = _stringifyHeaders($response) . $CRLF;

		$metaDataBytes{$httpClient} = - length($headers);

		addStreamingResponse($httpClient, $headers, $params);

		return 0;

	} elsif ($path =~ /music\/(\w+)\/(cover|thumb)\.jpg$/) {

		my ($obj, $imageData);
		my $image = $2;
		my $ds    = Slim::Music::Info::getCurrentDataStore();
		
		if ($1 eq "current" && defined $client) {

			$obj  = $ds->objectForUrl(Slim::Utils::Misc::fileURLFromPath(
				Slim::Player::Playlist::song($client)
			)) || return 0;

		} else {

			$obj = $ds->objectForId('track', $1);
		}

		$::d_http && msg("Cover Art asking for: $image\n");

		if ($obj) {
			($imageData, $contentType, $mtime) = $obj->coverArt($image);
		}

		if (defined($imageData)) {

			$body = \$imageData;

		} else {

			($body, $mtime) = getStaticContent("html/images/cover.png");
			$contentType = "image/png";
		}

	} elsif ($path =~ /music\/(.+)$/) {

		my $file = Slim::Utils::Misc::virtualToAbsolute($1);

		if (Slim::Music::Info::isSong($file) && Slim::Music::Info::isFile($file)) {

			$::d_http && msg("Opening $file to stream...\n");

			my $songHandle =  FileHandle->new(Slim::Utils::Misc::pathFromFileURL($file));

			if ($songHandle) {

				my $ds  = Slim::Music::Info::getCurrentDataStore();
				my $obj = $ds->objectForUrl($file);

				$response->content_type(Slim::Music::Info::mimeType($file));
				$response->content_length($obj->filesize());

				my $headers = _stringifyHeaders($response) . $CRLF;

				$streamingFiles{$httpClient} = $songHandle;

				addStreamingResponse($httpClient, $headers, $params);

				return 0;
			}
		}

	} elsif ($path =~ /favicon\.ico/) {

		($body, $mtime) = getStaticContent("html/mypage.ico", $params); 

	} elsif ($path =~ /slimserver\.css/) {

		($body, $mtime) = getStaticContent($path, $params);

	} elsif ($path =~ /status\.txt/ || $path =~ /log\.txt/) {

		# if the HTTP client has asked for a text file, then always return the text on the display
		$contentType = "text/plain";

		$response->header("Refresh" => "30; url=$path");

		if ($path =~ /status/) {

			my ($line1, $line2) = Slim::Display::Display::curLines($client);
			$line1 = '' if (!defined($line1));
			$line2 = '' if (!defined($line2));
			$$body = $line1 . $CRLF . $line2 . $CRLF;

		} else {

			$$body = $Slim::Utils::Misc::log;

		}

	} elsif ($path =~ /status\.m3u/) {

		# if the HTTP client has asked for a .m3u file, then always return the current playlist as an M3U
		if (defined($client)) {

			my $count = Slim::Player::Playlist::count($client) && do {
				$$body = Slim::Formats::Parse::writeM3U(\@{Slim::Player::Playlist::playList($client)});
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

			# otherwise just send back the binary file
			($body, $mtime) = getStaticContent($path, $params);
		}

	} else {
		# who knows why we're here, we just know that something ain't right
		$$body = undef;
	}

	# if there's a reference to an empty value, then there is no valid page at all
	if (defined $body && !defined $$body) {

		$response->code(RC_NOT_FOUND);
		$body = filltemplatefile('html/errors/404.html', $params);
	}

	return 0 unless $body;

	# for our static content
	$response->last_modified($mtime) if defined $mtime;

	# If we're perl 5.8 or above, always send back utf-8
	# Otherwise, send back the charset from the current locale
	if ($contentType =~ m!^text/(?:html|xml)!) {

		if ($] > 5.007) {
			$contentType .= '; charset=utf-8';
		} else {
			$contentType .= "; charset=$Slim::Utils::Misc::locale";
		}
	}

	$response->content_type($contentType);

	# if the reference to the body is itself undefined, then we've started
	# generating the page in the background
	return prepareResponseForSending($client, $params, $body, $httpClient, $response);
}

sub prepareResponseForSending {
	my ($client, $params, $body, $httpClient, $response) = @_;

	use bytes;

	# Set the Content-Length - valid for either HEAD or GET, even if HEAD
	# will clear out the actual content below.
	$response->content_length(length($$body));
	$response->date(time());

	my $request = $response->request();
	my $mtime   = $response->last_modified() || 0;
	my $method  = $request->method();

	# Don't send back content for a HEAD request.
	if ($method eq 'HEAD') {
		$$body = "";
	}

	my $ifModified  = $request->if_modified_since();
	my $requestTime = $request->client_date();

	if (0 && $ifModified && $requestTime && $mtime) {

		if (($ifModified >= $mtime) && ($ifModified <= $requestTime)) {

			$::d_http && msg("Content has not been modified - returning 304.\n");

			$response->code(RC_NOT_MODIFIED);
		}
	}

	if ($response->code() eq RC_NOT_MODIFIED) {

		for my $header (qw(Content-Length Cache-Control Content-Type Expires Last-Modified)) {
			$response->remove_header($header);
		}

		$$body = "";
	}

	addHTTPResponse($httpClient, $response, $body);

	return 0;
}

# XXX - ick ick
sub _stringifyHeaders {
	my $response = shift;

	my $data = sprintf("%s %s %s%s",
		$response->protocol(),
		$response->code(),
    		status_message($response->code()) || "",
		$CRLF
	);

	$data .= $response->headers_as_string($CRLF);
	
	# hack to make xmms like the audio better, since it appears to be case sensitive on for headers.
	$data =~ s/^(Icy-.+\:)/\L$1/mg; 

	return $data;
}

=pod

=HEAD1 This section handles standard HTTP responses

=cut

sub addHTTPResponse {
	my $httpClient = shift;
	my $response   = shift;
	my $body       = shift;

	# Force byte semantics on $body and length($$body) - otherwise we'll
	# try to write out multibyte characters with invalid byte lengths in
	# sendResponse() below.
	use bytes;

	# Take the refcnt down, so we don't leak.
	if ($Class::DBI::Weaken_Is_Available) {

		Scalar::Util::weaken($body);
	}

	# First add the headers
	my $headers = _stringifyHeaders($response) . $CRLF;

	push @{$outbuf{$httpClient}}, {
		'data'     => \$headers,
		'offset'   => 0,
		'length'   => length($headers),
		'response' => $response,
	};

	# And now the body.
	if ($body && length($$body)) {

		push @{$outbuf{$httpClient}}, {
			'data'     => $body,
			'offset'   => 0,
			'length'   => length($$body),
			'response' => $response,
		};
	}

	Slim::Networking::Select::addWrite($httpClient, \&sendResponse);
}

sub sendResponse {
	my $httpClient = shift;

	use bytes;

	my $segment    = shift(@{$outbuf{$httpClient}});
	my $sentbytes  = 0;

	# abort early if we don't have anything.
	unless ($httpClient->connected()) {

		$::d_http && msg("Got nothing for message to " . $peeraddr{$httpClient} . ", closing socket\n");
		closeHTTPSocket($httpClient);
		return;
	}

	unless ($segment) {
		$::d_http && msg("No segment to send to " . $peeraddr{$httpClient} . ", waiting for next request..\n");
		# Nothing to send, so we take the socket out of the write list.
		# When we process the next request, it will get put back on.
		Slim::Networking::Select::addWrite($httpClient, undef); 

		return;
	}

	if (defined $segment->{'data'} && defined ${$segment->{'data'}}) {

		$sentbytes = syswrite($httpClient, ${$segment->{'data'}}, $segment->{'length'}, $segment->{'offset'});
	}

	if ($! == EWOULDBLOCK) {
		$::d_http && msg("Would block while sending. Resetting sentbytes for: " . $peeraddr{$httpClient} . "\n");
		$sentbytes = 0 unless defined $sentbytes;
	}

	if (!defined($sentbytes)) {

		# Treat $httpClient with suspicion
		$::d_http && msg("Send to " . $peeraddr{$httpClient} . " had error, closing and aborting.\n");

		closeHTTPSocket($httpClient);

		return;
	}

	# sent incomplete message
	if ($sentbytes < $segment->{'length'}) {

		$segment->{'length'} -= $sentbytes;
		$segment->{'offset'} += $sentbytes;
		unshift @{$outbuf{$httpClient}}, $segment;

	} else {

		# sent full message
		if (@{$outbuf{$httpClient}} == 0) {

			# no more messages to send
			$::d_http && msg("No more messages to send to " . $peeraddr{$httpClient} . "\n");

			my $connection = 0;

			if ($segment->{'response'}) {
				$connection = $segment->{'response'}->header('Connection');
			}

			# if either the client or the server has requested a close, respect that.
			if (($connection && $connection eq 'close') || !$connection) {

				$::d_http && msg("End request, connection closing for: $httpClient\n");
				closeHTTPSocket($httpClient);
			}

		} else {

			$::d_http && msg("More to send to " . $peeraddr{$httpClient} . "\n");
		}
	}
}

=pod

=HEAD1 These two routines handle HTTP streaming of audio (a la ShoutCast and IceCast)

=cut

sub addStreamingResponse {
	my $httpClient = shift;
	my $message    = shift;
	my $params     = shift;
	
	my %segment = ( 
		'data'   => \$message,
		'offset' => 0,
		'length' => length($message)
	);

	push @{$outbuf{$httpClient}}, \%segment;

#   May want to enable this later, if we find that that it has any effect on some platforms...
#	setsockopt $httpClient, SOL_SOCKET, SO_SNDBUF, MAXCHUNKSIZE;
	
	Slim::Networking::Select::addWrite($httpClient, \&sendStreamingResponse);

	# we aren't going to read from this socket anymore so don't select on it...
	Slim::Networking::Select::addRead($httpClient, undef);

	my $client = $peerclient{$httpClient};

	if ($client) {

		$client->streamingsocket($httpClient);

		my $newpeeraddr = getpeername($httpClient);
	
		$client->paddr($newpeeraddr) if $newpeeraddr;
	}	
}

sub clearOutputBuffer {
	my $client = shift;
	foreach my $httpClient (keys %peerclient) {
		if ($client eq $peerclient{$httpClient}) {
			delete $outbuf{$httpClient};
			last;
		}
	}	
}

sub sendStreamingResponse {
	my $httpClient = shift;
	my $sentbytes;

	my $client = $peerclient{$httpClient};
	
	# when we are streaming a file, we may not have a client, rather it might just be going to a web browser.
	# assert($client);

	my $segment = shift(@{$outbuf{$httpClient}});
	my $streamingFile = $streamingFiles{$httpClient};

	my $silence = 0;
	
	$::d_http && msg("sendstreaming response begun...\n");

	if ($client && 
			$client->isa("Slim::Player::Squeezebox") && 
			defined($httpClient) &&
			(!defined($client->streamingsocket()) || $httpClient != $client->streamingsocket())
		) {

		$::d_http && msg($client->id() . " We're done streaming this socket to client\n");
		closeStreamingSocket($httpClient);
		return;
	}
	
	if (!$httpClient->connected()) {
		closeStreamingSocket($httpClient);
		$::d_http && msg("Streaming client closed connection...\n");
		return undef;
	}
	
	if (!$streamingFile && 
			$client && 
			$client->isa("Slim::Player::Squeezebox") && 
			(Slim::Player::Source::playmode($client) eq 'stop')) {
		closeStreamingSocket($httpClient);
		$::d_http && msg("Squeezebox closed connection...\n");
		return undef;
	}
	
	if (!defined($streamingFile) && 
			$client && 
			$client->isa("Slim::Player::HTTP") && 
			((Slim::Player::Source::playmode($client) ne 'play') || (Slim::Player::Playlist::count($client) == 0))) {

		$silence = 1;
	} 

	# if we don't have anything in our queue, then get something
	if (!defined($segment)) {

		# if we aren't playing something, then queue up some silence
		if ($silence) {

			$::d_http && msg("(silence)");

			my $silencedataref = getStaticContent("html/silence.mp3");

			my %segment = ( 
				'data'   => $silencedataref,
				'offset' => 0,
				'length' => length($$silencedataref)
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
					$::d_http && msg("we're done streaming this stored file, closing connection....\n");
					return 0;
				}

			} else {
				$chunkRef = Slim::Player::Source::nextChunk($client, MAXCHUNKSIZE);
			}
			
			# otherwise, queue up the next chunk of sound
			if ($chunkRef && length($chunkRef)) {

				$::d_http && msg("(audio: " . length($$chunkRef) . " bytes)\n" );
				my %segment = ( 
					'data'   => $chunkRef,
					'offset' => 0,
					'length' => length($$chunkRef)
				);

				unshift @{$outbuf{$httpClient}},\%segment;

			} else {
				# let's try again after RETRY_TIME
				$::d_http && msg("Nothing to stream, let's wait for " . RETRY_TIME . " seconds...\n");
				Slim::Networking::Select::addWrite($httpClient, 0);
				Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + RETRY_TIME, \&tryStreamingLater,($httpClient));
			}
		}

		# try again...
		$segment = shift(@{$outbuf{$httpClient}});
	}
	
	# try to send metadata, if appropriate
	if ($sendMetaData{$httpClient}) {

		# if the metadata would appear in the middle of this message, just send the bit before
		$::d_http && msg("metadata bytes: " . $metaDataBytes{$httpClient} . "\n");

		if ($metaDataBytes{$httpClient} == METADATAINTERVAL) {

			unshift @{$outbuf{$httpClient}}, $segment;

			my $song = Slim::Player::Playlist::song($client);

			my $title = $song ? Slim::Music::Info::standardTitle($client, $song) : string('WELCOME_TO_SLIMSERVER');
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
			$::d_http && msg("sending metadata of length $length: '$metastring' (" . length($message) . " bytes)\n");

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
			$::d_http && msg("splitting message for metadata at " . $splitpoint . "\n");
		
		} else {
			# if it's time to send the metadata, just send the metadata
			$metaDataBytes{$httpClient} += $segment->{'length'} if defined $segment;
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

#				if (($sentbytes % 2) == 1) {
#					msg( "ODD!:$sentbytes (tried: $prebytes)\n");
#				} else {
#					msg( "even:$sentbytes (tried: $prebytes)\n");
#				}

				$::d_http && $sentbytes && msg("sent incomplete chunk, requeuing " . 
					($segment->{'length'} - $sentbytes). " bytes\n");

				$metaDataBytes{$httpClient} -= $segment->{'length'} - $sentbytes;
				$segment->{'length'} -= $sentbytes;
				$segment->{'offset'} += $sentbytes;
				unshift @{$outbuf{$httpClient}},$segment;
			}

		} else {
			$::d_http && msg("sendstreamingsocket syswrite returned undef: $!\n");
			closeStreamingSocket($httpClient);
			return undef;
		}

	} else {
		$::d_http && msg("Got nothing for streaming data to " . $peeraddr{$httpClient} . "\n");
		return 0;
	}

	$::d_http && $sentbytes && msg("Streamed $sentbytes to " . $peeraddr{$httpClient} . "\n");
	return $sentbytes;
}

sub tryStreamingLater {
	my $client = shift;
	my $httpClient = shift;
	Slim::Networking::Select::addWrite($httpClient, \&sendStreamingResponse);
}

=pod

=HEAD1 Templates
# The filltemplate code described below is not currently in use.  It has
# been replaced by Template Toolkit
#  all the HTML is read from template files, to make it easier to edit
#  templates are parsed with the following rules, in this order:
#
#  replace this:			with this:
#
#  [EVAL]bar[/EVAL]			evaluate bar as perl code and replace with
#                       	the value of the $out variable
#  {foo}					$hash{'foo'}
#  {%foo}					&uri_escape($hash{'foo'})
#  {&foo}                   &encode_entities($hash{'foo'})

#  [S stringname]			string('stringname')

#  [SET foo bob] 			$hash{'foo'} = 'bob'
#  [IF foo]bar[/IF] 		if $hash{'foo'} then 'bar' else ''
#  [IFN foo]bar[/IFN] 		if !$hash{'foo'} then 'bar' else ''
#  [EQ foo bob]bar[/EQ] 	if ($hash{'foo'} eq 'bob') then 'bar' else ''
#  [NE foo bob]bar[/NE] 	if ($hash{'foo'} ne 'bob') then 'bar' else ''
#  [GT foo bob]bar[/GT] 	if ($hash{'foo'} > 'bob') then 'bar' else ''
#  [LT foo bob]bar[/LT] 	if ($hash{'foo'} < 'bob') then 'bar' else ''

#  [INCLUDE foo.html]       include and parse the HTML file specified
#  [STATIC foo.html]		include, but don't parse the file specified
#  [E]foo[/E]				uri_escape('foo');
#  [NB]foo[/NB]				nonBreak('foo');

#  &lsqb;          	[
#  &rsqb;			]
#  &lbrc;          	{
#  &rbrc;			}

#
# Fills the template string $template with the key/values in the hash pointed to by hashref
# returns the filled template string

=cut

sub filltemplate {
	my ($template, $hashref) = @_;

	return \$template if (!defined($template) || length($template) == 0);

	my $client = defined($hashref) ? $hashref->{'myClientState'} : undef;

	my $out = '';

	$template =~ s{\[EVAL\](.*?)\[/EVAL\]}{eval($1) || ''}esg;
	
	# first, substitute {%key} with the url escaped value for the given key in the hash
	$template =~ s/{%([^{}]+)}/defined($hashref->{$1}) ? uri_escape_utf8($hashref->{$1}) : ""/eg;
	
	# first, substitute {%key} with the url escaped value for the given key in the hash
	#
	# This is using a slightly modified version of HTML::Entities, that
	# doesn't rely on HTML::Parser, which is implemented as native code.
	# When we get around to compiling that, use it. 
	$template =~ s/{&([^{}]+)}/defined($hashref->{$1}) ? encode_entities($hashref->{$1}) : ""/eg;

	# do the same, but without the escape when given {key}
	$template =~ s/{([^{}]+)}/defined($hashref->{$1}) ? $hashref->{$1} : ""/eg;
	
	# look up localized strings with [S stringname]
	$template =~ s/\[S\s+([^\[\]]+)\]/&string($1)/eg;
	
	# set the value of a hash item
	$template =~ s/\[SET\s+([^\[\] ]+)\s+([^\]]+)\]/$hashref->{$1} = $2; ""/esg;

	# [IF hashkey], [IFN hashkey], [EQ hashkey value], and [NE hashkey value]
	$template =~ s/\[IF\s+([^\[\]]+)\](.*?)\[\/IF\]/$hashref->{$1} ? $2 : ''/esg;
	$template =~ s/\[IFN\s+([^\[\]]+)\](.*?)\[\/IFN\]/$hashref->{$1} ? '' : $2/esg;
	$template =~ s/\[EQ\s+([^\[\]]+)\s+(.+?)\](.*?)\[\/EQ\]/(defined($hashref->{$1}) && $hashref->{$1} eq $2) ? $3 :  ''/esg;
	$template =~ s/\[NE\s+([^\[\]]+)\s+(.+?)\](.*?)\[\/NE\]/(!defined($hashref->{$1}) || $hashref->{$1} ne $2) ? $3 :  ''/esg;
	$template =~ s/\[GT\s+([^\[\]]+)\s+(.+?)\](.*?)\[\/GT\]/(defined($hashref->{$1}) && $hashref->{$1} > $2) ? $3 :  ''/esg;
	$template =~ s/\[LT\s+([^\[\]]+)\s+(.+?)\](.*?)\[\/LT\]/(defined($hashref->{$1}) && $hashref->{$1} < $2) ? $3 :  ''/esg;

	$template =~ s|\[INCLUDE\s+([^\[\]]+)\]|${filltemplatefile($1, $hashref)}|esg;
	$template =~ s{\[STATIC\s+([^\[\]]+)\]}{getStaticContentForTemplate($1, $hashref)}esg;

	# make strings with spaces in them non-breaking by replacing the spaces with &nbsp;
	$template =~ s/\[NB\](.+?)\[\/NB\]/nonBreaking($1)/esg;
	
	# escape any text between [E] and [/E]
	$template =~ s/\[E\](.+?)\[\/E\]/uri_escape_utf8($1)/esg;
	
	$template =~ s/&lsqb;/\[/g;
	$template =~ s/&rsqb;/\]/g;
	$template =~ s/&lbrc;/{/g;
	$template =~ s/&rbrc;/}/g;

	return \$template;
}

sub nonBreaking {
	my $string = shift;
	$string =~ s/\s/\&nbsp;/g;
	return $string;
}
my %skinTemplates;

sub newSkinTemplate {
	my $skin = shift;
	my $baseSkin = baseSkin();
	my @include_path = ();

	foreach my $dir ($skin, $baseSkin) {

		foreach my $rootdir (HTMLTemplateDirs()) {
			push @include_path, catdir($rootdir,$dir);
		}
	}

	$skinTemplates{$skin} = Template->new({

		INCLUDE_PATH => \@include_path,
		COMPILE_DIR => Slim::Utils::Prefs::get('cachedir'),
		PLUGIN_BASE => ['Plugins::TT',"HTML::$skin"],

		FILTERS => {
			'string' => \&Slim::Utils::Strings::string,
			'nbsp' => \&nonBreaking,
			'uri' => \&URI::Escape::uri_escape_utf8,
			'unuri' => \&URI::Escape::uri_unescape,
			'utf8decode' => \&Slim::Utils::Misc::utf8decode,
			'utf8encode' => \&Slim::Utils::Misc::utf8encode,
		},

		EVAL_PERL => 1,
	});

	return $skinTemplates{$skin};
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

sub getStaticContentForTemplate {
	return ${_generateContentFromFile('get', @_)};
}

sub _generateContentFromFile {
	my ($type, $path, $params) = @_;

	my $skin = $params->{'skinOverride'} || Slim::Utils::Prefs::get('skin');

	$::d_http && msg("generating from $path\n");

	if ($type eq 'fill') {

		my $template = $skinTemplates{$skin} || newSkinTemplate($skin);
		my $output = '';

		# Always set the locale
		if ($Slim::Utils::Misc::locale && $Slim::Utils::Misc::locale =~ /utf\d+/) {

			$params->{'LOCALE'} = $Slim::Utils::Misc::locale;
			$params->{'LOCALE'} =~ s/utf(\d+)/utf-$1/;

		} else {

			$params->{'LOCALE'} = $Slim::Utils::Misc::locale || 'utf-8';
		}

		unless ($template->process($path,$params,\$output)) {
			print $template->error() . "\n";
		}

		return \$output;
	}

	my ($content, $mtime) = _getFileContent($path, $skin, 1);

	# some callers want the mtime for last-modified
	if (wantarray()) {
		return ($content, $mtime);
	} else {
		return $content;
	}
}

# Retrieves the file specified as $path, relative to HTMLTemplateDir() and
# the specified $skin or the $baseskin if not present in the $skin.
# Uses binmode to read file if $binary is specified.
# Keeps a cache of files internally to reduce file i/o.
# Returns a reference to the file data.

sub _getFileContent {
	my ($path, $skin, $binary) = @_;

	my $content = undef;
	my $template;
	my $mtime;
	my $skinkey = "${skin}/${path}";

	# return if we have the template cached.
	# XXX - this seems broken, and will start returning data of 0 length
	# at some point. - dsully
	if (Slim::Utils::Prefs::get('templatecache')) {

		if (defined $templatefiles{$skinkey}) {

			$::d_http && msg("Sending $skinkey from cache\n");

			return @{$templatefiles{$skinkey}};
		}
	}

	$::d_http && msg("reading http file for ($skin $path)\n");

	my $skinpath = fixHttpPath($skin, $path);

	if (!defined($skinpath) || 
		(!open($template, $skinpath . '.' . lc(Slim::Utils::Prefs::get('language'))) && !open($template, $skinpath))
	   ) {

		my $baseSkin = baseSkin();

		$::d_http && msg("couldn't find $skin $path trying for $baseSkin\n");

		my $defaultpath = fixHttpPath($baseSkin, $path);

		if (defined($defaultpath)) {
			$::d_http && msg("reading template: $defaultpath\n");

			# try to open language specific files, and if not, the specified one.
			open($template, $defaultpath . '.' . lc(Slim::Utils::Prefs::get('language'))) || open($template, $defaultpath);

			$mtime = (stat($template))[9];
		} 

	} else {
		$mtime = (stat($template))[9];
	}
	
	if ($template) {
		local $/ = undef;
		binmode($template) if $binary;
		$content = <$template>;
		close $template;
		$::d_http && (length($content) || msg("File empty: $path"));

	} else {
		$::d_http && msg("Couldn't open: $path\n");
	}
	
	# add this template to the cache if we are using it
	if (Slim::Utils::Prefs::get('templatecache') && defined($content)) {
		$templatefiles{$skinkey} = [\$content, $mtime];
	}

	# don't return the mtime time the first time to make sure we reload the client cache.
	# useful when we switch skins.  unfortunately, reloads the clients cache when the server restarts.
	return (\$content, time());
}

sub clearCaches {
	%templatefiles = ();
}

sub HomeURL {
	my $host = $main::httpaddr || Sys::Hostname::hostname() || '127.0.0.1';
	my $port = Slim::Utils::Prefs::get('httpport');

	return "http://$host:$port/";
}

sub HTMLTemplateDirs {
	return @templateDirs;
}

sub fixHttpPath {
	my $skin = shift;
	my $path = shift;

	foreach my $dir (HTMLTemplateDirs()) {
		my $fullpath = catdir($dir, $skin, $path);
		$::d_http && msg("Checking for $fullpath.\n");
		return $fullpath if (-r $fullpath);
	} 

	return undef;
}

sub forgetClient {
	my $client = shift;

	if (defined($client->streamingsocket)) {
		closeStreamingSocket($client->streamingsocket);
	}
}

sub closeHTTPSocket {
	my $httpClient = shift;
	
	Slim::Networking::Select::addRead($httpClient, undef);
	Slim::Networking::Select::addWrite($httpClient, undef);
	Slim::Networking::Select::addError($httpClient, undef);

	# clean up the various caches
	delete($outbuf{$httpClient});
	delete($sendMetaData{$httpClient});
	delete($metaDataBytes{$httpClient});
	delete($peeraddr{$httpClient});
	delete($keepAlives{$httpClient});
	delete($peerclient{$httpClient});

	$httpClient->close();
	undef($httpClient);
	$connected--;
}

sub closeStreamingSocket {
	my $httpClient = shift;
	
	$::d_http && msg("Closing streaming socket.\n");
	
	if (defined $streamingFiles{$httpClient}) {

		$::d_http && msg("Closing streaming file.\n");
		close  $streamingFiles{$httpClient};
		delete $streamingFiles{$httpClient};
	}
	
	foreach my $client (Slim::Player::Client::clients()) {

		if (defined($client->streamingsocket) && $client->streamingsocket == $httpClient) {
			$client->streamingsocket(undef);
		}
	}

	closeHTTPSocket($httpClient);

	return;
}

sub checkAuthorization {
	my $username = shift;
	my $password = shift;

	my $ok = 0;

	# No authorization needed
	unless (Slim::Utils::Prefs::get('authorize')) {
		$ok = 1;
		return $ok;
	}

	if ($username eq Slim::Utils::Prefs::get('username')) {

		my $pwd  = Slim::Utils::Prefs::get('password');

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

	$::d_http && msg("Adding handler for regular expression /$regexp\n");
	$pageFunctions{$regexp} = $func;
}

sub addTemplateDirectory {
	my $dir = shift;

	$::d_http && msg("Adding template directory $dir\n");
	push @templateDirs, $dir;
}

sub isCsrfAuthCodeValid {
	
	my $req = shift;
	my $csrfProtectionLevel = Slim::Utils::Prefs::get("csrfProtectionLevel");

	if (! defined($csrfProtectionLevel) ) {

		# Prefs.pm should have set this!
		$::d_http && msg("Server unable to determine CRSF protection level due to missing server pref\n");
		return 0;
	}

	# no protection, so we don't care
	return 1 if ( !$csrfProtectionLevel);

	my $uri = $req->uri();
	my $code = $req->header("X-Slim-CSRF");

	if ( (!defined($uri)) || (!defined($code)) ) { return 0; }

	my $secret = Slim::Utils::Prefs::get("securitySecret");

	if ( (!defined($secret)) || ($secret !~ m|^[0-9a-f]{32}$|) ) {

		# invalid secret!
		$::d_http && msg("Server unable to verify CRSF auth code due to missing or invalid securitySecret server pref\n");
		return 0;
	}

	my $expectedCode = $secret;

	# calculate what the auth code should look like
	my $highHash = new Digest::MD5;
	my $mediumHash = new Digest::MD5;

	# only the "HIGH" cauth code depends on the URI
	$highHash->add($uri);

	# both "HIGH" and "MEDIUM" depend on the securitySecret
	$highHash->add($secret);
	$mediumHash->add($secret);

	# a "HIGH" hash is always accepted
	return 1 if ( $code eq $highHash->hexdigest() );

	if ( $csrfProtectionLevel == 1 ) {

		# at "MEDIUM" level, we'll take the $mediumHash, too
		return 1 if ( $code eq $mediumHash->hexdigest() );
	}

	# the code is no good (invalid or MEDIUM hash presented when using HIGH protection)!
	return 0;

}

sub isRequestCSRFSafe {
	
	my ($request,$response,$params) = @_;
	my $rc = 0;

	# referer test from SlimServer 5.4.0 code

	if ($request->header('Referer') && defined($request->header('Referer')) && defined($request->header('Host')) ) {

		my ($host, $port, $path, $user, $password) = Slim::Utils::Misc::crackURL($request->header('Referer'));

		# if the Host request header lists no port, crackURL() reports it as port 80, so we should
		# pretend the Host header specified port 80 if it did not

		my $hostHeader = $request->header('Host');

		if ($hostHeader !~ m/:\d{1,}$/ ) { $hostHeader .= ":80"; }

		if ("$host:$port" ne $hostHeader) {
			$::d_http && msg("Invalid referer: [" . join(' ', ($request->method(), $request->uri())) . "]\n");
		} else {
			# looks good
			$rc = 1;
		}

	}

	if ( ! $rc ) {

		# need to also check if there's a valid "cauth" token
		if ( ! isCsrfAuthCodeValid($request) ) {

			$params->{'suggestion'} = "Invalid referrer and no valid cauth code.";
			$::d_http && msg("No valid CSRF auth code: [" . join(' ', ($request->method(), $request->uri(), $request-header('X-Slim-CSRF'))) . "]\n");

		} else {

			# looks good
			$rc = 1;
		}
	}

	return $rc;
}

sub makeAuthorizedURI {

	my $uri = shift;
	my $secret = Slim::Utils::Prefs::get("securitySecret");

	if ( (!defined($secret)) || ($secret !~ m|^[0-9a-f]{32}$|) ) {

		# invalid secret!
		$::d_http && msg("Server unable to compute CRSF auth code URL due to missing or invalid securitySecret server pref\n");
		return undef;
	}

	my $csrfProtectionLevel = Slim::Utils::Prefs::get("csrfProtectionLevel");

	if (! defined($csrfProtectionLevel) ) {

		# Prefs.pm should have set this!
		$::d_http && msg("Server unable to determine CRSF protection level due to missing server pref\n");
		return 0;
	}

	my $hash = new Digest::MD5;

	if ( $csrfProtectionLevel == 2 ) {

		# different code for each different URI
		$hash->add($uri);
	}

	$hash->add($secret);

	return $uri . ';cauth=' . $hash->hexdigest();
}

sub throwCSRFError {

	my ($httpClient,$request,$response,$params) = @_;

	# throw 403, we don't this from non-server pages
	# unless valid "cauth" token is present
	$params->{'suggestion'} = "Invalid Referer and no valid CSRF auth code.";

	my $protoHostPort = 'http://' . $request->header('Host');
	my $authURI = makeAuthorizedURI($request->uri());
	my $authURL = $protoHostPort . $authURI;

	# add a long SGML comment so Internet Explorer displays the page
	my $msg = "<!--" . ( '.' x 500 ) . "-->\n<p>";

	$msg .= string('CSRF_ERROR_INFO'); 
	$msg .= "<br>\n<br>\n<A HREF=\"${authURI}\">${authURL}</A></p>";
	
	my $csrfProtectionLevel = Slim::Utils::Prefs::get("csrfProtectionLevel");
	
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

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
