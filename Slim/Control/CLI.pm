package Slim::Control::CLI;

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use FindBin qw($Bin);
use IO::Socket;
use IO::Select;
use Net::hostent;              # for OO version of gethostbyaddr
use File::Spec::Functions qw(:ALL);
use POSIX;
use Sys::Hostname;

use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::OSDetect;
use Slim::Networking::mDNS;


# This module provides a command-line interface to the server via a TCP/IP port.
# see the documentation in Stdio.pm for details on the command syntax
#
#constants
#
my $NEWLINE = "\012";

my $openedport = 0;
my $server_socket;
my $connected = 0;
my %outbuf = ();
my %listen = ();

my $mdnsID;

my $selRead;
my $selWrite;

# initialize the command line interface server
sub init {
	idle();
}

sub openport {
	my ($listenerport, $listeneraddr) = @_;

	#start our listener

	$server_socket = IO::Socket::INET->new(  
											Proto     => 'tcp',
											LocalPort => $listenerport,
											LocalAddr => $listeneraddr,
											Listen    => SOMAXCONN,
											ReuseAddr => 1,
											Reuse     => 1,
											Timeout   => 0.001
										  );

	die "can't setup the listening port $listenerport for the command line interface server: $!" unless $server_socket;

	$openedport = $listenerport;

	$selRead = IO::Select->new();
	$selWrite = IO::Select->new();

	$selRead->add(serverSocket());   # readability on the command line interface server
	$main::selRead->add(serverSocket());
	
	$mdnsID = Slim::Networking::mDNS::advertise(Slim::Utils::Prefs::get('mDNSname'), '_slimdevices_slimserver_cli._tcp', $listenerport);

	Slim::Control::Command::setExecuteCallback(\&Slim::Control::CLI::commandCallback);
	
	$::d_cli && msg("Server $0 accepting command line interface connections on port $listenerport\n");
}

sub check {
	# check to see if our command line interface port has changed.
	if ($openedport != Slim::Utils::Prefs::get('cliport')) {

		# if we've already opened a socket, let's close it
		if ($openedport) {
			if ($mdnsID) { Slim::Networking::mDNS::stopAdvertise($mdnsID); };

			$::d_cli && msg("closing command line interface server socket\n");
			$selRead->remove($server_socket);
			$main::selRead->remove($server_socket);
			$server_socket->close();
			$openedport = 0;
			Slim::Control::Command::clearExecuteCallback(\&commandCallback);
		}

		# if we've got an command line interface port specified, open it up!
		if (Slim::Utils::Prefs::get('cliport')) {
			openport(Slim::Utils::Prefs::get('cliport'), $::cliaddr, $Bin);
		}
	}
}

sub commandCallback {
	my $client = shift;
	my $paramsRef = shift;
	foreach my $sock (keys %listen) {
		$sock = $listen{$sock};
		if ($sock) {
			my $output = $client->id();
			foreach my $param (@$paramsRef) {
				$output .= ' ' . Slim::Web::HTTP::escape($param);
			}
			addresponse($sock, $output . $NEWLINE);
			sendresponse($sock);
		}
	}
}

sub idle {

	my $selCanRead;
	my $selCanWrite;

	# check to see if the command line interface settings have changed
	check();

	# check for command line interface data
	($selCanRead,$selCanWrite)=IO::Select->select($selRead,$selWrite,undef,0);

#	$::d_cli && defined($selCanRead) && msg( "\tSelect returned Read: ".join(',',@$selCanRead)."\n");
#	$::d_cli && defined($selCanWrite) && msg("\tSelect returned Write:".join(',',@$selCanWrite)."\n");

	# check to see if there's command line interface activity...
	my $tcpReads = 0;
	foreach my $sockHand (@$selCanRead) {
		if ($sockHand == serverSocket()) {
			next if connectedSocket() > Slim::Utils::Prefs::get("tcpConnectMaximum");
			acceptSocket();
		} else {
			processRequest($sockHand);
			last if ++$tcpReads >= Slim::Utils::Prefs::get("tcpReadMaximum") || Slim::Networking::Protocol::pending();
		}
	}

	#send command line interface responses
	my $tcpWrites = 0;
	foreach my $sockHand (@$selCanWrite) {
		last if ++$tcpWrites > Slim::Utils::Prefs::get("tcpWriteMaximum") || Slim::Networking::Protocol::pending();
		sendresponse($sockHand);
	}
}

sub serverSocket {
	return $server_socket;
}

sub connectedSocket {
	return $connected;
}

sub acceptSocket {
	my $clientsock = $server_socket->accept();
	if ($clientsock && $clientsock->connected && $clientsock->peeraddr) {
		my $tmpaddr = inet_ntoa($clientsock->peeraddr);
		if (
		    !(Slim::Utils::Prefs::get('filterHosts')) || 
		    (Slim::Utils::Misc::isAllowedHost($tmpaddr))
		   )
		{
			$selRead->add($clientsock);
			$main::selRead->add($clientsock);
			$connected++;
			$listen{$clientsock} = 0;
			$::d_cli && msg("Accepted connection $connected from ". $tmpaddr . "\n");
		} else {
			$::d_cli && msg("Did not accept CLI connection from ". $tmpaddr . ", unauthorized source\n");
			$clientsock->close();
		}
	} else {
		$::d_cli && msg("Did not accept connection\n");
	}
}

#
#  Handle an command line interface request
#
sub processRequest {
	my $clientsock = shift;
	my $firstline;

	if ($clientsock) {

		$clientsock->autoflush(1);

		$firstline = <$clientsock>;
	  	  	
		if (!defined($firstline)) { #socket half-closed from client
			$::d_cli && msg("Client at " . inet_ntoa($clientsock->peeraddr) . " disconnected\n");
			closer($clientsock);
		} else { 
			#process the commands
			chomp $firstline; 
			executeCmd($clientsock, $firstline);
		}
	$::d_cli && msg("Ready to accept a new command line interface connection.\n");
	}
}

# executeCmd - handles the execution of the command line interface request
#
#
sub executeCmd {
	my($clientsock, $command) = @_;
	my $output = "";
	my($client) = undef;

	$::d_cli && msg("Clients: ". join " " ,Slim::Player::Client::clientIPs(), "\n");
	$::d_cli && msg("Processing command: $command\n");
	
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
	
	# if the callback isn't goint to print the response...
	if (!$listen{$clientsock}) {
		if (!defined($output)) {
			$output = "";
		};
		
		$::d_cli && msg("command line interface response: " . $output);
		addresponse($clientsock, $output . $NEWLINE);
	}
	
	if ($command =~ /^exit/) { 
		sendresponse($clientsock);
		closer($clientsock); 
	}
}

sub addresponse {
	my $clientsock = shift;
	my $message = shift;
	push @{$outbuf{$clientsock}}, $message;
	$selWrite->add($clientsock);
	$main::selWrite->add($clientsock);
}

sub sendresponse {
	my $clientsock = shift;
	my $message = shift(@{$outbuf{$clientsock}});
	my $sentbytes;
	if ($message) {
		$::d_cli && msg("Sending response\n");
		
		$sentbytes = send $clientsock, $message,0;
		if (defined($sentbytes)) {
			if ($sentbytes < length($message)) { #sent incomplete message
				unshift @{$outbuf{$clientsock}},substr($message,$sentbytes);
			} else { #sent full message
				if (@{$outbuf{$clientsock}} == 0) { #no more messages to send
					$::d_cli && msg("No more messages to send to " . inet_ntoa($clientsock->peeraddr) . "\n");
					$selWrite->remove($clientsock);
					$main::selWrite->remove($clientsock);
				} else {
					$::d_cli && msg("More to send to " . inet_ntoa($clientsock->peeraddr) . "\n");
				}
			}
		} else {
			# Treat $clientsock with suspicion
			$::d_cli && msg("Send to " . inet_ntoa($clientsock->peeraddr)  . " had error\n");
			closer($clientsock);
		}
	}
}

sub closer {
	my $clientsock = shift;

	$selWrite->remove($clientsock);
	$main::selWrite->remove($clientsock);
	$selRead->remove($clientsock);
	$main::selRead->remove($clientsock);
	close $clientsock;
	delete($outbuf{$clientsock}); #clean up the hash
	delete($listen{$clientsock});
	$connected--;
}

1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
