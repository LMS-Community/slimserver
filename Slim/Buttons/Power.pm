package Slim::Buttons::Power;

# $Id: Power.pm,v 1.16 2005/01/04 03:38:52 dsully Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);

my %functions = ();

sub init {

	Slim::Buttons::Common::addMode('off',getFunctions(),\&setMode);

	# Each button on the remote has a function:
	%functions = (
		'play' => sub  {
			my $client = shift;
			Slim::Control::Command::execute($client,["power",1]);
			Slim::Control::Command::execute($client, ["play"]);
		},
	);
}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;

	$client->lines(\&lines);

	my $sync = Slim::Utils::Prefs::clientGet($client,'syncPower');

	if (defined $sync && $sync == 0) {
		$::d_sync && Slim::Utils::Misc::msg("Temporary Unsync ".$client->id()."\n");
		Slim::Player::Sync::unsync($client,1);
	}
	
	if (Slim::Player::Source::playmode($client) eq 'play' && Slim::Player::Playlist::song($client)) {
		if (Slim::Music::Info::isRemoteURL(Slim::Player::Playlist::song($client))) {
			Slim::Control::Command::execute($client, ["stop"]);
		} else {
			Slim::Control::Command::execute($client, ["pause", 1]);
		}
	}
	
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
