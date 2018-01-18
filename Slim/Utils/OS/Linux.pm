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
	
	require File::Slurp;

	if ( my $meminfo = File::Slurp::read_file('/proc/meminfo') ) {
		if ( $meminfo =~ /MemTotal:\s+(\d+) (\S+)/sig ) {
			my ($value, $unit) = ($1, $2);
			
			# some 1GB systems grab RAM for the video adapter - enable dbhighmem if > 900MB installed
			if ( ($unit =~ /KB/i && $value > 900_000) || ($unit =~ /MB/i && $value > 900) ) {
				return 1;
			}
		}
	}
	
	# in case we haven't been able to read /proc/meminfo, enable dbhighmem for x86 systems
	return $class->{osDetails}->{'osArch'} =~ /[x6]86/ ? 1 : 0;
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
