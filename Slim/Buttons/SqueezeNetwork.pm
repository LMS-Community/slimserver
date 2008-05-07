package Slim::Buttons::SqueezeNetwork;

# This code is derived from code with the following copyright message:
#
# SqueezeCenter Copyright 2006-2007 Logitech.
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
use Slim::Networking::SqueezeNetwork;

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.2 $,10);

sub init {
	Slim::Buttons::Common::addMode('squeezenetwork.connect',
				       getFunctions(),
				       \&setMode);
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

	if ($client->hasServ) {
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

sub connectSqueezeNetwork {
	my $client = shift;

	# don't disconnect unless we're still in this mode.
	return unless ($client->modeParam('squeezenetwork.connect'));

	if ($client->hasServ) {
		my $host = Slim::Networking::SqueezeNetwork->get_server("sn");
		my $packed;

		if ( $host eq "www.squeezenetwork.com" ) {
			$packed = pack 'N', 1;
		}
		elsif ( $host eq "www.test.squeezenetwork.com" ) {
			$packed = pack 'N', 2;
		}
		else {
			# anything else is probably a custom value by a developer
			# testing against a local SqueezeNetwork instance
			$packed = scalar gethostbyname($host);
		}

		$client->execute([ 'stop' ]);
		
		$client->sendFrame('serv', \$packed);

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

