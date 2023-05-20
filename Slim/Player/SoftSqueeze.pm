package Slim::Player::SoftSqueeze;

# Logitech Media Server Copyright 2001-2020 Logitech.
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
use Slim::Player::Client;
use Slim::Player::Transporter;
use Slim::Utils::Prefs;

sub initPrefs {
	my $client = shift;

	$client->SUPER::initPrefs(@_);
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
		return qw(ogg flc aif pcm mp3);
	}
	else {
		return qw(flc aif pcm mp3);
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

sub hasRTCAlarm {
	return 0;
}

sub hasLineIn() {
	return 0;
}

sub hasScrolling { 0 }

sub canDirectStream {
	my ($client, $url, $song) = @_;

	# this is client's canDirectStream, not protocol handler's
	my $handler = $song->currentTrackHandler;
	return unless $handler && !$handler->isa("Slim::Player::Protocols::MMS");

	if ($handler->can("canDirectStreamSong")) {
		return $handler->canDirectStreamSong($client, $song);
	} elsif ($handler->can("canDirectStream")) {
		return $handler->canDirectStream($client, $url);
	}
}


# Need to use weighted play-point
sub needsWeightedPlayPoint { 1 }

sub playPoint {
	return Slim::Player::Client::playPoint(@_);
}

sub skipAhead {
	my $client = shift;

	my $ret = $client->SUPER::skipAhead(@_);

	$client->playPoint(undef);

	return $ret;
}

1;

__END__
