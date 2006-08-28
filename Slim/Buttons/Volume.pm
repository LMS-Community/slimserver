package Slim::Buttons::Volume;

# $Id$
#
# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Buttons::Volume

=head1 DESCRIPTION

Creates a 'volume' mode to handle the volume setting when a user presses the
Volume button on a Transporter unit. Volume changes when using the remote are
handled by L<Slim::Player::Player::mixerDisplay>.

=cut

use strict;
use warnings;

use Time::HiRes;

use Slim::Buttons::Common;
use Slim::Hardware::IR;
use Slim::Utils::Timers;

my $AUTO_EXIT_TIME = 3.0; # seconds to leave volume automatically

sub init {
	Slim::Buttons::Common::addMode('volume', Slim::Buttons::Volume::getFunctions(), \&Slim::Buttons::Volume::setMode);
}

sub volumeExitHandler {
	my ($client, $exittype) = @_;

	if ($exittype) {
		$exittype = uc($exittype);
	}

	if (!$exittype || $exittype eq 'LEFT') {

		Slim::Utils::Timers::killTimers($client, \&_volumeIdleChecker);
		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {

		$client->bumpRight;
	}
}

sub getFunctions {
	return {};
}

sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Utils::Timers::killTimers($client, \&_volumeIdleChecker);
		Slim::Buttons::Common::popMode($client);
		return;
	}

	Slim::Buttons::Common::pushMode($client, 'INPUT.Bar', {
		'header'       => 'VOLUME',
		'stringHeader' => 1,
		'headerValue'  => sub { return $_[0]->volumeString($_[1]) },
		'onChange'     => \&Slim::Buttons::Settings::executeCommand,
		'command'      => 'mixer',
		'subcommand'   => 'volume',
		'initialValue' => sub { return $_[0]->volume },
		'valueRef'     => $client->volume,
		'callback'     => \&volumeExitHandler,
		'increment'    => 1,
		'lines'        => $client->customVolumeLines(),
		'screen2'      => 'inherit',
	});

	_volumeIdleChecker($client);
}

sub _volumeIdleChecker {
	my $client = shift;

	if (Time::HiRes::time() - Slim::Hardware::IR::lastIRTime($client) < $AUTO_EXIT_TIME) {

		Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 1.0, \&_volumeIdleChecker, $client);

	} else {

		volumeExitHandler($client);
	}
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

=cut

1;
