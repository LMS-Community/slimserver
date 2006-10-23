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

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::OSDetect;

{
	my $class = __PACKAGE__;

	for my $accessor (qw(confFile pidFile processObj isInitialized)) {

		$class->mk_classdata($accessor);
	}

	$class->isInitialized(0);
}

my $log = logger('network.mdns');
 
my %services = ();

sub init {
	my $class = shift;

	if (Slim::Utils::OSDetect::OS() eq 'win') {

		$log->debug("Skipping initialization on Windows.");

		return 0;
	}

	$log->info("Initializing..");

	my $cacheDir = Slim::Utils::Prefs::get('cachedir');

	if (!-d $cacheDir) {

		$log->error("Error: cachedir [$cacheDir] isn't set or writeable");
		return 0;
	}

	$class->confFile(catfile($cacheDir, 'mDNS.conf'));
	$class->pidFile(catfile($cacheDir, 'mDNS.pid'));

	$class->isInitialized(1);

	return 1;
}

sub addService {
	my ($class, $service, $port) = @_;

	if (!$class->isInitialized) {
		return if !$class->init;
	}

	my $name = Slim::Utils::Prefs::get('mDNSname');

	if (!$name) {

		$log->info("Blank name, skipping service: $service - TXT - $port");

	} else {

		$log->info("Adding service: $name - $service - TXT - $port");

		$services{$service} = [ $name, $port ];
	}
}

sub removeService {
	my ($class, $service) = @_;

	if (!$class->isInitialized) {
		return if !$class->init;
	}

	$log->info("Removing service: $service");

	delete $services{$service};
}

sub startAdvertising {
	my $class = shift;

	if (!$class->isInitialized) {
		return if !$class->init;
	}

	$log->info("Building configuration.");

	my $mDNSBin = Slim::Utils::Misc::findbin('mDNSResponderPosix') || do {

		$log->error("Error: Couldn't find mDNSResponderPosix binary! Aborting!");
		return;
	};

	if (!$class->isInitialized) {
		return if !$class->init;
	}

	# Remove any existing configs
	$class->stopAdvertising;

	open(CONF, '>', $class->confFile) or do {

		$log->error(sprintf("Error: Couldn't open %s for appending!: $!", $class->confFile));
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

		$log->info("Config has 0 size - disabling mDNS");
		return;
	}

	my $command = join(' ', (
		$mDNSBin,
		sprintf('-f %s', $class->confFile),
		sprintf('-P %s', $class->pidFile)
	));

	$log->info("About to run: $command");

	$class->processObj( Proc::Background->new($command) );

	$log->info(sprintf("Process is alive: [%d] with pid: [%d]",
		$class->processObj->alive, $class->processObj->pid
	));
}

sub stopAdvertising {
	my $class = shift;

	if (!$class->isInitialized) {
		return if !$class->init;
	}

	$log->info("Shutting down..");

	if (!$class->pidFile || !-f $class->pidFile) {

		$log->debug("Warning: No PID file.");

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
			$log->info("Killed PID: $pid");
		}

		unlink($class->confFile);
		unlink($class->pidFile);
	}

	return $dead;
}

1;

__END__
