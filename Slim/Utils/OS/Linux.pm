package Slim::Utils::OS::Linux;

# Copyright 2001-2011 Logitech.
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

sub getFlavor {
	if (-f '/etc/raidiator_version') {

		return 'Netgear RAIDiator';
			
	} elsif (-f '/etc/squeezeos.version') {
	
		return 'SqueezeOS';
	
	} elsif (-f '/etc/debian_version') {
	
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
