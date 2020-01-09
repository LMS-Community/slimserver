package Slim::Buttons::Power;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Buttons::Power

=head1 DESCRIPTION

L<Slim::Buttons::Power> is a Logitech Media Server module to add an 'off' mode.
The players are never truly off, instead entering and leaving this 
mode in reaction to the power button.

=cut

use strict;
use Slim::Utils::Misc;

our %functions = ();

sub init {

	Slim::Buttons::Common::addMode('off',getFunctions(),\&setMode);

	# Each button on the remote has a function:
	%functions = (
		'play' => sub  {
			my $client = shift;

			$client->execute(["power",1]);
			$client->execute(["play"]);
		},
	);
}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;

	$client->lines(\&lines);
	
	# disable visualizer in this mode
	$client->modeParam('visu',[0]);
	$client->modeParam('screen2', 'power');

	$client->update();

	# kick ScreenSaver::ScreenSaver to switch to off screensaver
	if ( Slim::Utils::Timers::killTimers($client, \&Slim::Buttons::ScreenSaver::screenSaver) ) {
		Slim::Utils::Timers::setTimer($client, Time::HiRes::time(), \&Slim::Buttons::ScreenSaver::screenSaver);
	}
}

sub lines {
	return { 'screen1' => {}, 'screen2' => {} };
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

L<Slim::Utils::Timers>

=cut

1;

__END__
