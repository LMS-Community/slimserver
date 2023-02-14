package Slim::Networking::SqueezeNetwork::Time;

# Get a timestamp for systems without a RTC

use strict;

use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

use constant POLL_INTERVAL => 3600 * 24 + 3600 * rand(1);
use constant ALERT_THRESHOLD => 10;

my $log   = logger('network.squeezenetwork');
my $prefs = preferences('server');
my $fetching;

sub init {
	Slim::Utils::Timers::setTimer(
		undef,
		time() + POLL_INTERVAL,
		\&fetch_timestamp,
	);
}

sub fetch_timestamp { if (main::NOMYSB) {
	logBacktrace("Support for mysqueezebox.com has been disabled. Please update your code: don't call me if main::NOMYSB.");
} else {
	# don't run this call if we're already waiting for player information
	if ($fetching++) {
		$log->warn("Ignoring request to get timestamp from mysqueezebox.com. A request is already running ($fetching)");
		return;
	}

	Slim::Utils::Timers::killTimers( undef, \&fetch_timestamp );

	# Get the list of players for our account that are on SN
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&_timestamp_done,
		\&_timestamp_error,
		{
			Timeout => 5,
		},
	);

	$http->get( $http->url( '/api/v1/time' ) );
} }


sub _timestamp_done {
	my $http = shift;

	my $snTime = $http->content * 1.0;

	if ($snTime) {
		my $diff = int($snTime - time());
		$prefs->set( sn_timediff => $diff );

		if (needsTimeSync()) {
			$log->error("Got SqueezeNetwork server time: $snTime, diff to local time: $diff");
			$log->error("Please note that a big difference in time might cause connection issues with remote sources.");
		}
		else {
			main::INFOLOG && $log->info("Got SqueezeNetwork server time: $snTime, diff: $diff");
		}
	}
	else {
		return _timestamp_error($http);
	}

	$fetching = 0;

	Slim::Utils::Timers::setTimer(
		undef,
		time() + POLL_INTERVAL,
		\&fetch_timestamp,
	);
}

sub _timestamp_error {
	my $http  = shift;
	my $error = $http->error || 'unexpected failure';

	$log->error( "Unable to get timestamp from MySB: $error" );

	$fetching = 0;

	Slim::Utils::Timers::setTimer(
		undef,
		time() + POLL_INTERVAL,
		\&fetch_timestamp,
	);
}

sub needsTimeSync {
	return abs($prefs->get('sn_timediff')) > ALERT_THRESHOLD ? 1 : 0;
}

1;