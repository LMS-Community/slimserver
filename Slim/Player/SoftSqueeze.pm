package Slim::Player::SoftSqueeze;

# SqueezeCenter Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use base qw(Slim::Player::Transporter);

use Slim::Player::ProtocolHandlers;
use Slim::Player::Transporter;
use Slim::Utils::Prefs;

sub init {
	my $client = shift;

	$client->SUPER::init(@_);

	preferences('server')->client($client)->set('autobrightness', 0);
}

sub reconnect {
	my $client = shift;
	$client->SUPER::reconnect(@_);

	# Update the knob in reconnect - as that's the last function that is
	# called when a new or pre-existing client connects to the server.
	$client->updateKnob(1);
}

sub model {
	return 'softsqueeze';
}
sub modelName { 'SoftSqueeze' }

# SoftSqueeze can't handle WMA
sub formats {
	my $client = shift;

	if ($client->revision() == 2) {
		return qw(ogg flc aif wav mp3);
	}
	else {
		return qw(flc aif wav mp3);
	}
}

sub signalStrength {
	return undef;
}

sub hasDigitalOut {
	return 0;
}

sub needsUpgrade {
	return 0;
}

sub maxTransitionDuration {
	return 0;
}

sub hasDigitalIn {
	return 0;
}

sub hasExternalClock {
	return 0;
}

sub hasAesbeu() {
    	return 0;
}

sub hasPowerControl() {
	return 0;
}

sub hasPolarityInversion() {
	return 0;
}

sub canDirectStream {
	my $client = shift;
	my $url = shift;

	my $handler = Slim::Player::ProtocolHandlers->handlerForURL($url);

	if ($handler && $handler->can("canDirectStream") && !$handler->isa("Slim::Player::Protocols::MMS")) {
		return $handler->canDirectStream($client, $url);
	}
	
	return undef;
}


1;

__END__
