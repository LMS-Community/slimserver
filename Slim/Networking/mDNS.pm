package Slim::Networking::mDNS;

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);
 
my $confFile;
my $pidFile;
my $init = 0;
my %services = ();

sub init {
	my $class = shift;

	$::d_mdns && msg("mDNS: Initializing..\n");

	my $cacheDir = Slim::Utils::Prefs::get('cachedir');

	unless (-d $cacheDir) {

		$::d_mdns && msg("mDNS: cachedir [$cacheDir] isn't set or writeable\n");
		return;
	}

	$confFile = catfile($cacheDir, 'mDNS.conf');
	$pidFile  = catfile($cacheDir, 'mDNS.pid');

	$init = 1;
}

sub addService {
	my ($class, $service, $port) = @_;

	unless ($init) {
		return unless $class->init;
	}

	my $name = Slim::Utils::Prefs::get('mDNSname');

	if (!defined $name || $name eq '') {

		$::d_mdns && msg("mDNS: Blank name, skipping service: $service - TXT - $port\n");

	} else {

		$::d_mdns && msg("mDNS: Adding service: $name - $service - TXT - $port\n");

		$services{$service} = [ $name, $port ];

	}
}

sub removeService {
	my ($class, $service) = @_;

	unless ($init) {
		return unless $class->init;
	}

	$::d_mdns && msg("mDNS: Removing service: $service\n");

	delete $services{$service};
}

sub startAdvertising {
	my $class = shift;

	my $mDNSBin = Slim::Utils::Misc::findbin('mDNSResponderPosix');

	unless ($mDNSBin) {

		$::d_mdns && msg("mDNS: Couldn't find mDNSResponderPosix binary! Aborting!\n");
		return;
	};

	unless ($init) {
		return unless $class->init;
	}

	# Remove any existing configs
	$class->stopAdvertising;

	open(CONF, ">$confFile") or do {
		
		$::d_mdns && msg("mDNS: Couldn't open $confFile for appending!: $!\n");
		return;
	};

	# Write out the service information
	while (my ($service, $data) = each %services) {

		my ($name, $port) = @$data;

		print CONF "$name\n";
		print CONF "$service\n";
		print CONF "TXT\n";
		print CONF "$port\n";
		print CONF "\n";
	}

	close(CONF);

	if (-z $confFile) {

		$::d_mdns && msg("mDNS: Config has 0 size - disabling mDNS\n");
		return;
	}

	my $command = sprintf("%s -d -f %s -P %s", $mDNSBin, $confFile, $pidFile);

	$::d_mdns && msg("mDNS: About to run: $command\n");

	return system($command);
}

sub stopAdvertising {
	my $class = shift;

	$::d_mdns && msg("mDNS: stopAdvertising()\n");

	if (!$pidFile || !-f $pidFile) {

		$::d_mdns && msg("mDNS: No PID file.\n");
		return;
	}

	open(PID, $pidFile) or do {

		$::d_mdns && msg("mDNS: Couldn't read PID file.\n");
		return;
	};

	my $pid = <PID>;
	close(PID);

	my $ret = kill "KILL", $pid;

	if ($ret) {
		$::d_mdns && msg("mDNS: Killed PID: $pid\n");

		unlink $confFile;
		unlink $pidFile;
	}

	return $ret;
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
