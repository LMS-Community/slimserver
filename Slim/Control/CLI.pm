package Slim::Control::CLI;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
#use FindBin qw($Bin);
use IO::Socket;
use File::Spec::Functions qw(:ALL);
use Socket qw(:crlf);

use Slim::Networking::mDNS;
use Slim::Networking::Select;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::OSDetect;
use Slim::Web::HTTP;


# This module provides a command-line interface to the server via a TCP/IP port.
# see the documentation in Stdio.pm for details on the command syntax

my $cli_socket;				# server socket
my $cli_socket_port = 0;	# CLI port on which socket is opened

my $client_socket_count = 0;# number of connected clients
my %client_socket_id;		# id of each client_sock IP:PORT (for debug)
my %client_socket_inbuff;	# input buffer per client_sock
my %client_socket_outbuff;	# output buffer per client_sock
my %client_socket_auth;		# authentification state per client_sock

my %listen = ();			# listen setting per client_sock


# initialize the command line interface server
sub init {
	# our idle routine takes care of opening the port
	idle();
}


# on idle, check to see if our command line interface port has changed
# and open/close accordingly.
sub idle {

	my $newport = Slim::Utils::Prefs::get('cliport');

	if ($cli_socket_port != $newport) {

		# if we've already opened a socket, let's close it
		if ($cli_socket_port) {
			cli_socket_close();
		}

		# if we've got an command line interface port specified, open it up!
		if ($newport) {
			cli_socket_open($newport);
		}
	}
}


# start our listener
sub cli_socket_open {
	my $listenerport = shift;

	if ($listenerport) {

		$cli_socket = IO::Socket::INET->new(  
			Proto     => 'tcp',
			LocalPort => $listenerport,
			LocalAddr => $::cliaddr,
			Listen    => SOMAXCONN,
			ReuseAddr => 1,
			Reuse     => 1,
			Timeout   => 0.001
		) or die "CLI: Can't setup the listening port $listenerport: $!";
	
		$cli_socket_port = $listenerport;
	
		Slim::Networking::Select::addRead($cli_socket, \&cli_socket_accept);
	
		Slim::Networking::mDNS->addService('_slimcli._tcp', $listenerport);
	
		Slim::Control::Command::setExecuteCallback(\&Slim::Control::CLI::commandCallback);
		
		$::d_cli && msg("CLI: Now accepting connections on port $listenerport\n");
	}
}


# stop our listener on cli_socket_port
sub cli_socket_close {

	if ($cli_socket_port) {

		$::d_cli && msg("CLI: Closing socket $cli_socket_port\n");
	
		Slim::Networking::mDNS->removeService('_slimcli._tcp');
		
		Slim::Networking::Select::addRead($cli_socket, undef);
		$cli_socket->close();
		$cli_socket_port = 0;
		Slim::Control::Command::clearExecuteCallback(\&commandCallback);
	}
}



# accept new connection!
sub cli_socket_accept {

	if ($client_socket_count > Slim::Utils::Prefs::get("tcpConnectMaximum")) {
		$::d_cli && msg("CLI: Too many connections, rejecting attempt...\n");
		return;
	}

	my $client_socket = $cli_socket->accept();

	if ($client_socket && $client_socket->connected && $client_socket->peeraddr) {

		my $tmpaddr = inet_ntoa($client_socket->peeraddr);

		if (!(Slim::Utils::Prefs::get('filterHosts')) || (Slim::Utils::Misc::isAllowedHost($tmpaddr))) {

			Slim::Networking::Select::addRead($client_socket, \&client_socket_read);
			Slim::Networking::Select::addError($client_socket, \&client_socket_close);
			
			$client_socket_count++;
			$client_socket_id{$client_socket} = $tmpaddr.':'.$client_socket->peerport;
			$client_socket_inbuff{$client_socket} = '';
			$client_socket_outbuff{$client_socket} = ();
			
			$listen{$client_socket} = 0;

			$::d_cli && msg("CLI: Accepted connection from ". $client_socket_id{$client_socket} . " ($client_socket_count active connections)\n");
		} 
		else {
			
			$::d_cli && msg("CLI: Did not accept connection from ". $client_socket_id{$client_socket} . ": unauthorized source\n");
			$client_socket->close();
		}

	} else {
		$::d_cli && msg("CLI: Did not accept connection\n");
	}
}


# close connection
sub client_socket_close {
	my $client_socket = shift;
		
	Slim::Networking::Select::addWrite($client_socket, undef);
	Slim::Networking::Select::addRead($client_socket, undef);
	Slim::Networking::Select::addError($client_socket, undef);
	
	close $client_socket;

	$client_socket_count--;
	
	$::d_cli && msg("CLI: Closed connection with " . $client_socket_id{$client_socket} . " ($client_socket_count active connections)\n");

	# clean up the hash
	delete($client_socket_id{$client_socket});
	delete($client_socket_inbuff{$client_socket});
	delete($client_socket_outbuff{$client_socket});
	
	delete($listen{$client_socket});
}



# data from connection
sub client_socket_read {
	my $client_socket = shift;

	if (!defined($client_socket)) {
		$::d_cli && msg("CLI: client_socket undefined in client_socket_read()!\n");
		return;		
	}

	if (!($client_socket->connected)) {
		$::d_cli && msg("CLI: connection closed by peer\n");
		client_socket_close($client_socket);		
		return;
	}			

	my $bytes_to_read = 100;
	my $indata = '';
	my $bytes_read = $client_socket->sysread($indata, $bytes_to_read);

	if (!defined($bytes_read) || ($bytes_read == 0)) {
		$::d_cli && msg("CLI: connection half-closed by peer\n");
		client_socket_close($client_socket);		
		return;
	}

	$client_socket_inbuff{$client_socket} .= $indata;

	# parse our buffer to find LF, CR, CRLF or even LFCR (for nutty clients)	
	while ($client_socket_inbuff{$client_socket}) {
		if ($client_socket_inbuff{$client_socket} =~ m/([^\r\n]*)[$CR|$LF|$CR$LF]+(.*)/s) {

			# Keep the leftovers for the next run...
			$client_socket_inbuff{$client_socket} = $2;

			cli_execute($client_socket, $1);
		}
		else {
			# there's data in our buffer but it doesn't match so wait for more data...
			last;
		}
	}
}


# handles the execution of the command line interface request
sub cli_execute {
	my($clientsock, $command) = @_;

	my $output = "";
	my $client = undef;

#	$::d_cli && msg("Clients: ". join " " ,Slim::Player::Client::clientIPs(), "\n");
	$::d_cli && msg("CLI: Excuting command: $command\n");
	
	# Check authentification if not already done
	if (!defined($client_socket_auth{$clientsock})) {
		if (Slim::Utils::Prefs::get('authorize')) {
			$::d_cli && msg("CLI: Connection requires authentication\n");
			if ($command =~ m|^login (\S*?) (\S*)|) {
				# unescape: like other CLI command arguments, user and password should be URI-escaped
				my ($user, $pass) = (Slim::Web::HTTP::unescape($1),Slim::Web::HTTP::unescape($2));
				if (Slim::Web::HTTP::checkAuthorization($user, $pass)) {
					$::d_cli && msg("CLI authentication successful.\n");
					$client_socket_auth{$clientsock} = 1;
					$output = "login " . Slim::Web::HTTP::escape($user) . " ******";
					addresponse($clientsock, $output . $LF);
					return;
				}
			}
			
			# failed, disconnect
			if (!defined($client_socket_auth{$clientsock})) {
				client_socket_close($clientsock);
				return;
			}
			
		} else {
			# we're authenticated if no authentication is required!
			$client_socket_auth{$clientsock} = 1;
		}
		
	}
	
	if (defined($client_socket_auth{$clientsock})) {
	
		if ($command =~ /^listen\s*(0|1|)/) {
			if ($1 eq 0) {
				$listen{$clientsock} = undef;
			} elsif ($1 eq 1) {
				$listen{$clientsock} = $clientsock;
			} else {
				$listen{$clientsock} = $listen{$clientsock} ? undef : $clientsock;
			}
		}
		
		$output = Slim::Control::Stdio::executeCmd($command);
		
	}	
	# if the callback isn't goint to print the response...
	if (!$listen{$clientsock}) {

		$output = "" unless defined $output;
		
		$::d_cli && msg("Command line interface response: " . $output . "\n");
		addresponse($clientsock, $output . $LF);
	}
	
	if ($command =~ /^exit/) { 
		sendresponse($clientsock);
		client_socket_close($clientsock); 
	}
}


sub addresponse {
	my $clientsock = shift;
	my $message = shift;

	push @{$client_socket_outbuff{$clientsock}}, $message;
	Slim::Networking::Select::addWrite($clientsock, \&sendresponse);
}


sub sendresponse {
	my $clientsock = shift;

	my $message = shift(@{$client_socket_outbuff{$clientsock}});
	my $sentbytes;

	return unless $message;

	$::d_cli && msg("Sending response\n");
	
	$sentbytes = send($clientsock, $message, 0);

	unless (defined($sentbytes)) {

		# Treat $clientsock with suspicion
		$::d_cli && msg("Send to " . inet_ntoa($clientsock->peeraddr)  . " had error\n");
		client_socket_close($clientsock);

		return;
	}

	if ($sentbytes < length($message)) {

		# sent incomplete message
		unshift @{$client_socket_outbuff{$clientsock}},substr($message,$sentbytes);

	} else {

		# sent full message
		if (@{$client_socket_outbuff{$clientsock}} == 0) {

			# no more messages to send
			$::d_cli && msg("No more messages to send to " . inet_ntoa($clientsock->peeraddr) . "\n");
			Slim::Networking::Select::addWrite($clientsock, undef);
		} else {
			$::d_cli && msg("More to send to " . inet_ntoa($clientsock->peeraddr) . "\n");
		}
	}
}


sub commandCallback {
	my $client = shift;
	my $paramsRef = shift;

	# XXX - this should really be passed and not global.
	foreach my $sock (keys %listen) {

		$sock = $listen{$sock};

		next unless $sock;

		my $output = '';
		
		$output = Slim::Web::HTTP::escape($client->id()) . ' ' if $client;

		foreach my $param (@$paramsRef) {
			$output .= Slim::Web::HTTP::escape($param) . ' ';
		}
		
		chop($output);

		addresponse($sock, $output . $LF);
		sendresponse($sock);
	}
}

#sub connectedSocket {
#	return $connected;
#}

#sub readable {
#	my $sock = shift;
#	
#}


1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
