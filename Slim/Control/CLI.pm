package Slim::Control::CLI;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use FindBin qw($Bin);
use IO::Socket;
use File::Spec::Functions qw(:ALL);
use Socket qw(:crlf);

use Slim::Networking::mDNS;
use Slim::Networking::Select;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::OSDetect;


# This module provides a command-line interface to the server via a TCP/IP port.
# see the documentation in Stdio.pm for details on the command syntax

my $openedport = 0;
my $server_socket;
my $connected = 0;
my %outbuf = ();
my %listen = ();

my $mdnsID;

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
	) or die "can't setup the listening port $listenerport for the command line interface server: $!";

	$openedport = $listenerport;

	Slim::Networking::Select::addRead($server_socket, \&acceptSocket);

	$mdnsID = Slim::Networking::mDNS::advertise(
		Slim::Utils::Prefs::get('mDNSname'), 'slimdevices_slimserver_cli._tcp', $listenerport
	);

	Slim::Control::Command::setExecuteCallback(\&Slim::Control::CLI::commandCallback);
	
	$::d_cli && msg("Server $0 accepting command line interface connections on port $listenerport\n");
}

sub idle {

	# check to see if our command line interface port has changed.
	if ($openedport != Slim::Utils::Prefs::get('cliport')) {

		# if we've already opened a socket, let's close it
		if ($openedport) {
			Slim::Networking::mDNS::stopAdvertise($mdnsID) if $mdnsID;

			$::d_cli && msg("closing command line interface server socket\n");
			Slim::Networking::Select::addRead($server_socket, undef);
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

	# XXX - this should really be passed and not global.
	foreach my $sock (keys %listen) {

		$sock = $listen{$sock};

		next unless $sock;

		my $output = $client->id();

		foreach my $param (@$paramsRef) {
			$output .= ' ' . Slim::Web::HTTP::escape($param);
		}

		addresponse($sock, $output . $LF);
		sendresponse($sock);
	}
}

sub connectedSocket {
	return $connected;
}

sub acceptSocket {
	return if connectedSocket() > Slim::Utils::Prefs::get("tcpConnectMaximum");

	my $clientsock = $server_socket->accept();

	if ($clientsock && $clientsock->connected && $clientsock->peeraddr) {

		my $tmpaddr = inet_ntoa($clientsock->peeraddr);

		if (!(Slim::Utils::Prefs::get('filterHosts')) || (Slim::Utils::Misc::isAllowedHost($tmpaddr))) {

			Slim::Networking::Select::addRead($clientsock, \&processRequest);
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

sub readable {
	my $sock = shift;
	
}

# Handle an command line interface request
sub processRequest {
	my $clientsock = shift;
	my $firstline;

	return unless $clientsock;

	$clientsock->autoflush(1);

	$firstline = <$clientsock>;
		
	if (!defined($firstline)) {
		# socket half-closed from client
		$::d_cli && msg("Client at " . inet_ntoa($clientsock->peeraddr) . " disconnected\n");
		closer($clientsock);
	} else { 
		# process the commands
		chomp $firstline; 
		executeCmd($clientsock, $firstline);
	}

	$::d_cli && msg("Ready to accept a new command line interface connection.\n");
}

# executeCmd - handles the execution of the command line interface request
sub executeCmd {
	my($clientsock, $command) = @_;

	my $output = "";
	my $client = undef;

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

		$output = "" unless defined $output;
		
		$::d_cli && msg("command line interface response: " . $output);
		addresponse($clientsock, $output . $LF);
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
	Slim::Networking::Select::addWrite($clientsock, \&sendresponse);
}

sub sendresponse {
	my $clientsock = shift;

	my $message = shift(@{$outbuf{$clientsock}});
	my $sentbytes;

	return unless $message;

	$::d_cli && msg("Sending response\n");
	
	$sentbytes = send($clientsock, $message, 0);

	unless (defined($sentbytes)) {

		# Treat $clientsock with suspicion
		$::d_cli && msg("Send to " . inet_ntoa($clientsock->peeraddr)  . " had error\n");
		closer($clientsock);

		return;
	}

	if ($sentbytes < length($message)) {

		# sent incomplete message
		unshift @{$outbuf{$clientsock}},substr($message,$sentbytes);

	} else {

		# sent full message
		if (@{$outbuf{$clientsock}} == 0) {

			# no more messages to send
			$::d_cli && msg("No more messages to send to " . inet_ntoa($clientsock->peeraddr) . "\n");
			Slim::Networking::Select::addWrite($clientsock, undef);
		} else {
			$::d_cli && msg("More to send to " . inet_ntoa($clientsock->peeraddr) . "\n");
		}
	}
}

sub closer {
	my $clientsock = shift;

	Slim::Networking::Select::addWrite($clientsock, undef);
	Slim::Networking::Select::addRead($clientsock, undef);
	
	close $clientsock;

	# clean up the hash
	delete($outbuf{$clientsock});
	delete($listen{$clientsock});
	$connected--;
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
