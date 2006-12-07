# Plugin for Slimserver to monitor Server and Network Health

# $Id$

# This code is derived from code with the following copyright message:
#
# SlimServer Copyright (C) 2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

package Plugins::Health::Plugin;

use strict;

use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

use Plugins::Health::NetTest;


sub enabled {
	return ($::VERSION ge '6.5');
}

# Main web interface
sub webPages {
	my %pages = ("index\.(?:htm|xml)"         => \&handleIndex,
				 "player|server\.(?:htm|xml)" => \&handleGraphs);

	if (grep {$_ eq 'Health::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins')) {
		Slim::Web::Pages->addPageLinks("help", { 'PLUGIN_HEALTH' => undef });
	} else {
		Slim::Web::Pages->addPageLinks("help", { 'PLUGIN_HEALTH' => "plugins/Health/index.html" });
	}

	return (\%pages);
}

# Player inteface for network test - shows up on player as 'NetTest'
sub getDisplayName {
	return('PLUGIN_HEALTH_NETTEST');
}

sub setMode {
	return Plugins::Health::NetTest::setMode(@_);
}

sub getFunctions {
	return \%Plugins::Health::NetTest::functions;
}

#################################################################################################### 

# Perfmon logs managed by this plugin
my @perfmonLogs = (
	{ 'type' => 'server', 'name' => 'response',     'monitor' => \$Slim::Networking::Select::responseTime,  },
	{ 'type' => 'server', 'name' => 'timerlate',    'monitor' => \$Slim::Utils::Timers::timerLate,          },
	{ 'type' => 'server', 'name' => 'selecttask',   'monitor' => \$Slim::Networking::Select::selectTask,    },
	{ 'type' => 'server', 'name' => 'timertask',    'monitor' => \$Slim::Utils::Timers::timerTask,          },
	{ 'type' => 'server', 'name' => 'request',      'monitor' => \$Slim::Control::Request::requestTask,     },
	{ 'type' => 'server', 'name' => 'schedulertask','monitor' => \$Slim::Utils::Scheduler::schedulerTask,   },
	{ 'type' => 'server', 'name' => 'dbaccess',     'monitor' => \$Slim::Schema::Storage::dbAccess,         },
	{ 'type' => 'server', 'name' => 'pagebuild',    'monitor' => \$Slim::Web::HTTP::pageBuild,              },
	{ 'type' => 'server', 'name' => 'proctemplate', 'monitor' => \$Slim::Web::Template::Context::procTemplate },
	{ 'type' => 'server', 'name' => 'irqueue',      'monitor' => \$Slim::Hardware::IR::irPerf,              },
	{ 'type' => 'player', 'name' => 'signal',       'monitor' => \&Slim::Player::Client::signalStrengthLog, },
	{ 'type' => 'player', 'name' => 'buffer',       'monitor' => \&Slim::Player::Client::bufferFullnessLog, },
	{ 'type' => 'player', 'name' => 'control',      'monitor' => \&Slim::Player::Client::slimprotoQLenLog,  },
);

sub clearAllCounters {

	foreach my $mon (@perfmonLogs) {
		if ($mon->{'type'} eq 'server') {
			${$mon->{'monitor'}}->clear();
		} elsif ($mon->{'type'} eq 'player') {
			foreach my $client (Slim::Player::Client::clients()) {
				my $perfmon = $mon->{'monitor'}($client);
				$perfmon->clear();
			}
		}
	}
	$Slim::Networking::Select::endSelectTime = undef;
}

# Summary info which attempts to categorise common problems based on performance measurments taken
sub summary {
	my $client = shift;
	
	my ($summary, @warn);

	if (defined($client) && $client->isa("Slim::Player::Squeezebox")) {

		my ($control, $stream, $signal, $buffer);

		if ($client->tcpsock() && $client->tcpsock()->opened()) {
			if ($client->slimprotoQLenLog()->percentAbove(2) < 5) {
				$control = string("PLUGIN_HEALTH_OK");
			} else {
				$control = string("PLUGIN_HEALTH_CONGEST");
				push @warn, string("PLUGIN_HEALTH_CONTROLCONGEST_DESC");
			}
		} else {
			$control = string("PLUGIN_HEALTH_FAIL");
			push @warn, string("PLUGIN_HEALTH_CONTROLFAIL_DESC");
		}

		if ($client->streamingsocket() && $client->streamingsocket()->opened()) {
			$stream = string("PLUGIN_HEALTH_OK");
		} else {
			$stream = string("PLUGIN_HEALTH_INACTIVE");
			push @warn, string("PLUGIN_HEALTH_STREAMINACTIVE_DESC");
		}

		if ($client->signalStrengthLog()->percentBelow(30) < 1) {
			$signal = string("PLUGIN_HEALTH_OK");
		} elsif ($client->signalStrengthLog()->percentBelow(30) < 5) {
			$signal = string("PLUGIN_HEALTH_SIGNAL_INTERMIT");
			push @warn, string("PLUGIN_HEALTH_SIGNAL_INTERMIT_DESC");
		} elsif ($client->signalStrengthLog()->percentBelow(30) < 20) {
			$signal = string("PLUGIN_HEALTH_SIGNAL_POOR");
			push @warn, string("PLUGIN_HEALTH_SIGNAL_POOR_DESC");
		} else {
			$signal = string("PLUGIN_HEALTH_SIGNAL_BAD");
			push @warn, string("PLUGIN_HEALTH_SIGNAL_BAD_DESC");
		}

		$summary .= sprintf "%-22s : %s\n", string('PLUGIN_HEALTH_CONTROL'), $control;
		$summary .= sprintf "%-22s : %s\n", string('PLUGIN_HEALTH_STREAM'), $stream;
		$summary .= sprintf "%-22s : %s\n", string('PLUGIN_HEALTH_SIGNAL'), $signal;

		if (Slim::Player::Source::playmode($client) eq 'play') {

			if ($client->isa("Slim::Player::Squeezebox2")) {
				if ($client->bufferFullnessLog()->percentBelow(30) < 15) {
					$buffer = string("PLUGIN_HEALTH_OK");
				} else {
					$buffer = string("PLUGIN_HEALTH_BUFFER_LOW");
					push @warn, string("PLUGIN_HEALTH_BUFFER_LOW_DESC2");
				}
			} else {
				if ($client->bufferFullnessLog()->percentBelow(50) < 5) {
					$buffer = string("PLUGIN_HEALTH_OK");
				} else {
					$buffer = string("PLUGIN_HEALTH_BUFFER_LOW");
					push @warn, string("PLUGIN_HEALTH_BUFFER_LOW_DESC1");
				}
			}			
			$summary .= sprintf "%-22s : %s\n", string('PLUGIN_HEALTH_BUFFER'), $buffer;
		}
	} elsif (defined($client) && $client->isa("Slim::Player::SLIMP3")) {
		push @warn, string("PLUGIN_HEALTH_SLIMP3_DESC");
	} else {
		push @warn, string("PLUGIN_HEALTH_NO_PLAYER_DESC");
	}

	if ($Slim::Networking::Select::responseTime->percentAbove(1) < 0.01 || 
		$Slim::Networking::Select::responseTime->above(1) < 3 ) {
		$summary .= sprintf "%-22s : %s\n", string("PLUGIN_HEALTH_RESPONSE"), string("PLUGIN_HEALTH_OK");
	} elsif ($Slim::Networking::Select::responseTime->percentAbove(1) < 0.5) {
		$summary .= sprintf "%-22s : %s\n", string("PLUGIN_HEALTH_RESPONSE"), string("PLUGIN_HEALTH_RESPONSE_INTERMIT");
		push @warn, string("PLUGIN_HEALTH_RESPONSE_INTERMIT_DESC");
	} else {
		$summary .= sprintf "%-22s : %s\n", string("PLUGIN_HEALTH_RESPONSE"), string("PLUGIN_HEALTH_RESPONSE_POOR");
		push @warn, string("PLUGIN_HEALTH_RESPONSE_POOR_DESC");
	}

	if (defined($client) && scalar(@warn) == 0) {
		push @warn, string("PLUGIN_HEALTH_NORMAL");
	}

	return ($summary, \@warn);
}

# Main page
sub handleIndex {
	my ($client, $params) = @_;
	
	my $refresh = 60; # default refresh of 60s 
	my ($newtest, $stoptest);

	# process input parameters

	if ($params->{'perf'}) {
		if ($params->{'perf'} eq 'on') {
			$::perfmon = 1;
			clearAllCounters();
			$refresh = 1;
		} elsif ($params->{'perf'} eq 'off') {
			$::perfmon = 0;
		}
		if ($params->{'perf'} eq 'clear') {
			clearAllCounters();
			$refresh = 1;
		}
	}

	if (defined($params->{'test'})) {
		if ($params->{'test'} eq 'stop') {
			$stoptest = 1;
		} else {
			$newtest = $params->{'test'};
		}
	}

	# create params to build new page

	# status of perfmon
	if ($::perfmon) {
		$params->{'perfon'} = 1;
	} else {
		$params->{'perfoff'} = 1;
		$refresh = undef;
	}

	# summary section
	($params->{'summary'}, $params->{'warn'}) = summary($client);
	
	# client specific details
	if (defined($client)) {

		$params->{'playername'} = $client->name();
		$params->{'nettest_options'} = \@Plugins::Health::NetTest::testRates;

		if (!$client->display->isa("Slim::Display::Graphics")) {
			$params->{'nettest_notsupported'} = 1;
			
		} elsif (Slim::Buttons::Common::mode($client) eq 'PLUGIN.Health::Plugin') {
			# network test currently running on this player
			my $modeParam = $client->modeParam('Health.NetTest');
			if ($stoptest) {
				# stop tests
				Plugins::Health::NetTest::exitMode($client);
				Slim::Buttons::Common::popMode($client);
				$client->update();
				$refresh = 2;
			} elsif (defined($newtest)) {
				# change test rate
				Plugins::Health::NetTest::setTest($client, undef, $newtest, $modeParam);
				$refresh = 2;
			} 
			if (!$stoptest && defined($modeParam) && ref($modeParam) eq 'HASH' && defined $modeParam->{'log'}) { 
				# display current results
				$params->{'nettest_rate'} = $modeParam->{'rate'};
				$params->{'nettest_graph'} = $modeParam->{'log'}->sprint();
			}

		} elsif (defined($newtest)) {
			# start tests - power on if necessary
			$client->power(1) if !$client->power();
			Slim::Buttons::Common::pushMode($client, 'PLUGIN.Health::Plugin');
			my $modeParam = $client->modeParam('Health.NetTest');
			Plugins::Health::NetTest::setTest($client, undef, $newtest, $modeParam);
			if (defined($modeParam) && ref($modeParam) eq 'HASH' && defined $modeParam->{'log'}) { 
				$params->{'nettest_rate'} = $modeParam->{'rate'};
				$params->{'nettest_graph'} = $modeParam->{'log'}->sprint();
			}
			$refresh = 2;
		}
	}

	$params->{'refresh'} = $refresh;

	return Slim::Web::HTTP::filltemplatefile('plugins/Health/index.html',$params);
}

# Statistics pages
sub handleGraphs {
	my ($client, $params) = @_;
	my @graphs;

	my $type = ($params->{'path'} =~ /server/) ? 'server' : 'player';

	foreach my $mon (@perfmonLogs) {

		next if ($type ne $mon->{'type'} || $type eq 'player' && !$client);

		my $monitor = ($type eq 'server') ? ${$mon->{'monitor'}} : $mon->{'monitor'}($client);

		if (defined $params->{'monitor'} && ($params->{'monitor'} eq $mon->{'name'} || $params->{'monitor'} eq 'all') ) {
			if (exists($params->{'setwarn'})) {
				$monitor->setWarnHigh(Slim::Utils::Validate::number($params->{'warnhi'}));
				$monitor->setWarnLow(Slim::Utils::Validate::number($params->{'warnlo'}));
				$monitor->setWarnBt($params->{'warnbt'});
			}
			if (exists($params->{'clear'})) {
				$monitor->clear();
			}
		}

		push @graphs, {
			'name'  => $mon->{'name'},
			'graph' => $monitor->sprint(),
			'warnlo'=> $monitor->warnLow(),
			'warnhi'=> $monitor->warnHigh(),
			'warnbt'=> $monitor->warnBt(),
		};
	}

	$params->{'playername'} = $client->name() if $client;
	$params->{'type'} = $type;
	$params->{'graphs'} = \@graphs;
	$params->{'serverlog'} = Slim::Utils::Log::perfmonLogFile();

	return Slim::Web::HTTP::filltemplatefile("plugins/Health/graphs.html",$params);
}

1;

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
