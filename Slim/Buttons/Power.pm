package Slim::Buttons::Power;

# $Id: Power.pm,v 1.2 2003/07/24 23:14:03 dean Exp $

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Utils::Strings qw(string);
use POSIX qw(strftime);

# Each button on the remote has a function:

my %functions = (
	'play' => sub  {
		my $client = shift;
		Slim::Control::Command::execute($client, ["play"]);
	}
);

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	$client->lines(\&lines);
	Slim::Player::Playlist::unsync($client);
	
	if (Slim::Player::Playlist::playmode($client) eq 'play' && Slim::Player::Playlist::song($client)) {
		if (Slim::Music::Info::isHTTPURL(Slim::Player::Playlist::song($client))) {
			Slim::Control::Command::execute($client, ["stop"]);
		} else {
			Slim::Control::Command::execute($client, ["pause", 1]);
		}
	}
	
	# switch to power off mode
	# use our last saved brightness
	Slim::Hardware::VFD::vfdBrightness($client, Slim::Utils::Prefs::clientGet($client, "powerOffBrightness"));
	Slim::Display::Display::update($client);	
}

sub lines {
	my $client = shift;
	return Slim::Buttons::Common::dateTime($client);
}

1;

__END__
