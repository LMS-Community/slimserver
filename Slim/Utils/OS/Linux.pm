package Slim::Utils::OS::Linux;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Utils::OS::Unix);

use Config;

sub initDetails {
	my $class = shift;

	$class->{osDetails}->{'os'} = 'Linux';

	$class->{osDetails}->{osName} = getFlavor();
	$class->{osDetails}->{uid}    = getpwuid($>);
	$class->{osDetails}->{osArch} = $Config{'myarchname'};

	return $class->{osDetails};
}

sub canDBHighMem {
	my $class = shift;

	my $meminfo = getMemInfo();

	if ($meminfo && $meminfo->{MemTotal}) {
		# some 1GB systems grab RAM for the video adapter - enable dbhighmem if > 900MB installed
		return $meminfo->{MemTotal} > 900_000_000;
	}

	# in case we haven't been able to read /proc/meminfo, enable dbhighmem for x86 systems
	return $class->{osDetails}->{'osArch'} =~ /[x6]86/ ? 1 : 0;
}

sub canVacuumInMemory {
	my ($class, $dbSize) = @_;

	return unless Slim::Utils::Prefs::preferences('server')->get('dbhighmem');

	my $meminfo = getMemInfo() || return;

	# we're good if we have two times the library file's size in memory available
	return ($meminfo->{MemAvailable} + $meminfo->{SwapFree}) > (2 * $dbSize);
}

sub getMemInfo() {
	open(INFIL,"/proc/meminfo") || return;

	my %units = (
		kb => 1024,
		mb => 1024 * 1024,
		gb => 1024 * 1024 * 1024
	);

	my %mem;
	foreach(<INFIL>) {
		if ( m/^(\S+):\s+(\S+) (\S+)/ ) {
			$mem{$1} = $2 * ($units{lc($3)} || 0);
		}
	}

	$mem{MemAvailable} ||= $mem{MemFree} + $mem{Buffers};

	close(INFIL);
	return \%mem
}

sub getFlavor {
	if (-f '/etc/raidiator_version') {

		return 'Netgear RAIDiator';

	} elsif (-f '/etc/squeezeos.version') {

		return 'SqueezeOS';

	} elsif (-f '/etc/debian_version' || -f '/etc/devuan_version') {

		return 'Debian';

	} elsif (-f '/etc/redhat_release' || -f '/etc/redhat-release' || -f '/etc/fedora-release') {

		return 'Red Hat';

	} elsif (-f '/etc/SuSE-release') {

		return 'SuSE';

	} elsif (-f '/etc/synoinfo.conf' || -f '/etc.defaults/synoinfo.conf') {

		return 'Synology DiskStation';
	}

	return 'Linux';
}

sub signalUpdateReady {
	my ($file) = @_;

	if ($file) {
		my ($version, $revision) = $file =~ /(\d+\.\d+\.\d+)(?:.*(\d{5,}))?/;
		$revision ||= 0;
		$::newVersion = Slim::Utils::Strings::string('SERVER_LINUX_UPDATE_AVAILABLE', "$version - $revision", $file);
	}
}

sub getDefaultGateway {
	my $route = `/sbin/route -n`;
	while ( $route =~ /^(?:0\.0\.0\.0)\s*(\d+\.\d+\.\d+\.\d+)/mg ) {
		if ( Slim::Utils::Network::ip_is_private($1) ) {
			return $1;
		}
	}

	return;
}

1;
