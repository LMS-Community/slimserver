package Slim::Networking::mDNS;

# $Id$
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Class::Data::Inheritable);

use FindBin qw($Bin);
use File::Slurp;
use File::Spec::Functions qw(:ALL);
use Proc::Background;

use Slim::Utils::Misc;
use Slim::Utils::Prefs;

{
	my $class = __PACKAGE__;

	for my $accessor (qw(confFile pidFile processObj isInitialized)) {

		$class->mk_classdata($accessor);
	}

	$class->isInitialized(0);
}
 
my %services = ();

sub init {
	my $class = shift;

	$::d_mdns && msg("mDNS: Initializing..\n");

	my $cacheDir = Slim::Utils::Prefs::get('cachedir');

	if (!-d $cacheDir) {

		$::d_mdns && msg("mDNS: cachedir [$cacheDir] isn't set or writeable\n");
		return;
	}

	$class->confFile(catfile($cacheDir, 'mDNS.conf'));
	$class->pidFile(catfile($cacheDir, 'mDNS.pid'));

	$class->isInitialized(1);
}

sub addService {
	my ($class, $service, $port) = @_;

	if (!$class->isInitialized) {
		return if !$class->init;
	}

	my $name = Slim::Utils::Prefs::get('mDNSname');

	if (!$name) {

		$::d_mdns && msg("mDNS: Blank name, skipping service: $service - TXT - $port\n");

	} else {

		$::d_mdns && msg("mDNS: Adding service: $name - $service - TXT - $port\n");

		$services{$service} = [ $name, $port ];
	}
}

sub removeService {
	my ($class, $service) = @_;

	if (!$class->isInitialized) {
		return if !$class->init;
	}

	$::d_mdns && msg("mDNS: Removing service: $service\n");

	delete $services{$service};
}

sub startAdvertising {
	my $class = shift;

	$::d_mdns && msg("mDNS: startAdvertising - building config.\n");

	my $mDNSBin = Slim::Utils::Misc::findbin('mDNSResponderPosix') || do {

		$::d_mdns && msg("mDNS: Couldn't find mDNSResponderPosix binary! Aborting!\n");
		return;
	};

	if (!$class->isInitialized) {
		return if !$class->init;
	}

	# Remove any existing configs
	$class->stopAdvertising;

	open(CONF, '>', $class->confFile) or do {

		$::d_mdns && msgf("mDNS: Couldn't open %s for appending!: $!\n", $class->confFile);
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

	if (-z $class->confFile) {

		$::d_mdns && msg("mDNS: Config has 0 size - disabling mDNS\n");
		return;
	}

	my $command = join(' ', (
		$mDNSBin,
		sprintf('-f %s', $class->confFile),
		sprintf('-P %s', $class->pidFile)
	));

	$::d_mdns && msgf("mDNS: About to run: $command\n");

	$class->processObj( Proc::Background->new($command) );

	$::d_mdns && msgf("Process is alive: [%d] with pid: [%d]\n",
		$class->processObj->alive, $class->processObj->pid
	);
}

sub stopAdvertising {
	my $class = shift;

	$::d_mdns && msg("mDNS: stopAdvertising()\n");

	if (!$class->pidFile || !-f $class->pidFile) {

		$::d_mdns && msg("mDNS: No PID file.\n");
		return;
	}

	my $dead = 0;
	my $pid  = undef;

	if ($class->processObj && $class->processObj->alive) {

		$class->processObj->die;

		if (!$class->processObj->alive) {
			$dead = 1;

			$class->processObj(undef);
		}
	}

	if (-f $class->pidFile || !$dead) {

		$pid  = read_file($class->pidFile);	

		if ($pid) {
			$dead = kill('KILL', $pid);
		}
	}
	
	if ($dead) {

		if ($pid) {
			$::d_mdns && msg("mDNS: Killed PID: $pid\n");
		}

		unlink($class->confFile);
		unlink($class->pidFile);
	}

	return $dead;
}

1;

__END__
