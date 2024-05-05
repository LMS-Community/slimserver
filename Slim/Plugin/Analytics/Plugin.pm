package Slim::Plugin::Analytics::Plugin;

use strict;

use Config;
use Digest::SHA1 qw(sha1_base64);
use JSON::XS::VersionOneAndTwo;
use List::Util qw(min);

use base qw(Slim::Plugin::Base);
use Slim::Utils::Log;
use Slim::Utils::Prefs;

use constant REPORT_URL => 'https://stats.lms-community.org/api/instance/%s/';
use constant REPORT_DELAY => 240;
use constant REPORT_BACKOFF_DELAY => 1800;
use constant REPORT_INTERVAL => 86400 * 7;

my $serverPrefs = preferences('server');

my $log;
my $id;
my $backoff = 1;

# delay init, as we want to be sure we're enabled before trying to read the display name
sub postinitPlugin {
	$id ||= sha1_base64(preferences('server')->get('server_uuid'));
	# replace / with +, as / would be interpreted as a path part
	$id =~ s/\//+/g;

	$log = Slim::Utils::Log->addLogCategory({
		'category'     => 'plugin.analytics',
		'defaultLevel' => 'WARN',
		'description'  => __PACKAGE__->getDisplayName(),
	});

	Slim::Utils::Timers::setTimer($id, time() + REPORT_DELAY, \&_report);
}

sub _report {
	Slim::Utils::Timers::killTimers($id, \&_report);

	my $osDetails = Slim::Utils::OSDetect::details();
	my $plugins = [ sort map {
		/^(?:Slim::Plugin|Plugins)::(.*)::/
	}  grep {
		my $pluginData = Slim::Utils::PluginManager->dataForPlugin($_) || {};
		$_ ne __PACKAGE__ && !$pluginData->{enforce};
	} Slim::Utils::PluginManager->enabledPlugins() ];

	my $totals = Slim::Schema->totals();

	my $playerTypes;
	my @players = map {
		$playerTypes->{$_->model}++;
		$_->model;
	} grep {
		$_->model ne 'group'
	} Slim::Player::Client::clients();

	my $data = {
		version  => $::VERSION,
		revision => $::REVISION,
		os       => lc($osDetails->{'os'}),
		osname   => $osDetails->{'osName'},
		platform => $osDetails->{'osArch'},
		perl     => $Config{'version'},
		players  => scalar @players,
		playerTypes => $playerTypes,
		plugins  => $plugins,
		skin     => $serverPrefs->get('skin'),
		tracks   => $totals->{track},
	};

	main::INFOLOG && $log->is_info && $log->info("Reporting system analytics");
	# we MUST clone the data, as Data::Dump::dump would convert numbers to strings...
	main::DEBUGLOG && $log->is_debug && $log->debug("$id: ", Data::Dump::dump(Storable::dclone($data)));

	Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			main::INFOLOG && $log->is_info && $log->info("Successfully reported analytics");
			_scheduleReport($data->{players} == 0 || $data->{tracks} == 0);
		},
		sub {
			my ($http, $error) = @_;
			$log->error("Failed to report analytics: $error");
			_scheduleReport(1);
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
	my ($failed) = @_;
	my $next = REPORT_INTERVAL;

	if ($failed) {
		$next = min(REPORT_INTERVAL, $backoff * REPORT_BACKOFF_DELAY);
		$backoff *= 2;
	}

	main::INFOLOG && $log->is_info && $log->info("Next analytics update in $next seconds.");

	Slim::Utils::Timers::setTimer($id, time() + $next, \&_report);
}

1;