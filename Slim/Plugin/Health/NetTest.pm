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

my $FRAME_LEN = 1400; # length of test frame

our @testRates = ( 64, 128, 192, 256, 320, 500, 1000, 1500, 2000, 2500, 3000, 4000, 5000 );

my $defaultSB  = 1000;
my $defaultSB2 = 2000;

sub initPlugin {
	my $class = shift;

	Slim::Control::Request::addDispatch(['nettest', '_query'], [1, 1, 0, \&cliQuery]);
	Slim::Control::Request::addDispatch(['nettest', 'start', '_rate'], [1, 1, 0, \&cliStartTest]);
	Slim::Control::Request::addDispatch(['nettest', 'stop'], [1, 1, 0, \&cliStopTest]);

	$class->next::method(@_);

	# we don't want this plugin to show up in the Extras menu
	Slim::Buttons::Home::delSubMenu($class->playerMenu, $class->displayName);

	Slim::Menu::SystemInfo->registerInfoProvider( health => (
		after => 'bottom',
		func  => \&systemInfoMenu,
	) );
}

our %functions = (
	'left' => sub  {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},

	'down' => sub  {
		my $client = shift;
		my $button = shift;
		return if ($button ne 'down');

		my $params = $client->modeParam('testparams') || return;;
		setTest($params, $params->{'test'} + 1, undef);
	},

	'up' => sub  {
		my $client = shift;
		my $button = shift;
		return if ($button ne 'up');

		my $params = $client->modeParam('testparams') || return;
		setTest($params, $params->{'test'} - 1, undef);
	},

	'knob' => sub {
		my ($client, $funct, $functarg) = @_;

		my $test = $client->knobPos;

		my $params = $client->modeParam('testparams') || return;
		setTest($params, $test, undef);
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


# We support pushing into this mode in two ways:
#
# 1) with no params set - this performs a test to the local client
#    - param 'testmode' is set to 'self'
#
# 2) with param 'target' set to another client - this performs a test to the defined client with this display here
#    - param 'testmode' is set to 'control' for this client
#    - we will push the target into this mode too and set its 'testmode' to 'target'
#    in this mode both clients can adjust the rate and exit from the test mode

sub setMode {
	my $class  = shift;
	my $client = shift;

	my $mode   = $client->modeParam('testmode');
	my $target = $client;

	if (!$mode) {

		if ($client->modeParam('target') && $target ne $client->modeParam('target')) {

			$mode   = 'control';
			$target = $client->modeParam('target');

		} else {

			$mode   = 'self';
			$target = $client;
		}

		$client->modeParam('testmode', $mode);
	}

	# show warning and exit if we can't test to this player
	if (!$target->isa("Slim::Player::Squeezebox")) {
		$client->lines(\&errorLines);
		$client->modeParam('testmode', undef);
		return;
	}

	# clear screen2 and stop other things displaying on it
	$client->modeParam('screen2', 'nettest');
	$client->update( { 'screen2' => {} } );
	$client->display->inhibitSaver(1);

	$client->lines(\&lines);

	if ($client->isa('Slim::Player::Transporter')) {
		$client->modeParam('listLen', scalar(@testRates));
		$client->modeParam('listIndex', 0);
		$client->updateKnob(1);
	}

	if ($mode eq 'self' || $mode eq 'control') {

		# store the params for a new test
		$client->modeParam('testparams', {
			'control'=> $client,
			'target' => $target,
			'test'   => 0,
			'rate'   => $testRates[0],
			'int'    => ($FRAME_LEN + 4 + 4) * 8 / $testRates[0] / 1000,
			'frame'  => 'A' x $FRAME_LEN,
			'Qlen0'  => 0,
			'Qlen1'  => 0, 
			'log'    => Slim::Utils::PerfMon->new('Network Throughput', [10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 100]),
			'refresh'=> Time::HiRes::time(),
		} );

	}

	if ($mode eq 'self' || $mode eq 'target') {

		# we are the player under test - set it up
		my $params = $client->modeParam('testparams');

		$client->execute(["stop"]);

		test($client, $params);

		# start display updates after push animation complete (we update the calculation on the control)
		Slim::Utils::Timers::setHighTimer($client, Time::HiRes::time() + 0.8, \&update, $params);

	} else {

		# force the player under test into test mode with the params shared with this mode so we can control it

		$target->power(1) if !$client->power();

		Slim::Buttons::Common::pushModeLeft($target, 'Slim::Plugin::Health::Plugin', { 
			'testmode'       => 'target', 
			'testparams'     => $client->modeParam('testparams'),
			'updateInterval' => 1, # use periodic updates on target
		});
	}
}

sub exitMode {
	my $class = shift;
	my $client = shift;

	my $testmode = $client->modeParam('testmode');
	my $params   = $client->modeParam('testparams');
	my $mode = Slim::Buttons::Common::mode($client);

	if ($testmode eq 'control' && !$params->{'poped'}) {
		$params->{'poped'} = 1;
		Slim::Buttons::Common::popModeRight($params->{'target'});
	}

	if ($testmode eq 'target' && !$params->{'poped'}) {
		$params->{'poped'} = 1;
		Slim::Buttons::Common::popModeRight($params->{'control'});
	}

	$client->modeParam('testmode', undef);

	$client->display->inhibitSaver(0);

	Slim::Utils::Timers::killHighTimers($params->{'target'}, \&test);
	Slim::Utils::Timers::killHighTimers($params->{'control'}, \&update);
}

sub setTest {
	my $params = shift;
	my $test = shift;
	my $rate = shift;

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
		return undef;
	}
	
	$params->{'test'} = $test;
	$params->{'rate'} = $rate;
	$params->{'frame'} = 'A' x $FRAME_LEN;
	$params->{'int'}  = ($FRAME_LEN + 4 + 4) * 8 / $params->{'rate'} / 1000;
	$params->{'Qlen0'} = 0;
	$params->{'Qlen1'} = 0;
	$params->{'log'}->clear();

	# restart test at new rate
	Slim::Utils::Timers::killHighTimers($params->{'target'}, \&test);
	Slim::Utils::Timers::killHighTimers($params->{'control'}, \&update);
	test($params->{'target'}, $params);
	update($params->{'control'}, $params);

	return 1;
}

# send the test traffic over slimproto
sub test {
	my $client = shift;
	my $params = shift;

	if (Slim::Buttons::Common::mode($client) ne 'Slim::Plugin::Health::Plugin') {
		return;
	}

	if ($client->isPlaying()) {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	if (Slim::Networking::Select::writeNoBlockQLen($client->tcpsock) > 0) {
		# slimproto socket is backed up - don't send test frame
		$params->{'Qlen1'}++;
	} else {
		# send test frame with the slimproto type 'test' this is discarded by the player
		$client->sendFrame('test', \($params->{'frame'}));
		$params->{'Qlen0'}++;
	}

	my $timenow = Time::HiRes::time();

	$params->{'refresh'} += $params->{'int'};

	# skip if running late [reduces actual rate sent, but avoids recording throughput drop when timers are late]
	if ($params->{'refresh'} < $timenow && ($params->{'refresh'} + $params->{'int'} * 5) < $timenow) {
		$params->{'refresh'} = $timenow;
	}

	Slim::Utils::Timers::setHighTimer($client, $params->{'refresh'}, \&test, $params);
}

# update measurement once a second using the rate successfully sent over that period
sub update {
	my $client = shift;
	my $params = shift;
	my $now = Time::HiRes::time();

	my $total = $params->{'Qlen1'} + $params->{'Qlen0'};
	$params->{'inst'} = $total ? 100 * $params->{'Qlen0'} / $total : 0;
	$params->{'log'}->log($params->{'inst'});
	$params->{'Qlen0'} = 0;
	$params->{'Qlen1'} = 0;

	$client->update();

	Slim::Utils::Timers::setHighTimer($client, $now + 1.0, \&update, $params);
}

sub lines {
	my $client = shift;
	my $params = $client->modeParam('testparams') || return {};

	my $test = $params->{'test'};
	my $rate = $params->{'rate'};
	my $inst = $params->{'inst'};
	my $avg  = $params->{'log'}->avg;
	my $text = sprintf("%i kbps : %3i%% Avg: %3i%%", $rate, $inst, $avg);

	my $target = $params->{'target'};

	my ($line, $overlay);

	if ($client->displayWidth > 160) {
		$line    = [ $client eq $target
					 ? $client->string('PLUGIN_HEALTH_NETTEST_SELECT_RATE')
					 : $client->string('PLUGIN_HEALTH_NETTEST_TESTING_TO') . ' ' . $target->name 
					];
		$overlay = [ $client->symbols($client->progressBar(100, $inst/100)), $text ];
	} else {
		$line    = [ $text, $client->symbols($client->progressBar($client->displayWidth, $inst/100)) ];
	}

	return {
		'line'    => $line,
		'overlay' => $overlay,
		'fonts'    => {
			'graphic-320x32' => 'standard',
			'graphic-160x32' => 'light_n',
			'graphic-280x16' => 'medium',
			'text' => 2,
		}
	};
}

sub errorLines {
	my $client = shift;
	return { 'line' => [ $client->string('PLUGIN_HEALTH_NETTEST_NOT_SUPPORTED') ] };
}

sub cliQuery {
	my $request = shift;
	my $client = $request->client;
	my $query  = $request->getParam('_query');

	if (!$client->isa('Slim::Player::Squeezebox')) {
		# only support players with slimproto connection
		$request->setStatusDone();
		return;
	}

	if ($query eq 'rates') {
		for my $i (0..$#testRates) {
			$request->addResultLoop('rates_loop', $i, $i, $testRates[$i]);
		}
		$request->addResult('default', $client->isa('Slim::Player::Squeezebox2') ? $defaultSB2 : $defaultSB);
	}

	if (Slim::Buttons::Common::mode($client) ne 'Slim::Plugin::Health::Plugin') {

		$request->addResult('state', 'off');

	} else {

		$request->addResult('state', 'running');

		my $params = $client->modeParam('testparams');
		my $log = $params->{'log'};

		$request->addResult('rate', $params->{'rate'});
		$request->addResult('inst', $params->{'inst'});
		$request->addResult('avg',  $log->avg);
			
		if ($query eq 'log') {
			$request->addResult('log', $log);
		} else {
			$request->addResult('distrib', $log->distrib);
		}
	}

	$request->setStatusDone();
}

sub cliStartTest {
	my $request = shift;
	my $client = $request->client;

	my $rate = $request->getParam('_rate');

	$client->power(1) if !$client->power();

	if (Slim::Buttons::Common::mode($client) ne 'Slim::Plugin::Health::Plugin') {
		Slim::Buttons::Common::pushMode($client, 'Slim::Plugin::Health::Plugin');
	}

	my $params = $client->modeParam('testparams');

	if ( setTest($params, undef, $rate) ) {

		$request->setStatusDone();

	} else {

		$request->setStatusBadParams();
	}
}

sub cliStopTest {
	my $request = shift;
	my $client = $request->client;

	if (Slim::Buttons::Common::mode($client) eq 'Slim::Plugin::Health::Plugin') {
		Slim::Buttons::Common::popMode($client);
		$client->update;
	}

	$request->setStatusDone();
}


sub systemInfoMenu {
	my ($client, $tags) = @_;
	
	return if $tags->{menuMode} || !$client;
	
	return {
		type      => 'redirect',
		name      => displayName(),

		player => {
			mode => 'Slim::Plugin::Health::Plugin',
			# specify the player to test to
			modeParams => { target => $client }
		},

		web  => {
			hide => 1
		},
	};
}

1;

