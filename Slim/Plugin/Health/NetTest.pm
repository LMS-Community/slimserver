# Plugin for SqueezeCenter to monitor Server and Network Health
#
# Network Throughput Tests for Health Plugin
# Operated via Health web page or player user interface

# $Id: NetTest.pm 11030 2006-12-22 20:23:52Z adrian $

# This code is derived from code with the following copyright message:
#
# SqueezeCenter Copyright 2005-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

package Slim::Plugin::Health::NetTest;

use base qw(Slim::Plugin::Base);
use Class::C3;

use strict;

our @testRates = ( 64, 128, 192, 256, 320, 500, 1000, 1500, 2000, 2500, 3000, 4000, 5000);

our %functions = (
	'left' => sub  {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},

	'down' => sub  {
		my $client = shift;
		my $button = shift;
		return if ($button ne 'down');

		my $params = $client->modeParam('Health.NetTest') || return;;
		setTest($client, $params->{'test'} + 1, undef, $params);
		Slim::Utils::Timers::killTimers($client, \&updateDisplay);
		updateDisplay($client, $params);
	},

	'up' => sub  {
		my $client = shift;
		my $button = shift;
		return if ($button ne 'up');

		my $params = $client->modeParam('Health.NetTest') || return;
		setTest($client, $params->{'test'} - 1, undef, $params);
		Slim::Utils::Timers::killTimers($client, \&updateDisplay);
		updateDisplay($client, $params);
	},

	'knob' => sub {
		my ($client, $funct, $functarg) = @_;

		my $test = $client->knobPos;

		my $params = $client->modeParam('Health.NetTest') || return;
		setTest($client, $test, undef, $params);
		Slim::Utils::Timers::killTimers($client, \&updateDisplay);
		updateDisplay($client, $params);
	},

);

sub getFunctions {
	my $class = shift;
	return \%functions;
}

sub displayName {
	my $class = shift;
	return Slim::Utils::Strings::string('PLUGIN_HEALTH_NETTEST');
}

sub setMode {
	my $class  = shift;
	my $client = shift;
	my $display= $client->display;

	if (!$client->display->isa("Slim::Display::Graphics")) {
		$client->lines(\&errorLines);
		return;
	}

	if ($client->isa('Slim::Player::Transporter')) {
		$client->modeParam('listLen', scalar(@testRates));
		$client->modeParam('listIndex', 0);
		$client->updateKnob(1);
	}

	$client->execute(["stop"]); # ensure this player is not streaming

	my $params = { 
		'test'   => 0,
		'rate'   => $testRates[0],
		'int'    => undef,
		'Qlen0'  => 0,
		'Qlen1'  => 0, 
		'log'    => Slim::Utils::PerfMon->new('Network Throughput', [10, 20, 30, 40, 50, 60, 70, 75, 80, 85, 90, 95, 100]),
		'header' => $display->scrollHeader,
		'refresh'=> Time::HiRes::time(), 
	};

	$client->modeParam('Health.NetTest', $params);

	# clear screen2 and stop other things displaying on it
	$client->modeParam('screen2', 'nettest');
	$client->update( { 'screen2' => {} } );

	$client->lines(\&lines);

	# start display functions after delay [to allow push animation to complete]
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 0.8, \&startDisplay, $params); 
}

sub exitMode {
	my $class = shift;
	my $client = shift;

	Slim::Utils::Timers::killTimers($client, \&updateDisplay);
	Slim::Utils::Timers::killHighTimers($client, \&sendDisplay);
	Slim::Utils::Timers::killTimers($client, \&startDisplay);

	$client->modeParam('Health.NetTest', undef);
	$client->updateMode(0); # unblock screen updates
}

sub setTest {
	my $client = shift;
	my $test = shift;
	my $rate = shift;
	my $params = shift;

	if (defined($test)) {
		$rate = $testRates[$test];
	} elsif (defined($rate)) {
		foreach my $t (0..$#testRates) {
			if ($testRates[$t] eq $rate) {
				$test = $t;
				last;
			}
		}
	}

	if (!defined $test || $test < 0 || $test > $#testRates) {
		return;
	}

	$params->{'test'} = $test;
	$params->{'rate'} = $rate;
	$params->{'int'} = ($client->display->screenBytes() + 10) * 8 / $params->{'rate'} / 1000;
	$params->{'Qlen0'} = 0;
	$params->{'Qlen1'} = 0;
	$params->{'log'}->clear();
}

sub startDisplay {
	my $client = shift;
	my $params = shift;

	$client->killAnimation(); # kill any outstanding animation
	$client->updateMode(2);   # block screen updates
	updateDisplay($client, $params);
	sendDisplay($client, $params);
}

sub updateDisplay {
	my $client = shift;
	my $params = shift;

	if (Slim::Buttons::Common::mode($client) ne 'Slim::Plugin::Health::Plugin') {
		exitMode(undef, $client);
		return;
	}

	$client->display->render(lines($client, $params));

	$params->{'Qlen0'} = 0;
	$params->{'Qlen1'} = 0;

	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 1.0, \&updateDisplay, $params);
}

sub sendDisplay {
	my $client = shift;
	my $params = shift;

	if (Slim::Buttons::Common::mode($client) ne 'Slim::Plugin::Health::Plugin') {
		exitMode(undef, $client);
		return;
	}

	my $frame = $params->{'header'} . ${$client->display->renderCache()->{'screen1'}->{'bitsref'}};

	my $slimprotoQLen = Slim::Networking::Select::writeNoBlockQLen($client->tcpsock);

	$slimprotoQLen ? $params->{'Qlen1'}++ : $params->{'Qlen0'}++;

	if ($slimprotoQLen == 0) {
		$client->sendFrame($client->display->graphicCommand, \$frame);
	}

	if ($params->{'int'}) {
		$params->{'refresh'} += $params->{'int'};
		# skip if running late [reduces actual rate sent, but avoids recording throughput drop when timers are late]
		my $timenow = Time::HiRes::time();
		if ($params->{'refresh'} < $timenow && ($params->{'refresh'} + $params->{'int'} * 3) < $timenow) {
			$params->{'refresh'} = $timenow;
		}
	} else {
		$params->{'refresh'} += 0.5;
	}

	Slim::Utils::Timers::setHighTimer($client, $params->{'refresh'}, \&sendDisplay, $params);
}

sub lines {
	my $client = shift;
	my $params = shift;

	my $test = $params->{'test'};
	my $rate = $params->{'rate'};
	my $inst = $params->{'Qlen0'} ? $params->{'Qlen0'} / ($params->{'Qlen1'} + $params->{'Qlen0'}) : 0;

	$params->{'log'}->log($inst * 100) if ($inst > 0);

	my $logTotal = defined($params->{'log'}) ? $params->{'log'}->count() : 0;
	my $avgPercent = $logTotal ? $params->{'log'}->{'sum'} / $logTotal : 0;

	return {
		'line'    => [$client->string('PLUGIN_HEALTH_NETTEST_SELECT_RATE') ],
		'overlay' => [ $client->symbols($client->progressBar(100, $inst)),
					   sprintf("%i kbps : %3i%% Avg: %3i%%", $rate, $inst * 100, $avgPercent) ],
		'fonts'    => {
			'graphic-320x32' => 'standard',
			'graphic-280x16' => 'medium',
		}
	};
}

sub errorLines {
	my $client = shift;
	return { 'line' => [ $client->string('PLUGIN_HEALTH_NETTEST_NOT_SUPPORTED') ] };
}

1;

