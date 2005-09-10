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

	# this is a date-time screen, so it should get updated every second
	$client->param('modeUpdateInterval', 1);

	$client->update();
}

sub lines {
	my $client = shift;
	return Slim::Buttons::Common::dateTime($client);
}

1;

__END__
