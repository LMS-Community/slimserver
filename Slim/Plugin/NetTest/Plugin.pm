# Plugin for Logitech Media Server to test network bandwidth
#

# This code is derived from code with the following copyright message:
#
# Logitech Media Server Copyright 2005-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

package Slim::Plugin::NetTest::Plugin;

use strict;

use base qw(Slim::Plugin::Base);

use constant HANDLER => qw(Slim::Plugin::NetTest::ProtocolHandler);

Slim::Player::ProtocolHandlers->registerHandler('teststream', HANDLER);

my $FRAME_LEN_SB1 =  560; # test frame len - SB1 can't support longer frames
my $FRAME_LEN_SB2 = 1400; # test frame len for SB2 and later

my $defaultRate   = 1000; # default test rate

sub initPlugin {
	my $class = shift;

	Slim::Control::Request::addDispatch(['nettest', '_query'], [1, 1, 0, \&cliQuery]);
	Slim::Control::Request::addDispatch(['nettest', 'start', '_rate'], [1, 1, 0, \&cliStartTest]);
	Slim::Control::Request::addDispatch(['nettest', 'stop'], [1, 1, 0, \&cliStopTest]);

	$class->SUPER::initPlugin(@_);

	# we don't want this plugin to show up in the Extras menu
	Slim::Buttons::Home::delSubMenu($class->playerMenu, $class->getDisplayName);

	Slim::Menu::SystemInfo->registerInfoProvider( nettest => (
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
	return Slim::Utils::Strings::string('PLUGIN_NETTEST');
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

	my @testRates = testRates($target);

	if ($client->isa('Slim::Player::Transporter')) {
		$client->modeParam('listLen', scalar(@testRates));
		$client->modeParam('listIndex', 0);
		$client->updateKnob(1);
	}

	if ($mode eq 'self' || $mode eq 'control') {

		my $testFrameLen = $client->isa('Slim::Player::Squeezebox1') ? $FRAME_LEN_SB1 : $FRAME_LEN_SB2;

		# store the params for a new test
		$client->modeParam('testparams', {
			'control'=> $client,
			'target' => $target,
			'test'   => 0,
			'rate'   => $testRates[0],
			'int'    => ($testFrameLen + 4 + 4) * 8 / $testRates[0] / 1000,
			'frame'  => 'A' x $testFrameLen,
			'framelen'=> $testFrameLen,
			'Qlen0'  => 0,
			'Qlen1'  => 0,
			'inst'   => 0,
			'sum'    => 0,
			'count'  => 0,
			'log'    => [
				{ 10 => 0 }, { 20 => 0 }, { 30 => 0 }, { 40 => 0 }, { 50 => 0 }, { 60 => 0 },
				{ 70 => 0 }, { 80 => 0 }, { 90 => 0 }, { 95 => 0 }, { 100 => 0 },
			],
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

		Slim::Buttons::Common::pushModeLeft($target, 'Slim::Plugin::NetTest::Plugin', { 
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

	my @testRates = testRates($params->{'target'});

	if (defined($test)) {

		$rate = $testRates[$test];

	} elsif (defined($rate)) {

		foreach my $t (0..$#testRates) {
			if ($testRates[$t] == $rate) {
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
	$params->{'frame'} = 'A' x $params->{'framelen'};
	$params->{'int'}  = ($params->{'framelen'} + 4 + 4) * 8 / $params->{'rate'} / 1000;
	$params->{'Qlen0'} = 0;
	$params->{'Qlen1'} = 0;
	$params->{'sum'}   = 0;
	$params->{'count'} = 0;
	$params->{'log'} = [ { 10 => 0 }, { 20 => 0 }, { 30 => 0 }, { 40 => 0 }, { 50 => 0 }, { 60 => 0 },
						 { 70 => 0 }, { 80 => 0 }, { 90 => 0 }, { 95 => 0 }, { 100 => 0 } ];

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

	if (Slim::Buttons::Common::mode($client) ne 'Slim::Plugin::NetTest::Plugin') {
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
	if ($params->{'refresh'} < $timenow && ($params->{'refresh'} + $params->{'int'} * 10) < $timenow) {
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
	$params->{'sum'} += $params->{'inst'};
	$params->{'count'}++;
	$params->{'Qlen0'} = 0;
	$params->{'Qlen1'} = 0;

	for my $bucket (@{$params->{'log'}}) {
		my ($key) = keys(%$bucket);
		next if $params->{'inst'} > $key;
		$bucket->{$key}++;
		last;
	}

	$client->update();

	Slim::Utils::Timers::setHighTimer($client, $now + 1.0, \&update, $params);
}

sub lines {
	my $client = shift;
	my $params = $client->modeParam('testparams') || return {};

	my $test = $params->{'test'};
	my $rate = $params->{'rate'};
	my $inst = $params->{'inst'};
	my $avg  = $params->{'count'} ? $params->{'sum'} / $params->{'count'} : 0;
	my $text = sprintf("%i kbps : %3i%% Avg: %3i%%", $rate, $inst, $avg);

	my $target = $params->{'target'};

	my ($line, $overlay);

	if ($client->displayWidth > 160) {
		$line    = [ $client eq $target
					 ? $client->string('PLUGIN_NETTEST_SELECT_RATE')
					 : $client->string('PLUGIN_NETTEST_TESTING_TO') . ' ' . $target->name 
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
	return { 'line' => [ $client->string('PLUGIN_NETTEST_NOT_SUPPORTED') ] };
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

	my @testRates = testRates($client);

	if ($query && $query eq 'rates') {
		for my $i (0..$#testRates) {
			$request->addResultLoop('rates_loop', $i, $i, $testRates[$i]);
		}
		$request->addResult('default', $defaultRate);
	}

	if ($client->isa('Slim::Player::SqueezePlay')) {

		my $fd = $client->controller()->songStreamController() ? $client->controller()->songStreamController()->streamHandler() : undef;

		if ($fd && $fd->isa(HANDLER) && $client->isPlaying) {

			$request->addResult('state', 'running');
			$request->addResult('rate', $fd->testrate / 1000);

			my $inst = $fd->currentrate / $fd->testrate * 100;

			$inst = $inst > 100 ? 100 : $inst;

			if (!$fd->stash) {
				$fd->stash([ { 10 => 0 }, { 20 => 0 }, { 30 => 0 }, { 40 => 0 }, { 50 => 0 }, { 60 => 0 },
							 { 70 => 0 }, { 80 => 0 }, { 90 => 0 }, { 95 => 0 }, { 100 => 0 } ]);
			} else {
				for my $bucket (@{$fd->stash}) {
					my ($key) = keys(%$bucket);
					next if $inst > $key;
					$bucket->{$key}++;
					last;
				}
			}

			$request->addResult('inst', $inst);
			$request->addResult('distrib', $fd->stash);

		} else {

			$request->addResult('state', 'off');
		}

	} else {

		if (Slim::Buttons::Common::mode($client) ne 'Slim::Plugin::NetTest::Plugin') {
			
			$request->addResult('state', 'off');
			
		} else {
			
			$request->addResult('state', 'running');
			
			my $params = $client->modeParam('testparams');
			
			$request->addResult('rate', $params->{'rate'} +0);
			$request->addResult('inst', $params->{'inst'} +0);
			$request->addResult('avg',  $params->{'count'} ? $params->{'sum'} / $params->{'count'} : 0);
			$request->addResult('distrib', $params->{'log'});
		}

	}

	$request->setStatusDone();
}

sub cliStartTest {
	my $request = shift;
	my $client = $request->client;

	my $rate = $request->getParam('_rate');

	$client->power(1) if !$client->power();

	if ($client->isa('Slim::Player::SqueezePlay')) {

		$client->execute(['playlist', 'play', "teststream://test?rate=$rate"]);

		$request->setStatusDone();

	} else {

		if (Slim::Buttons::Common::mode($client) ne 'Slim::Plugin::NetTest::Plugin') {
			Slim::Buttons::Common::pushMode($client, 'Slim::Plugin::NetTest::Plugin');
		}
		
		my $params = $client->modeParam('testparams');
		
		if ( setTest($params, undef, $rate) ) {
			
			$request->setStatusDone();
			
		} else {
			
			$request->setStatusBadParams();
		}
	}
}

sub cliStopTest {
	my $request = shift;
	my $client = $request->client;

	if ($client->isa('Slim::Player::SqueezePlay')) {

		my $fd = $client->controller()->songStreamController() ? $client->controller()->songStreamController()->streamHandler() : undef;

		if ($fd && $fd->isa(HANDLER) && $client->isPlaying) {

			$client->execute(['playlist', 'clear']);
		}

	} elsif (Slim::Buttons::Common::mode($client) eq 'Slim::Plugin::NetTest::Plugin') {

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
			mode => 'Slim::Plugin::NetTest::Plugin',
			# specify the player to test to
			modeParams => { target => $client }
		},

		web  => {
			hide => 1
		},
	};
}

sub maxRate {
	my $class = shift;
	my $client = shift;

	my $model = $client->model;

	return  3_000_000 if $model eq 'baby';

	return 10_000_000 if $model =~ /fab4|squeezeplay/;

	return  2_000_000 if $model eq 'squeezebox'; # using old test method

	return  2_000_000; # FIXME - Squeezebox2 no longer works with new firmware
}

sub testRates {
	my $client = shift;

	my $maxRate = __PACKAGE__->maxRate($client) / 1000;

	my @rates = ( 64, 128, 192, 256, 320, 500, 1000, 1500, 2000, 2500, 3000, 4000, 5000, 6000, 8000, 10000 );

	while ($rates[$#rates] > $maxRate) {
		pop @rates;
	}

	return @rates;
}

1;

