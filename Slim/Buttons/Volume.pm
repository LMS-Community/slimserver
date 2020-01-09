package Slim::Buttons::Volume;

# Logitech Media Server Copyright 2001-2020 Logitech.
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

use Time::HiRes;

use Slim::Buttons::Common;
use Slim::Hardware::IR;
use Slim::Utils::Timers;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

my $AUTO_EXIT_TIME = 3.0; # seconds to leave volume automatically

sub init {
	Slim::Buttons::Common::addMode('volume', Slim::Buttons::Volume::getFunctions(), \&Slim::Buttons::Volume::setMode);
}

sub volumeExitHandler {
	my ($client, $exittype) = @_;

	if ($exittype) {
		$exittype = uc($exittype);
	}

	if (!$exittype || $exittype =~ /LEFT|PASSBACK|EXIT/) {

		Slim::Utils::Timers::killTimers($client, \&_volumeIdleChecker);

		if ($client->modeParam('transition')) {

			Slim::Buttons::Common::popModeRight($client);

		} else {

			Slim::Buttons::Common::popMode($client);

			# If the exposed mode is a screensaver pop this too
			if ($exittype && $exittype =~ /LEFT|EXIT/ && Slim::Buttons::Common::mode($client) =~ /^screensaver/i) {
				Slim::Buttons::Common::popMode($client);
			}
			
			$client->update();
		}

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

	my $timeout = $client->modeParam('timeout') || $AUTO_EXIT_TIME;
	my $passthrough = $client->modeParam('passthrough');
	my $transition = $client->modeParam('transition');

	Slim::Buttons::Common::pushMode($client, 'INPUT.Volume', {
		'header'       => 'VOLUME',
		'stringHeader' => 1,
		'headerValue'  => sub { return $_[0]->volumeString($_[1]) },
		'onChange'     => \&Slim::Buttons::Settings::executeCommand,
		'command'      => 'mixer',
		'subcommand'   => 'volume',
		'initialValue' => sub { return $prefs->client($_[0])->get('volume') },
		'valueRef'     => $prefs->client($client)->get('volume'),
		'callback'     => \&volumeExitHandler,
		'increment'    => 1,
		'lines'        => $client->customVolumeLines(),
		'screen2'      => 'inherit',
		'visu'         => $client->display->isa('Slim::Display::Transporter') ? undef : [0],
		'transition'   => $transition,
	});

	if ($passthrough) {
		Slim::Hardware::IR::executeButton($client, $client->lastirbutton, $client->lastirtime);
	}

	_volumeIdleChecker($client, $timeout);
}

sub _volumeIdleChecker {
	my $client = shift;
	my $timeout= shift;

	if (Time::HiRes::time() - Slim::Hardware::IR::lastIRTime($client) < $timeout) {

		Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 0.5, \&_volumeIdleChecker, $timeout);

	} else {

		volumeExitHandler($client);
	}
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

=cut

1;
