package Slim::Buttons::Power;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);

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

	my $sync = Slim::Utils::Prefs::clientGet($client,'syncPower');

	if (defined $sync && $sync == 0) {
		$::d_sync && msg("Temporary Unsync ".$client->id()."\n");
		Slim::Player::Sync::unsync($client,1);
	}
	
	if (Slim::Player::Source::playmode($client) eq 'play' && Slim::Player::Playlist::song($client)) {
		if (Slim::Music::Info::isRemoteURL(Slim::Player::Playlist::song($client))) {
			$client->execute(["stop"]);
		} else {
			$client->execute(["pause", 1]);
		}
	}
	
	# this is a date-time screen, so it should get updated every second
	$client->param('modeUpdateInterval', 1);
	
	# switch to power off mode
	# use our last saved brightness
	$client->brightness(Slim::Utils::Prefs::clientGet($client, "powerOffBrightness"));
	$client->update();	
}

sub lines {
	my $client = shift;
	return Slim::Buttons::Common::dateTime($client);
}

1;

__END__
