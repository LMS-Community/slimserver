package Slim::Web::HTTP;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
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
use Template;
use Tie::RegexpHash;
use URI::Escape;
use YAML::Syck qw(LoadFile);

use Slim::Formats::Playlists::M3U;
use Slim::Networking::mDNS;
use Slim::Networking::Select;
use Slim::Player::HTTP;
use Slim::Music::Info;
use Slim::Web::Pages;
use Slim::Web::Graphics;

use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Unicode;


# constants
BEGIN {
	if ($^O =~ /Win32/) {
		*EWOULDBLOCK = sub () { 10035 };
		*EINPROGRESS = sub () { 10036 };
	} else {
		require Errno;
		import Errno qw(EWOULDBLOCK EINPROGRESS);
	}
	
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

my $openedport = 0;
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

our @templateDirs = ();

our %pageFunctions = ();
tie %pageFunctions, 'Tie::RegexpHash';

our $pageBuild = Slim::Utils::PerfMon->new('Web Page Build', [0.002, 0.005, 0.010, 0.015, 0.025, 0.050, 0.1, 0.5, 1, 5]);

our %dangerousCommands = (
	# name of command => regexp for URI patterns that make it dangerous
	# e.g.
	#	\&Slim::Web::Pages::status => '\bp0=rescan\b'
	# means inisist on CSRF protection for the status command *only*
	# if the URL includes p0=rescan
	\&Slim::Web::Setup::setup_HTTP => '.',
	\&Slim::Web::EditPlaylist::editplaylist => '.',
	\&Slim::Web::Pages::Status::status => '(p0=debug|p0=pause|p0=stop|p0=play|p0=sleep|p0=playlist|p0=mixer|p0=display|p0=button|p0=rescan|(p0=(|player)pref\b.*p2=[^\?]|p2=[^\?].*p0=(|player)pref))',
);

# initialize the http server
sub init {

	push @templateDirs, Slim::Utils::OSDetect::dirsFor('HTML');

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

	# if we've got an HTTP port specified, open it up!
	if (Slim::Utils::Prefs::get('httpport')) {
		Slim::Web::HTTP::openport(Slim::Utils::Prefs::get('httpport'), $::httpaddr, $Bin);
	}
}

sub escape {
	msg("Slim::Web::HTTP::escape has been deprecated in favor of 
	     Slim::Utils::Misc::escape(). Please update your calls!\n");
	Slim::Utils::Misc::bt();

	return Slim::Utils::Misc::escape(@_);
}

sub unescape {
	msg("Slim::Web::HTTP::unescape has been deprecated in favor of 
	     Slim::Utils::Misc::unescape(). Please update your calls!\n");
	Slim::Utils::Misc::bt();
	
	return Slim::Utils::Misc::unescape(@_);
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
	
	defined(Slim::Utils::Network::blocking($http_server_socket,0)) || die "Cannot set port nonblocking";

	$openedport = $listenerport;
	Slim::Networking::Select::addRead($http_server_socket, \&acceptHTTP);
	
	$::d_http && msg("Server $0 accepting http connections on port $listenerport\n");

	Slim::Networking::mDNS->addService('_http._tcp', $listenerport);
	Slim::Networking::mDNS->addService('_slimhttp._tcp', $listenerport);
}

sub adjustHTTPPort {
	# do this on a timer so current page can be updated first and it executed outside select
	Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 0.5, \&_adjustHTTPPortCallback);
}

sub _adjustHTTPPortCallback {
	# if we've already opened a socket, let's close it
	if ($openedport) {

		Slim::Networking::mDNS->removeService('_http._tcp');
		Slim::Networking::mDNS->removeService('_slimhttp._tcp');
		
		$::d_http && msg("closing http server socket\n");
		Slim::Networking::Select::addRead($http_server_socket, undef);
		$http_server_socket->close();
		undef($http_server_socket);
		$openedport = 0;
	}

	# open new port if specified
	if (Slim::Utils::Prefs::get('httpport')) {
		Slim::Web::HTTP::openport(Slim::Utils::Prefs::get('httpport'), $::httpaddr, $Bin);
	}
}

# TODO: Turn this back on
#		my $tcpReadMaximum = Slim::Utils::Prefs::get("tcpReadMaximum");
#		my $streamWriteMaximum = Slim::Utils::Prefs::get("tcpWriteMaximum");

sub connectedSocket {
	return $connected;
}

sub acceptHTTP {
	# try and pull the handle
	my $httpClient = $http_server_socket->accept() || do {
		$::d_http && msg("Did not accept connection, accept returned nothing\n");
		return;
	};

	defined(Slim::Utils::Network::blocking($httpClient,0)) || die "Cannot set port nonblocking";
	
	binmode($httpClient);
	
	my $peer = $httpClient->peeraddr();

	if ($httpClient->connected() && $peer) {

		$peer = inet_ntoa($peer);

		# Check if source address is valid
		if (!(Slim::Utils::Prefs::get('filterHosts')) ||
		     (Slim::Utils::Network::isAllowedHost($peer))) {

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

	# Set the request time - for If-Modified-Since
	$request->client_date(time());

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
	
	# Read cookie(s)
	if ( my $cookie = $request->header('Cookie') ) {
		$params->{'cookies'} = { CGI::Cookie->parse($cookie) };
	}

	# this bundles up all our response headers and content
	my $response = HTTP::Response->new();

	# respond in kind.
	$response->protocol($request->protocol());
	$response->request($request);

	if ($::d_http_verbose) {
		#msg("Request Headers: [\n" . $request->as_string() . "]\n");
	}

	if ($request->method() eq 'GET' || $request->method() eq 'HEAD' || $request->method() eq 'POST') {

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
		my $query = ($request->method() eq "POST") ? $request->content() : $uri->query();

		$params->{url_query} = $query;

		$params->{content} = $request->content();

		# XXX - unfortunately slimserver uses a query form
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
						$value = Slim::Utils::Unicode::utf8encode_locale($value);
					}

					$params->{$name} = $value;

					$::d_http && msg("HTTP parameter $name = $value\n");

				} else {

					my $name = Slim::Utils::Misc::unescape($param, 1);

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
						. qq( skin, try ) . Slim::Utils::Prefs::homeURL() . qq( instead.);
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
			$params->{"path"} = Slim::Utils::Misc::unescape($path);
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
		#$response->content("");
		#msg("Response Headers: [\n" . $response->as_string() . "]\n");
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

	# This is trumped by query parameters 'command' and 'subcommand'.
	# These are passed as the first two command parameters (p0 and p1), 
	# while the rest of the query parameters are passed as third (p3).
	if (defined $params->{'command'} && $path !~ /^memoryusage/) {
		$p[0] = $params->{'command'};
		$p[1] = $params->{'subcommand'};
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
			# set to the closest lower value of its not a match
			my $temprate = $params->{'bitrate'};

			foreach my $i (qw(320 256 244 192 160 128 112 96 80 64 56 48 40 32)) {
				$temprate = $i; 	 
				last if ($i <= $params->{'bitrate'}); 	 
			}

			$client->prefSet('transcodeBitrate',$temprate); 	 
			$::d_http && msg("Setting transcode bitrate to $temprate\n"); 	 

		} else {

			$client->prefSet('transcodeBitrate',undef);
		}
	}
	
	# player specified from cookie
	if ( !defined $client && $params->{'cookies'} ) {
		if ( my $player = $params->{'cookies'}->{'SlimServer-player'} ) {
			$client = Slim::Player::Client::getClient( $player->value );
		}
	}

	# if we don't have a player specified, just pick one if there is one...
#	if (!defined($client) && Slim::Player::Client::clientCount() > 0) {
#		$client = (Slim::Player::Client::clients())[0];
#	}
	$client = Slim::Player::Client::clientRandom() if !defined $client;

	if (blessed($client) && $client->can('id')) {

		$peerclient{$httpClient} = $client->id;
	}

	if ($client && $client->isa("Slim::Player::SLIMP3")) {

		$params->{'playermodel'} = 'slimp3';
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

=HEAD1 Send the response to the client

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

	$params->{'player'} = '';
	$params->{'nosetup'} = 1   if $::nosetup;
	$params->{'noserver'} = 1   if $::noserver;

	if (Slim::Web::Graphics::serverResizesArt()) {
		$params->{'serverResizesArt'} = 1;
	}

	my $path = $params->{"path"};
	my $type = Slim::Music::Info::typeFromSuffix($path, 'htm');

	# lots of people need this
	my $contentType = $params->{'Content-Type'} = $Slim::Music::Info::types{$type};

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

	$::d_http && msg("Generating response for ($type, $contentType) $path\n");

	# some generally useful form details...
	if (defined($client)) {
		$params->{'player'} = $client->id();
		$params->{'myClientState'} = $client;
		
		# save the player id in a cookie
		my $cookie = CGI::Cookie->new(
			-name    => 'SlimServer-player',
			-value   => $params->{'player'},
			-expires => '+1y',
		);
		$response->headers->push_header( 'Set-Cookie' => $cookie );
	}

	# this might do well to break up into methods
	if ($contentType =~ /image/) {

		# images should expire from cache one year from now
		$response->expires(time() + HALFYEAR);
		$response->header('Cache-Control' => sprintf('max-age=%d, public', 3600));
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

		$::perfmon && (my $startTime = Time::HiRes::time());

		$body = &{$pageFunctions{$path}}(
			$client,
			$params,
			\&prepareResponseForSending,
			$httpClient,
			$response,
		);

		$::perfmon && $startTime && $pageBuild->log(Time::HiRes::time() - $startTime) &&
			msgf ("  Generating page for %s\n", $path || '/');

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

	} elsif ($path =~ /music\/(\w+)\/(cover|thumb)/) {

		($body, $mtime, $inode, $size, $contentType) = Slim::Web::Graphics::processCoverArtRequest($client, $path);

	} elsif ($path =~ /music\/(\d+)\/download$/) {

		my $obj = Slim::Schema->find('Track', $1);

		if (blessed($obj) && Slim::Music::Info::isSong($obj) && Slim::Music::Info::isFile($obj)) {

			$::d_http && msg("Opening $obj to stream...\n");

			my $songHandle =  FileHandle->new(Slim::Utils::Misc::pathFromFileURL($obj->url()));

			if ($songHandle) {

				# Send the file down - and hint to the browser
				# the correct filename to save it as.
				$response->content_type( $Slim::Music::Info::types{$obj->content_type()} );
				$response->content_length($obj->filesize());
				$response->header('Content-Disposition', 
					sprintf('attachment; filename="%s"', Slim::Utils::Misc::unescape(basename($obj->url())))
				);

				my $headers = _stringifyHeaders($response) . $CRLF;

				$streamingFiles{$httpClient} = $songHandle;

				addStreamingResponse($httpClient, $headers, $params);

				return 0;
			}
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

	} elsif ($path =~ /status\.txt/ || $path =~ /log\.txt/) {

		# if the HTTP client has asked for a text file, then always return the text on the display
		$contentType = "text/plain";

		$response->header("Refresh" => "30; url=$path");
		$response->header("Content-Type" => "text/plain; charset=utf-8");

		buildStatusHeaders($client, $response, $p);

		if ($path =~ /status/) {

			if (defined($client)) {
				my $parsed = $client->parseLines(Slim::Display::Display::curLines($client));
				my $line1 = $parsed->{line1} || '';
				my $line2 = $parsed->{line2} || '';
				$$body = $line1 . $CRLF . $line2 . $CRLF;
			} else {
				$$body = '';
			}

		} else {
			$$body = $Slim::Utils::Misc::log;

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

			$::d_http_verbose && msgf("\tifMatch - RC_PRECONDITION_FAILED\n");
			$response->code(RC_PRECONDITION_FAILED);
		}

	 } else {

		# Else if a valid If-Unmodified-Since request-header field was given
		# AND the requested resource has been modified since the time
		# specified in this field, then the server MUST
		#     respond with a status of 412 (Precondition Failed).
		my $ifUnmodified = $request->if_unmodified_since();

		if ($ifUnmodified && time() > $ifUnmodified) {

			 $::d_http_verbose && msgf("\tifUnmodified - RC_PRECONDITION_FAILED\n");

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

			$::d_http_verbose && msg("\tifNoneMatch - * - returning 304\n");
 			$response->code(RC_NOT_MODIFIED);

		} elsif ($etag) {

			if ($request->if_range()) {

				if ($etag ne 'W' && $ifNoneMatch eq $etag) {

					$::d_http_verbose && msg("\tETag is not weak and ifNoneMatch eq ETag - returning 304\n");
					$response->code(RC_NOT_MODIFIED);
				}

			} elsif ($ifNoneMatch eq $etag) {

				$::d_http_verbose && msg("\tifNoneMatch eq ETag - returning 304\n");
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

				$::d_http && msgf("Content at: %s has not been modified - returning 304.\n", $request->uri());

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
	$response->date(time());

	# If we're already a 304 - that means we've already checked before the static content fetch.
	if ($response->code() ne RC_NOT_MODIFIED) {

		contentHasBeenModified($response);
	}

	addHTTPResponse($httpClient, $response, $body);

	return 0;
}

# XXX - ick ick
sub _stringifyHeaders {
	my $response = shift;

	my $code = $response->code();
	my $data = '';

	$data .= sprintf("%s %s %s%s", $response->protocol(), $code, status_message($code) || "", $CRLF);

	$data .= sprintf("Date: %s%s", time2str(time), $CRLF);

	$data .= sprintf("Server: SlimServer (%s - %s)%s", $::VERSION, $::REVISION, $CRLF);

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

	# First add the headers
	my $headers = _stringifyHeaders($response) . $CRLF;

	push @{$outbuf{$httpClient}}, {
		'data'     => \$headers,
		'offset'   => 0,
		'length'   => length($headers),
		'response' => $response,
	};

	# And now the body.
	# Don't send back any content on a HEAD or 304 response.
	if ($response->request()->method() ne 'HEAD' && 
		$response->code() ne RC_NOT_MODIFIED &&
		$response->code() ne RC_PRECONDITION_FAILED) {

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
			if (!$connection || $connection =~ /close/i) {

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

	# Set the kernel's send buffer to be higher so that there is less
	# chance of audio skipping if/when we block elsewhere in the code.
	# 
	# Check to make sure that our target size isn't smaller than the
	# kernel's default size.
	if (unpack('I', getsockopt($httpClient, SOL_SOCKET, SO_SNDBUF)) < (MAXCHUNKSIZE * 2)) {

		setsockopt($httpClient, SOL_SOCKET, SO_SNDBUF, (MAXCHUNKSIZE * 2));
	}

	Slim::Networking::Select::addWrite($httpClient, \&sendStreamingResponse, 1);

	# we aren't going to read from this socket anymore so don't select on it...
	Slim::Networking::Select::addRead($httpClient, undef);

	if (my $client = Slim::Player::Client::getClient($peerclient{$httpClient})) {

		$client->streamingsocket($httpClient);

		my $newpeeraddr = getpeername($httpClient);
	
		$client->paddr($newpeeraddr) if $newpeeraddr;
	}	
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

			my $bitrate = Slim::Utils::Prefs::maxRate($client);
			my $silencedataref = ($bitrate == 320 || $bitrate == 0) ? getStaticContent("html/silence.mp3") : getStaticContent("html/lbrsilence.mp3");

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
			if ($chunkRef && length($$chunkRef)) {

				$::d_http && msg("(audio: " . length($$chunkRef) . " bytes)\n" );
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

				$::d_http && msg("Nothing to stream, let's wait for " . $retry . " seconds...\n");
				Slim::Networking::Select::addWrite($httpClient, 0);
				Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $retry, \&tryStreamingLater,($httpClient));
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

			my $title = $song ? Slim::Music::Info::getCurrentTitle($client, $song) : string('WELCOME_TO_SLIMSERVER');
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
				errorMsg("Could not load skin configuration file: $skinConfig\n$!\n");
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

	foreach my $dir ($skin, @skinParents, $baseSkin) {

		foreach my $rootDir (HTMLTemplateDirs()) {

			push @include_path, catdir($rootDir, $dir);
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
			$::d_http && !$found && msg("$checkfile not found in include path, skipping\n");
		}
	}

	$skinTemplates{$skin} = Template->new({

		INCLUDE_PATH => \@include_path,
		COMPILE_DIR => templateCacheDir(),
		PLUGIN_BASE => ['Plugins::TT',"HTML::$skin"],
		PRE_PROCESS => \@preprocess,
		FILTERS => {
			'string'        => \&Slim::Utils::Strings::string,
			'getstring'     => \&Slim::Utils::Strings::getString,
			'resolvestring' => \&Slim::Utils::Strings::resolveString,
			'nbsp'          => \&nonBreaking,
			'uri'           => \&URI::Escape::uri_escape_utf8,
			'unuri'         => \&URI::Escape::uri_unescape,
			'utf8decode'    => \&Slim::Utils::Unicode::utf8decode,
			'utf8encode'    => \&Slim::Utils::Unicode::utf8encode,
			'utf8on'        => \&Slim::Utils::Unicode::utf8on,
			'utf8off'       => \&Slim::Utils::Unicode::utf8off,
		},

		EVAL_PERL => 1,
	});

	return $skinTemplates{$skin};
}

sub templateCacheDir {

	return catdir( Slim::Utils::Prefs::get('cachedir'), 'templates' );
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

	my $skin = $params->{'skinOverride'} || Slim::Utils::Prefs::get('skin');

	$::d_http && msg("generating from $path\n");

	if ($type eq 'fill') {
		
		my $template = $skinTemplates{$skin} || newSkinTemplate($skin);
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

		if (!$template->process($path,$params,\$output)) {
			errorMsg($template->error() . "\n");
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

# Retrieves the file specified as $path, relative to HTMLTemplateDir() and
# the specified $skin or the $baseskin if not present in the $skin.
# Uses binmode to read file if $binary is specified.
# Returns a reference to the file data.

sub _getFileContent {
	my ($path, $skin, $binary, $statOnly) = @_;

	my ($content, $template, $mtime, $inode, $size);

	my $skinkey = "${skin}/${path}";

	$::d_http && msg("reading http file for ($skin $path)\n");

	my $skinpath = fixHttpPath($skin, $path);

	if (!defined($skinpath) || 
		(!open($template, $skinpath . '.' . lc(Slim::Utils::Prefs::get('language'))) && !open($template, $skinpath))
	   ) {

		my $baseSkin = baseSkin();

		$::d_http && msg("couldn't find $skin $path trying for $baseSkin\n");

		my $defaultpath = fixHttpPath($baseSkin, $path);

		if (defined($defaultpath)) {
			$::d_http && msg("reading file: $defaultpath\n");

			# try to open language specific files, and if not, the specified one.
			open($template, $defaultpath . '.' . lc(Slim::Utils::Prefs::get('language'))) || open($template, $defaultpath);

			($inode, $size, $mtime) = (stat($template))[1,7,9];
		} 

	} else {

		($inode, $size, $mtime) = (stat($template))[1,7,9];
	}

	# If we only want the file attributes and not the content - close the
	# filehandle before slurping in the bits.
	if ($statOnly) {

		close $template if $template;

	} elsif ($template) {

		local $/ = undef;
		binmode($template) if $binary;
		$content = <$template>;
		close $template;
		$::d_http && (length($content) || msg("File empty: $path"));

	} else {

		errorMsg("_getFileContent: Couldn't open: $path\n");
	}
	
	return (\$content, $mtime, $inode, $size);
}

sub HomeURL {
	msg("Info: Slim::Web::HTTP::HomeURL is deprecated. Please call Slim::Utils::Prefs::homeURL() instead.\n");
	bt(); 

	return Slim::Utils::Prefs::homeURL();
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

sub buildStatusHeaders {
	my $client   = shift;
	my $response = shift;
	my $p = shift;

	my %headers;
	
	if ($client) {
		# send headers
		%headers = ( 
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
	
			$headers{"x-playervolume"} = int($client->prefGet("volume") + 0.5);
			$headers{"x-playermode"}   = Slim::Buttons::Common::mode($client) eq "power" ? "off" : Slim::Player::Source::playmode($client);
	
			my $sleep = $client->sleepTime() - Time::HiRes::time();
	
			$headers{"x-playersleep"}  = $sleep < 0 ? 0 : int($sleep/60);
		}	
		
		if ($client && Slim::Player::Playlist::count($client)) { 

			my $track = Slim::Schema->rs('Track')->objectForUrl(Slim::Player::Playlist::song($client));
	
			$headers{"x-playertrack"} = Slim::Player::Playlist::song($client); 
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
	
	# include returned parameters
	my $i = 0;
	foreach my $pn (@$p) {
		$headers{"x-p$i"} = $pn;
		$i++;
	}
	
	# simple quoted printable encoding
	while (my ($key, $value) = each %headers) {
		if (defined($value) && length($value)) {

			if ($] > 5.007) {
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

	closeHTTPSocket($httpClient, 1);

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
	push @templateDirs, $dir if (not grep({$_ eq $dir} @templateDirs));
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
			$::d_http && msg("No valid CSRF auth code: [" . join(' ', ($request->method(), $request->uri(), $request->header('X-Slim-CSRF'))) . "]\n");

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
