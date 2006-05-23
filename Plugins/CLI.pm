package Plugins::CLI;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.


use strict;
use IO::Socket;
use Socket qw(:crlf);
use Scalar::Util qw(blessed);
use URI::Escape;

use Slim::Control::Request;
use Slim::Utils::Misc;
use Slim::Utils::Unicode;

# This plugin provides a command-line interface to the server via a TCP/IP port.
# See cli-api.html for documentation.

# Queries and commands handled by this module:
#  can
#  exit
#  login
#  listen
#  shutdown
#  subscribe
# Other CLI queries/commands are handled through Request.pm
#
# This module also handles parameters "charset" and "subscribe"


my $d_cli_v = 0;            # verbose debug, for developpement
my $d_cli_vv = 0;           # very verbose debug, function calls...


my $cli_socket;             # server socket
my $cli_socket_port = 0;    # CLI port on which socket is opened

my $cli_busy = 0;           # 1 if CLI is processing command
my $cli_subscribed = 0;     # 1 if CLI is subscribed to the notification system

our %connections;           # hash indexed by client_sock value
                            # each element is a hash with following keys
                            # .. id:         "IP:PORT" for debug
                            # .. socket:     the socket (a hash key is *not* an 
                            #                object, but the value is...)
                            # .. inbuff:     input buffer
                            # .. outbuff:    output buffer (array)
                            # .. auth:       1 if connection authenticated (login)
                            # .. terminator: terminator last used by client, we
                            #                use it when replying
                            # .. subscribe:  undef if the client is not listening
                            #                to anything, otherwise see below.
                            
our %pending;

################################################################################
# PLUGIN CODE
################################################################################

# plugin: initialize the command line interface server
sub initPlugin {

	$d_cli_vv && msg("CLI: initPlugin()\n");

	# enable general debug if verbose debug is on
	$::d_cli = $d_cli_v if !$::d_cli;
	
	# make sure we have a default value for our preference
	if (!defined Slim::Utils::Prefs::get('cliport')) {
		Slim::Utils::Prefs::set('cliport', 9090);
	}
	
	# register our functions
	
#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F

    Slim::Control::Request::addDispatch(['can'], 
        [0, 1, 0, \&canQuery]);
    Slim::Control::Request::addDispatch(['listen',    '_newvalue'],  
        [0, 0, 0, \&listenCommand]);
    Slim::Control::Request::addDispatch(['listen',    '?'],          
        [0, 1, 0, \&listenQuery]);
    Slim::Control::Request::addDispatch(['subscribe', '_functions'], 
        [0, 0, 0, \&subscribeCommand]);

	
	# open our socket
	cli_socket_change();
}

# plugin: name of our plugin
sub getDisplayName {
	return 'PLUGIN_CLI';
}

sub getDisplayDescription {
	return "PLUGIN_CLI_DESC";
}

# plugin: manage the CLI preference
sub setupGroup {
	my $client = shift;
	
	my %setupGroup = (
		PrefOrder => ['cliport'],
	);
	
	my %setupPrefs = (
		'cliport'	=> {
			'validate' => \&Slim::Utils::Validate::port,
			'onChange' => \&cli_socket_change,
		}
	);
	
	return (\%setupGroup, \%setupPrefs);
}


# plugin: shutdown the CLI
sub shutdownPlugin {

	$d_cli_vv && msg("CLI: shutdownPlugin()\n");

	# close all connections
	foreach my $client_socket (keys %connections) {

		# retrieve the socket object
		$client_socket = $connections{$client_socket}{'socket'};
		
		# close the connection
		client_socket_close($client_socket);
	}
	
	# close the socket
	cli_socket_close();
}

# plugin strings at the end of the file


################################################################################
# SOCKETS
################################################################################

# start our listener
sub cli_socket_open {
	my $listenerport = shift;

	$d_cli_vv && msg("CLI: cli_socket_open($listenerport)\n");

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
	
		Slim::Networking::mDNS->addService('_slimcli._tcp', $cli_socket_port);

		$::d_cli && msg("CLI: Now accepting connections on port $listenerport\n");
	}
}


# open or change our socket
sub cli_socket_change {

	$d_cli_vv && msg("CLI: cli_socket_change()\n");

	# get the port we must use
	my $newport = Slim::Utils::Prefs::get('cliport');

	# if the port changed...
	if ($cli_socket_port != $newport) {

		# if we've already opened a socket, let's close it
		# (this is false the first time through)
		if ($cli_socket_port) {
			cli_socket_close();
		}

		# if we've got an command line interface port specified, open it up!
		if ($newport) {
			cli_socket_open($newport);
		}
	}
}


# stop our listener on cli_socket_port
sub cli_socket_close {

	$d_cli_vv && msg("CLI: cli_socket_close()\n");

	if ($cli_socket_port) {

		$::d_cli && msg("CLI: Closing socket $cli_socket_port\n");
	
		Slim::Networking::mDNS->removeService('_slimcli._tcp');
		
		Slim::Networking::Select::addRead($cli_socket, undef);
		$cli_socket->close();
		$cli_socket_port = 0;
		Slim::Control::Request::unsubscribe(\&Plugins::CLI::cli_request_notification);
	}
}


# accept new connection!
sub cli_socket_accept {

	$d_cli_vv && msg("CLI: cli_socket_accept()\n");

	# Check max connections
	if (scalar keys %connections > Slim::Utils::Prefs::get("tcpConnectMaximum")) {
		$::d_cli && msg("CLI: Did not accept connection: too many connections open\n");
		return;
	}

	my $client_socket = $cli_socket->accept();

	if ($client_socket && $client_socket->connected && $client_socket->peeraddr) {

		my $tmpaddr = inet_ntoa($client_socket->peeraddr);

		# Check allowed hosts
		
		if (!(Slim::Utils::Prefs::get('filterHosts')) || (Slim::Utils::Network::isAllowedHost($tmpaddr))) {

			Slim::Networking::Select::addRead($client_socket, \&client_socket_read);
			Slim::Networking::Select::addError($client_socket, \&client_socket_close);
			
			$connections{$client_socket}{'socket'} = $client_socket;
			$connections{$client_socket}{'id'} = $tmpaddr.':'.$client_socket->peerport;
			$connections{$client_socket}{'inbuff'} = '';
			$connections{$client_socket}{'outbuff'} = ();
			$connections{$client_socket}{'auth'} = !Slim::Utils::Prefs::get('authorize');
			$connections{$client_socket}{'terminator'} = $LF;

			$::d_cli && msg("CLI: Accepted connection from ". $connections{$client_socket}{'id'} . " (" . (scalar keys %connections) . " active connections)\n");
		} 
		else {
			
			$::d_cli && msg("CLI: Did not accept connection from ". $tmpaddr . ": unauthorized source\n");
			$client_socket->close();
		}

	} else {
		$::d_cli && msg("CLI: Could not accept connection\n");
	}
}


# close connection
sub client_socket_close {
	my $client_socket = shift;
	
	$d_cli_vv && msg("CLI: client_socket_close()\n");


	my $client_id = $connections{$client_socket}{'id'};
		
	Slim::Networking::Select::addWrite($client_socket, undef);
	Slim::Networking::Select::addRead($client_socket, undef);
	Slim::Networking::Select::addError($client_socket, undef);
	
	close $client_socket;
	delete($connections{$client_socket});
	
	$::d_cli && msg("CLI: Closed connection with $client_id (" . (scalar keys %connections) . " active connections)\n");
}


# data from connection
sub client_socket_read {
	my $client_socket = shift;
	use bytes;
	
	$d_cli_vv && msg("CLI: client_socket_read()\n");


	# handle various error cases
	
	if (!defined($client_socket)) {
		$::d_cli && msg("CLI: client_socket undefined in client_socket_read()!\n");
		return;		
	}

	if (!($client_socket->connected())) {
		$::d_cli && msg("CLI: connection with " 
			. $connections{$client_socket}{'id'} . " closed by peer\n");
		client_socket_close($client_socket);
		return;
	}			

	# attempt to read data from the stream
	my $bytes_to_read = 100;
	my $indata = '';
	my $bytes_read = $client_socket->sysread($indata, $bytes_to_read);

	if (!defined($bytes_read) || ($bytes_read == 0)) {
		$::d_cli && msg("CLI: connection with " 
			. $connections{$client_socket}{'id'} . " half-closed by peer\n");
		client_socket_close($client_socket);
		return;
	}

	# buffer the data
	$connections{$client_socket}{'inbuff'} .= $indata;
	
	# only parse when we're not busy
	if ($connections{$client_socket}{'busy'}) {
	
		# manage a stack of connections requiring processing
		$pending{$client_socket} = $client_socket;
		
		if ($::d_cli) {
			my $numpending = scalar keys %pending;
			msg("CLI: BUSY!!!!! ($numpending pending)\n");
		}
	}
	else {
	
		# parse and process
		# if the underlying code ever calls Idle, there is a chance
		# we get called again for the same connection (or another)
		client_socket_buf_parse($client_socket);
		
		# handle any pending items...
		while (scalar keys %pending) {
		
			$::d_cli && msg("CLI: Found pending reads\n");
			
			foreach my $socket (keys %pending) {
			
				delete $pending{$socket};
				
				$socket = $connections{$socket}{'socket'};
				client_socket_buf_parse($socket);
			}
		}
	}
}

# parse buffer data
sub client_socket_buf_parse {
	my $client_socket = shift;

	$d_cli_vv && msg("CLI: client_socket_buf_parse(" . $connections{$client_socket}{'id'} . ")\n");

	# parse our buffer to find LF, CR, CRLF or even LFCR (for nutty clients)
	while ($connections{$client_socket}{'inbuff'}) {

		if ($connections{$client_socket}{'inbuff'} =~ m/([^\r\n]*)([$CR|$LF|$CR$LF|\x0]+)(.*)/s) {
			
			# $1 : command
			# $2 : terminator used
			# $3 : rest of buffer

			# Keep the leftovers for the next run...
			$connections{$client_socket}{'inbuff'} = $3;

			# Remember the terminator used
			if ($connections{$client_socket}{'terminator'} ne $2) {
				$connections{$client_socket}{'terminator'} = $2;
				if ($::d_cli) {
					my $str;
					for (my $i = 0; $i < length($2); $i++) {
						$str .= ord(substr($2, $i, 1)) . " ";
					}
					msg("CLI: Using terminator $str for " . $connections{$client_socket}{'id'} . "\n");
				}
			}

			# Process the command
			# Indicate busy so that any incoming data is buffered and not parsed
			# during command processing
			$connections{$client_socket}{'busy'} = 1;
			my $exit = cli_process($client_socket, $1);
			$connections{$client_socket}{'busy'} = 0 unless $exit == 2;
			
			if ($exit == 1) {
				client_socket_write($client_socket);
				client_socket_close($client_socket);
				
				# cancel our subscription if we can
				cli_subscribe_manage();
				return;
			}
		}
		else {
			# there's data in our buffer but it doesn't match 
			# so wait for more data...
			last;
		}
	}
}


# data to connection
sub client_socket_write {
	my $client_socket = shift;

	$d_cli_vv && msg("CLI: client_socket_write(" . $connections{$client_socket}{'id'} . ")\n");

	my $message = shift(@{$connections{$client_socket}{'outbuff'}});
	my $sentbytes;

	return unless $message;

	if ($::d_cli) {
		my $msg = substr($message, 0, 40);
		chop($msg);
		chop($msg);
		msg("CLI: Sending response [$msg...] to " . $connections{$client_socket}{'id'} ."\n");
	}
	
	$sentbytes = send($client_socket, $message, 0);

	unless (defined($sentbytes)) {

		# Treat $clientsock with suspicion
		$::d_cli && msg("CLI: Send to " . $connections{$client_socket}{'id'}  . " had error\n");
		client_socket_close($client_socket);

		return;
	}

	if ($sentbytes < length($message)) {

		# sent incomplete message
		unshift @{$connections{$client_socket}{'outbuff'}}, substr($message, $sentbytes);

	} else {

		# sent full message
		if (@{$connections{$client_socket}{'outbuff'}} == 0) {

			# no more messages to send
			$::d_cli && msg("CLI: Sent response to " . $connections{$client_socket}{'id'}  . "\n");
			Slim::Networking::Select::addWrite($client_socket, undef);
			
		} else {
			$::d_cli && msg("CLI: More to send to " . $connections{$client_socket}{'id'}  . "\n");
		}
	}
}


# buffer a response
sub client_socket_buffer {
	my $client_socket = shift;
	my $message = shift;

	$d_cli_vv && msg("CLI: client_socket_buffer(" . $connections{$client_socket}{'id'} . ")\n");

	# we're no longer busy, this is atomic
	$connections{$client_socket}{'busy'} = 0;
	
	# add the message to the buffer
	push @{$connections{$client_socket}{'outbuff'}}, $message;
	
	# signal select we got something to write
	Slim::Networking::Select::addWrite($client_socket, \&client_socket_write);
}

################################################################################
# COMMAND PROCESSING
################################################################################


# process command 
sub cli_process {
	my($client_socket, $command) = @_;

	$d_cli_vv && msg("CLI: cli_process($command)\n");
	
	my $exit = 0;			# do we close the connection after this command

	# parse the command
	my ($client, $arrayRef) = Slim::Control::Stdio::string_to_array($command);
	my $clientid = blessed($client) ? $client->id() : undef;

	$::d_cli && $clientid && msg("CLI: Parsing command: Found client [$clientid]\n");

	return if !defined $arrayRef;

	# create a request
	my $request = Slim::Control::Request->new($clientid, $arrayRef);

	return if !defined $request;

	# fix the encoding and/or manage charset param
	$request->fixEncoding();

	# remember we're the source and the $client_socket
	$request->source('CLI');
	$request->privateData($client_socket);
	
	my $cmd = $request->getRequest();
	
	# if a command cannot be found in the dispatch table, then the request
	# name is partial or even empty. In this last case, consider the first
	# element of the array as the command
	if (!defined $cmd && $request->isStatusNotDispatchable()) {
		$cmd = $arrayRef->[0];	
	}

	# give the command a client if it misses one
	if ($request->isStatusNeedsClient()) {
	
		$client = Slim::Player::Client::clientRandom();
		$clientid = blessed($client) ? $client->id() : undef;
		$request->clientid($clientid);
		
		if ($::d_cli) {
			if (defined $client) {
				msg("CLI: Request [$cmd] requires client, allocated $clientid\n");
			} else {
				msg("CLI: Request [$cmd] requires client, none found!\n");
			}
		}
	}
			
	$::d_cli && msg("CLI: Processing request [$cmd]\n");
	
	# try login before checking for authentication
	if ($cmd eq 'login') {
		$exit = cli_cmd_login($client_socket, $request);
	}

	# check authentication
	elsif ($connections{$client_socket}{'auth'} == 0) {
			$::d_cli && msg("CLI: Connection requires authentication, bye!\n");
			# log it so that old code knows what the problem is
			errorMsg("CLI: Connections require authentication, check login command. Disconnecting: " . $connections{$client_socket}{'id'} . "\n");
			$exit = 1;
	}

	else {
		
		if ($cmd eq 'exit'){
			$exit = 1;
		}

		elsif ($cmd eq 'shutdown') {
			# delay execution so we have time to reply...
			Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 0.2,
				\&main::forceStopServer);
			$exit = 1;
		} 

		elsif ($request->isStatusDispatchable()) {

			$::d_cli && msg("CLI: Dispatching [$cmd]\n");

			$request->execute();

			if ($request->isStatusError()) {

				$::d_cli && msg ("CLI: Request [$cmd] failed with error: "
					. $request->getStatusText() . "\n");

			} else {

				# check if this command or query needs CLI subscription 
				# processing
				cli_request_check_subscribe($client_socket, $request);
				
				
				# handle async commands
				if ($request->isStatusProcessing()) {
				
					$::d_cli && msg ("CLI: Request [$cmd] is async: will be back\n");
					
					# add our write routine as a callback
					$request->callbackParameters(\&cli_request_write);
					
					# return async info to caller
					return 2;
				}
			}
		} 
		
		else {

			$::d_cli && msg("CLI: Request [$cmd] unkown or missing client -- will echo as is...\n");
		}
	}
		
	cli_request_write($request);

	return $exit;
}

# generate a string output from a request
sub cli_request_write {
	my $request = shift;
	my $client_socket = shift;

	$d_cli_vv && msg("CLI: cli_request_write("
		. $request->getRequestString() . ")\n");

	$client_socket = $request->privateData() unless defined $client_socket;
	my $encoding      = $request->getParam('charset') || 'utf8';
	my @elements      = $request->renderAsArray($encoding);

	my $output = Slim::Control::Stdio::array_to_string($request->clientid(), \@elements);

#	$::d_cli && msg("CLI: Sending: " . $output . "\n");
	if (defined $client_socket) {
		client_socket_buffer($client_socket, $output . $connections{$client_socket}{'terminator'});
	} else {
		errorMsg("CLI: client_socket undef in cli_request_write()!!!\n");
	}
}

# check for subscribe parameters in suitable commands
sub cli_request_check_subscribe {
	my $client_socket = shift;
	my $request = shift;

	# we must have a subscribe param
	my $subparam = $request->getParam('subscribe');

	return unless defined $subparam;

	# and we only care about status
	return unless $request->isQuery([['status']]);

	$d_cli_vv && msg("CLI: cli_request_check_subscribe()\n");

	cli_subscribe_status($client_socket, $request, $subparam);
}

################################################################################
# CLI commands & queries
################################################################################

# handles the "login" command
sub cli_cmd_login {
	my $client_socket = shift;
	my $request = shift;

	$d_cli_vv && msg("CLI: cli_cmd_login()\n");

	my $login = $request->getParam('_p1');
	my $pwd   = $request->getParam('_p2');
	
	# Replace _p2 with ***** in all cases...
	$request->addParam('_p2', '******');
	
	# if we're not authorized yet, try to be...
	if ($connections{$client_socket}{'auth'} == 0) {
	
		if (Slim::Web::HTTP::checkAuthorization($login, $pwd)) {

			$::d_cli && 
				msg("CLI: Connection requires authentication: authorized!\n");
			$connections{$client_socket}{'auth'} = 1;
			return 0;
		}

		errorMsg("CLI: Connections require authentication, "
			."wrong creditentials received. Disconnecting: " 
			. $connections{$client_socket}{'id'} . "\n");
		return 1;
	}
	return 0;
}

# handles the "can" query
sub canQuery {
	my $request = shift;
 
	$d_cli_vv && msg("CLI::canQuery()\n");
 
	if ($request->isNotQuery([['can']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my @array;
	my $i = 1;
	
	# get all parameters in the array
	while (defined(my $elem = $request->getParam("_p$i"))) {
	
		if ($elem eq '?') {
			# the ? has not been deleted by the parsing since it does not
			# appear in the parsing array above. It does not appear because
			# we do not know how many parameters the request name to test has!
			# delete the ? so that we don't echo it back
			$request->deleteParam("_p$i");
			last;
			
		} else {
			# add the term to our array
			push @array, $elem;
			$i++;
		}
	}
	
	if ($array[0] eq 'login' || 
	    $array[0] eq 'shutdown' || 
	    $array[0] eq 'exit' ) {

		# these do not go through the normal mechanism and are always available
		$request->addResult('_can', 1);
	    
	} else {
		# create a request with the array...
		my $testrequest = Slim::Control::Request->new(undef, \@array);
		
		# ... and return if we found a func for it or not
		$request->addResult('_can', 
			($testrequest->isStatusNotDispatchable()?0:1));
			
		undef $testrequest;
	}
	
	$request->setStatusDone();
}

# handles the "listen" command
sub listenCommand {
	my $request = shift;
 
	$d_cli_vv && msg("CLI::listenCommand()\n");
 
	if ($request->isNotCommand([['listen']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $param = $request->getParam('_newvalue');
	my $client_socket = $request->privateData();
	
	if (!defined $client_socket) {
		$request->setStatusBadParams();
		return;
	}	

	if (!defined $param) {
		$param = !defined($connections{$client_socket}{'subscribe'});
	}

	if ($param == 0) {
		cli_subscribe_terms_none($client_socket);
	} 
	elsif ($param == 1) {
		cli_subscribe_terms_all($client_socket);
	}

	$request->setStatusDone();
}

# handles the "listen" query
sub listenQuery {
	my $request = shift;
 
	$d_cli_vv && msg("CLI::listenQuery()\n");
 
	if ($request->isNotQuery([['listen']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $client_socket = $request->privateData();
	
	if (!defined $client_socket) {
		$request->setStatusBadParams();
		return;
	}	

	$request->addResult('_listen',  defined($connections{$client_socket}{'subscribe'}{'listen'}) || 0);

	$request->setStatusDone();
}

# handles the "subscribe" command
sub subscribeCommand {
	my $request = shift;
 
	$d_cli_vv && msg("CLI::subscribeCommand()\n");
 
	if ($request->isNotCommand([['subscribe']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $param = $request->getParam('_functions');
	my $client_socket = $request->privateData();
	
	if (!defined $client_socket) {
		$request->setStatusBadParams();
		return;
	}	

	if (defined $param) {
		my @elems = split(/,/, $param);
		cli_subscribe_terms($client_socket, \@elems);
	} else {
		cli_subscribe_terms_none();
	}

	$request->setStatusDone();
}

################################################################################
# Subscription management
################################################################################

# subscribe hash:
# .. listen:      * to get everything
#                 array ref containing array ref containing list of cmds to get
#                 (in Request->isCommand form, i.e. [['cmd1', 'cmd2', 'cmd3']])
# .. status:      hash ref:
#                   ..<clientid> : Request object to use for client


# cancels all subscriptions
sub cli_subscribe_terms_none {
	my $client_socket = shift;

	$d_cli_vv && msg("CLI: cli_subscribe_terms_none()\n");

	delete $connections{$client_socket}{'subscribe'}{'listen'};
	
	cli_subscribe_manage();
}

# monitor all things happening on server
sub cli_subscribe_terms_all {
	my $client_socket = shift;
	
	$d_cli_vv && msg("CLI: cli_subscribe_terms_all()\n");

	$connections{$client_socket}{'subscribe'}{'listen'} = '*';
	
	cli_subscribe_manage();
}

# monitor only certain commands
sub cli_subscribe_terms {
	my $client_socket = shift;
	my $array_ref = shift;
	
	$d_cli_vv && msg("CLI: cli_subscribe_terms()\n");

	$connections{$client_socket}{'subscribe'}{'listen'} = [$array_ref];
	
	cli_subscribe_manage();
}

# monitor status for a given client
sub cli_subscribe_status {
	my $client_socket = shift;
	my $request = shift;
	my $subparam = shift;
	
	$d_cli_vv && msg("CLI: cli_subscribe_status()\n");

	my $clientid = $request->clientid();
	
	# kill any previous subscription we might have laying around
	my $statusrequest = $connections{$client_socket}{'subscribe'}{'status'}{$clientid};

	delete $connections{$client_socket}{'subscribe'}{'status'}{$clientid};

	Slim::Utils::Timers::killOneTimer($statusrequest,
		\&cli_subscribe_status_output);

	# store the new subscription if this is what is asked of us
	if ($subparam ne '-') {
		
		# copy the request
		my $statusrequest = $request->virginCopy();

		$connections{$client_socket}{'subscribe'}{'status'}{$clientid} = $statusrequest;

		if ($subparam > 0) {
			# start the timer
			Slim::Utils::Timers::setTimer($statusrequest, 
				Time::HiRes::time() + $subparam,
				\&cli_subscribe_status_output);
		}
	}
	
	cli_subscribe_manage();
}

# subscribes or unsubscribes to the Request notification system
sub cli_subscribe_manage {

	$d_cli_vv && msg("CLI: cli_subscribe_manage()\n");

	# do we need to subscribe?
	my $subscribe = 0;
	foreach my $client_socket (keys %connections) {

		if (keys(%{$connections{$client_socket}{'subscribe'}})) {

			$subscribe++;
			last;
		}
	}
	
	# subscribe
	if ($subscribe && !$cli_subscribed) {

		Slim::Control::Request::subscribe(\&Plugins::CLI::cli_subscribe_notification);
		$cli_subscribed = 1;

	# unsubscribe
	} elsif (!$subscribe && $cli_subscribed) {

		Slim::Control::Request::unsubscribe(\&Plugins::CLI::cli_subscribe_notification);
		$cli_subscribed = 0;
	}
}

# handles notifications
sub cli_subscribe_notification {
	my $request = shift;

	$::d_cli && msg("CLI: cli_subscribe_notification(" 
		. $request->getRequestString() . ")\n");


	# iterate over each connection, we have a single notification handler
	# for all connections
	foreach my $client_socket (keys %connections) {

		# don't send if unsubscribed
		next if !defined($connections{$client_socket}{'subscribe'});

		# retrieve the socket object
		$client_socket = $connections{$client_socket}{'socket'};

		# remember & decide if we send the echo
		my $sent = 0;

		# handle sending unique commands
		if (defined $connections{$client_socket}{'subscribe'}{'listen'}) {

			# don't echo twice to the sender
			if (!($request->source() eq 'CLI' && 
				  $request->privateData() eq $client_socket)) {

				# assume no array in {'listen'}: we send everything
				$sent = 1;
				
				# if we have an array in {'listen'}...
				if (ref $connections{$client_socket}{'subscribe'}{'listen'} 
					eq 'ARRAY') {

					# check the command matches the list of wanted commands
					$sent = $request->isCommand($connections{$client_socket}{'subscribe'}{'listen'});
				}

				# send if needed
				if ($sent) {

					# write request
					cli_request_write($request, $client_socket);
				}
			}
		}

		# commands we ignore for status (to change if other subscriptions are
		# supported!)
		next if $request->isCommand([['ir', 'button', 'debug', 'pref', 'playerpref', 'display']]);
		next if $request->isCommand([['playlist'], ['open', 'jump']]);

		# retrieve the clientid
		my $clientid = $request->clientid();
		next if !defined $clientid;
		
		# handle status sending on changes
		if (defined (my $statusrequest = $connections{$client_socket}{'subscribe'}{'status'}{$clientid})) {

			# special case: the client is gone!
			if ($request->isCommand([['client'], ['forget']])) {

				# abandon ship, client is gone!
				cli_subscribe_status($client_socket, $statusrequest, '-');

				# notify listener if not already done
				cli_request_write($request, $client_socket) if !$sent;
			}

			# something happened to our client, send status
			else {

				# don't delay for newsong
				if ($request->isCommand([['playlist'], ['newsong']])) {

					cli_subscribe_status_output($statusrequest);
				}
				
				else {

					# send everyother notif with a small delay to accomodate
					# bursts of commands

					Slim::Utils::Timers::killOneTimer($statusrequest,
						\&cli_subscribe_status_output);

					Slim::Utils::Timers::setTimer($statusrequest, 
						Time::HiRes::time() + 0.3,
						\&cli_subscribe_status_output);
				}
			}
		}
	}
}

sub cli_subscribe_status_output {
	my $request = shift;

	$d_cli_vv && msg("CLI: cli_subscribe_status_output()\n");

	$request->cleanResults();
	$request->execute();
	
	my $client_socket = $request->privateData();

	cli_request_write($request);

	# kill the delay timer (there is at most one)
	Slim::Utils::Timers::killOneTimer($request, \&cli_subscribe_status_output);

	# set the timer according to the subscribe value
	my $delay = $request->getParam('subscribe');

	if (!defined $delay || $delay eq '-') {
		# Houston we have a problem, this should not happen!
		cli_subscribe_status($client_socket, $request, '-');
	}

	elsif ($delay > 0) {

		Slim::Utils::Timers::setTimer($request, 
			Time::HiRes::time() + $delay,
			\&cli_subscribe_status_output);
	}
}


################################################################################
# PLUGIN STRINGS
################################################################################
# plugin: return strings
sub strings {
	return "
PLUGIN_CLI
	EN	Command Line Interface (CLI)
	ES	Interface de Línea de Comando (CLI)

PLUGIN_CLI_DESC
	DE	Mit Hilfe des Command Line Interface Plugin können SlimServer und Squeezeboxen über eine TCP/IP Verbindung ferngesteuert werden.  
	EN	The Command Line Interface plugin allows SlimServer and the Squeezeboxen to be controlled remotely over a TCP/IP connection, for example by a third party automation system like AMX or Crestron.

SETUP_CLIPORT
	CS	Číslo portu příkazové řádky
	DE	Kommandozeilen-Schnittstellen Port-Nummer
	DA	Port-nummer for Command Line Interface
	EN	Command Line Interface Port Number
	ES	Número de puerto para la interfaz de linea de comandos
	FR	Numéro de port de l'interface en ligne de commande
	HE	פורט לממשק שורת הפקודה
	IT	Numero della porta dell'Interfaccia a linea di comando
	JA	コマンドライン インターフェース ポートナンバー
	NL	Poortnummer van de Opdrachtprompt interface
	NO	Portnummer for terminalgrensesnitt
	PT	Porta TCP da Interface de Linha de Comando
	SV	Portnummer för terminalgränssnitt
	ZH_CN	命令行界面端口号

SETUP_CLIPORT_DESC
	CS	Můžete změnit číslo portu, který bude použit k ovládání přehrávače z příkazové řádky.
	DE	Sie können den Port wechseln, der für die Kommandozeilen-Schnittstellen verwendet werden soll.
	DA	Du kan ændre hvilket port-nummer der anvendes til at styre player-afspilleren via Command Line Interfacet.
	EN	You can change the port number that is used to by a command line interface to control the player.
	ES	Puede cambiar el número de puerto que se usa para controlar el reproductor con la linea de comandos.
	FR	Vous pouvez changer le port utilisé par l'interface en ligne de commande pour contrôler la platine.
	HE	פורט זה משמש לשליטה על נגנים
	IT	Puoi cambiare il numero della porta usata dall'interfaccia a linea di comando per controllare il lettore. (Imposta a zero per disabilitare l'interfaccia a linea di comando).
	JA	プレーヤーをコントロールする、コマンドライン インターフェースに使われるポートナンバーを変更することができます。
	NL	Je kunt het poortnummer aanpassen dat gebruikt wordt om de player via een Opdrachtprompt interface te bedienen. Zet dit poortnummer op 0 (nul) als je de Opdrachtprompt interface wilt uitschakelen.
	NO	Du kan endre portnummeret som brukes for å kontrollere din spiller via et terminalgrensesnitt.
	PT	Pode mudar o número da porta para ligação da interface de linha de comando do player.
	SV	Du kan ändra portnumret som används för att kontrollera din spelare via ett terminalgränssnitt.
	ZH_CN	您可以改变控制播放机的命令行界面所使用的端口号。

SETUP_CLIPORT_OK
	CS	Nyní bude používán následující port pro ovládaní příkazovým řádkem
	DE	Der folgende Port wird für die Kommandozeilen-Schnittstelle verwendet:
	DA	Anvender nu følgende port til Command Line Interfacet:
	EN	Now using the following port for the command line interface:
	ES	Utilizando puerto:
	FR	L'interface en ligne de commande utilise maintenant le port :
	IT	E' attualmente in uso la seguente porta per l'interfaccia a linea di comando:
	JA	現在コマンドライン インターフェースには、以下のポートが使われています:
	NL	De volgende poort wordt gebruikt voor de Opdrachtprompt interface:
	NO	Bruker nå følgende portnummer for terminalgrensesnitt:
	PT	A porta para acesso via linha de comando é
	SV	Använder nu följande portnummer för terminalgränssnittet:
	ZH_CN	当前正使用如下的命令行界面端口：

";
}

1;

