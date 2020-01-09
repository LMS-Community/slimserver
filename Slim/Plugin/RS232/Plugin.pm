package Slim::Plugin::RS232::Plugin;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# This plugin allows data to be trasmitted over the transporter 
# rs232 port via the cli interface. The commands are:
#	rs232 baud 9600  		- set the baud rate
#	rs232 tx hello%20world	- transmit data
#   subscribe rs232 rx		- subscribe to rs232 received data
#	rs232 rx testing123		- notification of received data

# CLI over RS232
#	Additional code allows to use the CLI over the RS232 when enabled

use strict;

use IO::Socket;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

if ( main::WEBUI ) {
	require Slim::Plugin::RS232::Settings;
}

my %gSocket;		# There will be a connection per client
my %gClient;		# Reverse hash for easier reference

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.rs232',
	'defaultLevel' => 'OFF',
	'description'  => 'PLUGIN_RS232_NAME',
});

# Get correct CLI port
my $prefsCLI = preferences('plugin.cli');
# Our prefs
my $prefsRS232 = preferences('plugin.rs232');

sub getDisplayName {
	return 'PLUGIN_RS232_NAME';
}

sub initPlugin {
	my $class = shift;

	Slim::Control::Request::addDispatch(['rs232', 'baud', '_rate'], [1, 0, 0, \&rs232baud]);
	Slim::Control::Request::addDispatch(['rs232', 'tx', '_data'], [1, 0, 0, \&rs232tx]);
	Slim::Control::Request::addDispatch(['rs232', 'rx', '_data'], [1, 0, 0, \&rs232rx]);
	
	Slim::Networking::Slimproto::addHandler('RSRX', \&rsrx);

	# Initialize settings classes
	if ( main::WEBUI ) {
		Slim::Plugin::RS232::Settings->new;
		Slim::Web::HTTP::CSRF->protectCommand('rs232');
	}

	# Initial turn on or off CLI over RS232
	cliOverRS232Change();
}

sub cliOverRS232Change {
	# Get current setting
	my $bCLIoverRS232 = $prefsRS232->get( "clioverrs232enable");
	# Make sure a default is set in slimserver.prefs
	if( !defined( $bCLIoverRS232)) {
		$bCLIoverRS232 = 0;
		$prefsRS232->set( "clioverrs232enable", $bCLIoverRS232);
	}
	if( $bCLIoverRS232 == 1) {
		# Start getting chars from RS232 to relay to CLI
		Slim::Control::Request::subscribe( \&rs232rxCallback, [['rs232'],['rx']]);
	} else {
		# Stop getting chars from RS232
		Slim::Control::Request::unsubscribe( \&rs232rxCallback);
	}
}

sub rsrx {
	my $client = shift;
	my $data_ref = shift;

	Slim::Control::Request::executeRequest($client, ['rs232', 'rx', $$data_ref]);
}

sub rs232rx {
	my $request = shift;
	$request->setStatusDone();
}

sub rs232tx {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotCommand([['rs232', 'tx']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client = $request->client();
	my $data   = $request->getParam('_data');

	# only for transporter
	return unless $client && $client->isa('Slim::Player::Transporter');

	$client->sendFrame('rstx', \$data);
	$request->setStatusDone();
}

sub rs232baud {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotCommand([['rs232', 'tx']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client = $request->client();
	my $rate   = $request->getParam('_rate');

	# only for transporter
	return unless $client && $client->isa('Slim::Player::Transporter');

	my $data = pack('N', $rate);
	$client->sendFrame('rsps', \$data);
	$request->setStatusDone();
}

sub rs232rxCallback {
	my $request = shift;
	my $client = $request->client();
	
	my $data = $request->getParam('_data');

	main::DEBUGLOG && $log->debug( "RS232: rx data: " . $data . "\n");

	# When the first character on RS232 is received we open a socket connection to CLI (localhost)
	if( !defined( $gSocket{$client})) {
		$gSocket{$client} = IO::Socket::INET->new( PeerAddr => "127.0.0.1",
							   PeerPort => $prefsCLI->get('cliport'),
							   Proto => "tcp",
							   Type => SOCK_STREAM);
	}
	# Check if socket was opened successful
	if( !defined( $gSocket{$client})) {
		main::DEBUGLOG && $log->debug( "RS232: Cannot connect to CLI!\n");
	}
	# If we have a socket connection
	if( defined( $gSocket{$client})) {
		my $socket = $gSocket{$client};
		# Save for later reference
		$gClient{$socket} = $client;
		# Send received data from RS232 to CLI
		print $socket $data;
		# Start relaying CLI data back to RS232
		relayAnswerNext( $client);
	}
}

sub relayAnswerNext {
	my $client = shift;
	
	# Add us to the select loop so we get notified
	Slim::Networking::Select::addRead( $gSocket{$client}, \&relayAnswer);
}

sub relayAnswer {
	my $socket = shift;
	my $client = $gClient{$socket};

	if( !defined( $client)) {
		return;
	}
	
	# Remove us from the select loop
	Slim::Networking::Select::removeRead( $socket);

	my $indata;

	# Read 1 byte from the socket (CLI)
	my $bytes_read = $socket->sysread( $indata, 1);

	main::DEBUGLOG && $log->debug( "RS232: byte: " . $indata . "\n");

	# Relay 1 byte back over RS232
	Slim::Control::Request::executeRequest( $client, ['rs232', 'tx', $indata]);

	# If we go faster than 0.001 the current RS232 implementation in Transporter firmware drops chars
	Slim::Utils::Timers::setTimer( $client, Time::HiRes::time() + 0.001, \&relayAnswerNext);
}


1;
