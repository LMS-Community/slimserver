package Slim::Plugin::Analytics::Plugin;

use strict;

use Config;
use Digest::SHA1 qw(sha1_base64);
use JSON::XS::VersionOneAndTwo;
use List::Util qw(min max);

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

	my ($playerTypes, $playersSeen);
	my @players = map {
		$playerTypes->{$_->model}++;
		$playersSeen->{$_->id}++;
		$_->model;
	} grep {
		$_->model ne 'group'
	} Slim::Player::Client::clients();

	push @players, map {
		$playerTypes->{$_}++;
		$_;
	} grep { $_ ne 'group' } _getClients($playersSeen);

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

sub _getClients {
	my ($seen) = @_;
	my @clients;

	foreach my $key (keys %{$serverPrefs->{prefs}}) {
		if ($key =~ /^$Slim::Utils::Prefs::Client::clientPreferenceTag:(.*)/) {
			my $id = $1;

			next if $seen->{$id};

			my $clientPrefs = Slim::Utils::Prefs::Client->new($serverPrefs, $id, 'nomigrate');
			my $name = $clientPrefs->get('playername');

			my $ts = 0;
			foreach (keys %{ $clientPrefs->{prefs} }) {
				next unless /^_ts_/;
				next if /^_ts_apps$/;
				$ts = max($ts, $clientPrefs->{prefs}->{$_});
			}

			next if (time() - $ts) > (86400 * 7);

			push @clients, _guessPlayerTypeFromMac($id, $name);
		}
	}

	return @clients;
}

my %playerTypes = (
	'04' => 'slimp3',
	'05' => 'squeezebox2',
	'06' => 'squeezebox3',
	'07' => 'squeezebox3',
	'08' => 'boom',
	'10' => 'transporter',
	'11' => 'transporter',
	'12' => 'squeezebox3',
	'13' => 'squeezebox3',
	'14' => 'squeezebox3',
	'15' => 'squeezebox3',
	'16' => 'receiver',
	'17' => 'receiver',
	'18' => 'receiver',
	'19' => 'receiver',
	'1a' => 'controller',
	'1b' => 'controller',
	'1c' => 'controller',
	'1d' => 'controller',
	'1e' => 'boom',
	'1f' => 'boom',
	'20' => 'boom',
	'21' => 'boom',
	'22' => 'fab4',
	'23' => 'fab4',
	'24' => 'fab4',
	'25' => 'fab4',
	'26' => 'baby',
	'27' => 'baby',
	'28' => 'baby',
	'29' => 'baby',
);

sub _guessPlayerTypeFromMac {
	my ($mac, $name) = @_;

	# most likely...
	my $playerType = 'squeezelite';

	if ($mac =~ /^00:04:20:(\d\d):/) {
		$playerType = $playerTypes{$1} || 'squeezebox';
	}
	elsif ($mac =~ /^20:02:/) {
		$playerType = 'group';
	}
	elsif ($name =~ /(softsqueeze|daphile|m6encore|squeezeplay|squeezeplayer|squeezeslave)/i) {
		$playerType = lc($1);
	}
	elsif ($name =~ /(iPengiP[ao]d|Euphony)/) {
		$playerType = $1;
	}
	elsif ($name =~ /iPeng/i) {
		$playerType = 'iPengiPod';
	}
	elsif ($name =~ /squeeze.*esp|SqueezeAMP/i) {
		$playerType = 'squeezeesp32';
	}

	return $playerType;
}

1;