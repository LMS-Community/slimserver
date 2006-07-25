package Slim::Buttons::Power;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
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

	$client->update();

	# kick ScreenSaver::ScreenSaver to switch to off screensaver
	Slim::Utils::Timers::killTimers($client, \&Slim::Buttons::ScreenSaver::screenSaver);
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time(), \&Slim::Buttons::ScreenSaver::screenSaver);
}

sub lines {
	return { 'screen1' => {}, 'screen2' => {} };
}

1;

__END__
