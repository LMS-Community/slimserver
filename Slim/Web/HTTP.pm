package Slim::Web::HTTP;

# $Id: HTTP.pm,v 1.74 2004/02/25 19:21:19 dean Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use FindBin qw($Bin);
use IO::Socket;
use FileHandle;
use Net::hostent;              # for OO version of gethostbyaddr
use Sys::Hostname;
use File::Spec::Functions qw(:ALL);
use MIME::Base64;
use HTTP::Date;

use POSIX qw(:fcntl_h strftime);
use Fcntl qw(F_GETFL F_SETFL);

use Tie::RegexpHash;
use Slim::Player::HTTP;
use Slim::Web::History;
use Slim::Networking::mDNS;
use Slim::Networking::Select;
use Slim::Utils::Misc;
use Slim::Web::Olson;
use Slim::Utils::OSDetect;
use Slim::Web::Pages;
use Slim::Utils::Strings qw(string);
use Slim::Web::EditPlaylist;

#
#constants
#
BEGIN {
	if ($^O =~ /Win32/) {
		*EWOULDBLOCK = sub () { 10035 };
		*EINPROGRESS = sub () { 10036 };
	} else {
		require Errno;
		import Errno qw(EWOULDBLOCK EINPROGRESS);
	}
}

our ($EOL) = "\015\012";
my($BLANK) = $EOL x 2;
my($NEWLINE) = "\012";
my($defaultskin)="Default";
my($baseskin)="EN";
my($METADATAINTERVAL) = 32768;

my($MAXCHUNKSIZE) = 32768;

my($RETRY_TIME) = 0.05;

my $ONE_YEAR = 60 * 60 * 24 * 365;

#
# Package variables
#

my(%templatefiles);

my $openedport = 0;
my $http_server_socket;
my $connected = 0;

my %outbuf = (); # a hash for each writeable socket containing a queue of output segments
                 #   each segment is a hash of a ref to data, an offset and a length
my %sendMetaData;
my %metaDataBytes;
my %streamingFiles;
my %peeraddr;
my %peerclient;

my $mdnsIDslimserver;
my $mdnsIDhttp;

my %pageFunctions;
tie %pageFunctions, 'Tie::RegexpHash';

$pageFunctions{qr/^$/} = \&Slim::Web::Pages::home;
$pageFunctions{qr/^index\.(?:htm|xml)/} = \&Slim::Web::Pages::home;
$pageFunctions{qr/browseid3\.(?:htm|xml)/} = \&Slim::Web::Pages::browseid3;
$pageFunctions{qr/browse\.(?:htm|xml)/} = \&Slim::Web::Pages::browser;
$pageFunctions{qr/edit_playlist\.(?:htm|xml)/} = \&Slim::Web::EditPlaylist::editplaylist;  # Needs to be before playlist
$pageFunctions{qr/^firmware\.(?:html|xml)/} = \&Slim::Web::Pages::firmware;
$pageFunctions{qr/hitlist\.(?:htm|xml)/} = \&Slim::Web::History::hitlist;
$pageFunctions{qr/home\.(?:htm|xml)/} = \&Slim::Web::Pages::home;
$pageFunctions{qr/instant_mix\.(?:htm|xml)/} = \&Slim::Web::Pages::instant_mix;
$pageFunctions{qr/mood_wheel\.(?:htm|xml)/} = \&Slim::Web::Pages::mood_wheel;
$pageFunctions{qr/olsondetail\.(?:htm|xml)/} = \&Slim::Web::Olson::olsondetail;
$pageFunctions{qr/olsonmain\.(?:htm|xml)/} = \&Slim::Web::Olson::olsonmain;
$pageFunctions{qr/playlist\.(?:htm|xml)/} = \&Slim::Web::Pages::playlist;
$pageFunctions{qr/search\.(?:htm|xml)/} = \&Slim::Web::Pages::search;
$pageFunctions{qr/songinfo\.(?:htm|xml)/} = \&Slim::Web::Pages::songinfo;
$pageFunctions{qr/status_header\.(?:htm|xml)/} = \&Slim::Web::Pages::status_header;
$pageFunctions{qr/status\.(?:htm|xml)/} = \&Slim::Web::Pages::status;
$pageFunctions{qr/^update_firmware\.(?:htm|xml)/} = \&Slim::Web::Pages::update_firmware;
$pageFunctions{qr/setup\.(?:htm|xml)/} = \&Slim::Web::Setup::setup_HTTP;

# initialize the http server
sub init {
	idle();
}	

sub openport {
	my ($listenerport, $listeneraddr) = @_;
	#start our listener

	$http_server_socket = IO::Socket::INET->new( Proto     => 'tcp',
									 LocalPort => $listenerport,
									 LocalAddr => $listeneraddr,
									 Listen    => SOMAXCONN,
									 ReuseAddr     => 1,
									 Reuse     => 1,
									 Timeout   => 0.001
									 );

	die "can't setup the listening port $listenerport for the HTTP server: $!" unless $http_server_socket;
	
	defined(Slim::Utils::Misc::blocking($http_server_socket,0)) || die "Cannot set port nonblocking";

	$openedport = $listenerport;
	Slim::Networking::Select::addRead($http_server_socket, \&acceptHTTP);
	
	$::d_http && msg("Server $0 accepting http connections on port $listenerport\n");
	
	$mdnsIDhttp = Slim::Networking::mDNS::advertise(Slim::Utils::Prefs::get('mDNSname'), '_http._tcp', $listenerport);
	$mdnsIDslimserver = Slim::Networking::mDNS::advertise(Slim::Utils::Prefs::get('mDNSname'), '_slimdevices_slimserver_http._tcp', $openedport);

}

sub checkHTTP {
	# check to see if our HTTP port has changed.
	if ($openedport != Slim::Utils::Prefs::get('httpport')) {

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

	my $httpclientsock = $http_server_socket->accept();

	if ($httpclientsock) {
		defined(Slim::Utils::Misc::blocking($httpclientsock,0)) || die "Cannot set port nonblocking";

		my $peer = $httpclientsock->peeraddr;
		if ($httpclientsock->connected && $peer) {
			my $tmpaddr = inet_ntoa($peer);
			# Check if source address is valid
			if (
			    !(Slim::Utils::Prefs::get('filterHosts')) || 
			    (Slim::Utils::Misc::isAllowedHost($tmpaddr))
			   )
			{	
				$peeraddr{$httpclientsock} = $tmpaddr;
				Slim::Networking::Select::addRead($httpclientsock, \&processHTTP);
				$connected++;
				$::d_http && msg("Accepted connection $connected from ". $peeraddr{$httpclientsock} . "\n");
			} else {
				$::d_http && msg("Did not accept HTTP connection from ". $tmpaddr . ", unauthorized source\n");
				$httpclientsock->close();
			}
		} else {
			$::d_http && msg("Did not accept connection, couldn't get peer addr\n");
		}
	} else {
		$::d_http && msg("Did not accept connection, accept returned nothing\n");
	}
}

#
#  Handle an HTTP request
#
sub processHTTP {
	my $httpclientsock = shift;
	my %params;
	my $firstline;

	if ($httpclientsock) {

		%params = ();
		my %headers = ();
		$httpclientsock->autoflush(1);

		$::d_http && msg("reading request...\n");
		$firstline = Slim::Utils::Misc::sysreadline($httpclientsock,1); # <$httpclientsock>;	  
	  	$::d_http && msg("HTTP request: $firstline\n");
	  	
		if (!defined($firstline)) { #socket half-closed from client
			$::d_http && msg("Client at " . $peeraddr{$httpclientsock} . " disconnected\n");

			closeHTTPSocket($httpclientsock);
		} elsif ($firstline =~ /^GET ([\w\$\-\.\+\*\(\)\?\/,;:@&=!\'%]*) HTTP\/1.[01][\015\012]+$/i)  {
			my @paramarray;
			my $param;
			my $url;
		    my $path;

			$url = $1;
			
			$sendMetaData{$httpclientsock} = 0;
			
			my $authorized = !Slim::Utils::Prefs::get("authorize");

			while (my $line = Slim::Utils::Misc::sysreadline($httpclientsock,1)){ # <$httpclientsock>) {
				if ($line) {
					# authorization header.
					if ($line =~ /^Icy-MetaData/i) {
						$sendMetaData{$httpclientsock} = 1;
					}
					
					if ($line =~ /^Authorization: Basic (.*)/) {
						$authorized = &checkAuthorization($1);
					}
                    # End of headers
					if ($line !~ /\S/) {  
						last;
					}
				}
			}

			if (!$authorized) { # no Valid authorization supplied!
				my $name = string('SLIMSERVER');
				my $result = "HTTP/1.0 401 Authorization Required";
				$headers{'WWW-Authenticate'} = qq(basic realm="$name");
				$headers{'Content-type'} = 'text/html';
				generateResponse_Done(undef,\%params
							,filltemplatefile('html/errors/401.html',\%params)
							,$httpclientsock,\$result,\%headers,{});
				return undef;
			}
				
			# parse out URI:
			
			$url =~ /^([\/\w\$\-\.\+\*\(\),;:@&=!'%]*).*(?:\?([\w\$\-\.\+\*\(\),;:@&=!'%]*|))$/; 	

			if ($1) {
				$path = $1;
				$::d_http && msg("HTTP request from " . $peeraddr{$httpclientsock} . " for: " . $url . "\n");
			}

			if ($2) {
				$params{'queryparams'} = $2;
				@paramarray = split(/&/, $2);
				foreach $param (@paramarray) {
					if ($param =~ /([^=]+)=(.*)/) {
						my $name = unescape($1,1);
						my $value = unescape($2,1);
						$params{$name} = $value;
						$::d_http && msg("HTTP parameter $name = $value\n");
					} else {
						my $name = unescape($param,1);
						$params{$name} = 1;
						$::d_http && msg("HTTP parameter from $name = 1\n");
					}
				}
			}
			
			if ($path) {
				$params{'webroot'} = '/';
				if ($path =~ s{^/slimserver/}{/}i) {
					$params{'webroot'} = "/slimserver/"
				}
				if ($path =~ m|^/(.+?)/.*| && $path !~ m|^/html/|i) {
					my $desiredskin = $1;
					#Requesting a specific skin, verify and set the skinOverride param
					$::d_http && msg("Alternate skin $desiredskin requested\n");
					my %skins = Slim::Web::Setup::skins();
					foreach my $skin (keys %skins) {
						 if ($skin =~ /$desiredskin$/i) {
							$params{'skinOverride'} = $desiredskin;
							$params{'webroot'} = $params{'webroot'} . "$desiredskin/";
							$path =~ s{^/.+?/}{/};
							last;
						}
					}
				}
				$path =~ s|^/+||;
				$params{"path"} = unescape($path);
			}
			
			#process the commands
			executeurl($httpclientsock, \%params);

		} else {	 
			$::d_http && msg("Bad Request: [". $firstline . "]\n");
			my $result = "HTTP/1.0 400 Bad Request";
			$headers{'Content-type'} = 'text/html';
			$params{'request'} = $firstline;
			generateResponse_Done(undef,\%params
						,filltemplatefile('html/errors/400.html',\%params)
						,$httpclientsock,\$result,\%headers,{});
		}

	$::d_http && msg("Ready to accept a new HTTP connection.\n\n");
	
	}
}

# executeurl - handles the execution of the HTTP request
#
#
sub executeurl {
	my($httpclientsock, $paramsref) = @_;
	my $output = "";
	my @p;
	my($client) = undef;

	my $path = $$paramsref{"path"};
	
	# Command parameters are query parameters named p0 through pN
	# 	For example:
	#		http://host/status.m3u?p0=playlist&p1=jump&p2=2 
	# This example jumps to the second song in the playlist and sends a playlist as the response
	#
	# If there are multiple players, then they are specified by the player id
	#   For example:
	#		http://host/status.html?p0=mixer&p1=volume&p2=11&player=10.0.1.203:69
	#


	my $i = 0;
	while (defined $$paramsref{"p$i"}) {
		$p[$i] = $$paramsref{"p$i"};
		$i++;
	}
	
	$::d_http && msg("ExecuteURL Clients $path: ".join(" ", Slim::Player::Client::clientIPs())."\n");

	# explicitly specified player (for web browsers or squeezeboxen)
	
	if (defined($$paramsref{"player"})) {
		$client = Slim::Player::Client::getClient($$paramsref{"player"});
	}

	# is this an HTTP stream?
	if (!defined($client) && ($path =~ /(?:stream\.mp3|stream)$/)) {
	
		my $address = $peeraddr{$httpclientsock};
	
		$::d_http && msg("executeurl found HTTP client at address=$address\n");
	
		$client = Slim::Player::Client::getClient($address);
		
		if (!defined($client)) {
			my $paddr = getpeername($httpclientsock);
			$::d_http && msg ("new http client at $address\n");
			if ($paddr) {
				$client = Slim::Player::HTTP->new(
					$address,
					$paddr, 
					$httpclientsock);
					
				$client->init();
			}
		}
	}

	#if we don't have a player specified, just pick one if there is one...
	if (!defined($client) && Slim::Player::Client::clientCount() > 0) {
		my @allclients = Slim::Player::Client::clients();
		$client = $allclients[0];
	}

	$peerclient{$httpclientsock} = $client;

	if ($client && $client->isPlayer() && $client->model() eq 'slimp3') {
		$$paramsref{"playermodel"} = 'slimp3';
	} else {
		$$paramsref{"playermodel"} = 'squeezebox';
	}

	my @callbackargs = ($client, $httpclientsock, $paramsref);

	# only execute a command on the client if there is one and if we have a command.
	if (defined($client) && defined($p[0])) {
		if (defined($$paramsref{"player"}) && $$paramsref{"player"} eq "*") {
			foreach my $client2 (Slim::Player::Client::clients()) {
				next if $client eq $client2;
				Slim::Control::Command::execute($client2, \@p);
			}
		}
		Slim::Control::Command::execute($client, \@p, \&generateresponse, \@callbackargs);
	} else {
		generateresponse(@callbackargs);
	}
}

sub addresponse {
	my $httpclientsock = shift;
	my $messageref = shift;
	my %segment = ( 
		'data' => $messageref,
		'offset' => 0,
		'length' => length($$messageref)
	);
	push @{$outbuf{$httpclientsock}}, \%segment;
	Slim::Networking::Select::addWrite($httpclientsock, \&sendresponse);
}

sub sendresponse {
	my $httpclientsock = shift;
	my $segmentref = shift(@{$outbuf{$httpclientsock}});
	my $sentbytes;
	if ($segmentref && $httpclientsock->connected) {
		$::d_http && msg("Sending message to " . $peeraddr{$httpclientsock} . "\n");
		$sentbytes = syswrite $httpclientsock,${$segmentref->{'data'}}, $segmentref->{'length'}, $segmentref->{'offset'};

		if ($! == EWOULDBLOCK) {
			$sentbytes = 0 unless defined($sentbytes);
		}	

		if (defined($sentbytes)) {
			if ($sentbytes < $segmentref->{'length'}) { #sent incomplete message
				$segmentref->{'length'} -= $sentbytes;
				$segmentref->{'offset'} += $sentbytes;
				unshift @{$outbuf{$httpclientsock}},$segmentref;
			} else { #sent full message
				if (@{$outbuf{$httpclientsock}} == 0) { #no more messages to send
					$::d_http && msg("No more messages to send to " . $peeraddr{$httpclientsock} . ", closing socket\n");
					closeHTTPSocket($httpclientsock);
				} else {
					$::d_http && msg("More to send to " . $peeraddr{$httpclientsock} . "\n");
				}
			}
		} else {
			# Treat $httpclientsock with suspicion
			$::d_http && msg("Send to " . $peeraddr{$httpclientsock} . " had error\n");
			closeHTTPSocket($httpclientsock);
		}
	} else {
		$::d_http && msg("Got nothing for message to" . $peeraddr{$httpclientsock} . ", closing socket\n");
		closeHTTPSocket($httpclientsock);
	}
}

# the two following routines support HTTP streaming of audio (a la ShoutCast and IceCast)
sub addstreamingresponse {
	my $httpclientsock = shift;
	my $message = shift;
	my $paramref = shift;
	
	my %segment = ( 
		'data' => \$message,
		'offset' => 0,
		'length' => length($message)
	);

	push @{$outbuf{$httpclientsock}}, \%segment;
	Slim::Networking::Select::addWrite($httpclientsock, \&sendstreamingresponse);
		
	# we aren't going to read from this socket anymore so don't select on it...
	Slim::Networking::Select::addRead($httpclientsock, undef);

	my $client = $peerclient{$httpclientsock};
		if ($client) {
			$client->streamingsocket($httpclientsock);
		my $newpeeraddr = getpeername($httpclientsock);
	
		if ($newpeeraddr) {
			$client->paddr($newpeeraddr)
		}
	}	
}

sub checkAuthorization {
	my $ok = 0;
	if (Slim::Utils::Prefs::get('authorize')) {
		my ($username, $password) = split (':',decode_base64(shift));
		if ($username eq Slim::Utils::Prefs::get('username')) {
			my $pwd  = Slim::Utils::Prefs::get('password');
			if ($pwd eq $password && $pwd eq '') {
				$ok = 1;
			} else {
				my $salt = substr($pwd, 0, 2);
				if (crypt($password, $salt) eq $pwd) {
					$ok = 1;
				}
			}
		} else {
			foreach my $client (Slim::Player::Client::clients()) {
				if (defined($client->password) && $client->password eq $password) {
					$ok = 1;
					last;
				}
			}
		}
	}
	else { # No authorization needed
		$ok = 1;
	}
	return $ok;
}

sub forgetClient {
	my $client = shift;
	if (defined($client->streamingsocket)) {
		closeStreamingSocket($client->streamingsocket);
	}
}

sub closeHTTPSocket {
	my $httpclientsock = shift;

	Slim::Networking::Select::addRead($httpclientsock, undef);
	Slim::Networking::Select::addWrite($httpclientsock, undef);
	delete($outbuf{$httpclientsock}); #clean up the hashes
	delete($sendMetaData{$httpclientsock});
	delete($metaDataBytes{$httpclientsock});
	delete($peeraddr{$httpclientsock});
	$httpclientsock->close();
	$connected--;
}

sub closeStreamingSocket {
	my $httpclientsock = shift;
	
	$::d_http && msg("Closing streaming socket.\n");
	
	if (defined $streamingFiles{$httpclientsock}) {
		$::d_http && msg("Closing streaming file.\n");
		close $streamingFiles{$httpclientsock};
		delete $streamingFiles{$httpclientsock};
	}
	
	foreach my $client (Slim::Player::Client::clients()) {
		if (defined($client->streamingsocket) && $client->streamingsocket == $httpclientsock) {
			$client->streamingsocket(undef);
			Slim::Utils::Timers::killTimers($client, \&tryStreamingLater);
		}
	}
	delete($peerclient{$httpclientsock});
	closeHTTPSocket($httpclientsock);
	return;
} 

sub sendstreamingresponse {
	my $httpclientsock = shift;
	my $sentbytes;
	
	my $client = $peerclient{$httpclientsock};
	assert($client);
	my $segmentref = shift(@{$outbuf{$httpclientsock}});
	my $streamingFile = $streamingFiles{$httpclientsock};
	my $silence = 0;
	
	$::d_http && msg("sendstreaming response begun...\n");

	if (($client->model eq 'squeezebox') && 
		defined($httpclientsock) && 
		(!defined($client->streamingsocket()) || $httpclientsock != $client->streamingsocket())) {
		$::d_http && msg($client->id() . " We're done streaming this socket to client\n");
		closeStreamingSocket($httpclientsock);
		return;
	}
	
	if (!$httpclientsock->connected) {
		closeStreamingSocket($httpclientsock);
		$::d_http && msg("Streaming client closed connection...\n");
		return undef;
	}
	
	if ( !$streamingFile && $client && ($client->model eq 'squeezebox') && (Slim::Player::Source::playmode($client) eq 'stop')) {
		closeStreamingSocket($httpclientsock);
		$::d_http && msg("Squeezebox closed connection...\n");
		return undef;
	}
	
	if (!defined($streamingFile) && 
			$client && ($client->model eq 'http') && 
			((Slim::Player::Source::playmode($client) ne 'play') || (Slim::Player::Playlist::count($client) == 0))) {
		$silence = 1;
	} 

	# if we don't have anything in our queue, then get something
	if (!defined($segmentref)) {
		# if we aren't playing something, then queue up some silence
		if ($silence) {
			$::d_http && msg("(silence)");
			my $silencedataref = getStaticContentRef("html/silence.mp3");
			my %segment = ( 
				'data' => $silencedataref,
				'offset' => 0,
				'length' => length($$silencedataref)
			);
			unshift @{$outbuf{$httpclientsock}},\%segment;
		} else {
			my $chunkRef;
			if (defined($streamingFile)) {
				my $chunk;
				$streamingFile->sysread($chunk, $MAXCHUNKSIZE);
				if (defined($chunk) && length($chunk)) {
					$chunkRef = \$chunk;
				} else {
					# we're done streaming this stored file, closing connection.
					closeStreamingSocket($httpclientsock);
					$::d_http && msg("we're done streaming this stored file, closing connection....\n");
					return 0;
				}
			} else {
				$chunkRef = Slim::Player::Source::nextChunk($client, $MAXCHUNKSIZE);
			}
			
			# otherwise, queue up the next chunk of sound
			if ($chunkRef && length($chunkRef)) {
				$::d_http && msg("(audio: " . length($$chunkRef) . "bytes)\n" );
				my %segment = ( 
					'data' => $chunkRef,
					'offset' => 0,
					'length' => length($$chunkRef)
				);
				unshift @{$outbuf{$httpclientsock}},\%segment;
			} else {
				# let's try again after RETRY_TIME
				$::d_http && msg("Nothing to stream, let's wait for $RETRY_TIME seconds...\n");
				Slim::Networking::Select::addWrite($httpclientsock, 0);
				Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $RETRY_TIME, \&tryStreamingLater,($httpclientsock));
			}
		}
		# try again...
		$segmentref = shift(@{$outbuf{$httpclientsock}});
	}
	
	# try to send metadata, if appropriate
	if ($sendMetaData{$httpclientsock}) {
		# if the metadata would appear in the middle of this message, just send the bit before
		$::d_http && msg("metadata bytes: " . $metaDataBytes{$httpclientsock} . "\n");
		if ($metaDataBytes{$httpclientsock} == $METADATAINTERVAL) {
			unshift @{$outbuf{$httpclientsock}},$segmentref;
			my $song = Slim::Player::Playlist::song($client);
			my $title = $song ? Slim::Music::Info::standardTitle($client, $song) : string('WELCOME_TO_SLIMSERVER');
			$title =~ tr/'/ /;
			my $metastring = "StreamTitle='" . $title . "';";
			my $length = length($metastring);
			$metastring .= chr(0) x (16 - ($length % 16));
			$length = length($metastring) / 16;
			my $message = chr($length) . $metastring;
			my %segment = ( 
				'data' => \$message,
				'offset' => 0,
				'length' => length($message)
			);
			$segmentref = \%segment;
			
			$metaDataBytes{$httpclientsock} = 0;
			$::d_http && msg("sending metadata of length $length: '$metastring' (" . length($message) . " bytes)\n");
		} elsif (defined($segmentref) && $metaDataBytes{$httpclientsock} + $segmentref->{'length'} > $METADATAINTERVAL) {
			my $splitpoint = $METADATAINTERVAL - $metaDataBytes{$httpclientsock};
			
			# make a copy of the segment, and point to the second half, to be sent later.
			my %splitsegment = %$segmentref;
			$splitsegment{'offset'} += $splitpoint;
			$splitsegment{'length'} -= $splitpoint;
			
			unshift @{$outbuf{$httpclientsock}},\%splitsegment;
			
			#only send the first part
			$segmentref->{'length'} = $splitpoint;
			
			$metaDataBytes{$httpclientsock} += $splitpoint;
			$::d_http && msg("splitting message for metadata at " . $splitpoint . "\n");
		
		# if it's time to send the metadata, just send the metadata
		} else {
			if (defined($segmentref)) {
				$metaDataBytes{$httpclientsock} += $segmentref->{'length'};
			}
		}
	}

	if (defined($segmentref) && $httpclientsock->connected) {
		my $prebytes =  $segmentref->{'length'};
		$sentbytes = syswrite $httpclientsock,${$segmentref->{'data'}}, $segmentref->{'length'}, $segmentref->{'offset'};

		if ($! == EWOULDBLOCK) {
			$sentbytes = 0 unless defined($sentbytes);
		}	

		if (defined($sentbytes)) {
			if ($sentbytes < $segmentref->{'length'}) { #sent incomplete message
#				if (($sentbytes % 2) == 1) { msg( "ODD!:$sentbytes (tried: $prebytes)\n"); } else { msg( "even:$sentbytes (tried: $prebytes)\n"); }
				$::d_http && $sentbytes && msg("sent incomplete chunk, requeuing " . ($segmentref->{'length'} - $sentbytes). " bytes\n");
				$metaDataBytes{$httpclientsock} -= $segmentref->{'length'} - $sentbytes;
				$segmentref->{'length'} -= $sentbytes;
				$segmentref->{'offset'} += $sentbytes;
				unshift @{$outbuf{$httpclientsock}},$segmentref;
			}
		} else {
			$::d_http && msg("sendstreamingsocket syswrite returned undef\n");
			closeStreamingSocket($httpclientsock);
			return undef;
		}
	} else {
		$::d_http && msg("Got nothing for streaming data to " . $peeraddr{$httpclientsock} . "\n");
		return 0;
	}

	$::d_http && $sentbytes && msg("Streamed $sentbytes to " . $peeraddr{$httpclientsock} . "\n");
	return $sentbytes;
}

sub tryStreamingLater {
	my $client = shift;
	my $httpclientsock = shift;
	Slim::Networking::Select::addWrite($httpclientsock, \&sendstreamingresponse);
}

#
# Send the HTTP headers
#
sub printheaders {
	my(%headers) = @_;
	my $name;
	my $value;
	my $output = "";

	while (($name, $value) = each(%headers)) {
		if (defined($name) && defined($value)) {
			$output .= $name . ": " . $value . $EOL;
		}
	}
	return $output . $EOL;
}

#  all the HTML is read from template files, to make it easier to edit
#  templates are parsed with the following rules, in this order:
#
#  replace this:			with this:
#
#  [EVAL]bar[/EVAL]			evaluate bar as perl code and replace with
#                       	the value of the $out variable
#  {foo}					$hash{'foo'}
#  {%foo}					&escape($hash{'foo'})
#  {&foo}                   &htmlsafe($hash{'foo'})

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
#  [E]foo[/E]				escape('foo');
#  [NB]foo[/NB]				nonBreak('foo');

#  &lsqb;          	[
#  &rsqb;			]
#  &lbrc;          	{
#  &rbrc;			}

#
# Fills the template string $template with the key/values in the hash pointed to by hashref
# returns the filled template string
#
sub filltemplate {

	my ($template, $hashref) = @_;
	
	return \$template if (!defined($template) || length($template) == 0);

	my $client = defined($hashref) ? $$hashref{'myClientState'} : undef;

	my $out = '';
	$template=~s{\[EVAL\](.*?)\[/EVAL\]}{eval($1) || ''}esg;
	
	# first, substitute {%key} with the url escaped value for the given key in the hash
	$template=~s/{%([^{}]+)}/defined($$hashref{$1}) ? escape($$hashref{$1}) : ""/eg;
	
	# first, substitute {%key} with the url escaped value for the given key in the hash
	$template=~s/{&([^{}]+)}/defined($$hashref{$1}) ? htmlsafe($$hashref{$1}) : ""/eg;

	# do the same, but without the escape when given {key}
	$template=~s/{([^{}]+)}/defined($$hashref{$1}) ? $$hashref{$1} : ""/eg;
	
	# look up localized strings with [S stringname]
	$template=~s/\[S\s+([^\[\]]+)\]/&string($1)/eg;
	
	# set the value of a hash item
	$template=~s/\[SET\s+([^\[\] ]+)\s+([^\]]+)\]/$$hashref{$1} = $2; ""/esg;

	# [IF hashkey], [IFN hashkey], [EQ hashkey value], and [NE hashkey value]
	$template=~s/\[IF\s+([^\[\]]+)\](.*?)\[\/IF\]/$$hashref{$1} ? $2 : ''/esg;
	$template=~s/\[IFN\s+([^\[\]]+)\](.*?)\[\/IFN\]/$$hashref{$1} ? '' : $2/esg;
	$template=~s/\[EQ\s+([^\[\]]+)\s+(.+?)\](.*?)\[\/EQ\]/(defined($$hashref{$1}) && $$hashref{$1} eq $2) ? $3 :  ''/esg;
	$template=~s/\[NE\s+([^\[\]]+)\s+(.+?)\](.*?)\[\/NE\]/(!defined($$hashref{$1}) || $$hashref{$1} ne $2) ? $3 :  ''/esg;
	$template=~s/\[GT\s+([^\[\]]+)\s+(.+?)\](.*?)\[\/GT\]/(defined($$hashref{$1}) && $$hashref{$1} > $2) ? $3 :  ''/esg;
	$template=~s/\[LT\s+([^\[\]]+)\s+(.+?)\](.*?)\[\/LT\]/(defined($$hashref{$1}) && $$hashref{$1} < $2) ? $3 :  ''/esg;

	$template=~s|\[INCLUDE\s+([^\[\]]+)\]|${filltemplatefile($1, $hashref)}|esg;
	$template=~s{\[STATIC\s+([^\[\]]+)\]}{getStaticContent($1, $hashref)}esg;

	# make strings with spaces in them non-breaking by replacing the spaces with &nbsp;
	$template=~s/\[NB\](.+?)\[\/NB\]/nonBreaking($1)/esg;
	
	# escape any text between [E] and [/E]
	$template=~s/\[E\](.+?)\[\/E\]/escape($1)/esg;
	
	$template=~s/&lsqb;/\[/g;
    $template=~s/&rsqb;/\]/g;
	$template=~s/&lbrc;/{/g;
    $template=~s/&rbrc;/}/g;
	return \$template;
}

sub nonBreaking {
	my $string = shift;
	$string =~ s/\s/\&nbsp;/g;
	return $string;
}

#
# Retrieves the file specified as $path, relative to HTMLTemplateDir() and
# the specified $skin or the $baseskin if not present in the $skin.
# Uses binmode to read file if $binary is specified.
# Keeps a cache of files internally to reduce file i/o.
# Returns a reference to the file data.
#
sub getFileContent {
	my ($path,$skin,$binary) = @_;
	my $contentref;
	$$contentref = undef;
	my $template;
	my $skinkey = "${skin}/${path}";

	if (Slim::Utils::Prefs::get('templatecache')) {
		if (defined $templatefiles{$skinkey}) {
			return $templatefiles{$skinkey};
		}
	}

	$::d_http && msg("reading http file for ($skin $path)\n");

	my $skinpath = fixHttpPath($skin, $path);
	if (!defined($skinpath) || !open($template, $skinpath)) {
		$::d_http && msg("couldn't find $skin $path trying for $baseskin\n");
		my $defaultpath = fixHttpPath($baseskin, $path);
		if (defined($defaultpath)) {
			$::d_http && msg("reading template: $defaultpath\n");
			open $template, $defaultpath;
		} 
	}
	
	if ($template) {
		if ($binary) {
			binmode($template);
		}
		
		$$contentref=join('',<$template>);
	
		close $template;
		$::d_http && (length($$contentref) || msg("File empty: $path"));
	} else {
		msg("Couldn't open: $path\n");
	}
	
	if (Slim::Utils::Prefs::get('templatecache') && defined($contentref)) {
		$templatefiles{$skinkey} = $contentref;
	}
	
	return $contentref;
}

#
# Fills the template file specified as $path, using either the currently selected
# skin, or an override.
# Returns the filled template string
#

sub filltemplatefile {
	my ($path, $hashref) = @_;

	my $templateref;
	
	if (defined $hashref->{'skinOverride'}) {
		$templateref = getFileContent($path, $hashref->{'skinOverride'},1);
	} else {
		$templateref = getFileContent($path, Slim::Utils::Prefs::get('skin'),1);
	}

	return &filltemplate($$templateref, $hashref);
}

#
# Gets the static image file specified as $path, using either the currently selected
# skin, or an override.
# Returns the retrieved binary data.
#
sub getStaticContent {
	my $contentref = getStaticContentRef(@_);
	return $$contentref;
}

sub getStaticContentRef {
	my ($path, $hashref) = @_;
	my $contentref;
	if (defined $hashref->{'skinOverride'}) {
		$contentref = getFileContent($path, $hashref->{'skinOverride'},1);
	} else {
		$contentref = getFileContent($path, Slim::Utils::Prefs::get('skin'),1);
	}
	return $contentref;
}

sub clearCaches {
	%templatefiles = ();
}

sub HTMLTemplateDirs {
	my @dirs;
	if (Slim::Utils::OSDetect::OS() eq 'mac') {
		push @dirs, $ENV{'HOME'} . "/Library/SlimDevices/html/";
		push @dirs, "/Library/SlimDevices/html/";
	}
	push @dirs, catdir($Bin,'HTML');
	return @dirs;
}

sub defaultSkin {
	return $defaultskin;
}

sub baseSkin {
	return $baseskin;
}

sub HomeURL {
	my $host = $main::httpaddr || hostname || '127.0.0.1';
	my $port = Slim::Utils::Prefs::get('httpport');
	return "http://$host:$port/";
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


sub generateresponse {
	my($client, $httpclientsock, $paramsref, $pRef) = @_;
	my %headers;
	my $item;
	my $i;
	my $body; 
	my $result = "";
	
	my %paramheaders;
	
	$i = 0;
	while (defined($$pRef[$i])) {
		$paramheaders{"x-p$i"} = $$pRef[$i];
		$i++;
	}
	
	$$paramsref{'player'} = "";

	my $path = $$paramsref{"path"};
	
	my $type = Slim::Music::Info::typeFromSuffix($path, 'htm');
	my $contentType = $Slim::Music::Info::types{$type};
	
	$headers{"Content-Type"} = $contentType;
	$$paramsref{'Content-Type'} = $contentType;
	
	$::d_http && msg("Generating response for ($type, $contentType) $path\n");

	# some generally useful form details...
	if (defined($client)) {
#		$$paramsref{'player'} = escape($client->id());
		$$paramsref{'player'} = $client->id();
		$$paramsref{'myClientState'} = $client;
	}

	if (defined($contentType)) {
		if ($contentType =~ /image/) {
			# images should expire from cache one year from now
			# get the format right: Thu, 01 Dec 1994 16:00:00 GMT
			$headers{"Expires"} = time2str(time() + $ONE_YEAR);
		} else {
			$headers{"Expires"} = 0;
		}

	    $result = "HTTP/1.0 200 OK";

	    # force the cache to always be public.
	    $headers{'Cache-Control'} = 'public';
	    
	    if ($contentType =~ /text/) {
	    	filltemplatefile('include.html', $paramsref);
	    }
	    
	    my $coderef = $pageFunctions{$path};
	    if (ref($coderef) eq 'CODE') {
	    		$body = &$coderef($client, $paramsref, \&generateResponse_Done, $httpclientsock, \$result, \%headers, \%paramheaders);
	    } elsif ($path =~ /(?:stream\.mp3|stream)$/) {
			%headers = statusHeaders($client);
			$headers{"x-audiocast-name"} = string('SLIMSERVER');
			if ($sendMetaData{$httpclientsock}) {
				$headers{"icy-metaint"} = $METADATAINTERVAL;
				$headers{"icy-name"} = string('WELCOME_TO_SLIMSERVER');
			}
			my $output = $result . $EOL . printheaders(%headers, %paramheaders);
			$metaDataBytes{$httpclientsock} = - length($output);
			addstreamingresponse($httpclientsock, $output, $paramsref);
			return 0;

 		} elsif ($path =~ /music\/(.+)\/(cover|thumb)\.jpg$/) {
 			my $contenttype;
 			my $song = Slim::Utils::Misc::virtualToAbsolute($1);
			my @components = splitdir($path);
 			my $image = $2;
 			$::d_http && msg("Cover Art asking for: $image\n");
			$song = Slim::Utils::Misc::fixPath($song);
			my $imagedata;
 			($imagedata, $contenttype) = Slim::Music::Info::coverArt($song,$image);

 			if (defined($imagedata)) {
 				$body = \$imagedata; #$body should be a ref
				$headers{"Expires"} = time2str(time() + $ONE_YEAR);
 			} else {
				$body = getStaticContentRef("html/images/spacer.gif");
				$contentType = "image/gif";
			}
 			$headers{"Content-Type"} = $contentType;
		} elsif ($path =~ /music\/(.+)$/) {
			my $file = Slim::Utils::Misc::virtualToAbsolute($1);
			if (Slim::Music::Info::isSong($file) && Slim::Music::Info::isFile($file)) {
				$::d_http && msg("Opening $file to stream...\n");
				my $songHandle =  FileHandle->new();
				$songHandle->open($file);
				if ($songHandle) {			
					%headers = statusHeaders($client);
					$headers{"Content-Type"} = Slim::Music::Info::mimeType($file);
					$headers{"Content-Length"} = Slim::Music::Info::fileLength($file);
					my $output = $result . $EOL . printheaders(%headers, %paramheaders);
					$streamingFiles{$httpclientsock} = $songHandle;
					addstreamingresponse($httpclientsock, $output, $paramsref);
					return 0;
				}
			}
	    } elsif ($path =~ /favicon\.ico/) {
			$body = getStaticContentRef("html/mypage.ico", $paramsref); 
	    } elsif ($path =~ /slimserver\.css/) {
	    	$body = getStaticContentRef($path, $paramsref);
		} elsif ($path =~ /status\.txt/) {
			# if the HTTP client has asked for a text file, then always return the text on the display
			%headers = statusHeaders($client);
			$headers{"Expires"} = 0;
			$headers{"Content-Type"} = "text/plain";
			$headers{"Refresh"} = "30; url=$path";
			my ($line1, $line2) = Slim::Display::Display::curLines($client);
	
			$$body = $line1 . $EOL . $line2 . $EOL;
	
		} elsif ($path =~ /log\.txt/) {
			# if the HTTP client has asked for a text file, then always return the text on the display
			%headers = statusHeaders($client);
			$headers{"Expires"} = 0;
			$headers{"Content-Type"} = "text/plain";
			$headers{"Refresh"} = "30; url=$path";
			$$body = $Slim::Utils::Misc::log;

		} elsif ($path =~ /status\.m3u/) {
		# if the HTTP client has asked for a .m3u file, then always return the current playlist as an M3U
			%headers = statusHeaders($client);
	
			if (defined($client)) {
				my $count = Slim::Player::Playlist::count($client);
				if ($count) {
					$$body = Slim::Formats::Parse::writeM3U(\@{Slim::Player::Playlist::playList($client)});
				}
			}
		} elsif ($path =~ /html\//) {
			# content is in the "html" subdirectory within the template directory.
			
			# if it's HTML then use the template mechanism
			if ($contentType eq 'text/html' || $contentType eq 'text/xml') {
				# if the path ends with a slash, then server up the index.html file
				if ($path =~ m|/$|) {
					$path .= 'index.html';
				}
				$body = filltemplatefile($path, $paramsref);
			} else {
				# otherwise just send back the binary file
				$body = getStaticContentRef($path, $paramsref);
			}
		} elsif ($path =~ /status$/i) {
			# send back an empty response.
			$result = "HTTP/1.0 200 OK";
			$$body = '';
	    } else {
	    	$$body = undef;
	    }
	} else {
		$$body = undef;
	}
	
	# if there's a reference to an empty value, then there is no valid page at all
	if (defined($body) && !defined($$body)) {
		$body = filltemplatefile('html/errors/404.html',$paramsref);
		$result = "HTTP/1.0 404 Not Found";
	}

	# if the reference to the body is itself undefined, then we've started generating the page in the background
	if ($body) {
		return generateResponse_Done($client, $paramsref, $body, $httpclientsock, \$result, \%headers, \%paramheaders);
	} else {
		return 0;
	}
}

sub generateResponse_Done {
	my ($client, $paramsref, $bodyref, $httpclientsock, $resultref, $headersref, $paramheadersref) = @_;
	$$headersref{'Content-Length'} = length($$bodyref);
	$$headersref{'Connection'} = 'close';
	my $message = $$resultref . $EOL . printheaders(%$headersref, %$paramheadersref) . $$bodyref;
	addresponse($httpclientsock, \$message);
	return 0;
}
	

sub statusHeaders {
	my $client = shift;

	if (!defined($client)) { return; }
	
	my $sleeptime = $client->sleepTime() - Time::HiRes::time();
	if ($sleeptime < 0) { $sleeptime = 0 };
	
	# send headers
	my %headers = ( 
			"x-player"			=> $client->id(),
			"x-playername"		=> $client->name(),
			"x-playertracks" 	=> Slim::Player::Playlist::count($client),
			"x-playershuffle" 	=> Slim::Player::Playlist::shuffle($client) ? "1" : "0",
			"x-playerrepeat" 	=> Slim::Player::Playlist::repeat($client),
	# unsupported yet
	#		"x-playerbalance" => "0",
	#		"x-playerbase" => "0",
	#		"x-playertreble" => "0",
	#		"x-playersleep" => "0",
	);
	
	if ($client->isPlayer()) {
		$headers{"x-playervolume"} = int(Slim::Utils::Prefs::clientGet($client, "volume") + 0.5);
		$headers{"x-playermode"} = Slim::Buttons::Common::mode($client) eq "power" ? "off" : Slim::Player::Source::playmode($client);
		$headers{"x-playersleep"} = $sleeptime;
	}	
	
	if (Slim::Player::Playlist::count($client)) { 
		$headers{"x-playertrack"} 	 = Slim::Player::Playlist::song($client); 
		$headers{"x-playerindex"} 	 = Slim::Player::Source::currentSongIndex($client) + 1;
		$headers{"x-playertime"} 	 = Slim::Player::Source::songTime($client);
		$headers{"x-playerduration"} = Slim::Music::Info::durationSeconds(Slim::Player::Playlist::song($client));

		my $i = Slim::Music::Info::artist(Slim::Player::Playlist::song($client));
		if ($i) { $headers{"x-playerartist"} = $i; }
		$i = Slim::Music::Info::album(Slim::Player::Playlist::song($client));
		if ($i) { $headers{"x-playeralbum"} = $i; }
		$i = Slim::Music::Info::title(Slim::Player::Playlist::song($client));
		if ($i) { $headers{"x-playertitle"} = $i; }
		$i = Slim::Music::Info::genre(Slim::Player::Playlist::song($client));
		if ($i) { $headers{"x-playergenre"} = $i; }
	};

	return %headers;
}

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

sub escape {
	my $in = shift;
	if (defined($in)) {
		$in =~ s/([^a-zA-Z0-9\$\-_\.!\*\'\(\),])/'%' . sprintf "%02x", ord($1)/eg;
		return $in;
	} else {
		return '';
	}
}

sub htmlsafe {
	my $in = shift;
	if (defined($in)) {
		$in =~ s/&(?!\S+;)/&amp;/g;
		$in =~ s/>/&gt;/g;
		$in =~ s/</&lt;/g;
		$in =~ s/"/&quot;/g;
		return $in;
	} else {
		return '';
	}
}

1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
#
