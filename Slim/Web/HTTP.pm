package Slim::Web::HTTP;

# $Id: HTTP.pm,v 1.8 2003/08/04 23:53:47 sadams Exp $

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use FindBin qw($Bin);
use IO::Socket;
use IO::Select;
use FileHandle;
use Net::hostent;              # for OO version of gethostbyaddr
use Sys::Hostname;
use File::Spec::Functions qw(:ALL);
use MIME::Base64;

use POSIX qw(:fcntl_h strftime);
use Fcntl qw(F_GETFL F_SETFL);

use Slim::Web::History;
use Slim::Networking::mDNS;
use Slim::Utils::Misc;
use Slim::Web::Olson;
use Slim::Utils::OSDetect;
use Slim::Web::Pages;
use Slim::Utils::Strings qw(string);

BEGIN {
 		if ($^O =~ /Win32/) {
 			*EWOULDBLOCK = sub () { 10035 };
 			*EINPROGRESS = sub () { 10036 };
 		} else {
 			require Errno;
 			import Errno qw(EWOULDBLOCK EINPROGRESS);
 		}
}

#
#constants
#
my($EOL) = "\015\012";
my($BLANK) = $EOL x 2;
my($NEWLINE) = "\012";
my($defaultskin)="Default";
my($baseskin)="EN";
my($METADATAINTERVAL) = 32768;

#
# Package variables
#

my(%templatefiles);

my $openedport = 0;
my $http_server_socket;
my $connected = 0;

my $httpSelRead = IO::Select->new();
my $httpSelWrite = IO::Select->new();

my $streamingSelWrite = IO::Select->new();

my %outbuf = ();
my %sendMetaData;
my %metaDataBytes;
my %streamingFiles;
my %peeraddr;
my %paddr;

my $mdnsIDslimserver;
my $mdnsIDhttp;

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
	
 	if( $^O =~ /Win32/ ) {
 		my $temp = 1;
 		ioctl($http_server_socket, 0x8004667e, \$temp);
 	} else {
 		defined($http_server_socket->blocking(0))  || die "Cannot set port nonblocking";
 	}
	$openedport = $listenerport;

	$httpSelRead->add(Slim::Web::HTTP::serverSocket());   # readability on the HTTP server
	$main::selRead->add(Slim::Web::HTTP::serverSocket());
	
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
			$httpSelRead->remove($http_server_socket);
			$main::selRead->remove($http_server_socket);
			$http_server_socket->close();
			$openedport = 0;
		}

		# if we've got an HTTP port specified, open it up!
		if (Slim::Utils::Prefs::get('httpport')) {
			Slim::Web::HTTP::openport(Slim::Utils::Prefs::get('httpport'), $::httpaddr, $Bin);
		}
	}
}

sub idle {

	my $httpSelCanRead;
	my $httpSelCanWrite;
	my $streamingSelCanWrite;

	# check to see if the HTTP settings have changed
	Slim::Web::HTTP::checkHTTP();
	
	# check for HTTP
	($httpSelCanRead,$httpSelCanWrite)=IO::Select->select($httpSelRead,$httpSelWrite,undef, 0);

	#$::d_http && msg("Select returned\n");
	#$::d_http && defined($httpSelCanRead) && msg( "\tRead: ".join(',',@$httpSelCanRead)."\n");
	#$::d_http && defined($httpSelCanWrite) && msg("\tWrite:".join(',',@$httpSelCanWrite)."\n");

	# check to see if there's HTTP activity...
	my $tcpReads = 0;
	if (defined($httpSelCanRead) && scalar(@$httpSelCanRead)) {
		my $tcpConnectMaximum = Slim::Utils::Prefs::get("tcpConnectMaximum");
		my $tcpReadMaximum = Slim::Utils::Prefs::get("tcpReadMaximum");
		foreach my $sockHand (@$httpSelCanRead) {
			if ($sockHand == Slim::Web::HTTP::serverSocket()) {
				next if Slim::Web::HTTP::connectedSocket() > $tcpConnectMaximum;
				Slim::Web::HTTP::acceptHTTP();
			} else {
				Slim::Web::HTTP::processHTTP($sockHand);
				last if ++$tcpReads >= $tcpReadMaximum || Slim::Networking::Protocol::pending();
			}
		}
	}

	#send HTTP responses
	my $tcpWrites = 0;
	if (defined($httpSelCanWrite) && scalar(@$httpSelCanWrite)) {
		my $tcpWriteMaximum = Slim::Utils::Prefs::get("tcpWriteMaximum");
		foreach my $sockHand (@$httpSelCanWrite) {
			last if ++$tcpWrites > $tcpWriteMaximum || Slim::Networking::Protocol::pending();
			Slim::Web::HTTP::sendresponse($sockHand);
		}
	}
	
	#send data to streaming clients
	my $count = 0; 
	
	my $continue = $streamingSelWrite->count();

	while ($continue) {
    	(undef,$streamingSelCanWrite) = IO::Select->select(undef,$streamingSelWrite,undef,0);

	    if (defined($streamingSelCanWrite) && scalar(@$streamingSelCanWrite)) {
	    		#my $streamWriteMaximum = Slim::Utils::Prefs::get("streamWriteMaximum");
	    		#use tcp write maximum for now
	    		my $streamWriteMaximum = Slim::Utils::Prefs::get("tcpWriteMaximum");
			foreach my $sockHand (@$streamingSelCanWrite) {
				$continue = (Slim::Web::HTTP::sendstreamingresponse($sockHand) && 
							!Slim::Networking::Protocol::pending() && 
						($count < $streamWriteMaximum) && $continue );
				$count++;
				last if (!$continue || Slim::Networking::Protocol::pending() || $count > $streamWriteMaximum);
			}
	    } else {
			$continue=0
	    }
	}
	
	$::d_http && $count && msg("Done streaming to all players\n");
}

sub serverSocket {
	return $http_server_socket;
}

sub connectedSocket {
	return $connected;
}

sub acceptHTTP {
	my $httpclientsock = $http_server_socket->accept();
	if ($httpclientsock) {
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
				$httpSelRead->add($httpclientsock);
				$main::selRead->add($httpclientsock);
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

		$httpclientsock->autoflush(1);

		$firstline = <$httpclientsock>;
	  
	  	$::d_http && msg("HTTP request: $firstline\n");
		if (!defined($firstline)) { #socket half-closed from client
			$::d_http && msg("Client at " . $peeraddr{$httpclientsock} . " disconnected\n");
			$httpSelRead->remove($httpclientsock);
			$main::selRead->remove($httpclientsock);
			if (!($httpSelWrite->exists($httpclientsock)) && !($streamingSelWrite->exists($httpclientsock))) {
				close $httpclientsock;
				$connected--;
			}
		} elsif ($firstline =~ /^GET ([\w\$\-\.\+\*\(\)\?\/,;:@&=!\'%]*) HTTP\/1.[01][\015\012]+$/i)  {
			my @paramarray;
			my $param;
			my $url;
		    my $path;

			$url = $1;
			
			$sendMetaData{$httpclientsock} = 0;
			
			my $authorized = !Slim::Utils::Prefs::get("authorize");

			while (<$httpclientsock>) {
				if ($_) {
					# authorization header.
					if ($_ =~ /^Icy-MetaData/i) {
						$sendMetaData{$httpclientsock} = 1;
					}
					
					if ($_ =~ /^Authorization: Basic (.*)/) {
						$authorized = &checkAuthorization($1);
					}
                    # End of headers
					if ($_ !~ /\S/) {  
						last;
					}
				}
			}

			if (!$authorized) { # no Valid authorization supplied!
				my $name = string('SLIM_SERVER');
				my $message = "HTTP/1.0 401 Authorization Required" . $EOL . 
					"WWW-Authenticate: basic realm=\"$name\"" . $EOL .
					"Content-type: text/html$BLANK" . 
					"<HTML><HEAD><TITLE>401 Authorization Required</TITLE></HEAD>" . 
					"<BODY>401 Authorization is Required to access this Slim Server</BODY></HTML>$EOL";
				addresponse($httpclientsock,$message);
				return undef;
			}
				
			# parse out URI:
			
			$url =~ /^([\/\w\$\-\.\+\*\(\),;:@&=!'%]*).*(?:\?([\w\$\-\.\+\*\(\),;:@&=!'%]*|))$/; 	

			if ($1) {
				$path = $1;
				$::d_http && msg("HTTP request from " . $peeraddr{$httpclientsock} . " for: " . $url . "\n");
			}

			if ($2) {
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
					#Requesting a specific skin, verify and set the skinOverride param
					my %skins = Slim::Web::Setup::skins();
					my $skinlist = join '|',keys %skins;
					if ($1 =~ /($skinlist)/i) {
						$::d_http && msg("Alternate skin $1 requested\n");
						$params{'skinOverride'} = $1;
						$params{'webroot'} = $params{'webroot'} . "$1/";
						$path =~ s{^/.+?/}{/};
					} else {
						$::d_http && msg("Alternate skin $1 requested but not found\n");
					}
				}
				$path =~ s|^/+||;
				$params{"path"} = unescape($path);
			}
			
			#process the commands
			executeurl($httpclientsock, \%params);

		} else {	 
			$::d_http && msg("Bad Request: [". $firstline . "]\n");

			my $message = "HTTP/1.0 400 Bad Request" . $EOL . 
					"Content-type: text/html$BLANK<HTML><HEAD><TITLE>400 Bad Request</TITLE></HEAD><BODY>400 Bad Request: $firstline</BODY></HTML>$EOL";
			addresponse($httpclientsock,$message);
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
	my($command);
	my @p;
	my($client) = undef;

	$$paramsref{"path"} =~ /(?:\/|)([^.]*)(|\.[^.]+)$/;
	
	# Commands are extracted from the parameters p0 through pN
	#   For example:
	#       http://host/status.html?p0=stop
	# Both examples above execute a stop command, and sends an html status response
	#
	# Command parameters are query parameters named p0 through pN
	# 	For example:
	#		http://host/status.m3u?p0=playlist&p1=jump&p2=2 
	# This example jumps to the second song in the playlist and sends a playlist as the response
	#
	# If there are multiple players, then they are specified by the player id
	#   For example:
	#		http://host/status.html?p0=mixer&p1=volume&p2=11&player=10.0.1.203:69
	#

	$command = $1;

	my $i = 0;
	while (defined $$paramsref{"p$i"}) {
		$p[$i] = $$paramsref{"p$i"};
		$i++;
	}

	$::d_http && msg("ExecuteURL Clients $command: ", join " ", Slim::Player::Client::clientIPs(), "\n");

	if (defined($$paramsref{"player"})) {
		$client = Slim::Player::Client::getClient($$paramsref{"player"});
	}

	#if we don't have a player specified, just pick one if there is one...
	if (!defined($client) && Slim::Player::Client::clientCount() > 0) {
		my @allclients = Slim::Player::Client::clients();
		$client = $allclients[0];
	}
	
	if ($client && $client->model() && $client->model() eq 'slimp3') {
		$$paramsref{"playermodel"} = 'slimp3';
	} else {
		$$paramsref{"playermodel"} = 'squeezebox';
	}

	my @callbackargs = ($client, $httpclientsock, $paramsref);
	
	# only execute a command on the client if there is one and if we have a command.
	if (defined($client) && defined($p[0]) && $command ne 'stream') {
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
	my $message = shift;
	push @{$outbuf{$httpclientsock}}, $message;
	$httpSelWrite->add($httpclientsock);
	$main::selWrite->add($httpclientsock);
}

sub sendresponse {
	my $httpclientsock = shift;
	my $message = shift(@{$outbuf{$httpclientsock}});
	my $sentbytes;
	if ($message && $httpclientsock->connected) {
		$::d_http && msg("Sending message to " . $peeraddr{$httpclientsock} . "\n");
		$sentbytes = send $httpclientsock,substr($message,0,Slim::Utils::Prefs::get("tcpChunkSize")),0;

		if ($! == EWOULDBLOCK) {
			$sentbytes = 0 unless defined($sentbytes);
		}	

		if (defined($sentbytes)) {
			if ($sentbytes < length($message)) { #sent incomplete message
				unshift @{$outbuf{$httpclientsock}},substr($message,$sentbytes);
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
	
	my $newclient = 0;
	
	my $address = $peeraddr{$httpclientsock};

	$::d_http && msg("addstreamingresponse: $address\n");

	my $client;

#	my $client = Slim::Player::Client::getClient($address);
	
#	if (!defined($client) && !defined($streamingFiles{$httpclientsock})) {
		$client = Slim::Player::Client::newClient(
			$address,
			getpeername($httpclientsock), 
			$address,
			0, 
			0, 
			0, 
			$httpclientsock);
		$newclient = 1;
#	}
	
#	if (defined($client)) {
#		$client->paddr(getpeername($httpclientsock));
#		$client->usage(undef);
#		$client->streamingsocket($httpclientsock);
#		$client->type('http');
#		$client->decoder('shoutcast');
#	}
	
	push @{$outbuf{$httpclientsock}}, $message;
	$streamingSelWrite->add($httpclientsock);
	$main::selWrite->add($httpclientsock);
		
	# we aren't going to read from this socket anymore so don't select on it...
	$httpSelRead->remove($httpclientsock);
	$main::selRead->remove($httpclientsock);
	
#	# once the client is initialized, then we can start it right up.
#	if ($newclient) {
#		Slim::Player::Client::startup($client);
#	}
	
	if (defined $paramref->{'p0'} && $paramref->{'p0'} eq 'playlist') {
		Slim::Control::Command::execute($client, [$paramref->{'p0'},$paramref->{'p1'},$paramref->{'p2'}]);
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
			}
			my $salt = substr($pwd, 0, 2);
			if (crypt($password, $salt) eq $pwd) {
				$ok = 1;
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

	$streamingSelWrite->remove($httpclientsock);
	$httpSelWrite->remove($httpclientsock);
	$main::selWrite->remove($httpclientsock);
	$httpSelRead->remove($httpclientsock);
	$main::selRead->remove($httpclientsock);
	close $httpclientsock;
	delete($outbuf{$httpclientsock}); #clean up the hashes
	delete($sendMetaData{$httpclientsock});
	delete($metaDataBytes{$httpclientsock});
	delete($peeraddr{$httpclientsock});

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
		}
	}
	closeHTTPSocket($httpclientsock);
	return;
} 

sub sendstreamingresponse {
	my $httpclientsock = shift;
	my $sentbytes = 0;
	my $fullsend = 0;
	
	if (!$httpclientsock->connected) {
		closeStreamingSocket($httpclientsock);
		$::d_http && msg("Streaming client closed connection...\n");
		return $fullsend;
	}
	
	my $address = inet_ntoa($httpclientsock->peeraddr);
	my $client = Slim::Player::Client::getClient($address);
	my $message = shift(@{$outbuf{$httpclientsock}});
	my $streamingFile = $streamingFiles{$httpclientsock};
	my $silence = 0;
	
	if (!defined($streamingFile) && ((Slim::Player::Playlist::playmode($client) ne 'play') || (Slim::Player::Playlist::count($client) == 0))) {
		$silence = 1;
	}
	
	# if we don't have anything in our queue, then get something
	if (!defined($message)) {
		# if we aren't playing something, then queue up some silence
		if ($silence) {
			$::d_http && msg("(silence)");
			$silence = 1;
			unshift @{$outbuf{$httpclientsock}},getStaticContent("html/silence.mp3");
		} else {
			my $chunkRef;
			if (defined($streamingFile)) {
				my $chunk;
				$streamingFile->read($chunk, Slim::Utils::Prefs::get("tcpChunkSize"));
				$chunkRef = \$chunk;
			} else {
				$chunkRef = Slim::Player::Playlist::nextChunk($client, Slim::Utils::Prefs::get("tcpChunkSize"));
			}
			# otherwise, queue up the next chunk of sound
			if ($chunkRef) {
				$::d_http && msg("(audio)");
				unshift @{$outbuf{$httpclientsock}},$$chunkRef;
			}
		}
		# try again...
		$message = shift(@{$outbuf{$httpclientsock}});
	}
	
	# try to send metadata, if appropriate
	if ($sendMetaData{$httpclientsock}) {
		# if the metadata would appear in the middle of this message, just send the bit before
		$::d_http && msg("metadata bytes: " . $metaDataBytes{$httpclientsock} . "\n");
		if ($metaDataBytes{$httpclientsock} == $METADATAINTERVAL) {
			unshift @{$outbuf{$httpclientsock}},$message;
			my $song = Slim::Player::Playlist::song($client);
			my $title = $song ? Slim::Music::Info::standardTitle($client, $song) : string('WELCOME_TO_SQUEEZEBOX');
			$title =~ tr/'/ /;
			my $metastring = "StreamTitle='" . $title . "';";
			my $length = length($metastring);
			$metastring .= chr(0) x (16 - ($length % 16));
			$length = length($metastring) / 16;
			$message = chr($length) . $metastring;
			$metaDataBytes{$httpclientsock} = 0;
			$::d_http && msg("sending metadata of length $length: '$metastring' (" . length($message) . " bytes)\n");
		} elsif (defined($message) && $metaDataBytes{$httpclientsock} + length($message) > $METADATAINTERVAL) {
			unshift @{$outbuf{$httpclientsock}},substr($message,$METADATAINTERVAL - $metaDataBytes{$httpclientsock});
			$message = substr($message,0,$METADATAINTERVAL - $metaDataBytes{$httpclientsock});
			$metaDataBytes{$httpclientsock} += length($message);
			$::d_http && msg("splitting message for metadata at " . length($message) . "\n");
		# if it's time to send the metadata, just send the metadata
		} else {
			if (defined($message)) {
				$metaDataBytes{$httpclientsock} += length($message);
			}
		}
	}

	if ($message && $httpclientsock->connected) {
		$sentbytes = send $httpclientsock,substr($message,0,Slim::Utils::Prefs::get("tcpChunkSize")),0;	

		if ($! == EWOULDBLOCK) {
			$sentbytes = 0 unless defined($sentbytes);
		}	

		if (defined($sentbytes)) {
			if ($sentbytes < length($message)) { #sent incomplete message
				unshift @{$outbuf{$httpclientsock}},substr($message,$sentbytes);
				$metaDataBytes{$httpclientsock} -= length($message) - $sentbytes;
				$fullsend = 0;
			} else {
				$fullsend = 1;
			}
		} else {
			closeStreamingSocket($httpclientsock);
			return $fullsend;
		}
	} else {
		$::d_http && msg("Got nothing for message to " . $peeraddr{$httpclientsock} . ", closing socket\n");
		closeStreamingSocket($httpclientsock);
		return $fullsend;
	}

	$::d_http && $sentbytes && msg("Streamed $sentbytes to " . $peeraddr{$httpclientsock} . "\n");
	return $fullsend;
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

	my $client = defined($hashref) ? $$hashref{'myClientState'} : undef;

	my $out = '';
	$template=~s{\[EVAL\](.*?)\[/EVAL\]}{eval($1)}esg;
	
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

	$template=~s{\[INCLUDE\s+([^\[\]]+)\]}{filltemplatefile($1, $hashref)}esg;
	$template=~s{\[STATIC\s+([^\[\]]+)\]}{getStaticContent($1, $hashref)}esg;

	# make strings with spaces in them non-breaking by replacing the spaces with &nbsp;
	$template=~s/\[NB\](.+?)\[\/NB\]/nonBreaking($1)/esg;
	
	# escape any text between [E] and [/E]
	$template=~s/\[E\](.+?)\[\/E\]/escape($1)/esg;
	
	$template=~s/&lsqb;/\[/g;
    $template=~s/&rsqb;/\]/g;
	$template=~s/&lbrc;/{/g;
    $template=~s/&rbrc;/}/g;
	return $template;
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
	$$contentref = '';
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
		open $template, $defaultpath || $::d_http && msg("couldn't find $skinpath, reading template: $defaultpath\n");
	}
	
	if ($template) {
		if ($binary) {
			binmode($template);
		}
		
		$$contentref=join('',<$template>);
	
		close $template;
		$::d_http && (length($$contentref) || msg("File empty: $path"));
	} else {
		$::d_http && msg("Couldn't open: $path\n");
	}
	
	if (Slim::Utils::Prefs::get('templatecache')) {
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
	my ($path, $hashref) = @_;
	my $contentref;
	if (defined $hashref->{'skinOverride'}) {
		$contentref = getFileContent($path, $hashref->{'skinOverride'},1);
	} else {
		$contentref = getFileContent($path, Slim::Utils::Prefs::get('skin'),1);
	}

	return $$contentref;
}

sub clearCaches {
	%templatefiles = ();
}

sub HTMLTemplateDirs {
	my @dirs;
	push @dirs, catdir($Bin,'HTML');
	if ($^O eq 'darwin') {
		push @dirs, $ENV{'HOME'} . "/Library/SlimDevices/html/";
		push @dirs, "/Library/SlimDevices/html/";
	}
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
		$path = catdir($dir, $skin, $path);
		return $path if (-r $path);
	} 
	return undef;
}

#
# generate HTTP response - TODO: commments...what exactly does this do?
#
sub generateresponse {
	my($client, $httpclientsock, $paramsref, $pRef) = @_;
	my %headers;
	my $item;
	my $i;
	my $body = ""; 
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

	$::d_http && msg("Generating response for ($type, $contentType) $path\n");

	# some generally useful form details...
	if (defined($client)) {
#		$$paramsref{'player'} = escape(Slim::Player::Client::id($client));
		$$paramsref{'player'} = Slim::Player::Client::id($client);
		$$paramsref{'myClientState'} = $client;
	}

	if (defined($contentType)) {
		if ($contentType =~ /image/) {
			# images should expire from cache one year from now
			my $imageExpireHeader = strftime "%a %b %e %H:%M:%S %Y", gmtime(time + 31536000);
			$headers{"Expires"} = "$imageExpireHeader";
		} else {
			$headers{"Expires"} = "0";
		}

	    $result = "HTTP/1.0 200 OK";
	    
	    if ($contentType =~ /text/) {
	    	filltemplatefile('include.html', $paramsref);
	    }
	    
	    if ($path =~ /home\.(htm|xml)/ || $path =~ /^index\.(htm|xml)/ || $path eq '') {
			$body = Slim::Web::Pages::home($client, $paramsref);
	    } elsif ($path =~ /browse\.(htm|xml)/) {

			##
			## Special case - browser() goes into the background in addToList, because it can
			##                take a long time. When addtoList finishes, we go to browse_addtolist_done, 
			##		  which takes care of sending the output to the client
			##
			my $browser_ret;
			my $output = $result . $EOL . printheaders((%headers, %paramheaders));
			if ($browser_ret = Slim::Web::Pages::browser($client, $httpclientsock, $output, $paramsref)) {
				$body = $browser_ret;
			} else {
				return(0); 
			}

	    } elsif ($path =~ /(stream\.mp3|stream)$/) {
			%headers = statusHeaders($client);
			$headers{"x-audiocast-name"} = string('SLIM_SERVER');
			if ($sendMetaData{$httpclientsock}) {
				$headers{"icy-metaint"} = $METADATAINTERVAL;
				$headers{"icy-name"} = string('WELCOME_TO_SQUEEZEBOX');
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

 			($body, $contenttype) = Slim::Music::Info::coverArt($song,$image);
 			 			
 			if (defined($body)) {
				%headers = statusHeaders($client);
 			} else {
				$body = getStaticContent("html/images/spacer.gif");
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
			# we failed to open the specified file
			$result = "HTTP/1.0 404 Not Found";
			$body = "<HTML><HEAD><TITLE>404 Not Found</TITLE></HEAD><BODY>404 Not Found: $path</BODY></HTML>$EOL";
	    } elsif ($path =~ /browseid3\.(htm|xml)/) {
			$body = Slim::Web::Pages::browseid3($client, $paramsref);
	    } elsif ($path =~ /mood_wheel\.(htm|xml)/) {
			$body = Slim::Web::Pages::mood_wheel($client, $paramsref);
	    } elsif ($path =~ /instant_mix\.(htm|xml)/) {
			$body = Slim::Web::Pages::instant_mix($client, $paramsref);
        } elsif ($path =~ /hitlist\.(htm|xml)/) {
			$body = Slim::Web::History::hitlist($client, $paramsref);
	    } elsif ($path =~ /olsonmain\.(htm|xml)/) {
			$body = Slim::Web::Olson::olsonmain($client, $paramsref);
	    } elsif ($path =~ /olsondetail\.(htm|xml)/) {
			$body = Slim::Web::Olson::olsondetail($client, $paramsref);
	    } elsif ($path =~ /songinfo\.(htm|xml)/) {
			$body = Slim::Web::Pages::songinfo($client, $paramsref);
	    } elsif ($path =~ /search\.(htm|xml)/) {
			$body = Slim::Web::Pages::search($client, $paramsref);
	    } elsif ($path =~ /status_header\.(htm|xml)/) {
			$body = Slim::Web::Pages::status($client, $paramsref, 0);
	    } elsif ($path =~ /playlist\.(htm|xml)/) {
			$body = Slim::Web::Pages::playlist($client, $paramsref);
	    } elsif ($path =~ /favicon\.ico/) {
			$body = getStaticContent("html/mypage.ico", $paramsref); 
	    } elsif ($path =~ /setup\.(htm|xml)/) {
			if ($::nosetup) {
				$result = "HTTP/1.0 403 Forbidden";
				$body = "<HTML><HEAD><TITLE>403 Forbidden</TITLE></HEAD><BODY>403 Forbidden: $path</BODY></HTML>$EOL";
			} else {
				$body = Slim::Web::Setup::setup_HTTP($client, $paramsref);
			}
	    } elsif ($path =~ /slimserver\.css/) {
	    	$body = getStaticContent($path, $paramsref);
		} elsif ($path =~ /status\.txt/) {
			# if the HTTP client has asked for a text file, then always return the text on the display
			%headers = statusHeaders($client);
			$headers{"Expires"} = "0";
			$headers{"Content-Type"} = "text/plain";
			$headers{"Refresh"} = "30; url=$path";
			my ($line1, $line2) = Slim::Display::Display::curLines($client);
	
			$body = $line1 . $EOL;
			$body .= $line2 . $EOL; 
	
		} elsif ($path =~ /log\.txt/) {
			# if the HTTP client has asked for a text file, then always return the text on the display
			%headers = statusHeaders($client);
			$headers{"Expires"} = "0";
			$headers{"Content-Type"} = "text/plain";
			$headers{"Refresh"} = "30; url=$path";
			$body = $Slim::Utils::Misc::log;

		} elsif ($path =~ /status\.m3u/) {
		# if the HTTP client has asked for a .m3u file, then always return the current playlist as an M3U
			%headers = statusHeaders($client);
	
			if (defined($client)) {
				my $count = Slim::Player::Playlist::count($client);
				if ($count) {
					$body .= Slim::Formats::Parse::writeM3U(\@{Slim::Player::Playlist::playList($client)});
				}
			}
		} elsif ($path =~ /html\//) {
			# content is in the "html" subdirectory within the template directory.
			
			# if it's HTML then use the template mechanism
			if ($contentType eq 'text/html' || $contentType eq 'text/xml') {
				# if the path ends with a slash, then server up the index.html file
				if ($path =~ /\/$/) {
					$path .= 'index.html';
				}
				$body = &filltemplatefile($path, $paramsref);
			} else {
				# otherwise just send back the binary file
				$body = getStaticContent($path, $paramsref);
			}
	    } elsif ($path =~ /status\.(htm|xml)/) {
	   		if ($contentType eq 'text/html') {
				# status page
				if (defined($client)) {
					if (!$$paramsref{'refresh'} || !$client->htmlstatusvalid() || !Slim::Utils::Prefs::get('templatecache')) {
						$::d_http && msg("Generating new status\n");
						$client->htmlstatus(Slim::Web::Pages::status($client, $paramsref, 1));
						$client->htmlstatusvalid(1);
					}
					$body = $client->htmlstatus();
				} else {
					$body = &filltemplatefile("status_noclients.html", $paramsref);
				}
			} else {
				if (defined($client)) {
					$body = Slim::Web::Pages::status($client, $paramsref, 1);
				} else {
					$body = &filltemplatefile("status_noclients.html", $paramsref);
				}
			}
	    }  else {
			$result = "HTTP/1.0 404 Not Found";
			$body = "<HTML><HEAD><TITLE>404 Not Found</TITLE></HEAD><BODY>404 Not Found: $path</BODY></HTML>$EOL";
		}
	} else {	
		if ($path !~ /status/i) {
			$result = "HTTP/1.0 404 Not Found";
			$body = "<HTML><HEAD><TITLE>404 Not Found</TITLE></HEAD><BODY>404 Not Found: $path</BODY></HTML>$EOL";
		} else {
			$result = "HTTP/1.0 200 OK";
		}
	}
	$headers{'Content-Length'} = length($body);
	$headers{'Connection'} = 'close';
	addresponse($httpclientsock, $result . $EOL . printheaders(%headers, %paramheaders) . $body);
	return 0;
}

sub statusHeaders {
	my $client = shift;

	if (!defined($client)) { return; }
	
	my $sleeptime = $client->sleepTime() - Time::HiRes::time();
	if ($sleeptime < 0) { $sleeptime = 0 };
	
	# send headers
	my %headers = ( 
			"x-player"			=> Slim::Player::Client::id($client),
			"x-playername"		=> Slim::Player::Client::name($client),
			"x-playertracks" 	=> Slim::Player::Playlist::count($client),
			"x-playershuffle" 	=> Slim::Player::Playlist::shuffle($client) ? "1" : "0",
			"x-playerrepeat" 	=> Slim::Player::Playlist::repeat($client),
	# unsupported yet
	#		"x-playerbalance" => "0",
	#		"x-playerbase" => "0",
	#		"x-playertreble" => "0",
	#		"x-playersleep" => "0",
	);
	
	if (Slim::Player::Client::isPlayer($client)) {
		$headers{"x-playervolume"} = int(Slim::Utils::Prefs::clientGet($client, "volume") + 0.5);
		$headers{"x-playermode"} = Slim::Buttons::Common::mode($client) eq "power" ? "off" : Slim::Player::Playlist::playmode($client);
		$headers{"x-playersleep"} = $sleeptime;
	}	
	
	if (Slim::Player::Playlist::count($client)) { 
		$headers{"x-playertrack"} 	 = Slim::Player::Playlist::song($client); 
		$headers{"x-playerindex"} 	 = Slim::Player::Playlist::currentSongIndex($client) + 1;
		$headers{"x-playertime"} 	 = Slim::Player::Playlist::songTime($client);
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
# End:
