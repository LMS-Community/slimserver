package Slim::Plugin::Stats::Plugin;

use strict;

use Config;
use Digest::SHA1 qw(sha1_base64);
use JSON::XS::VersionOneAndTwo;

use base qw(Slim::Plugin::Base);
use Slim::Utils::Log;
use Slim::Utils::Prefs;

use constant REPORT_URL => 'https://stats.lms-community.org/api/instance/%s/';
use constant REPORT_DELAY => 2.40;
use constant REPORT_INTERVAL => 86400 * 7;

my $serverPrefs = preferences('server');

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.stats',
	'defaultLevel' => 'WARN',
	'description'  => __PACKAGE__->getDisplayName(),
});

my $id;

sub initPlugin {
	$id ||= sha1_base64(preferences('server')->get('server_uuid'));

	Slim::Utils::Timers::setTimer($id, time() + REPORT_DELAY, \&_reportStats);
}

sub _reportStats {
	Slim::Utils::Timers::killTimers($id, \&_reportStats);

	my $osDetails = Slim::Utils::OSDetect::details();
	my $plugins = [ sort map { /^(?:Slim::Plugin|Plugins)::(.*)::/; $1 }  grep { $_ ne __PACKAGE__ }Slim::Utils::PluginManager->enabledPlugins() ];
	my $totals = Slim::Schema->totals();

	my $data = {
		version  => $::VERSION,
		os       => $osDetails->{'osName'},
		platform => $osDetails->{'osArch'},
		perl     => $Config{'version'},
		players  => scalar (Slim::Player::Client::clients() || ()) || 0,
		plugins  => $plugins,
		skin     => $serverPrefs->get('skin'),
		tracks   => $totals->{track},
	};

	main::INFOLOG && $log->is_info && $log->info("Reporting system stats");
	# we MUST clone the data, as Data::Dump::dump would convert numbers to strings...
	main::DEBUGLOG && $log->is_debug && $log->debug("$id: ", Data::Dump::dump(Storable::dclone($data)));

	Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			main::INFOLOG && $log->is_info && $log->info("Successfully reported stats");
			_scheduleReport();
		},
		sub {
			my ($http, $error) = @_;
			$log->error("Failed to report stats: $error");
			_scheduleReport();
		},
		{
			timeout  => 5,
		},
	)->post(
		sprintf(REPORT_URL, $id),
		'x-lms-id' => $id,
		'Content-Type' => 'application/json',
		to_json($data),
	);
}

sub _scheduleReport {
	Slim::Utils::Timers::setTimer($id, time() + REPORT_INTERVAL, \&_reportStats);
}

1;