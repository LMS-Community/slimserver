package Slim::Buttons::Block;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Utils::Strings qw(string);
use Slim::Utils::Timers;
use Slim::Utils::Misc;
use Slim::Buttons::Common;


my $ticklength = .25;            # length of each tick, seconds
my $tickdelay = .5;              # wait half a second before starting the display update
my @tickchars=('|','/','-','\\');

Slim::Buttons::Common::addMode('block',getFunctions(),\&setMode);

# Each button on the remote has a function:

my %functions = ();

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	$client->lines(\&lines);
}

sub block {
	my $client = shift;
	my $line1 = shift;
	my $line2 = shift;
	$client->blocklines(1, $line1);
	$client->blocklines(2, $line2);
	Slim::Buttons::Common::pushMode($client,'block');
	if (defined $line1) {
		$client->showBriefly($line1, $line2);
	}
	# set the first timer to go after .5 sec. We only want to show the status
	# indicator if it has been a while
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time()+$tickdelay, \&updateBlockedStatus);
}

sub updateBlockedStatus {
	my $client=shift;

	die unless ($client);

	$client->update();

	Slim::Utils::Timers::setTimer($client, Time::HiRes::time()+$ticklength, \&updateBlockedStatus);
}

sub unblock {
	my $client = shift;
	Slim::Utils::Timers::killTimers($client, \&updateBlockedStatus);
	Slim::Buttons::ScreenSaver::wakeup($client);
	if (Slim::Buttons::Common::mode($client) eq 'block') {
		Slim::Buttons::Common::popMode($client);
	}
}

sub lines {
	my $client = shift;
	
	my $pos = int(Time::HiRes::time() / $ticklength) % (@tickchars);
	my $tickchar = $tickchars[$pos];

	my ($line1, $line2) = ($client->blocklines(1), $client->blocklines(2));

	return($line1, $line2, $tickchar, undef);
}

1;

__END__
