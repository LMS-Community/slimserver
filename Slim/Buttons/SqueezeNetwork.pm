package Slim::Buttons::SqueezeNetwork;

# This code is derived from code with the following copyright message:
#
# SqueezeCenter Copyright (C) 2006-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Buttons::SqueezeNetwork

=head1 DESCRIPTION

L<Slim::Buttons:SqueezeNetwork> is simple module to offer a UI
for breaking a player's connection with SqueezeCenter in order to reconnect 
to SqueezeNetwork.

=cut

use strict;

use Slim::Control::Request;
use Slim::Utils::Timers;
use Slim::Buttons::Common;

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.1 $,10);

sub init {
	Slim::Buttons::Common::addMode('squeezenetwork.connect',
				       getFunctions(),
				       \&setMode);
	Slim::Buttons::Home::addMenuOption('SQUEEZENETWORK_CONNECT',
				{useMode => 'squeezenetwork.connect'});
}

sub setMode {
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	# Stop the player before disconnecting
	Slim::Control::Request::executeRequest($client, ['stop']);

	$client->lines(\&lines);

	# we want to disconnect, but not immediately, because that
	# makes the UI jerky.  Postpone disconnect for a short while
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 1,
				      \&connectSqueezeNetwork);

	# this flag prevents disconnect if user has popped out of this mode
	$client->modeParam('squeezenetwork.connect', 1);
}

our %functions = (
	'up' => sub  {
		my $client = shift;
		my $button = shift;
		$client->bumpUp() if ($button !~ /repeat/);
	},
	'down' => sub  {
		my $client = shift;
		my $button = shift;
		$client->bumpDown() if ($button !~ /repeat/);
	},
	'left' => sub  {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
	'right' => sub  {
		my $client = shift;
		$client->bumpRight();
	}
);

sub lines {
	my $client = shift;
	my ($line1, $line2, $overlay);

	$line1 = $client->string('SQUEEZENETWORK');

	if (clientIsCapable($client)) {
		$line2 = $client->string('SQUEEZENETWORK_CONNECTING');
	} else {
		$line2 = $client->string('SQUEEZENETWORK_SB2_REQUIRED');
	}

	return {
		'line' => [ $line1, $line2 ]
	};
}

sub getFunctions() {
	return \%functions;
}

# can the client handle the 'serv' message?
sub clientIsCapable {
	my $client = shift;
	# for now, only SB2s can do it
	return $client->isa('Slim::Player::Squeezebox2');
}

sub connectSqueezeNetwork {
	my $client = shift;

	# don't disconnect unless we're still in this mode.
	return unless ($client->modeParam('squeezenetwork.connect'));

	if (clientIsCapable($client)) {
		my $host = pack('N',1);  # 1 is squeezenetwork
		$client->sendFrame('serv', \$host);

		# TODO: ensure client actually received the message

		# if message recieved, client has disconnected
		Slim::Control::Request::executeRequest(
			$client,
			['client', 'forget']);
	}
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

=cut

1;

