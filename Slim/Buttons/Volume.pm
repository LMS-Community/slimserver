package Slim::Buttons::Volume;

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Buttons::Volume

=head1 DESCRIPTION

L<Slim::Buttons::Volume> is the module for creating a 'volume' mode to handle the volume setting UI.

=cut

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Buttons::Common;
use Slim::Buttons::AlarmClock;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Buttons::Information;

my $params    = {};
my %functions = ();
my $AUTO_EXIT_TIME = 3.0; # seconds to leave volume automatically

sub init {
	Slim::Buttons::Common::addMode('volume', Slim::Buttons::Volume::getFunctions(), \&Slim::Buttons::Volume::setMode);

	%functions = ();

	$params = {
		'header'       => 'VOLUME',
		'stringHeader' => 1,
		'headerValue'  => \&volumeValue,
		'onChange'     => \&executeCommand,
		'command'      => 'mixer',
		'subcommand'   => 'volume',
		'initialValue' => sub { return $_[0]->volume() },
		'callback'     => \&volumeExitHandler,
		'screen2'      => 'inherit',
	};
}

sub volumeValue {
	my ($client, $arg) = @_;

	return ' ('.($arg <= 0 ? $client->string('MUTED') : int($arg/100*40+0.5)).')';
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

		$client->bumpRight();

	} else {
		return;
	}
}

sub executeCommand {
	my $client = shift;
	my $value = shift;
	
	my $command = $client->param('command');
	my $subcmd  = $client->param('subcommand');
	
	$client->execute([$command, $subcmd, $value]);
}
	
sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Utils::Timers::killTimers($client, \&_volumeIdleChecker);
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my %modeParams = %$params;
	$modeParams{'valueRef'} = $client->volume();

	$client->param('screen2', 'inherit');

	Slim::Buttons::Common::pushMode($client, 'INPUT.Bar', \%modeParams);

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

L<Slim::Utils::Prefs>

=cut

1;
