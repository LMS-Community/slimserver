package Plugins::PreventStandby::Plugin;

# $Id$

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
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;

# how many seconds between checks for playing clients
my $interval = 60;

# keep the timer so we can kill it if we want
my $timer = undef;

# reference to the windows function of same name
my $SetThreadExecutionState = undef;

sub enabled {
	return ($::VERSION ge '6.1');
}

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

		$::d_plugins && msgf("Prevent Standby plugin: client %s in playmode %s\n", $client->name, $playmode);

		if ($playmode ne 'stop' && $playmode ne 'pause') {

			$::d_plugins && msg("Prevent Standby plugin: setting thread execution state\n");

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

		$::d_plugins && msg("Prevent Standby plugin: starting timer\n");

		$timer = Slim::Utils::Timers::setTimer(0, time + $interval, \&checkClientActivity);

		$::d_plugins && !defined($timer) && msg("Prevent Standby plugin: starting timer failed\n");
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

	if (Slim::Utils::OSDetect::OS() eq 'win') {

		require Win32::API;

		$SetThreadExecutionState = Win32::API->new('kernel32', 'SetThreadExecutionState', 'N', 'N');

		return startTimer();
	}

	$::d_plugins && msg("Prevent Standby plugin: Only available under Windows\n");
}

sub shutdownPlugin {
	stopTimer();
}

sub strings { return '
PLUGIN_PREVENTSTANDBY
	DE	Standby Modus während der Wiedergabe verhindern (nur in Windows)
	EN	Windows: Prevent System Standby While Playing
	FR	Windows : empêcher la mise en veille du système lors de la lecture
	NL	Windows: Voorkom systeem slaapstand gedurende het afspelen
'};

1;

__END__
