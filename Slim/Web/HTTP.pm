package Slim::Web::HTTP;

# $Id: HTTP.pm,v 1.86 2004/03/11 04:27:05 kdf Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Data::Dumper;
use FileHandle;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);
use HTTP::Daemon;
use HTTP::Headers;
use HTTP::Status;
use MIME::Base64;
use HTML::Entities;
use Socket qw(:DEFAULT :crlf);
use Sys::Hostname;
use Tie::RegexpHash;
use URI::Escape;

use Slim::Networking::mDNS;
use Slim::Networking::Select;

use Slim::Player::HTTP;

use Slim::Web::EditPlaylist;
use Slim::Web::History;
use Slim::Web::Olson;
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
}

use constant defaultSkin => 'Default';
use constant baseSkin	 => 'EN';
use constant ONEYEAR	 => 60 * 60 * 24 * 365;

use constant METADATAINTERVAL => 32768;
use constant MAXCHUNKSIZE     => 32768;
use constant RETRY_TIME	      => 0.05;

use constant MAXKEEPALIVES    => 30;
use constant KEEPALIVETIMEOUT => 10;

# Package variables

my %templatefiles = ();

my $openedport = 0;
my $http_server_socket;
my $connected = 0;

my %outbuf = (); # a hash for each writeable socket containing a queue of output segments
                 #   each segment is a hash of a ref to data, an offset and a length

my %sendMetaData   = ();
my %metaDataBytes  = ();
my %streamingFiles = ();
my %peeraddr       = ();
my %peerclient     = ();
my %keepAlives     = ();

my $mdnsIDslimserver;
my $mdnsIDhttp;

my %pageFunctions = ();

{
	tie %pageFunctions, 'Tie::RegexpHash';

	%pageFunctions = (
		qr/^$/				=> \&Slim::Web::Pages::home,
		qr/^index\.(?:htm|xml)/		=> \&Slim::Web::Pages::home,
		qr/browseid3\.(?:htm|xml)/	=> \&Slim::Web::Pages::browseid3,
		qr/browse\.(?:htm|xml)/		=> \&Slim::Web::Pages::browser,
		qr/edit_playlist\.(?:htm|xml)/	=> \&Slim::Web::EditPlaylist::editplaylist,  # Needs to be before playlist
		qr/^firmware\.(?:html|xml)/	=> \&Slim::Web::Pages::firmware,
		qr/hitlist\.(?:htm|xml)/	=> \&Slim::Web::History::hitlist,
		qr/home\.(?:htm|xml)/		=> \&Slim::Web::Pages::home,
		qr/instant_mix\.(?:htm|xml)/	=> \&Slim::Web::Pages::instant_mix,
		qr/mood_wheel\.(?:htm|xml)/	=> \&Slim::Web::Pages::mood_wheel,
		qr/olsondetail\.(?:htm|xml)/	=> \&Slim::Web::Olson::olsondetail,
		qr/olsonmain\.(?:htm|xml)/	=> \&Slim::Web::Olson::olsonmain,
		qr/playlist\.(?:htm|xml)/	=> \&Slim::Web::Pages::playlist,
		qr/search\.(?:htm|xml)/		=> \&Slim::Web::Pages::search,
		qr/songinfo\.(?:htm|xml)/	=> \&Slim::Web::Pages::songInfo,
		qr/status_header\.(?:htm|xml)/	=> \&Slim::Web::Pages::status_header,
		qr/status\.(?:htm|xml)/		=> \&Slim::Web::Pages::status,
		qr/setup\.(?:htm|xml)/		=> \&Slim::Web::Setup::setup_HTTP,
		qr/^update_firmware\.(?:htm|xml)/ => \&Slim::Web::Pages::update_firmware,
	);
}

# initialize the http server
*init     = \&idle;

# other people call us externally.
*escape   = \&URI::Escape::uri_escape;

# don't use the external one because it doesn't know about the difference between a param and not...
#*unescape = \&URI::Escape::unescape;
sub unescape {
	my $in = shift;
	my $isparam = shift;
	if (defined $in) {
		if ($isparam) {$in =~ s/\+/ /g;}
		$in =~ s/%([\da-fA-F][\da-fA-F])/chr(hex($1))/eg;
		return $in;
	} else {
		return '';
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
		Timeout   => 0.001,

	) or die "can't setup the listening port $listenerport for the HTTP server: $!";
	
	defined(Slim::Utils::Misc::blocking($http_server_socket,0)) || die "Cannot set port nonblocking";

	$openedport = $listenerport;
	Slim::Networking::Select::addRead($http_server_socket, \&acceptHTTP);
	
	$::d_http && msg("Server $0 accepting http connections on port $listenerport\n");
	
	$mdnsIDhttp = Slim::Networking::mDNS::advertise(Slim::Utils::Prefs::get('mDNSname'), '_http._tcp', $listenerport);
	$mdnsIDslimserver = Slim::Networking::mDNS::advertise(Slim::Utils::Prefs::get('mDNSname'), '_slimdevices_slimserver_http._tcp', $openedport);
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
	Slim::Web::HTTP::checkHTTP();
}

sub connectedSocket {
	return $connected;
}

sub acceptHTTP {
	return if Slim::Web::HTTP::connectedSocket() > Slim::Utils::Prefs::get("tcpConnectMaximum");

	# try and pull the handle
	my $httpClient = $http_server_socket->accept() || do {
		$::d_http && msg("Did not accept connection, accept returned nothing\n");
		return;
	};

	defined(Slim::Utils::Misc::blocking($httpClient,0)) || die "Cannot set port nonblocking";

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
			$connected++;
			$::d_http && msg("Accepted connection $connected from ". $peeraddr{$httpClient} . "\n");

		} else {

			$::d_http && msg("Did not accept HTTP connection from $peer, unauthorized source\n");
			$httpClient->close();
		}

	} else {

		$::d_http && msg("Did not accept connection, couldn't get peer addr\n");
	}
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

	# this bundles up all our response headers and content
	my $response = HTTP::Response->new();

	# respond in kind.
	$response->protocol($request->protocol());
	$response->request($request);

	if ($::d_http_verbose) {
		msg("Request Headers: [\n" . $request->as_string() . "]\n");
	}

	#
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
			$response->content(${filltemplatefile('html/errors/401.html', $params)});
			$response->www_authenticate(sprintf('Basic realm="%s"', string('SLIMSERVER')));

			$httpClient->send_response($response);

			return;
		}
			
		# parse out URI:
		my $uri   = $request->uri();
		my $path  = $uri->path();
		my $query = $uri->query();

		# XXX - unfortunately slimserver uses a query form
		# that can have a key without a value, yet it's
		# differnet from a key with an empty value. So we have
		# to parse out like this.
		if ($query) {

			foreach my $param (split /\&/, $query) {

				if ($param =~ /([^=]+)=(.*)/) {

					my $name  = unescape($1, 1);
					my $value = unescape($2, 1);

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

			if ($path =~ m|^/(.+?)/.*| && $path !~ m{^/(?:html|music)/}i) {

				my $desiredskin = $1;

				# Requesting a specific skin, verify and set the skinOverride param
				$::d_http && msg("Alternate skin $desiredskin requested\n");

				my %skins = Slim::Web::Setup::skins();
				my $skinlist = join '|',keys %skins;
				if ($desiredskin =~ /($skinlist)/i) {
					$params->{'skinOverride'} = $1;
					$params->{'webroot'} = $params->{'webroot'} . "$1/";
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
					$response->content(${filltemplatefile('html/errors/404.html', $params)});
			
					$httpClient->send_response($response);
					closeHTTPSocket($httpClient);
					return;
				}
			}

			$path =~ s|^/+||;
			$params->{"path"} = unescape($path);
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
			}
		}

		# process the commands
		processURL($httpClient, $response, $params);

	} else {

		$::d_http && msg("Bad Request: [" . join(' ', ($request->method(), $request->uri())) . "]\n");

		$response->code(RC_METHOD_NOT_ALLOWED);
		$response->header('Connection' => 'close');
		$response->content_type('text/html');
		$response->content(${filltemplatefile('html/errors/405.html', $params)});

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
	}

	# if we don't have a player specified, just pick one if there is one...
	if (!defined($client) && Slim::Player::Client::clientCount() > 0) {
		$client = (Slim::Player::Client::clients())[0];
	}

	$peerclient{$httpClient} = $client;

	if ($client && $client->isPlayer() && $client->model() eq 'slimp3') {

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
	my ($client, $httpClient, $response, $params, $pCommands) = @_;

	# this is a scalar ref because of the potential size of the body.
	# not sure if it actually speeds things up considerably.
	my ($body, $mtime); 

	# default to 200
	$response->code(RC_OK);

	# parse the param headers
	if (ref($pCommands) && ref($pCommands) eq 'ARRAY') {

		for (my $i = 0; $i <= scalar @{$pCommands}; $i++) {
			$response->header("x-p$i" => $pCommands->[$i]);
		}
	}
	
	$params->{'player'} = '';

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
		$response->expires(time() + ONEYEAR);
		$response->header('Cache-Control' => 'public');
	}

	if ($contentType =~ /text/) {
		filltemplatefile('include.html', $params);
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
		buildStatusHeaders($client, $response);

		$response->header("x-audiocast-name" => string('SLIMSERVER'));

		if ($sendMetaData{$httpClient}) {
			$response->header("icy-metaint" => METADATAINTERVAL);
			$response->header("icy-name"    => string('WELCOME_TO_SLIMSERVER'));
		}

		my $headers = _stringifyHeaders($response) . $CRLF;

		$metaDataBytes{$httpClient} = - length($headers);

		addStreamingResponse($httpClient, $headers, $params);

		return 0;

	} elsif ($path =~ /music\/(.+)\/(cover|thumb)\.jpg$/) {

		my $song  = Slim::Utils::Misc::virtualToAbsolute($1);
		my $image = $2;
		my $imageData;

		$::d_http && msg("Cover Art asking for: $image\n");

		$song = Slim::Utils::Misc::fixPath($song);

		($imageData, $contentType, $mtime) = Slim::Music::Info::coverArt($song, $image);

		if (defined($imageData)) {

			$body  = \$imageData;
			buildStatusHeaders($client, $response);

		} else {

			($body, $mtime) = getStaticContent("html/images/spacer.gif");
			$contentType = "image/gif";
		}

	} elsif ($path =~ /music\/(.+)$/) {

		my $file = Slim::Utils::Misc::virtualToAbsolute($1);

		if (Slim::Music::Info::isSong($file) && Slim::Music::Info::isFile($file)) {

			$::d_http && msg("Opening $file to stream...\n");

			my $songHandle =  FileHandle->new($file);

			if ($songHandle) {

				buildStatusHeaders($client, $response);

				$response->content_type(Slim::Music::Info::mimeType($file));
				$response->content_length(Slim::Music::Info::fileLength($file));

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
		buildStatusHeaders($client, $response);

		$contentType = "text/plain";

		$response->header("Refresh" => "30; url=$path");

		if ($path =~ /status/) {
			my ($line1, $line2) = Slim::Display::Display::curLines($client);
			$$body = $line1 . $CRLF . $line2 . $CRLF;
		} else {
			$$body = $Slim::Utils::Misc::log;
		}

	} elsif ($path =~ /status\.m3u/) {

		# if the HTTP client has asked for a .m3u file, then always return the current playlist as an M3U
		buildStatusHeaders($client, $response);

		if (defined($client)) {

			my $count = Slim::Player::Playlist::count($client) && do {
				$body = Slim::Formats::Parse::writeM3U(\@{Slim::Player::Playlist::playList($client)});
			};
		}

	} elsif ($path =~ /html\//) {

		# content is in the "html" subdirectory within the template directory.

		# if it's HTML then use the template mechanism
		if ($contentType eq 'text/html' || $contentType eq 'text/xml') {

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
	$response->content_type($contentType);

	# if the reference to the body is itself undefined, then we've started
	# generating the page in the background
	return prepareResponseForSending($client, $params, $body, $httpClient, $response);
}

sub prepareResponseForSending {
	my ($client, $params, $body, $httpClient, $response) = @_;

	$response->header('Content-Length' => length($$body));

	# don't fill these in for HEAD requests
	if ($response->request()->method() eq 'HEAD') {
		$response->content("");
	} else {
		$response->content($$body);
	}

	my $request = $response->request();
	my $mtime   = $response->last_modified() || 0;

	# Don't send back content if it hasn't been modified.
	if (my $ifModified = $request->if_modified_since()) {

		if ($mtime && $mtime <= $ifModified) {

			$::d_http && msg("Content has not been modified - returning 304.\n");

			$response->code(RC_NOT_MODIFIED);
			$response->content("");
		}
	}

	addHTTPResponse($httpClient, $response);

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

	$data .= sprintf("Date: %s%s", HTTP::Date::time2str(time), $CRLF);
	$data .= $response->headers_as_string($CRLF);

	return $data;
}

=pod

=HEAD1 This section handles standard HTTP responses

=cut

sub addHTTPResponse {
	my $httpClient = shift;
	my $response   = shift;

	# XXX
	my $data = join($CRLF, _stringifyHeaders($response), $response->content());

	my $segment = {
		'data'	   => \$data,
		'offset'   => 0,
		'length'   => length($data),
		'response' => $response,
	};

	push @{$outbuf{$httpClient}}, $segment;

	Slim::Networking::Select::addWrite($httpClient, \&sendResponse);
}

sub sendResponse {
	my $httpClient = shift;

	my $segment    = shift(@{$outbuf{$httpClient}});
	my $sentbytes  = 0;

	# abort early if we don't have anything.
	unless ($segment && $httpClient->connected()) {

		$::d_http && msg("Got nothing for message to " . $peeraddr{$httpClient} . ", closing socket\n");
		closeHTTPSocket($httpClient);
		return;
	}

	$sentbytes = syswrite($httpClient, ${$segment->{'data'}}, $segment->{'length'}, $segment->{'offset'});

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

			my $connection = $segment->{'response'}->header('Connection');

			# if either the client or the server has requested a close, respect that.
			if ($connection && $connection eq 'close') {

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

sub sendStreamingResponse {
	my $httpClient = shift;
	my $sentbytes;

	my $client = $peerclient{$httpClient};
	assert($client);

	my $segment = shift(@{$outbuf{$httpClient}});
	my $streamingFile = $streamingFiles{$httpClient};
	my $silence = 0;
	
	$::d_http && msg("sendstreaming response begun...\n");

	if (($client->model eq 'squeezebox') && defined($httpClient) &&
		(!defined($client->streamingsocket()) || $httpClient != $client->streamingsocket())) {

		$::d_http && msg($client->id() . " We're done streaming this socket to client\n");
		closeStreamingSocket($httpClient);
		return;
	}
	
	if (!$httpClient->connected()) {
		closeStreamingSocket($httpClient);
		$::d_http && msg("Streaming client closed connection...\n");
		return undef;
	}
	
	if (!$streamingFile && $client && ($client->model eq 'squeezebox') && (Slim::Player::Source::playmode($client) eq 'stop')) {
		closeStreamingSocket($httpClient);
		$::d_http && msg("Squeezebox closed connection...\n");
		return undef;
	}
	
	if (!defined($streamingFile) && 
		$client && ($client->model eq 'http') && 
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
			$::d_http && msg("sendstreamingsocket syswrite returned undef\n");
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
	$template =~ s/{%([^{}]+)}/defined($hashref->{$1}) ? uri_escape($hashref->{$1}) : ""/eg;
	
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
	$template =~ s/\[E\](.+?)\[\/E\]/uri_escape($1)/esg;
	
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

	my ($content, $mtime);

	if (defined $params->{'skinOverride'}) {
		($content, $mtime) = _getFileContent($path, $params->{'skinOverride'}, 1);
	} else {
		($content, $mtime) = _getFileContent($path, Slim::Utils::Prefs::get('skin'), 1);
	}

	if ($type eq 'fill') {
		return &filltemplate($$content, $params);
	} else {

		# some callers want the mtime for last-modified
		if (wantarray()) {
			return ($content, $mtime);
		} else {
			return $content;
		}
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
	if (Slim::Utils::Prefs::get('templatecache')) {

		if (defined $templatefiles{$skinkey}) {
			return $templatefiles{$skinkey};
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
		binmode($template) if $binary;
		$content = join('', <$template>);
		close $template;
		$::d_http && (length($content) || msg("File empty: $path"));

	} else {
		$::d_http && msg("Couldn't open: $path\n");
	}
	
	# add this template to the cache if we are using it
	if (Slim::Utils::Prefs::get('templatecache') && defined($content)) {
		$templatefiles{$skinkey} = \$content;
	}

	return (\$content, $mtime);
}

sub clearCaches {
	%templatefiles = ();
}

sub HomeURL {
	my $host = $main::httpaddr || Sys::Hostname::hostname() || '127.0.0.1';
	my $port = Slim::Utils::Prefs::get('httpport');

	return "http://$host:$port/";
}

# XXX - cache this, or at the very least, inline
sub HTMLTemplateDirs {
	my @dirs = ();

	if (Slim::Utils::OSDetect::OS() eq 'mac') {
		push @dirs, $ENV{'HOME'} . "/Library/SlimDevices/html/";
		push @dirs, "/Library/SlimDevices/html/";
	}

	push @dirs, catdir($Bin, 'HTML');

	return @dirs;
}

sub fixHttpPath {
	my $skin = shift;
	my $path = shift;

	foreach my $dir (HTMLTemplateDirs()) {
		my $fullpath = catdir($dir, $skin, $path);
		return $fullpath if (-r $fullpath);
	} 

	return undef;
}

sub buildStatusHeaders {
	my $client   = shift || return;
	my $response = shift;

	# send headers
	my %headers = ( 
		"x-player"		=> $client->id(),
		"x-playername"		=> $client->name(),
		"x-playertracks" 	=> Slim::Player::Playlist::count($client),
		"x-playershuffle" 	=> Slim::Player::Playlist::shuffle($client) ? "1" : "0",
		"x-playerrepeat" 	=> Slim::Player::Playlist::repeat($client),

		# unsupported yet
	#	"x-playerbalance" => "0",
	#	"x-playerbase" => "0",
	#	"x-playertreble" => "0",
	#	"x-playersleep" => "0",
	);
	
	if ($client->isPlayer()) {

		$headers{"x-playervolume"} = int(Slim::Utils::Prefs::clientGet($client, "volume") + 0.5);
		$headers{"x-playermode"}   = Slim::Buttons::Common::mode($client) eq "power" ? "off" : Slim::Player::Source::playmode($client);

		my $sleep = $client->sleepTime() - Time::HiRes::time();

		$headers{"x-playersleep"}  = $sleep < 0 ? 0 : int($sleep/60);
	}	
	
	if (Slim::Player::Playlist::count($client)) { 

		$headers{"x-playertrack"}    = Slim::Player::Playlist::song($client); 
		$headers{"x-playerindex"}    = Slim::Player::Source::currentSongIndex($client) + 1;
		$headers{"x-playertime"}     = Slim::Player::Source::songTime($client);
		$headers{"x-playerduration"} = Slim::Music::Info::durationSeconds(Slim::Player::Playlist::song($client));

		my $i = Slim::Music::Info::artist(Slim::Player::Playlist::song($client));
		$headers{"x-playerartist"} = $i if $i;

		$i = Slim::Music::Info::album(Slim::Player::Playlist::song($client));
		$headers{"x-playeralbum"} = $i if $i;

		$i = Slim::Music::Info::title(Slim::Player::Playlist::song($client));
		$headers{"x-playertitle"} = $i if $i;

		$i = Slim::Music::Info::genre(Slim::Player::Playlist::song($client));
		$headers{"x-playergenre"} = $i if $i;
	};

	while (my ($key, $value) = each %headers) {
		$response->header($key => $value);
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

	Slim::Networking::Select::addRead($httpClient, undef);
	Slim::Networking::Select::addWrite($httpClient, undef);

	# clean up the various caches
	delete($outbuf{$httpClient});
	delete($sendMetaData{$httpClient});
	delete($metaDataBytes{$httpClient});
	delete($peeraddr{$httpClient});
	delete($keepAlives{$httpClient});

	$httpClient->close();

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

	delete($peerclient{$httpClient});
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

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
