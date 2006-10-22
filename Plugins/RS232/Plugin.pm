package Plugins::RS232::Plugin;

# SlimServer Copyright (C) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# This plugin allows data to be trasmitted over the transporter 
# rs232 port via the cli interface. The commands are:
#	rs232 baud 9600  		- set the baud rate
#	rs232 tx hello%20world	- transmit data
#   subscribe rs232 rx		- subscribe to rs232 received data
#	rs232 rx testing123		- notification of received data


use strict;

sub getDisplayName {
	return 'PLUGIN_RS232_NAME';
}

sub initPlugin {

	Slim::Control::Request::addDispatch(['rs232', 'baud', '_rate'], [1, 0, 0, \&rs232baud]);
	Slim::Control::Request::addDispatch(['rs232', 'tx', '_data'], [1, 0, 0, \&rs232tx]);
	Slim::Control::Request::addDispatch(['rs232', 'rx', '_data'], [1, 0, 0, \&rs232rx]);
	Slim::Networking::Slimproto::addHandler('RSRX', \&rsrx);
}

sub enabled {
	return ($::VERSION ge '6.5');
}

sub getFunctions {
	return '';
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


sub strings {
	return "
PLUGIN_RS232_NAME
	EN	RS232
";
}

1;


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
