package Slim::Plugin::PreventStandby::Plugin;

# $Id: Plugin.pm 11021 2006-12-21 22:28:39Z dsully $

# PreventStandby.pm by Julian Neil (julian.neil@internode.on.net)
#
# Prevent the server machine from going into standby when it is streaming
# music to any clients.  Only works in Windows because it uses the CPAN
# Win32:API module.
#
# Excuse my perl.. first time I've ever used it.
#
# Thanks to the PowerSave plugin by Jason Holtzapplefor some basics,
# to various ppl on the slim forums and to CPAN and the Win32::API module.
#
#-> Changelog
#
# 1.0 - 2006-04-05 - Initial Release

use strict;
use Win32::API;

use Slim::Utils::Log;
use Slim::Utils::OSDetect;

# how many seconds between checks for playing clients
my $interval = 60;

# keep the timer so we can kill it if we want
my $timer = undef;

# Logger object
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.preventstandby',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

# reference to the windows function of same name
my $SetThreadExecutionState = undef;

sub getFunctions {
	return '';
}

sub getDisplayName {
	return 'PLUGIN_PREVENTSTANDBY';
}

sub checkClientActivity {

	$timer = undef;

	for my $client (Slim::Player::Client::clients()) {

		my $playmode = $client->playmode();

		$log->info(sprintf("Client %s in playmode %s", $client->name, $playmode));

		if ($playmode ne 'stop' && $playmode ne 'pause') {

			$log->info("Setting thread execution state");

			if (defined $SetThreadExecutionState) {
				$SetThreadExecutionState->Call(1);
			}

			startTimer();

			return 1;
		}
	}

	startTimer();

	return 0;
}

sub startTimer {

	if (!defined $timer && defined $SetThreadExecutionState) {

		$log->info("Starting timer.");

		$timer = Slim::Utils::Timers::setTimer(undef, time + $interval, \&checkClientActivity);

		if (!defined $timer) {
			$log->error("Starting timer failed!");
		}
	}

	return defined($timer);
}

sub stopTimer {

	if (defined($timer)) {

		Slim::Utils::Timers::killSpecific($timer);
		$timer = undef;
	}
}

sub initPlugin {

	$SetThreadExecutionState = Win32::API->new('kernel32', 'SetThreadExecutionState', 'N', 'N');

	return startTimer();
}

sub shutdownPlugin {
	stopTimer();
}

1;

__END__
